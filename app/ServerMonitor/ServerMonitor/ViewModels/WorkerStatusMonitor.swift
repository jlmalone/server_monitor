import Foundation
import SwiftUI

/// Optional local "worker node" the menu bar can start/stop and watch.
///
/// What the worker actually *is* (which directory, which launch script, which
/// pid/log files) is machine-specific and deliberately NOT stored in this
/// open-source repo. It is read at runtime from an untracked local config at
/// `~/.config/server-monitor/worker.json` (see `config/worker.example.json`
/// for the schema). With no config present, the panel reports "not configured"
/// and the controls stay hidden — the app stays generic.
struct WorkerConfig: Codable {
    var repoDir: String      // working directory the launch script runs in
    var script: String       // launch script, e.g. "run.sh"
    var arg: String          // argument passed to the script, e.g. "local"
    var pidPath: String      // file holding the running node's PID
    var logPath: String      // log to tail for the throughput line
    var ratePattern: String  // regex for the throughput substring, e.g. "Rate: [0-9,]+/s"

    static func load() -> WorkerConfig? {
        let path = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".config/server-monitor/worker.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? JSONDecoder().decode(WorkerConfig.self, from: data)
    }
}

@MainActor
final class WorkerStatusMonitor: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var rate: String?
    @Published private(set) var busy = false
    let configured: Bool

    private let config: WorkerConfig?
    private let pollInterval: TimeInterval
    private var timer: Timer?

    init(pollInterval: TimeInterval = 5) {
        self.pollInterval = pollInterval
        self.config = WorkerConfig.load()
        self.configured = (config != nil)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    func refresh() {
        guard config != nil else { running = false; return }
        running = isRunning()
        if busy { return }                       // keep the "working…" label until the action finishes
        rate = running ? lastRate() : nil
    }

    var headline: String {
        if !configured { return "not configured" }
        if busy { return "working…" }
        return running ? "Running" : "Stopped"
    }

    var headlineColor: Color {
        if !configured { return .secondary }
        if busy { return .orange }
        return running ? .green : .secondary
    }

    private func isRunning() -> Bool {
        guard let c = config,
              let raw = try? String(contentsOfFile: c.pidPath, encoding: .utf8),
              let pid = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return kill(pid, 0) == 0                  // signal 0 = "does this pid exist?"
    }

    /// The log is progress-spam; read its tail and pull the latest throughput line.
    private func lastRate() -> String? {
        guard let c = config, let fh = FileHandle(forReadingAtPath: c.logPath) else { return nil }
        defer { try? fh.close() }
        guard let end = try? fh.seekToEnd() else { return nil }
        let chunk: UInt64 = 4096
        try? fh.seek(toOffset: end > chunk ? end - chunk : 0)
        guard let data = try? fh.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        for line in lines.reversed() {
            if let r = line.range(of: c.ratePattern, options: .regularExpression) {
                return String(line[r])
            }
        }
        return nil
    }

    func start() { run("start") }
    func stop()  { run("stop") }

    private func run(_ action: String) {
        guard let c = config, !busy else { return }
        busy = true
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.currentDirectoryURL = URL(fileURLWithPath: c.repoDir)
            // Login shell for the user's PATH, but pass the script + args POSITIONALLY
            // ("$1"/"$2"/"$3") so values with spaces or shell metacharacters can't break
            // the command or inject — nothing is interpolated into the shell string.
            p.arguments = ["-lc", "exec \"$1\" \"$2\" \"$3\"", "worker", "./\(c.script)", action, c.arg]
            try? p.run()
            p.waitUntilExit()
            await MainActor.run {
                self.busy = false
                self.refresh()
            }
        }
    }
}
