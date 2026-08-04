import AppKit
import Darwin
import Foundation
import OSLog

/// Protects a normally idle menu-bar app from silently consuming a core or
/// retaining hundreds of megabytes after a framework or UI fault.
final class AppResourceGuard {
    static let shared = AppResourceGuard()

    private struct Snapshot {
        let uptime: TimeInterval
        let cpuSeconds: TimeInterval
    }

    private let queue = DispatchQueue(label: "vision.salient.ServerMonitor.resource-guard", qos: .utility)
    private let logger = Logger(subsystem: "vision.salient.ServerMonitor", category: "ResourceGuard")
    private let defaults = UserDefaults.standard
    private let relaunchDateKey = "ResourceGuardLastRelaunchDate"
    private var timer: DispatchSourceTimer?
    private var previous: Snapshot?
    private var policy = SustainedResourcePolicy(
        cpuFractionLimit: AppResourceLimits.cpuFraction,
        residentByteLimit: AppResourceLimits.residentBytes,
        requiredSamples: AppResourceLimits.requiredSamples
    )

    private init() {}

    func start() {
        // A menu-bar monitor must yield to transfers, builds, and foreground
        // work even before the sustained-resource guard has enough samples.
        _ = setpriority(PRIO_PROCESS, 0, 19)
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            self.previous = self.snapshot()

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(
                deadline: .now() + AppResourceLimits.sampleInterval,
                repeating: AppResourceLimits.sampleInterval,
                leeway: .seconds(10)
            )
            timer.setEventHandler { [weak self] in self?.sample() }
            self.timer = timer
            timer.resume()
        }
    }

    private func sample() {
        guard let current = snapshot(), let previous else {
            previous = snapshot()
            return
        }
        self.previous = current

        let elapsed = current.uptime - previous.uptime
        guard elapsed > 0 else { return }
        let cpuFraction = max(0, (current.cpuSeconds - previous.cpuSeconds) / elapsed)
        let residentBytes = currentResidentBytes()

        guard let violation = policy.record(
            cpuFraction: cpuFraction,
            residentBytes: residentBytes
        ) else { return }

        recover(from: violation)
    }

    private func snapshot() -> Snapshot? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        let user = TimeInterval(usage.ru_utime.tv_sec)
            + TimeInterval(usage.ru_utime.tv_usec) / 1_000_000
        let system = TimeInterval(usage.ru_stime.tv_sec)
            + TimeInterval(usage.ru_stime.tv_usec) / 1_000_000
        return Snapshot(uptime: ProcessInfo.processInfo.systemUptime, cpuSeconds: user + system)
    }

    private func currentResidentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let status = withUnsafeMutablePointer(to: &info) { infoPointer in
            infoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { integerPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    integerPointer,
                    &count
                )
            }
        }
        return status == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }

    private func recover(from violation: AppResourceViolation) -> Never {
        timer?.cancel()
        timer = nil

        switch violation {
        case let .cpu(fraction):
            logger.fault("Sustained CPU limit exceeded at \(fraction * 100, format: .fixed(precision: 1)) percent")
        case let .memory(bytes):
            logger.fault("Sustained resident-memory limit exceeded at \(bytes / 1_048_576) MiB")
        }

        let now = Date()
        if let lastRelaunch = defaults.object(forKey: relaunchDateKey) as? Date,
           now.timeIntervalSince(lastRelaunch) < AppResourceLimits.relaunchCooldown {
            logger.fault("A guarded relaunch already occurred within the cooldown; exiting to prevent a restart loop")
            exit(EXIT_SUCCESS)
        }

        defaults.set(now, forKey: relaunchDateKey)

        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        relaunch.arguments = ["-g", "-n", Bundle.main.bundlePath]
        do {
            try relaunch.run()
            relaunch.waitUntilExit()
            if relaunch.terminationStatus != 0 {
                logger.error("Resource-guard relaunch command exited \(relaunch.terminationStatus)")
            }
        } catch {
            logger.error("Resource-guard relaunch failed: \(error.localizedDescription, privacy: .public)")
        }

        exit(EXIT_SUCCESS)
    }
}
