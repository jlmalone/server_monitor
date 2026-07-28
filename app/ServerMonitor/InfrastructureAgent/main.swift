import Darwin
import Foundation
import Network

private struct ManagedChildConfig: Decodable {
    let id: String
    let command: [String]
    let restartDelaySeconds: Double?
    let networkChangeSignal: String?
    let maxSilenceSeconds: Double?
}

private struct ScheduledJobConfig: Decodable {
    let id: String
    let command: [String]
    let intervalSeconds: Double
    let timeoutSeconds: Double?
    let runAtStart: Bool?
}

private struct AgentConfig: Decodable {
    let schema: Int
    let persistentChildren: [ManagedChildConfig]
    let scheduledJobs: [ScheduledJobConfig]
    let watchNetworkChanges: Bool?
    let watchPaths: [String]?
    let statusFile: String?
}

private struct ChildStatus: Encodable {
    let id: String
    let running: Bool
    let responsive: Bool
    let pid: Int32?
    let silenceSeconds: Int?
    let lastExitStatus: Int32?
}

private struct JobStatus: Encodable {
    let id: String
    let intervalSeconds: Double
    let running: Bool
    let lastRunAt: String?
    let lastExitStatus: Int32?
    let timedOut: Bool
}

private struct AgentStatus: Encodable {
    let schema = 2
    let timestamp: String
    let configLoaded: Bool
    let configError: String?
    let children: [ChildStatus]
    let scheduledJobs: [JobStatus]
}

private final class RunningChild {
    let config: ManagedChildConfig
    let process: Process
    let logHandle: FileHandle
    let logURL: URL
    let startedAt: Date

    init(config: ManagedChildConfig, process: Process, logHandle: FileHandle, logURL: URL) {
        self.config = config
        self.process = process
        self.logHandle = logHandle
        self.logURL = logURL
        startedAt = Date()
    }
}

private final class InfrastructureSupervisor {
    private let stateQueue = DispatchQueue(label: "vision.salient.infrastructure-agent.state")
    private let workQueue = DispatchQueue(label: "vision.salient.infrastructure-agent.jobs", qos: .utility,
                                          attributes: .concurrent)
    private let networkMonitorQueue = DispatchQueue(label: "vision.salient.infrastructure-agent.network")
    private let pathMonitor = NWPathMonitor()
    private let logLock = NSLock()
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/server-monitor/infrastructure-agent.json")
    private let logDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/ServerMonitor/InfrastructureAgent", isDirectory: true)
    private let defaultStatusURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/ServerMonitor/infrastructure-agent-status.json")

    private var config: AgentConfig?
    private var configError: String?
    private var configModifiedAt: Date?
    private var reloadDeferred = false
    private var children: [String: RunningChild] = [:]
    private var childLastExit: [String: Int32] = [:]
    private var terminatingChildPIDs: [String: Int32] = [:]
    private var jobTimers: [String: DispatchSourceTimer] = [:]
    private var activeJobIDs: Set<String> = []
    private var activeJobProcesses: [String: Process] = [:]
    private var jobLastRun: [String: String] = [:]
    private var jobLastExit: [String: Int32] = [:]
    private var jobTimedOut: Set<String> = []
    private var networkFingerprint: String?
    private var receivedInitialNetworkPath = false
    private var lastHeartbeatAt = Date.distantPast
    private var maintenanceTimer: DispatchSourceTimer?
    private var shuttingDown = false

    func start() {
        stateQueue.async {
            try? FileManager.default.createDirectory(at: self.logDirectory, withIntermediateDirectories: true)
            self.reloadConfiguration(force: true)
            self.startNetworkMonitor()
            self.startMaintenanceTimer()
            self.writeStatus()
        }
    }

    func shutdown() {
        stateQueue.async {
            guard !self.shuttingDown else { return }
            self.shuttingDown = true
            self.maintenanceTimer?.cancel()
            self.maintenanceTimer = nil
            self.pathMonitor.cancel()
            self.jobTimers.values.forEach { $0.cancel() }
            self.jobTimers.removeAll()
            for child in self.children.values where child.process.isRunning {
                child.process.terminate()
            }
            for process in self.activeJobProcesses.values where process.isRunning {
                process.terminate()
            }
            self.writeStatus()
            self.stateQueue.asyncAfter(deadline: .now() + .seconds(2)) {
                for child in self.children.values where child.process.isRunning {
                    Darwin.kill(child.process.processIdentifier, SIGKILL)
                }
                for process in self.activeJobProcesses.values where process.isRunning {
                    Darwin.kill(process.processIdentifier, SIGKILL)
                }
                Darwin.exit(EXIT_SUCCESS)
            }
        }
    }

    /// Explicit operator recovery hook. SIGUSR2 recycles only persistent
    /// children; scheduled work (including a long queue drain) is left alone.
    func restartPersistentChildren() {
        stateQueue.async {
            guard !self.shuttingDown else { return }
            self.log("operator requested persistent-child restart")
            for child in self.children.values where child.process.isRunning {
                self.recycleChild(child, reason: "operator request")
            }
            self.writeStatus()
        }
    }

    private func startMaintenanceTimer() {
        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now() + .seconds(2), repeating: .seconds(2), leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            guard let self, !self.shuttingDown else { return }
            self.reloadConfiguration(force: false)
            self.detectNetworkChange()
            self.recycleUnresponsiveChildren()
            if Date().timeIntervalSince(self.lastHeartbeatAt) >= 30 { self.writeStatus() }
        }
        timer.resume()
        maintenanceTimer = timer
    }

    private func reloadConfiguration(force: Bool) {
        let modified = (try? FileManager.default.attributesOfItem(atPath: configURL.path)[.modificationDate]) as? Date
        guard force || modified != configModifiedAt else { return }
        guard activeJobIDs.isEmpty else {
            if !reloadDeferred { log("configuration reload deferred while scheduled work is active") }
            reloadDeferred = true
            return
        }
        reloadDeferred = false
        configModifiedAt = modified

        do {
            let data = try Data(contentsOf: configURL)
            let decoded = try decoder.decode(AgentConfig.self, from: data)
            guard decoded.schema == 1 else {
                throw NSError(domain: "InfrastructureAgent", code: 78,
                              userInfo: [NSLocalizedDescriptionKey: "unsupported config schema \(decoded.schema)"])
            }
            try validate(decoded)
            config = decoded
            configError = nil
            networkFingerprint = fingerprint(decoded.watchPaths ?? [])
            reconfigureManagedWork(decoded)
            log("configuration loaded")
            writeStatus()
        } catch {
            config = nil
            configError = error.localizedDescription
            stopManagedWork()
            log("configuration unavailable: \(error.localizedDescription)")
        }
    }

    private func validate(_ candidate: AgentConfig) throws {
        func invalid(_ detail: String) -> NSError {
            NSError(domain: "InfrastructureAgent", code: 78,
                    userInfo: [NSLocalizedDescriptionKey: detail])
        }
        let childIDs = candidate.persistentChildren.map(\.id)
        let jobIDs = candidate.scheduledJobs.map(\.id)
        guard Set(childIDs).count == childIDs.count else { throw invalid("duplicate persistent child id") }
        guard Set(jobIDs).count == jobIDs.count else { throw invalid("duplicate scheduled job id") }
        guard candidate.persistentChildren.allSatisfy({
            !$0.id.isEmpty && !$0.command.isEmpty && ($0.restartDelaySeconds ?? 10) >= 1
                && ($0.maxSilenceSeconds == nil || $0.maxSilenceSeconds! >= 10)
        }) else { throw invalid("invalid persistent child") }
        guard candidate.scheduledJobs.allSatisfy({
            !$0.id.isEmpty && !$0.command.isEmpty && $0.intervalSeconds >= 1 && ($0.timeoutSeconds ?? 300) > 0
        }) else { throw invalid("invalid scheduled job") }
        if let statusFile = candidate.statusFile, statusFile.isEmpty {
            throw invalid("statusFile must not be empty")
        }
    }

    private func reconfigureManagedWork(_ newConfig: AgentConfig) {
        stopManagedWork()
        for child in newConfig.persistentChildren { startChild(child) }
        for job in newConfig.scheduledJobs { startTimer(for: job) }
    }

    private func stopManagedWork() {
        jobTimers.values.forEach { $0.cancel() }
        jobTimers.removeAll()
        activeJobIDs.removeAll()
        for child in children.values {
            if child.process.isRunning { child.process.terminate() }
            try? child.logHandle.close()
        }
        children.removeAll()
    }

    private func startChild(_ childConfig: ManagedChildConfig) {
        guard !shuttingDown else { return }
        // A delayed restart from an older configuration can fire after a new
        // instance with the same ID is already running. Treat that as a no-op;
        // scheduling another retry here would create an endless restart-timer
        // chain and falsely report exit 127 for a healthy child.
        guard children[childConfig.id] == nil else { return }
        guard let command = resolvedCommand(childConfig.command) else {
            childLastExit[childConfig.id] = 127
            writeStatus()
            scheduleChildRestart(childConfig)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())
        process.environment = childEnvironment()
        let logURL = childLogURL(id: childConfig.id)
        let handle = openLog(at: logURL)
        process.standardOutput = handle
        process.standardError = handle
        process.terminationHandler = { [weak self, weak process] finished in
            guard let self, let process else { return }
            self.stateQueue.async {
                guard self.children[childConfig.id]?.process === process else { return }
                self.children.removeValue(forKey: childConfig.id)
                self.terminatingChildPIDs.removeValue(forKey: childConfig.id)
                try? handle.close()
                self.childLastExit[childConfig.id] = finished.terminationStatus
                self.log("child \(childConfig.id) exited \(finished.terminationStatus)")
                self.writeStatus()
                self.scheduleChildRestart(childConfig)
            }
        }
        do {
            try process.run()
            // A running replacement supersedes any historical launch failure.
            // Keeping the old nonzero code beside running=true makes healthy
            // supervision look degraded to status consumers.
            childLastExit.removeValue(forKey: childConfig.id)
            children[childConfig.id] = RunningChild(
                config: childConfig, process: process, logHandle: handle, logURL: logURL
            )
            log("child \(childConfig.id) started pid=\(process.processIdentifier)")
            writeStatus()
        } catch {
            childLastExit[childConfig.id] = 127
            try? handle.close()
            log("child \(childConfig.id) failed to start: \(error.localizedDescription)")
            writeStatus()
            scheduleChildRestart(childConfig)
        }
    }

    private func scheduleChildRestart(_ childConfig: ManagedChildConfig) {
        guard !shuttingDown,
              config?.persistentChildren.contains(where: { $0.id == childConfig.id }) == true else { return }
        let delay = max(1, childConfig.restartDelaySeconds ?? 10)
        stateQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.shuttingDown,
                  let current = self.config?.persistentChildren.first(where: { $0.id == childConfig.id }) else {
                return
            }
            self.startChild(current)
        }
    }

    private func startTimer(for job: ScheduledJobConfig) {
        guard job.intervalSeconds >= 1 else {
            jobLastExit[job.id] = 78
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        let initial = job.runAtStart == false ? job.intervalSeconds : 1
        timer.schedule(deadline: .now() + initial,
                       repeating: job.intervalSeconds,
                       leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in self?.run(job) }
        timer.resume()
        jobTimers[job.id] = timer
    }

    private func run(_ job: ScheduledJobConfig) {
        guard !shuttingDown else { return }
        guard !activeJobIDs.contains(job.id) else {
            log("job \(job.id) skipped because its previous run is still active")
            return
        }
        activeJobIDs.insert(job.id)
        writeStatus()
        workQueue.async { [weak self] in
            guard let self else { return }
            let result = ProcessRunner.run(
                job.command,
                timeout: job.timeoutSeconds ?? 300,
                processStarted: { process in
                    self.stateQueue.sync {
                        if self.shuttingDown {
                            process.terminate()
                        } else {
                            self.activeJobProcesses[job.id] = process
                        }
                    }
                }
            )
            self.stateQueue.async {
                self.activeJobIDs.remove(job.id)
                self.activeJobProcesses.removeValue(forKey: job.id)
                self.jobLastRun[job.id] = ISO8601DateFormatter().string(from: Date())
                self.jobLastExit[job.id] = result.status
                if result.timedOut { self.jobTimedOut.insert(job.id) } else { self.jobTimedOut.remove(job.id) }
                self.log("job \(job.id) exited \(result.status)\(result.timedOut ? " (timeout)" : "")")
                self.writeStatus()
            }
        }
    }

    private func detectNetworkChange() {
        guard let paths = config?.watchPaths, !paths.isEmpty else { return }
        let current = fingerprint(paths)
        defer { networkFingerprint = current }
        guard let previous = networkFingerprint, current != previous else { return }
        signalNetworkAwareChildren(reason: "watched network configuration changed")
    }

    private func startNetworkMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            guard let self else { return }
            self.stateQueue.async {
                guard !self.shuttingDown else { return }
                if !self.receivedInitialNetworkPath {
                    self.receivedInitialNetworkPath = true
                    return
                }
                guard self.config?.watchNetworkChanges == true else { return }
                self.signalNetworkAwareChildren(reason: "system network path changed")
            }
        }
        pathMonitor.start(queue: networkMonitorQueue)
    }

    private func signalNetworkAwareChildren(reason: String) {
        log(reason)
        for child in children.values {
            guard let name = child.config.networkChangeSignal,
                  let signal = signalNumber(name), child.process.isRunning else { continue }
            Darwin.kill(child.process.processIdentifier, signal)
        }
    }

    private func recycleUnresponsiveChildren() {
        let now = Date()
        for child in children.values {
            guard child.process.isRunning,
                  let limit = child.config.maxSilenceSeconds,
                  terminatingChildPIDs[child.config.id] != child.process.processIdentifier else { continue }
            let silence = now.timeIntervalSince(lastOutputAt(for: child))
            guard silence > limit else { continue }
            recycleChild(child, reason: "silent for \(Int(silence))s (limit \(Int(limit))s)")
        }
    }

    private func recycleChild(_ child: RunningChild, reason: String) {
        let process = child.process
        let pid = process.processIdentifier
        guard process.isRunning, terminatingChildPIDs[child.config.id] != pid else { return }
        terminatingChildPIDs[child.config.id] = pid
        log("child \(child.config.id) unresponsive/recycling pid=\(pid): \(reason); command=\(child.config.command.joined(separator: " "))")
        process.terminate()
        writeStatus()
        stateQueue.asyncAfter(deadline: .now() + .seconds(5)) { [weak self, weak process] in
            guard let self, let process, process.isRunning,
                  self.terminatingChildPIDs[child.config.id] == pid else { return }
            self.log("child \(child.config.id) ignored SIGTERM for 5s; sending SIGKILL pid=\(pid)")
            Darwin.kill(pid, SIGKILL)
            self.writeStatus()
        }
    }

    private func lastOutputAt(for child: RunningChild) -> Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: child.logURL.path)
        let modified = attributes?[.modificationDate] as? Date ?? .distantPast
        return max(child.startedAt, modified)
    }

    private func fingerprint(_ paths: [String]) -> String {
        paths.map { raw in
            let path = (raw as NSString).expandingTildeInPath
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            let date = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let size = attributes?[.size] as? NSNumber ?? 0
            return "\(path)|\(date)|\(size)"
        }.joined(separator: "\n")
    }

    private func writeStatus() {
        let childReports = (config?.persistentChildren ?? []).map { item in
            let child = children[item.id]
            let process = child?.process
            let running = process?.isRunning == true
            let silence = child.map { max(0, Int(Date().timeIntervalSince(lastOutputAt(for: $0)))) }
            let responsive = running && item.maxSilenceSeconds.map { Double(silence ?? 0) <= $0 } != false
            return ChildStatus(id: item.id, running: running, responsive: responsive,
                               pid: running ? process?.processIdentifier : nil,
                               silenceSeconds: silence,
                               lastExitStatus: childLastExit[item.id])
        }
        let jobReports = (config?.scheduledJobs ?? []).map { item in
            JobStatus(id: item.id, intervalSeconds: item.intervalSeconds,
                      running: activeJobIDs.contains(item.id),
                      lastRunAt: jobLastRun[item.id], lastExitStatus: jobLastExit[item.id],
                      timedOut: jobTimedOut.contains(item.id))
        }
        let report = AgentStatus(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            configLoaded: config != nil,
            configError: configError,
            children: childReports,
            scheduledJobs: jobReports
        )
        let destination = config?.statusFile.map(expandedURL) ?? defaultStatusURL
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(report)
            try data.write(to: destination, options: .atomic)
            lastHeartbeatAt = Date()
        } catch {
            log("status write failed: \(error.localizedDescription)")
        }
    }

    private func resolvedCommand(_ argv: [String]) -> [String]? {
        guard let first = argv.first else { return nil }
        let expanded = (first as NSString).expandingTildeInPath
        let executable: String?
        if expanded.contains("/") {
            executable = FileManager.default.isExecutableFile(atPath: expanded) ? expanded : nil
        } else {
            executable = childEnvironment()["PATH"]?.split(separator: ":").lazy
                .map { String($0) + "/" + expanded }
                .first { FileManager.default.isExecutableFile(atPath: $0) }
        }
        guard let executable else { return nil }
        return [executable] + Array(argv.dropFirst())
    }

    private func childEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        return environment
    }

    private func childLogURL(id: String) -> URL {
        let safeID = id.replacingOccurrences(of: "/", with: "-")
        return logDirectory.appendingPathComponent("\(safeID).log")
    }

    private func openLog(at url: URL) -> FileHandle {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = FileHandle(forWritingAtPath: url.path) ?? FileHandle.nullDevice
        _ = try? handle.seekToEnd()
        return handle
    }

    private func expandedURL(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    private func signalNumber(_ name: String) -> Int32? {
        switch name.uppercased() {
        case "HUP", "SIGHUP": return SIGHUP
        case "USR1", "SIGUSR1": return SIGUSR1
        case "USR2", "SIGUSR2": return SIGUSR2
        default: return nil
        }
    }

    private func log(_ message: String) {
        logLock.lock()
        defer { logLock.unlock() }
        let url = logDirectory.appendingPathComponent("agent.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: url.path) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }
}

// Infrastructure work must remain subordinate to interactive use. Descendant
// processes inherit this priority, so every supervised child and scheduled job
// starts at the same low CPU priority without wrapper commands in private config.
_ = setpriority(PRIO_PROCESS, 0, 19)

private let supervisor = InfrastructureSupervisor()
supervisor.start()

signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
signal(SIGUSR2, SIG_IGN)
let terminationSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminationSource.setEventHandler { supervisor.shutdown() }
terminationSource.resume()
let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
interruptSource.setEventHandler { supervisor.shutdown() }
interruptSource.resume()
let restartChildrenSource = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
restartChildrenSource.setEventHandler { supervisor.restartPersistentChildren() }
restartChildrenSource.resume()

dispatchMain()
