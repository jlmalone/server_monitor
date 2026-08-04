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
    @Published private(set) var staleReason: String?
    @Published private(set) var schemaError: String?

    private let statusFileURL = URL(fileURLWithPath: "/tmp/darkmesh-status.json")
    private let pollInterval: TimeInterval
    private let maximumStatusAge: TimeInterval
    private var timer: Timer?
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    init(pollInterval: TimeInterval = 5, maximumStatusAge: TimeInterval = 60) {
        self.pollInterval = pollInterval
        self.maximumStatusAge = maximumStatusAge
        readNow()
        start()
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.readNow() }
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
            parseError = nil
            staleReason = nil
            schemaError = nil
            return
        }
        fileMissing = false

        do {
            let data = try Data(contentsOf: statusFileURL)
            let decoded = try decoder.decode(DarkmeshStatus.self, from: data)
            lastReadAt = Date()
            parseError = nil
            staleReason = nil
            schemaError = nil

            guard decoded.schema == 3 || decoded.schema == 4 else {
                status = nil
                schemaError = "unsupported status schema \(decoded.schema.map(String.init) ?? "missing") (expected 3 or 4)"
                return
            }
            guard let authoredAt = Self.parseTimestamp(decoded.timestamp) else {
                status = nil
                parseError = "invalid status timestamp: \(decoded.timestamp)"
                return
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: statusFileURL.path)
            let modifiedAt = attributes[.modificationDate] as? Date
            let now = Date()
            let authoredAge = now.timeIntervalSince(authoredAt)
            let modifiedAge = modifiedAt.map { now.timeIntervalSince($0) } ?? authoredAge
            let publishedMaximumAge = decoded.maxAgeSeconds.map(TimeInterval.init) ?? maximumStatusAge
            let effectiveMaximumAge = min(maximumStatusAge, max(10, publishedMaximumAge))
            guard authoredAge >= -300, authoredAge <= effectiveMaximumAge,
                  modifiedAge >= -300, modifiedAge <= effectiveMaximumAge else {
                status = nil
                let age = Int(max(authoredAge, modifiedAge).rounded())
                staleReason = "status is stale (\(age)s old; limit \(Int(effectiveMaximumAge))s)"
                return
            }
            status = decoded
        } catch {
            status = nil
            parseError = String(describing: error)
        }
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}

// MARK: - Protection integrity
//
// Periodically verifies the machine's fail-closed invariants. WHAT each invariant
// is — which launchd labels, which control binaries, which fail-closed doctor —
// is machine-specific and lives
// ONLY in untracked ~/.config/server-monitor/protection.json (schema in
// config/protection.example.json). This open-source code just runs the
// configured argv and reads the exit code (0 = OK, nonzero = AT RISK); no host
// names or tool specifics here. With no config the panel is inert.

/// One fail-closed invariant: a labeled, read-only check command.
struct ProtectionCheck: Codable {
    var id: String
    var label: String
    var check: [String]    // argv; exit 0 = OK, nonzero = AT RISK
    var note: String?      // optional hint shown when failing, e.g. "needs admin"
}

struct ProtectionConfig: Codable {
    var pollSeconds: Double?
    var timeoutSeconds: Double?
    var checks: [ProtectionCheck]
}

struct ProtectionResult: Identifiable {
    let id: String
    let label: String
    let ok: Bool
    let note: String?
    let detail: String?
}

@MainActor
final class ProtectionMonitor: ObservableObject {
    @Published private(set) var results: [ProtectionResult] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var hasCompletedRefresh = false
    @Published private(set) var lastCheckedAt: Date?
    let configured: Bool

    private let config: ProtectionConfig?
    private var timer: Timer?

    init(pollInterval: TimeInterval = 10) {
        let path = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".config/server-monitor/protection.json")
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            self.config = nil
            self.configured = false
            return
        }
        self.configured = true
        do {
            let decoded = try JSONDecoder().decode(ProtectionConfig.self, from: Data(contentsOf: url))
            guard !decoded.checks.isEmpty,
                  decoded.checks.allSatisfy({ !$0.id.isEmpty && !$0.label.isEmpty && !$0.check.isEmpty }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            self.config = decoded
        } catch {
            self.config = nil
            self.results = [ProtectionResult(
                id: "configuration",
                label: "Protection configuration",
                ok: false,
                note: "invalid or empty configuration",
                detail: "Check ~/.config/server-monitor/protection.json"
            )]
            self.hasCompletedRefresh = true
            self.lastCheckedAt = Date()
            return
        }
        guard let cfg = config else { return }
        let interval = max(10, cfg.pollSeconds ?? pollInterval)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    var hasResults: Bool { !results.isEmpty }
    var failing: [ProtectionResult] { results.filter { !$0.ok } }
    var atRisk: Bool { configured && (!hasCompletedRefresh || results.contains { !$0.ok }) }

    var badgeText: String {
        if !configured { return "—" }
        if !hasCompletedRefresh { return "…" }
        return atRisk ? "AT RISK" : "OK"
    }

    var badgeColor: Color {
        if !configured || !hasCompletedRefresh { return .secondary }
        return atRisk ? .red : .green
    }

    func refresh() {
        guard let cfg = config, !isRefreshing else { return }
        isRefreshing = true
        Task.detached {
            var out: [ProtectionResult] = []
            for c in cfg.checks {
                let run = ProcessRunner.run(c.check, timeout: cfg.timeoutSeconds ?? 30)
                out.append(ProtectionResult(id: c.id, label: c.label,
                                            ok: run.succeeded, note: c.note,
                                            detail: run.failureSummary()))
            }
            let final = out
            await MainActor.run { [weak self] in
                self?.results = final
                self?.isRefreshing = false
                self?.hasCompletedRefresh = true
                self?.lastCheckedAt = Date()
            }
        }
    }
}
