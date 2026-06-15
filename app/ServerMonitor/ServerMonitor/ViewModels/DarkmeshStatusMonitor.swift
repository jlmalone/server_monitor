import Foundation
import SwiftUI

/// Observable that mirrors `/tmp/darkmesh-status.json` for the menu-bar UI.
///
/// The source of truth is `darkmesh-healthcheck` (a LaunchAgent in the
/// darkmesh-vpn-guard project). This class is a read-only consumer: it polls
/// the JSON file every `pollInterval` seconds and republishes the latest
/// status to SwiftUI views.
///
/// No network policy is implemented here. If the file doesn't exist, `status`
/// stays nil and the UI should render a "darkmesh not installed" hint.
@MainActor
final class DarkmeshStatusMonitor: ObservableObject {
    @Published private(set) var status: DarkmeshStatus?
    @Published private(set) var lastReadAt: Date?
    @Published private(set) var fileMissing: Bool = false
    @Published private(set) var parseError: String?

    private let statusFileURL = URL(fileURLWithPath: "/tmp/darkmesh-status.json")
    private let pollInterval: TimeInterval
    private var timer: Timer?
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    init(pollInterval: TimeInterval = 5) {
        self.pollInterval = pollInterval
        readNow()
        start()
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.readNow() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func readNow() {
        guard FileManager.default.fileExists(atPath: statusFileURL.path) else {
            fileMissing = true
            status = nil
            return
        }
        fileMissing = false

        do {
            let data = try Data(contentsOf: statusFileURL)
            let decoded = try decoder.decode(DarkmeshStatus.self, from: data)
            status = decoded
            lastReadAt = Date()
            parseError = nil
        } catch {
            parseError = String(describing: error)
        }
    }
}

// MARK: - Protection integrity
//
// Continuously verifies the machine's fail-closed invariants and offers a
// one-click Repair. WHAT each invariant is — which launchd labels, which
// control binaries, which fail-closed doctor — is machine-specific and lives
// ONLY in untracked ~/.config/server-monitor/protection.json (schema in
// config/protection.example.json). This open-source code just runs the
// configured argv and reads the exit code (0 = OK, nonzero = AT RISK); no host
// names or tool specifics here. With no config the panel is inert.

/// One fail-closed invariant: a labeled check command plus an optional repair
/// command that re-arms it.
struct ProtectionCheck: Codable {
    var id: String
    var label: String
    var check: [String]    // argv; exit 0 = OK, nonzero = AT RISK
    var repair: [String]?  // argv to re-arm; nil/empty = no one-click fix
    var note: String?      // optional hint shown when failing, e.g. "needs admin"
}

struct ProtectionConfig: Codable {
    var pollSeconds: Double?
    var checks: [ProtectionCheck]

    static func load() -> ProtectionConfig? {
        let path = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".config/server-monitor/protection.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? JSONDecoder().decode(ProtectionConfig.self, from: data)
    }
}

struct ProtectionResult: Identifiable {
    let id: String
    let label: String
    let ok: Bool
    let repairable: Bool
    let note: String?
}

@MainActor
final class ProtectionMonitor: ObservableObject {
    @Published private(set) var results: [ProtectionResult] = []
    @Published private(set) var repairing = false
    @Published private(set) var lastRepairOutput: String?
    let configured: Bool

    private let config: ProtectionConfig?
    private var timer: Timer?

    init(pollInterval: TimeInterval = 10) {
        self.config = ProtectionConfig.load()
        self.configured = (config != nil)
        guard let cfg = config else { return }
        let interval = cfg.pollSeconds ?? pollInterval
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    var hasResults: Bool { !results.isEmpty }
    var failing: [ProtectionResult] { results.filter { !$0.ok } }
    var atRisk: Bool { results.contains { !$0.ok } }

    var badgeText: String {
        if !configured { return "—" }
        if results.isEmpty { return "…" }
        return atRisk ? "AT RISK" : "OK"
    }

    var badgeColor: Color {
        if !configured || results.isEmpty { return .secondary }
        return atRisk ? .red : .green
    }

    func refresh() {
        guard let cfg = config, !repairing else { return }
        Task.detached {
            var out: [ProtectionResult] = []
            for c in cfg.checks {
                let ok = Self.runArgv(c.check).status == 0
                out.append(ProtectionResult(id: c.id, label: c.label, ok: ok,
                                            repairable: (c.repair?.isEmpty == false), note: c.note))
            }
            let final = out
            await MainActor.run { [weak self] in self?.results = final }
        }
    }

    /// Re-arm every currently-failing invariant that has a repair command.
    func repair() {
        guard let cfg = config, !repairing else { return }
        repairing = true
        let failingIds = Set(failing.map { $0.id })
        Task.detached {
            var log: [String] = []
            for c in cfg.checks where failingIds.contains(c.id) {
                guard let cmd = c.repair, !cmd.isEmpty else { continue }
                let r = Self.runArgv(cmd)
                let detail = r.output.isEmpty ? "" : " — \(r.output.prefix(120))"
                log.append("\(c.label): " + (r.status == 0 ? "repaired" : "exit \(r.status)") + detail)
            }
            let summary = log.isEmpty ? "nothing to repair" : log.joined(separator: "\n")
            await MainActor.run { [weak self] in
                self?.lastRepairOutput = summary
                self?.repairing = false
                self?.refresh()
            }
        }
    }

    /// Run argv via a login shell, POSITIONALLY (no interpolation → no injection),
    /// and return its exit status + combined output. Drains the pipe before
    /// waiting so large output (e.g. `launchctl print`) can't deadlock.
    private nonisolated static func runArgv(_ argv: [String]) -> (status: Int32, output: String) {
        guard !argv.isEmpty else { return (1, "") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "exec \"$@\"", "protection"] + argv
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        do { try p.run() } catch { return (127, "spawn failed: \(error.localizedDescription)") }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (p.terminationStatus, text)
    }
}
