import Darwin
import Foundation
import SwiftUI

// MARK: - Manager backend (dual-pane cross-machine file manager)
//
// The "Files" tab browses directories on each configured machine and transfers
// between them. WHAT lists a remote dir and WHAT performs a transfer is machine-
// specific and lives ONLY in untracked ~/.config/server-monitor/transfers.json
// under the "manager" key (machine ssh targets + a transferCommand argv). This
// open-source code only runs the configured argv, or a generic `ls` against an
// ssh target supplied by config, substituting values per-element (never into a
// shell string, so paths with spaces or metacharacters can't inject). With no
// "manager" config the surface is inert. No host names or tool specifics here.
//
// Transfers stream to a per-operation log you can live-tail in the Logs tab, and
// retry with BOUNDED exponential backoff so the app can never become a runaway
// loop.

// MARK: - Config

struct ManagerMachine: Codable, Identifiable, Hashable {
    var label: String
    var local: Bool?
    var ssh: String?            // user@host for remote machines; nil when local
    var sshFallbacks: [String]? // ordered alternatives tried after ssh
    var start: String?          // initial directory
    var id: String { label }
    var isLocal: Bool { local == true }
    var startPath: String { start ?? (isLocal ? NSHomeDirectory() : "/") }
    var sshTargets: [String] {
        var targets: [String] = []
        for target in [ssh].compactMap({ $0 }) + (sshFallbacks ?? []) {
            if !target.isEmpty && !targets.contains(target) { targets.append(target) }
        }
        return targets
    }
}

struct ManagerConfig: Codable {
    var machines: [ManagerMachine]?
    var transferCommand: [String]?   // argv with {mode}/{srcMachine}/{srcPath}/{dstMachine}/{dstPath}
    var moveEnabled: Bool?
    var chickletsPath: String?
    var logDir: String?
    var maxAttempts: Int?
    var backoffBaseSeconds: Double?

    static func load() -> ManagerConfig? {
        let path = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".config/server-monitor/transfers.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        struct Wrapper: Codable { var manager: ManagerConfig? }
        return (try? JSONDecoder().decode(Wrapper.self, from: data))?.manager
    }
}

// MARK: - Directory entries + listing

struct DirEntry: Identifiable, Hashable {
    let name: String
    let isDir: Bool
    let size: Int64?
    let path: String            // full absolute path on its machine
    var id: String { path }
}

enum ListError: Error, LocalizedError {
    case unreachable(String)
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .unreachable(let m): return "\(m) is unreachable"
        case .failed(let s): return s
        }
    }
}

/// Lists a directory on a machine. Local machines use FileManager; remote ones
/// run `ls -lAp` over ssh (the ssh target comes from config, the command does
/// not). Dotfiles are hidden, matching Finder.
enum DirectoryLister {
    static func list(machine: ManagerMachine, path: String) async throws -> [DirEntry] {
        if machine.isLocal { return try listLocal(path: path) }
        let targets = machine.sshTargets
        guard !targets.isEmpty else {
            throw ListError.failed("no ssh target configured for \(machine.label)")
        }
        return try await listRemote(targets: targets, machineLabel: machine.label, path: path)
    }

    private static func listLocal(path: String) throws -> [DirEntry] {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let contents = try fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles])
        var out: [DirEntry] = []
        for u in contents {
            let vals = try? u.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDir = vals?.isDirectory ?? false
            out.append(DirEntry(name: u.lastPathComponent, isDir: isDir,
                                size: isDir ? nil : vals?.fileSize.map(Int64.init), path: u.path))
        }
        return sortEntries(out)
    }

    private static func listRemote(targets: [String], machineLabel: String, path: String) async throws -> [DirEntry] {
        let remote = "cd -- \(shQuote(path)) && /bin/ls -lAp"
        for target in targets {
            let r = await run(["/usr/bin/ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", target, remote])
            if r.status == 255 { continue }
            if r.status != 0 {
                let msg = r.err.trimmingCharacters(in: .whitespacesAndNewlines)
                throw ListError.failed(msg.isEmpty ? "ls exited \(r.status)" : msg)
            }
            return sortEntries(parseLS(r.out, parent: path))
        }
        throw ListError.unreachable(machineLabel)
    }

    // MARK: helpers

    private static func sortEntries(_ e: [DirEntry]) -> [DirEntry] {
        e.sorted { a, b in
            if a.isDir != b.isDir { return a.isDir }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// Parse BSD `ls -lAp`. Skips the "total" line and dotfiles; a leading 'd'
    /// perm (or a trailing slash) marks a directory; the name is everything after
    /// the 8th whitespace field (preserving spaces), with " -> target" stripped.
    private static func parseLS(_ text: String, parent: String) -> [DirEntry] {
        var out: [DirEntry] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            if line.hasPrefix("total ") { continue }
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard let perms = fields.first.map(String.init), !perms.isEmpty else { continue }
            guard var name = nameAfterFields(line, count: 8), !name.isEmpty else { continue }
            if perms.hasPrefix("l"), let r = name.range(of: " -> ") { name = String(name[..<r.lowerBound]) }
            var isDir = perms.hasPrefix("d")
            if name.hasSuffix("/") { isDir = true; name.removeLast() }
            if name.hasPrefix(".") || name == "." || name == ".." { continue }
            let size = fields.count > 4 ? Int64(fields[4]) : nil
            let full = (parent as NSString).appendingPathComponent(name)
            out.append(DirEntry(name: name, isDir: isDir, size: isDir ? nil : size, path: full))
        }
        return out
    }

    /// Substring after the first `count` whitespace-delimited fields, verbatim,
    /// so names containing spaces survive intact.
    private static func nameAfterFields(_ line: String, count: Int) -> String? {
        var idx = line.startIndex
        var fields = 0
        let end = line.endIndex
        while idx < end {
            while idx < end, line[idx] == " " { idx = line.index(after: idx) }
            if idx >= end { break }
            if fields == count { return String(line[idx...]) }
            while idx < end, line[idx] != " " { idx = line.index(after: idx) }
            fields += 1
        }
        return nil
    }

    private static func shQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func run(_ argv: [String]) async -> (status: Int32, out: String, err: String) {
        await Task.detached {
            let result = ProcessRunner.run(argv, timeout: 30)
            return (result.status, result.output, result.output)
        }.value
    }
}

// MARK: - Chicklets (pinned root shortcuts, mirrored on both panes)

struct Chicklet: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var machine: String
    var path: String
}

@MainActor
final class ChickletStore: ObservableObject {
    @Published private(set) var items: [Chicklet] = []
    private let path: String?

    init(path: String?) {
        self.path = path.map { ($0 as NSString).expandingTildeInPath }
        load()
    }

    func load() {
        guard let path, let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let list = try? JSONDecoder().decode([Chicklet].self, from: data) else { return }
        items = list
    }

    func add(label: String, machine: String, path dirPath: String) {
        let id = "\(machine):\(dirPath)"
        guard !items.contains(where: { $0.id == id }) else { return }
        items.append(Chicklet(id: id, label: label, machine: machine, path: dirPath))
        save()
    }

    func remove(_ c: Chicklet) {
        items.removeAll { $0.id == c.id }
        save()
    }

    private func save() {
        guard let path else { return }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
        guard let data = try? enc.encode(items) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - Transfer operations engine (Logs tab)

enum TransferMode: String { case copy = "Copy", move = "Move" }
enum TransferState { case running, retrying, succeeded, failed, stopped }

struct TransferOperation: Identifiable {
    let id: String
    let title: String           // source basename, for display
    let src: String             // "machine:path"
    let dst: String             // "machine:path"
    let mode: TransferMode
    let logPath: String
    let startedAt: Date
    var state: TransferState
    var attempt: Int
    let maxAttempts: Int
    var nextRetryAt: Date?

    var routeText: String { "\(src) → \(dst)" }
}

private struct TransferArgs {
    let mode: TransferMode
    let srcMachine: String
    let srcPath: String
    let dstMachine: String
    let dstPath: String
}

@MainActor
final class TransferActionsModel: ObservableObject {
    /// Newest first; active ops sit at the top.
    @Published private(set) var operations: [TransferOperation] = []

    let configured: Bool
    let canMove: Bool
    let machines: [ManagerMachine]
    let chickletsPath: String?
    let maxAttempts: Int

    private let config: ManagerConfig?
    private let backoffBase: Double
    private var seq = 0
    private var retryTimers: [String: Timer] = [:]
    private var runningProcesses: [String: Process] = [:]
    /// Per-op argument tuple so retries rebuild the command without re-deriving it.
    private var opArgs: [String: TransferArgs] = [:]

    init() {
        let cfg = ManagerConfig.load()
        self.config = cfg
        self.configured = (cfg?.transferCommand?.isEmpty == false) && (cfg?.machines?.isEmpty == false)
        self.canMove = (cfg?.moveEnabled == true)
        self.machines = cfg?.machines ?? []
        self.chickletsPath = cfg?.chickletsPath
        self.maxAttempts = max(1, cfg?.maxAttempts ?? 5)
        self.backoffBase = max(0.5, cfg?.backoffBaseSeconds ?? 2)
    }

    var activeCount: Int {
        operations.filter { $0.state == .running || $0.state == .retrying }.count
    }

    var failedCount: Int {
        operations.filter { $0.state == .failed }.count
    }

    var needsAttention: Bool { failedCount > 0 }

    /// True when `mode` is available (Copy always; Move only if enabled).
    func supports(_ mode: TransferMode) -> Bool { mode == .copy || canMove }

    /// Launch a transfer of a file/folder from one machine to another (attempt 1).
    func startTransfer(name: String, srcMachine: String, srcPath: String,
                       dstMachine: String, dstPath: String, mode: TransferMode) {
        guard let tmpl = config?.transferCommand, !tmpl.isEmpty else { return }
        seq += 1
        let id = "op-\(seq)-\(Int(Date().timeIntervalSince1970))"
        let logPath = Self.logFile(dir: config?.logDir, id: id, title: name)
        opArgs[id] = TransferArgs(mode: mode, srcMachine: srcMachine, srcPath: srcPath,
                                  dstMachine: dstMachine, dstPath: dstPath)
        let op = TransferOperation(id: id, title: name,
                                   src: "\(srcMachine):\(srcPath)", dst: "\(dstMachine):\(dstPath)",
                                   mode: mode, logPath: logPath, startedAt: Date(), state: .running,
                                   attempt: 0, maxAttempts: maxAttempts, nextRetryAt: nil)
        operations.insert(op, at: 0)
        runAttempt(id)
    }

    func retryNow(_ id: String) {
        cancelTimer(id)
        guard let op = operations.first(where: { $0.id == id }), op.state == .retrying else { return }
        runAttempt(id)
    }

    func stop(_ id: String) {
        cancelTimer(id)
        update(id) { $0.state = .stopped; $0.nextRetryAt = nil }
        if let process = runningProcesses[id], process.isRunning {
            let pid = process.processIdentifier
            process.terminate()
            Task.detached {
                try? await Task.sleep(for: .seconds(2))
                if process.isRunning { Darwin.kill(pid, SIGKILL) }
            }
        }
    }

    func retry(_ id: String) {
        cancelTimer(id)
        guard runningProcesses[id] == nil else { return }
        guard let op = operations.first(where: { $0.id == id }) else { return }
        guard op.state == .failed || op.state == .stopped else { return }
        update(id) { $0.attempt = 0; $0.state = .running; $0.nextRetryAt = nil }
        runAttempt(id)
    }

    func clearFinished() {
        for op in operations where op.state == .succeeded || op.state == .failed || op.state == .stopped {
            opArgs[op.id] = nil
        }
        operations.removeAll { $0.state == .succeeded || $0.state == .failed || $0.state == .stopped }
    }

    // MARK: attempt loop

    private func runAttempt(_ id: String) {
        guard let op = operations.first(where: { $0.id == id }), let a = opArgs[id],
              let tmpl = config?.transferCommand, !tmpl.isEmpty,
              runningProcesses[id] == nil else { return }
        let attempt = op.attempt + 1
        update(id) { $0.state = .running; $0.attempt = attempt; $0.nextRetryAt = nil }

        let argv = tmpl.map { Self.fill($0, a) }
        let header = "── \(op.mode.rawValue) attempt \(attempt)/\(op.maxAttempts)  \(op.src) → \(op.dst)\n$ \(argv.joined(separator: " "))\n\n"
        guard let running = Self.startToLog(argv: argv, logPath: op.logPath, header: header) else {
            completed(id, ok: false)
            return
        }
        runningProcesses[id] = running.process
        Task { [weak self] in
            let status = await Task.detached {
                running.process.waitUntilExit()
                let status = running.process.terminationStatus
                Self.finishLog(handle: running.handle, status: status)
                return status
            }.value
            guard let self else { return }
            self.runningProcesses[id] = nil
            self.completed(id, ok: status == 0)
        }
    }

    private func completed(_ id: String, ok: Bool) {
        guard let op = operations.first(where: { $0.id == id }) else { return }
        if ok { update(id) { $0.state = .succeeded; $0.nextRetryAt = nil }; return }
        if op.state == .stopped { return }
        guard op.attempt < op.maxAttempts else {
            update(id) { $0.state = .failed; $0.nextRetryAt = nil }
            Self.appendLine(op.logPath, "— gave up after \(op.attempt) attempts —")
            return
        }
        let delay = backoffBase * pow(2, Double(op.attempt - 1))
        let fireAt = Date().addingTimeInterval(delay)
        update(id) { $0.state = .retrying; $0.nextRetryAt = fireAt }
        Self.appendLine(op.logPath, "— attempt \(op.attempt) failed; retrying in \(Int(delay))s —")
        let t = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.fireRetry(id) }
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

    // MARK: shell + files

    private nonisolated static func fill(_ s: String, _ a: TransferArgs) -> String {
        s.replacingOccurrences(of: "{mode}", with: a.mode == .move ? "move" : "copy")
            .replacingOccurrences(of: "{srcMachine}", with: a.srcMachine)
            .replacingOccurrences(of: "{srcPath}", with: a.srcPath)
            .replacingOccurrences(of: "{dstMachine}", with: a.dstMachine)
            .replacingOccurrences(of: "{dstPath}", with: a.dstPath)
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

    /// Start argv directly (no shell), streaming stdout+stderr into `logPath`.
    /// The caller retains the Process so Stop can terminate the active attempt.
    private nonisolated static func startToLog(
        argv: [String], logPath: String, header: String
    ) -> (process: Process, handle: FileHandle)? {
        guard !argv.isEmpty else { return nil }
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: logPath) else { return nil }
        handle.seekToEndOfFile()
        handle.write(Data(header.utf8))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = argv
        var environment = ProcessInfo.processInfo.environment
        let fallback = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = [environment["PATH"], fallback].compactMap { $0 }.joined(separator: ":")
        p.environment = environment
        p.standardOutput = handle
        p.standardError = handle
        do { try p.run() } catch {
            try? handle.write(contentsOf: Data("\nspawn failed: \(error.localizedDescription)\n".utf8))
            try? handle.close()
            return nil
        }
        return (p, handle)
    }

    private nonisolated static func finishLog(handle: FileHandle, status: Int32) {
        try? handle.write(contentsOf: Data("\n— exit \(status) —\n".utf8))
        try? handle.close()
    }

    private nonisolated static func appendLine(_ path: String, _ line: String) {
        guard let h = FileHandle(forWritingAtPath: path) else { return }
        h.seekToEndOfFile()
        try? h.write(contentsOf: Data((line + "\n").utf8))
        try? h.close()
    }

    /// Tail of a log file for the live viewer — last `maxBytes`.
    nonisolated static func tail(_ path: String, maxBytes: UInt64 = 64_000) -> String {
        guard let fh = FileHandle(forReadingAtPath: path) else { return "" }
        defer { try? fh.close() }
        guard let end = try? fh.seekToEnd() else { return "" }
        try? fh.seek(toOffset: end > maxBytes ? end - maxBytes : 0)
        let data = (try? fh.readToEnd()) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
