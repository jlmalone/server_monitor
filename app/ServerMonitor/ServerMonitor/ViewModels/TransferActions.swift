import Foundation
import SwiftUI

// MARK: - Transfer actions (drag-and-drop between machines)
//
// Lets you drag a title from the Transfer History onto another machine to copy
// or move it there. WHAT actually performs the transfer is machine-specific and
// lives ONLY in untracked ~/.config/server-monitor/transfers.json under the
// optional "transfer" key — this open-source code just substitutes {title},
// {src}, {dst} into the configured argv and runs it, capturing every byte of
// output to a per-operation log you can inspect live. No host names or tool
// specifics here. With no "transfer" config the drag-and-drop surface is inert.
//
// Retries are BOUNDED: a failed transfer backs off exponentially up to
// maxAttempts and then stops — the app can never become a runaway retry loop.
// You can always skip the wait (Retry Now) or abandon it (Stop).

enum TransferMode: String { case copy = "Copy", move = "Move" }
enum TransferState { case running, retrying, succeeded, failed, stopped }

/// Command templates, machine list, and retry policy for the drag-and-drop
/// surface. `copyCommand` / `moveCommand` are argv with `{title}` / `{src}` /
/// `{dst}` placeholders the app fills in (substituted into single argv elements —
/// never concatenated into a shell string, so titles with spaces or
/// metacharacters can't inject).
struct TransferActionsConfig: Codable {
    var machines: [String]?         // explicit drop targets; else derived from history
    var copyCommand: [String]?      // e.g. ["your-transfer-cli","send","{title}","{dst}:/inbox/"]
    var moveCommand: [String]?      // adds delete-after; Move is disabled if omitted
    var describeCommand: [String]?  // optional: prints {"files":N,"folders":M} for exact counts
    var logDir: String?             // where per-op logs are written; defaults under ~/.config
    var maxAttempts: Int?           // total tries incl. the first (default 5; clamped ≥ 1)
    var backoffBaseSeconds: Double? // first retry delay, doubling each time (default 2)

    static func load() -> TransferActionsConfig? {
        let path = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".config/server-monitor/transfers.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        struct Wrapper: Codable { var transfer: TransferActionsConfig? }
        return (try? JSONDecoder().decode(Wrapper.self, from: data))?.transfer
    }
}

/// One launched transfer: its identity, route, the log file collecting every
/// attempt's output, and its live retry state.
struct TransferOperation: Identifiable {
    let id: String
    let title: String
    let src: String
    let dst: String
    let mode: TransferMode
    let logPath: String
    let startedAt: Date
    var state: TransferState
    var attempt: Int            // 1-based; how many tries have run
    let maxAttempts: Int
    var nextRetryAt: Date?      // when the backoff timer will fire (for the countdown)

    var routeText: String { "\(src) → \(dst)" }
}

/// Exact composition of a draggable item, when a `describeCommand` can supply it.
struct TransferDescription: Codable { let files: Int?; let folders: Int? }

@MainActor
final class TransferActionsModel: ObservableObject {
    /// Newest first; active ops sit at the top.
    @Published private(set) var operations: [TransferOperation] = []

    let configured: Bool
    let canMove: Bool
    let configuredMachines: [String]
    let maxAttempts: Int

    private let config: TransferActionsConfig?
    private let backoffBase: Double
    private var seq = 0
    private var retryTimers: [String: Timer] = [:]

    init() {
        self.config = TransferActionsConfig.load()
        self.configured = (config?.copyCommand?.isEmpty == false)
        self.canMove = (config?.moveCommand?.isEmpty == false)
        self.configuredMachines = config?.machines ?? []
        self.maxAttempts = max(1, config?.maxAttempts ?? 5)
        self.backoffBase = max(0.5, config?.backoffBaseSeconds ?? 2)
    }

    /// True when `mode` has a command configured (Copy always; Move only if set).
    func supports(_ mode: TransferMode) -> Bool { template(for: mode)?.isEmpty == false }

    /// Optional exact files/folders breakdown via `describeCommand`. Returns nil
    /// when unconfigured or on any failure — callers fall back to the counts the
    /// dragged history row already carries.
    func describe(title: String, src: String) async -> TransferDescription? {
        guard let tmpl = config?.describeCommand, !tmpl.isEmpty else { return nil }
        let argv = tmpl.map { Self.fill($0, title: title, src: src, dst: "") }
        return await Task.detached {
            let r = Self.run(argv)
            guard r.status == 0, let data = r.output.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(TransferDescription.self, from: data)
        }.value
    }

    /// Launch a transfer (attempt 1). Output streams to a fresh per-op log; on
    /// failure it auto-retries with exponential backoff up to `maxAttempts`.
    func start(title: String, src: String, dst: String, mode: TransferMode) {
        guard let tmpl = template(for: mode), !tmpl.isEmpty, src != dst else { return }
        seq += 1
        let id = "op-\(seq)-\(Int(Date().timeIntervalSince1970))"
        let logPath = Self.logFile(dir: config?.logDir, id: id, title: title)
        let op = TransferOperation(id: id, title: title, src: src, dst: dst, mode: mode,
                                   logPath: logPath, startedAt: Date(), state: .running,
                                   attempt: 0, maxAttempts: maxAttempts, nextRetryAt: nil)
        operations.insert(op, at: 0)
        runAttempt(id)
    }

    /// Skip the backoff wait and try again immediately.
    func retryNow(_ id: String) {
        cancelTimer(id)
        guard let op = operations.first(where: { $0.id == id }), op.state == .retrying else { return }
        runAttempt(id)
    }

    /// Give up: cancel any pending retry and mark the op stopped.
    func stop(_ id: String) {
        cancelTimer(id)
        update(id) { $0.state = .stopped; $0.nextRetryAt = nil }
    }

    /// Restart a finished (failed/stopped) op from a clean attempt count.
    func retry(_ id: String) {
        cancelTimer(id)
        guard let op = operations.first(where: { $0.id == id }) else { return }
        guard op.state == .failed || op.state == .stopped else { return }
        update(id) { $0.attempt = 0; $0.state = .running; $0.nextRetryAt = nil }
        runAttempt(id)
    }

    /// Drop finished ops (succeeded/failed/stopped) from the list; running and
    /// retrying ops are kept. Their log files are left on disk for inspection.
    func clearFinished() {
        operations.removeAll { $0.state == .succeeded || $0.state == .failed || $0.state == .stopped }
    }

    // MARK: - attempt loop

    private func runAttempt(_ id: String) {
        guard let op = operations.first(where: { $0.id == id }) else { return }
        guard let tmpl = template(for: op.mode), !tmpl.isEmpty else { return }
        let attempt = op.attempt + 1
        update(id) { $0.state = .running; $0.attempt = attempt; $0.nextRetryAt = nil }

        let argv = tmpl.map { Self.fill($0, title: op.title, src: op.src, dst: op.dst) }
        let header = "── \(op.mode.rawValue) attempt \(attempt)/\(op.maxAttempts)  \(op.src) → \(op.dst)\n$ \(argv.joined(separator: " "))\n\n"
        Task.detached {
            let ok = Self.runToLog(argv: argv, logPath: op.logPath, header: header)
            await MainActor.run { self.completed(id, ok: ok) }
        }
    }

    private func completed(_ id: String, ok: Bool) {
        guard let op = operations.first(where: { $0.id == id }) else { return }
        if ok { update(id) { $0.state = .succeeded; $0.nextRetryAt = nil }; return }
        if op.state == .stopped { return }                       // user abandoned mid-attempt
        guard op.attempt < op.maxAttempts else {                 // bounded — give up cleanly
            update(id) { $0.state = .failed; $0.nextRetryAt = nil }
            Self.appendLine(op.logPath, "— gave up after \(op.attempt) attempts —")
            return
        }
        let delay = backoffBase * pow(2, Double(op.attempt - 1))  // 2, 4, 8, 16 … seconds
        let fireAt = Date().addingTimeInterval(delay)
        update(id) { $0.state = .retrying; $0.nextRetryAt = fireAt }
        Self.appendLine(op.logPath, "— attempt \(op.attempt) failed; retrying in \(Int(delay))s —")
        let t = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fireRetry(id) }
        }
        retryTimers[id] = t
    }

    private func fireRetry(_ id: String) {
        retryTimers[id] = nil
        guard let op = operations.first(where: { $0.id == id }), op.state == .retrying else { return }
        runAttempt(id)
    }

    private func cancelTimer(_ id: String) { retryTimers[id]?.invalidate(); retryTimers[id] = nil }

    private func update(_ id: String, _ change: (inout TransferOperation) -> Void) {
        guard let i = operations.firstIndex(where: { $0.id == id }) else { return }
        change(&operations[i])
    }

    private func template(for mode: TransferMode) -> [String]? {
        mode == .move ? config?.moveCommand : config?.copyCommand
    }

    // MARK: - shell + files

    /// Substitute placeholders into one argv element. Done per-element so values
    /// are never concatenated into a shell string (no injection surface).
    private nonisolated static func fill(_ s: String, title: String, src: String, dst: String) -> String {
        s.replacingOccurrences(of: "{title}", with: title)
            .replacingOccurrences(of: "{src}", with: src)
            .replacingOccurrences(of: "{dst}", with: dst)
    }

    private nonisolated static func logDirURL(_ configured: String?) -> URL {
        let base = configured.map { ($0 as NSString).expandingTildeInPath }
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".config/server-monitor/transfer-logs")
        let url = URL(fileURLWithPath: base, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private nonisolated static func logFile(dir: String?, id: String, title: String) -> String {
        let safe = title.replacingOccurrences(of: "/", with: "_")
            .prefix(60).replacingOccurrences(of: " ", with: "_")
        return logDirURL(dir).appendingPathComponent("\(id)-\(safe).log").path
    }

    /// Run argv via a login shell (positional `exec "$@"` — no interpolation),
    /// appending stdout+stderr into `logPath`. Returns true on exit code 0.
    private nonisolated static func runToLog(argv: [String], logPath: String, header: String) -> Bool {
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: logPath) else { return false }
        handle.seekToEndOfFile()
        handle.write(Data(header.utf8))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "exec \"$@\"", "transfer"] + argv
        p.standardOutput = handle
        p.standardError = handle
        do { try p.run() } catch {
            try? handle.write(contentsOf: Data("\nspawn failed: \(error.localizedDescription)\n".utf8))
            try? handle.close()
            return false
        }
        p.waitUntilExit()
        try? handle.write(contentsOf: Data("\n— exit \(p.terminationStatus) —\n".utf8))
        try? handle.close()
        return p.terminationStatus == 0
    }

    private nonisolated static func appendLine(_ path: String, _ line: String) {
        guard let h = FileHandle(forWritingAtPath: path) else { return }
        h.seekToEndOfFile()
        try? h.write(contentsOf: Data((line + "\n").utf8))
        try? h.close()
    }

    private nonisolated static func run(_ argv: [String]) -> (status: Int32, output: String) {
        guard !argv.isEmpty else { return (1, "") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "exec \"$@\"", "transfer"] + argv
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return (127, "") }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    /// Tail of a log file for the live viewer — last `maxBytes` so a chatty
    /// transfer log stays cheap to render.
    nonisolated static func tail(_ path: String, maxBytes: UInt64 = 64_000) -> String {
        guard let fh = FileHandle(forReadingAtPath: path) else { return "" }
        defer { try? fh.close() }
        guard let end = try? fh.seekToEnd() else { return "" }
        try? fh.seek(toOffset: end > maxBytes ? end - maxBytes : 0)
        let data = (try? fh.readToEnd()) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
