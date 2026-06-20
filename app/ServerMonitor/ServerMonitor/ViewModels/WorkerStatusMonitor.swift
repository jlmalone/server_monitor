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

// MARK: - Transfers panel
//
// Generic, config-driven file-transfer monitor. WHAT it watches — which command
// prints the queue JSON, and which machines to poll — is machine-specific and
// lives in untracked ~/.config/server-monitor/transfers.json (schema in
// config/transfers.example.json). With no config the panel is inert. This
// open-source code only runs the configured command(s), decodes raw-byte queue
// JSON, and computes %/ETA for display — no host names or tool specifics here.

struct TransfersSource: Codable {
    var label: String          // machine label shown on each row, e.g. "this Mac"
    var command: [String]      // argv that prints the queue JSON (run via a login shell);
                               // remote example: ["ssh","<host>","nice","-n","19", ...]
    var runCommand: [String]?  // optional argv that reprocesses failed/pending transfers
                               // for this source; when set, failed rows get a Resume button.
}

/// Optional reader for the transfer tool's JSON-lines history log, surfaced in
/// the Transfer History window (distinct from the live queue above). `command`
/// is argv that prints one record per line (run via a login shell); it lives
/// under the optional "history" key in transfers.json. With it absent the
/// window says "not configured" — no host names or tool specifics in this repo.
struct TransfersHistorySource: Codable {
    var command: [String]
    var clearCommand: [String]?   // optional argv that prunes the history log; enables the Clean button
}

struct TransfersConfig: Codable {
    var sources: [TransfersSource]
    var pollSeconds: Double?
    var history: TransfersHistorySource?

    static func load() -> TransfersConfig? {
        let path = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".config/server-monitor/transfers.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? JSONDecoder().decode(TransfersConfig.self, from: data)
    }
}

// Decoded directly from the queue tool's `--json` output (raw bytes; we derive the rest).
struct TransfersQueueItem: Codable {
    let id: String
    let source: String
    let dest: String
    let status: String
    let mode: String
    let bytesTransferred: Int64
    let bytesTotal: Int64
    let filesDone: Int
    let filesTotal: Int
    let rateBytesPerSec: Int64
    let currentFile: String
}

struct TransfersQueueSummary: Codable { let running: Int; let pending: Int; let failed: Int }
struct TransfersQueueReport: Codable { let queue: [TransfersQueueItem]; let summary: TransfersQueueSummary }

struct TransferRow: Identifiable {
    let id: String
    let machine: String
    let title: String
    let status: String
    let pctText: String?
    let rateText: String?
    let etaText: String?
    let sortPct: Int
}

@MainActor
final class TransfersMonitor: ObservableObject {
    @Published private(set) var rows: [TransferRow] = []
    @Published private(set) var running = 0
    @Published private(set) var pending = 0
    @Published private(set) var failed = 0
    @Published private(set) var lastError: String?
    let configured: Bool

    private let config: TransfersConfig?
    private var timer: Timer?

    init() {
        self.config = TransfersConfig.load()
        self.configured = (config != nil)
        guard let cfg = config else { return }
        let interval = cfg.pollSeconds ?? 60
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    var headline: String {
        if !configured { return "not configured" }
        if running == 0 && pending == 0 && failed == 0 { return lastError ?? "no transfers" }
        var parts: [String] = []
        if running > 0 { parts.append("\(running) running") }
        if pending > 0 { parts.append("\(pending) pending") }
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.joined(separator: ", ")
    }

    var headlineColor: Color {
        if !configured { return .secondary }
        if failed > 0 { return .orange }
        if running > 0 { return .green }
        return .secondary
    }

    func refresh() {
        guard let cfg = config else { return }
        Task.detached {
            var allRows: [TransferRow] = []
            var r = 0, p = 0, f = 0
            var err: String? = nil
            for src in cfg.sources {
                guard let data = Self.runCommand(src.command),
                      let report = try? JSONDecoder().decode(TransfersQueueReport.self, from: data) else {
                    err = "\u{2018}\(src.label)\u{2019} unreachable"
                    continue
                }
                r += report.summary.running
                p += report.summary.pending
                f += report.summary.failed
                for item in report.queue where item.status == "running" || item.status == "pending" || item.status == "failed" {
                    allRows.append(Self.toRow(item, machine: src.label))
                }
            }
            let rank: [String: Int] = ["running": 0, "pending": 1, "failed": 2]
            allRows.sort {
                let a = rank[$0.status] ?? 9, b = rank[$1.status] ?? 9
                return a != b ? a < b : $0.sortPct > $1.sortPct
            }
            let fRows = allRows, fr = r, fp = p, ff = f, fe = err
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.rows = fRows
                self.running = fr
                self.pending = fp
                self.failed = ff
                self.lastError = fe
            }
        }
    }

    /// True when `machine` has a `runCommand` configured — i.e. its failed rows
    /// can offer a Resume button. Sources without one stay read-only.
    func canResume(machine: String) -> Bool {
        guard let run = config?.sources.first(where: { $0.label == machine })?.runCommand else { return false }
        return !run.isEmpty
    }

    /// Kick off the source's `runCommand` (e.g. reprocess failed/pending) detached,
    /// so it keeps running after the menu closes, then refresh shortly after to
    /// reflect the new state. No-op if the source has no `runCommand`.
    func resume(machine: String) {
        guard let run = config?.sources.first(where: { $0.label == machine })?.runCommand, !run.isEmpty else { return }
        Self.runDetached(run)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.refresh() }
    }

    private nonisolated static func runDetached(_ argv: [String]) {
        guard !argv.isEmpty else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Background + nohup so the transfer outlives the menu/app; argv passed
        // POSITIONALLY so nothing is interpolated into a shell string (no injection).
        p.arguments = ["-lc", "nohup \"$@\" >/dev/null 2>&1 &", "transfers"] + argv
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return }
        // zsh returns immediately after backgrounding; reap it off the main thread.
        Task.detached { p.waitUntilExit() }
    }

    private nonisolated static func runCommand(_ argv: [String]) -> Data? {
        guard !argv.isEmpty else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Login shell for the user's PATH; pass argv POSITIONALLY so nothing is
        // interpolated into a shell string (no injection from config values).
        p.arguments = ["-lc", "exec \"$@\"", "transfers"] + argv
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return data
    }

    private nonisolated static func toRow(_ i: TransfersQueueItem, machine: String) -> TransferRow {
        let title = (i.source as NSString).lastPathComponent
        let pct: Int? = i.bytesTotal > 0
            ? Int((Double(i.bytesTransferred) / Double(i.bytesTotal) * 100).rounded()) : nil
        let isRunning = i.status == "running" && i.rateBytesPerSec > 0
        let rateText: String? = isRunning ? formatRate(i.rateBytesPerSec) : nil
        let etaText: String? = (isRunning && i.bytesTotal > i.bytesTransferred)
            ? "ETA " + formatDuration(Int((i.bytesTotal - i.bytesTransferred) / i.rateBytesPerSec)) : nil
        return TransferRow(
            id: "\(machine):\(i.id)", machine: machine, title: title, status: i.status,
            pctText: pct.map { "\($0)%" }, rateText: rateText, etaText: etaText, sortPct: pct ?? -1
        )
    }

    private nonisolated static func formatRate(_ bps: Int64) -> String {
        let mb = Double(bps) / 1_000_000
        return mb >= 1 ? String(format: "%.1f MB/s", mb) : String(format: "%.0f KB/s", Double(bps) / 1000)
    }

    private nonisolated static func formatDuration(_ s: Int) -> String {
        if s >= 3600 { return "\(s / 3600)h \((s % 3600) / 60)m" }
        if s >= 60 { return "\(s / 60)m" }
        return "\(s)s"
    }
}

// MARK: - Transfer History (secondary window)
//
// Browse the transfer tool's PAST operations from its JSON-lines history log —
// distinct from the live queue above. Useful for spotting failure spikes and
// drilling into a single run. WHAT emits the log is machine-specific and lives
// in untracked transfers.json under the optional "history" key (one JSON object
// per line). This open-source code only runs the configured command and decodes
// generic fields; no host names or tool specifics live here.

/// One past transfer operation, decoded from a single line of the history log.
/// Everything past `id`/`startTime`/`status` is optional so a schema drift or an
/// incomplete (e.g. cancelled) record degrades one cell rather than dropping the
/// whole row.
struct TransferHistoryRecord: Codable, Identifiable {
    let id: String
    let repositories: [String]?
    let sourceMachine: String?
    let targetMachine: String?
    let startTime: String
    let endTime: String?
    let status: String
    let filesTransferred: Int?
    let bytesTransferred: Int64?
    let errors: Int?
}

/// Loads + decodes the history log on demand (it is browsed, not watched, so no
/// polling timer — just an explicit Refresh). Decode + sort happen off the main
/// thread because the log can be tens of thousands of lines.
@MainActor
final class TransferHistoryLoader: ObservableObject {
    @Published private(set) var records: [TransferHistoryRecord] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    let configured: Bool

    private let command: [String]?
    private let clearCommand: [String]?

    /// True when a `history.clearCommand` is configured — enables the Clean button.
    var canClear: Bool { clearCommand?.isEmpty == false }

    init() {
        let history = TransfersConfig.load()?.history
        self.command = history?.command
        self.clearCommand = history?.clearCommand
        self.configured = (command?.isEmpty == false)
    }

    /// Run the configured prune command (e.g. drop FAILED entries from the log),
    /// then reload. The app only runs the argv you configure — what "clean" means
    /// is yours to define; it never edits a history store it wasn't told about.
    func clear() {
        guard let cmd = clearCommand, !cmd.isEmpty, !loading else { return }
        loading = true
        error = nil
        Task.detached {
            _ = Self.runArgv(cmd)
            await MainActor.run { [weak self] in
                self?.loading = false
                self?.reload()
            }
        }
    }

    func reload() {
        guard let cmd = command, !cmd.isEmpty else { return }
        loading = true
        error = nil
        Task.detached {
            let result = Self.loadRecords(cmd)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.loading = false
                self.records = result.records
                if let e = result.error {
                    self.error = e
                } else {
                    self.error = result.records.isEmpty ? "no history records" : nil
                }
            }
        }
    }

    private nonisolated static func loadRecords(_ argv: [String]) -> (records: [TransferHistoryRecord], error: String?) {
        guard let data = runArgv(argv) else { return ([], "history command failed to run") }
        guard let text = String(data: data, encoding: .utf8) else { return ([], "history output was not UTF-8") }
        let dec = JSONDecoder()
        var out: [TransferHistoryRecord] = []
        out.reserveCapacity(4096)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            // tolerate junk/partial lines — skip what doesn't decode rather than failing the load
            guard let rec = try? dec.decode(TransferHistoryRecord.self, from: Data(line.utf8)) else { continue }
            out.append(rec)
        }
        // newest first; parse each timestamp once (decorate-sort), unparseable sink to the bottom
        let sorted = out
            .map { (rec: $0, t: TransferHistoryDates.parse($0.startTime) ?? .distantPast) }
            .sorted { $0.t > $1.t }
            .map { $0.rec }
        return (sorted, nil)
    }

    /// Run argv POSITIONALLY via a login shell (user PATH) — nothing is
    /// interpolated into the shell string, so config values can't inject.
    private nonisolated static func runArgv(_ argv: [String]) -> Data? {
        guard !argv.isEmpty else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "exec \"$@\"", "history"] + argv
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return data
    }
}

/// ISO8601 parsing that tolerates any sub-second precision. The log writes
/// microseconds (e.g. `…55.705754Z`), which `ISO8601DateFormatter`'s fractional
/// mode rejects, so we strip the fractional part and parse to whole seconds —
/// ample for display + sort.
enum TransferHistoryDates {
    private static let fmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        let cleaned = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return fmt.date(from: cleaned)
    }
}
