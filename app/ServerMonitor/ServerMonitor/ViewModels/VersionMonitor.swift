import Foundation
import SwiftUI

// MARK: - Component versions
//
// Surfaces the app's OWN version/build (from the bundle) plus the versions of the
// external tools it monitors. WHICH tools and HOW each one reports its version is
// machine-specific and lives ONLY in untracked ~/.config/server-monitor/versions.json
// (schema in config/versions.example.json). This open-source code just runs the
// configured argv positionally and shows the first line of its output. No tool
// names, host paths, or vendor specifics here. With no config only the app's own
// version shows.
//
// Version commands run LAZILY (first time the panel is expanded, and on manual
// Refresh) and are cached, never on a status poll, so a heavyweight probe (e.g.
// a JVM CLI or `brew`) costs nothing until you actually look.

/// One external component whose version we surface. `command` prints the version
/// on stdout; the first non-empty line is displayed.
struct VersionComponent: Codable, Identifiable {
    var label: String
    var command: [String]   // argv; first line of stdout = version string
    var enabled: Bool?
    var id: String { label }
}

struct VersionsConfig: Codable {
    var components: [VersionComponent]

    static func load() -> VersionsConfig? {
        let path = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".config/server-monitor/versions.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? JSONDecoder().decode(VersionsConfig.self, from: data)
    }
}

/// Resolved version for display.
struct ComponentVersion: Identifiable {
    let id: String
    let label: String
    var version: String?     // nil until resolved / on failure
    var failed: Bool
}

@MainActor
final class VersionMonitor: ObservableObject {
    /// The app's own version + build, always available from the bundle.
    let appVersion: String
    let appBuild: String

    @Published private(set) var components: [ComponentVersion]
    @Published private(set) var loading = false
    @Published private(set) var loadedOnce = false

    private let config: VersionsConfig?

    init() {
        let info = Bundle.main.infoDictionary
        self.appVersion = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        self.appBuild   = (info?["CFBundleVersion"] as? String) ?? "?"
        let cfg = VersionsConfig.load()
        self.config = cfg
        let enabled = (cfg?.components ?? []).filter { $0.enabled ?? true }
        self.components = enabled.map {
            ComponentVersion(id: $0.label, label: $0.label, version: nil, failed: false)
        }
    }

    /// "1.0.1 (2)": short version with build in parentheses.
    var appVersionText: String { "\(appVersion) (\(appBuild))" }

    var hasComponents: Bool { !components.isEmpty }

    /// Run every enabled component command off the UI actor with a deadline.
    /// Lazy + cached: called on first expand and on manual Refresh, never on a poll.
    func refresh() {
        guard let cfg = config, !loading else { return }
        let comps = cfg.components.filter { $0.enabled ?? true }
        guard !comps.isEmpty else { return }
        loading = true
        Task.detached {
            var out: [ComponentVersion] = []
            for c in comps {
                let r = ProcessRunner.run(c.command, timeout: 30)
                let firstLine = r.output
                    .split(separator: "\n", omittingEmptySubsequences: true).first
                    .map(String.init)?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                out.append(ComponentVersion(
                    id: c.label, label: c.label,
                    version: firstLine.isEmpty ? nil : firstLine,
                    failed: !r.succeeded || firstLine.isEmpty))
            }
            let final = out
            await MainActor.run { [weak self] in
                self?.components = final
                self?.loading = false
                self?.loadedOnce = true
            }
        }
    }

    /// Load versions the first time only; safe to call whenever the panel appears.
    func refreshIfNeeded() {
        if !loadedOnce { refresh() }
    }

}
