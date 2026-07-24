import Darwin
import Foundation

struct ProcessRunResult {
    let status: Int32
    let data: Data
    let timedOut: Bool

    var succeeded: Bool { !timedOut && status == 0 }

    var output: String {
        String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func failureSummary(maxLength: Int = 180) -> String? {
        guard !succeeded else { return nil }
        if timedOut { return "timed out" }
        let firstLine = output
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let message = firstLine?.isEmpty == false
            ? firstLine!
            : "exited with status \(status)"
        guard message.count > maxLength else { return message }
        return String(message.prefix(maxLength - 1)) + "…"
    }
}

enum SnapshotFreshness {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func age(of timestamp: String, now: Date = Date()) -> TimeInterval? {
        guard let date = formatter.date(from: timestamp) ?? fallbackFormatter.date(from: timestamp) else {
            return nil
        }
        return max(0, now.timeIntervalSince(date))
    }

    static func fileAge(path: String, now: Date = Date()) -> TimeInterval? {
        let expanded = (path as NSString).expandingTildeInPath
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: expanded),
              let modified = attributes[.modificationDate] as? Date else {
            return nil
        }
        return max(0, now.timeIntervalSince(modified))
    }

    static func staleReason(
        timestamp: String?,
        filePath: String?,
        maxAge: TimeInterval,
        label: String,
        now: Date = Date()
    ) -> String? {
        let observedAge = timestamp.flatMap { age(of: $0, now: now) }
            ?? filePath.flatMap { fileAge(path: $0, now: now) }
        guard let observedAge else { return "\(label) timestamp unavailable" }
        guard observedAge > maxAge else { return nil }
        return "\(label) stale (\(Int(observedAge))s old)"
    }
}

/// Runs a configured argv directly with a deadline. Callers decide whether stderr
/// should be captured; no implicit shell is involved, so configuration values are
/// never re-parsed as shell source. A temporary output file avoids pipe backpressure
/// if a child produces more output than expected.
enum ProcessRunner {
    private static let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    static func run(
        _ argv: [String],
        timeout: TimeInterval = 30,
        includeStandardError: Bool = true,
        maxOutputBytes: Int = 1_048_576,
        currentDirectory: URL? = nil,
        processStarted: ((Process) -> Void)? = nil
    ) -> ProcessRunResult {
        guard let command = argv.first, !command.isEmpty else {
            return failure("empty command")
        }

        var environment = ProcessInfo.processInfo.environment
        if environment["PATH"]?.isEmpty != false {
            environment["PATH"] = fallbackPath
        } else if let path = environment["PATH"], !path.contains("/opt/homebrew/bin") {
            environment["PATH"] = path + ":" + fallbackPath
        }

        guard let executable = resolve(command, path: environment["PATH"] ?? fallbackPath) else {
            return failure("executable not found: \(command)")
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("server-monitor-process-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
            return failure("unable to create process output file")
        }
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(argv.dropFirst())
        process.environment = environment
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = outputHandle
        process.standardError = includeStandardError ? outputHandle : FileHandle.nullDevice

        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }

        do {
            try process.run()
            processStarted?(process)
        } catch {
            try? outputHandle.close()
            return failure("spawn failed: \(error.localizedDescription)")
        }

        let deadline = DispatchTime.now() + .milliseconds(max(1, Int(timeout * 1_000)))
        var timedOut = terminated.wait(timeout: deadline) == .timedOut
        if timedOut {
            process.terminate()
            if terminated.wait(timeout: .now() + .seconds(2)) == .timedOut {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = terminated.wait(timeout: .now() + .seconds(2))
            }
        }

        try? outputHandle.synchronize()
        try? outputHandle.close()
        let data: Data
        if let readHandle = try? FileHandle(forReadingFrom: outputURL) {
            data = (try? readHandle.read(upToCount: maxOutputBytes)) ?? Data()
            try? readHandle.close()
        } else {
            data = Data()
        }

        if process.isRunning {
            timedOut = true
            return ProcessRunResult(status: -1, data: data, timedOut: true)
        }
        return ProcessRunResult(status: process.terminationStatus, data: data, timedOut: timedOut)
    }

    private static func resolve(_ command: String, path: String) -> String? {
        let expanded = (command as NSString).expandingTildeInPath
        if expanded.contains("/") {
            return FileManager.default.isExecutableFile(atPath: expanded) ? expanded : nil
        }
        for directory in path.split(separator: ":", omittingEmptySubsequences: true) {
            let candidate = String(directory) + "/" + expanded
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    private static func failure(_ message: String) -> ProcessRunResult {
        ProcessRunResult(status: 127, data: Data(message.utf8), timedOut: false)
    }
}
