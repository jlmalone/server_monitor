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

enum TransferMode: String { case copy = "Copy", move = "Move" }
enum TransferState { case running, succeeded, failed }

/// Command templates + machine list for the drag-and-drop surface. `copyCommand`
/// / `moveCommand` are argv with `{title}` / `{src}` / `{dst}` placeholders the
/// app fills in (substituted into single argv elements — never concatenated into
/// a shell string, so titles with spaces or metacharacters can't inject).
struct TransferActionsConfig: Codable {
    var machines: [String]?         // explicit drop targets; else derived from history
    var copyCommand: [String]?      // e.g. ["your-transfer-cli","send","{title}","{dst}:/inbox/"]
    var moveCommand: [String]?      // adds delete-after; Move is disabled if omitted
    var describeCommand: [String]?  // optional: prints {"files":N,"folders":M} for exact counts
    var logDir: String?             // where per-op logs are written; defaults under ~/.config

    static func load() -> TransferActionsConfig? {
        let path = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".config/server-monitor/transfers.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        struct Wrapper: Codable { var transfer: TransferActionsConfig? }
        return (try? JSONDecoder().decode(Wrapper.self, from: data))?.transfer
    }
}

/// One launched transfer: its identity, route, the log file collecting its
/// output, and its live status.
struct TransferOperation: Identifiable {
    let id: String
    let title: String
    let src: String
    let dst: String
    let mode: TransferMode
    let logPath: String
    let startedAt: Date
    var state: TransferState

    var routeText: String { "\(src) → \(dst)" }
}

/// Exact composition of a draggable item, when a `describeCommand` can supply it.
struct TransferDescription: Codable { let files: Int?; let folders: Int? }

@MainActor
final class TransferActionsModel: ObservableObject {
    /// Newest first; running ops sit at the top.
    @Published private(set) var operations: [TransferOperation] = []

    let configured: Bool
    let canMove: Bool
    let configuredMachines: [String]

    private let config: TransferActionsConfig?
    private var seq = 0

    init() {
        self.config = TransferActionsConfig.load()
        self.configured = (config?.copyCommand?.isEmpty == false)
        self.canMove = (config?.moveCommand?.isEmpty == false)
        self.configuredMachines = config?.machines ?? []
    }

    /// True when `mode` has a command configured (Copy always; Move only if set).
    func supports(_ mode: TransferMode) -> Bool {
        template(for: mode)?.isEmpty == false
    }

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

    /// Launch a transfer: fill the template, capture combined output to a fresh
    /// per-op log, and track its exit status. The child runs under the app (a
    /// long-lived menu-bar agent); for fire-and-forget that outlives the app,
    /// configure a queue-based command and watch the Transfers panel instead.
    func start(title: String, src: String, dst: String, mode: TransferMode) {
        guard let tmpl = template(for: mode), !tmpl.isEmpty, src != dst else { return }
        seq += 1
        let id = "op-\(seq)-\(Int(Date().timeIntervalSince1970))"
        let argv = tmpl.map { Self.fill($0, title: title, src: src, dst: dst) }
        let logPath = Self.logFile(dir: config?.logDir, id: id, title: title)
        let op = TransferOperation(id: id, title: title, src: src, dst: dst, mode: mode,
                                   logPath: logPath, startedAt: Date(), state: .running)
        operations.insert(op, at: 0)

        let header = "\(mode.rawValue)  \(src) → \(dst)\n$ \(argv.joined(separator: " "))\n\n"
        Task.detached {
            let ok = Self.runToLog(argv: argv, logPath: logPath, header: header)
            await MainActor.run { self.finish(id: id, ok: ok) }
        }
    }

    private func finish(id: String, ok: Bool) {
        guard let i = operations.firstIndex(where: { $0.id == id }) else { return }
        operations[i].state = ok ? .succeeded : .failed
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
    /// streaming stdout+stderr into `logPath`. Returns true on exit code 0.
    private nonisolated static func runToLog(argv: [String], logPath: String, header: String) -> Bool {
        FileManager.default.createFile(atPath: logPath, contents: header.data(using: .utf8))
        guard let handle = FileHandle(forWritingAtPath: logPath) else { return false }
        handle.seekToEndOfFile()
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
        let footer = "\n— exit \(p.terminationStatus) —\n"
        try? handle.write(contentsOf: Data(footer.utf8))
        try? handle.close()
        return p.terminationStatus == 0
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
