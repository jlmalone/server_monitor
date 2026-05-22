# Roadmap — darkmesh integration in server_monitor

Status as of 2026-05-22. The endpoint of this roadmap is the deletion of the
SwiftBar plugin in `darkmesh-vpn-guard`; everything below is the work between
"now" and that point.

Read this in conjunction with [CLAUDE.md](./CLAUDE.md). Future AI sessions
working on this integration should follow both.

---

## Why this exists

The user wants protection-status visibility in the macOS menu bar. As a
stopgap during the darkmesh investigation (see
`darkmesh-vpn-guard/docs/investigation-log.md`), a SwiftBar plugin
(`swiftbar/darkmesh.10s.sh` in that repo) was set up to render the same
`/tmp/darkmesh-status.json` data. SwiftBar is a temporary dependency. The
long-term home is this app, server_monitor.

The native integration started in commit `18a9d3f` ("Add darkmesh protection
status to menu bar"). That commit shipped the *read-only* status display.
This roadmap covers the remaining work to reach feature parity with the
SwiftBar plugin so SwiftBar can be retired.

---

## Done (commit `18a9d3f`)

- `Models/DarkmeshStatus.swift` — Codable struct for `/tmp/darkmesh-status.json`
- `ViewModels/DarkmeshStatusMonitor.swift` — ObservableObject polling every 5s
- `Views/DarkmeshStatusView.swift` — verdict header, four-probe grid, last-auto-disconnect footnote
- `ServerMonitorApp.swift` — embeds DarkmeshStatusView at top of dropdown; tints menu-bar icon worst-of-(services, darkmesh)

These three .swift files exist on disk but are not yet referenced in
`app/ServerMonitor/ServerMonitor.xcodeproj/project.pbxproj`. They need to be
added via "File → Add Files to ServerMonitor…" in Xcode before the first
build. The project uses explicit PBX file references rather than Xcode 16+
synchronized groups.

---

## Phase 1 — Action controller

**Goal**: a single ObservableObject responsible for invoking the CLI tools
the SwiftBar plugin currently shells out to. Keep network policy out of the
UI; the controller does nothing the user can't already do from a terminal.

**New file**: `app/ServerMonitor/ServerMonitor/ViewModels/DarkmeshActions.swift`

Mirrors `ServiceMonitor`'s `Process()` pattern (see
`ViewModels/ServiceMonitor.swift` around line 140). Each action returns
quickly and lets the UI re-poll the status file via `DarkmeshStatusMonitor`
afterwards.

Skeleton (paste as starting point, then refine):

```swift
import Foundation
import AppKit

@MainActor
final class DarkmeshActions: ObservableObject {
    @Published private(set) var lastResult: String?
    @Published private(set) var isRunning: Bool = false

    private let expressvpnctl  = "/Applications/ExpressVPN.app/Contents/MacOS/expressvpnctl"
    private let healthcheckBin = "\(NSHomeDirectory())/.local/bin/darkmesh-healthcheck"
    private let emergencyBin   = "\(NSHomeDirectory())/.local/bin/emergency-restore-internet"
    private let statusFile     = "/tmp/darkmesh-status.json"

    func connectVPN()      { run(expressvpnctl,  ["connect"]) }
    func disconnectVPN()   { run(expressvpnctl,  ["disconnect"]) }
    func runHealthcheck()  { run(healthcheckBin, ["--no-revert"]) }

    /// Emergency restore needs a Terminal because it expects to be interactive
    /// and may need sudo. Open Terminal with the command rather than capturing.
    func emergencyRestore() {
        let script = "tell application \"Terminal\" to do script \"\(emergencyBin)\""
        runAppleScript(script)
    }

    func openExpressVPN()  { NSWorkspace.shared.launchApplication("ExpressVPN") }
    func openTailscale()   { NSWorkspace.shared.launchApplication("Tailscale") }

    func revealStatusJSON() {
        NSWorkspace.shared.selectFile(statusFile, inFileViewerRootedAtPath: "")
    }

    // MARK: - private

    private func run(_ launchPath: String, _ args: [String]) {
        isRunning = true
        let task = Process()
        task.launchPath = launchPath
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.terminationHandler = { [weak self] _ in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8) ?? ""
            Task { @MainActor in
                self?.lastResult = out.isEmpty ? "ok" : out
                self?.isRunning = false
            }
        }
        do { try task.run() } catch {
            lastResult = "error: \(error.localizedDescription)"
            isRunning = false
        }
    }

    private func runAppleScript(_ source: String) {
        var err: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&err)
        if let e = err { lastResult = "applescript error: \(e)" }
    }
}
```

Caveat to verify: if server_monitor's entitlements declare `app-sandbox` true,
`Process()` against `/Applications/ExpressVPN.app/...` will fail. Check
`app/ServerMonitor/ServerMonitor/ServerMonitor.entitlements`. If sandboxed,
either drop the sandbox (the app already needs to invoke launchctl outside
the sandbox, so it's likely already disabled) or expose the actions via
helper scripts the user installs.

---

## Phase 2 — Wire actions into the view

Update `Views/DarkmeshStatusView.swift` to take an `@ObservedObject var
actions: DarkmeshActions` and append an actions section. Pattern matches
`MenuBarView.swift`'s "Bulk actions" / "Footer actions" rows.

```swift
HStack(spacing: 12) {
    if monitor.status?.expressvpnState == "Connected" {
        Button(action: { actions.disconnectVPN() }) {
            Label("Disconnect", systemImage: "stop.fill").font(.caption)
        }.buttonStyle(.borderless)
    } else {
        Button(action: { actions.connectVPN() }) {
            Label("Connect", systemImage: "play.fill").font(.caption)
        }.buttonStyle(.borderless)
    }

    Button(action: { actions.runHealthcheck() }) {
        Label("Probe now", systemImage: "stethoscope").font(.caption)
    }.buttonStyle(.borderless)

    Spacer()

    Menu {
        Button("Open ExpressVPN")          { actions.openExpressVPN() }
        Button("Open Tailscale")           { actions.openTailscale() }
        Button("Reveal status JSON")       { actions.revealStatusJSON() }
        Divider()
        Button("Emergency restore internet") { actions.emergencyRestore() }
    } label: {
        Image(systemName: "ellipsis.circle").font(.caption)
    }
    .menuStyle(.borderlessButton)
    .frame(width: 30)
}
.padding(.horizontal)
.padding(.vertical, 6)
.disabled(actions.isRunning)
```

`ServerMonitorApp.swift` then instantiates `@StateObject private var
darkmeshActions = DarkmeshActions()` and passes both objects:

```swift
DarkmeshStatusView(monitor: darkmesh, actions: darkmeshActions)
```

---

## Phase 3 — Xcode project membership

The four files (three already on disk from `18a9d3f`, plus the new
`DarkmeshActions.swift`) must be added to the Xcode project:

1. Open `app/ServerMonitor/ServerMonitor.xcodeproj` in Xcode.
2. In the project navigator, right-click the appropriate group (Models /
   ViewModels / Views) and choose "Add Files to 'ServerMonitor'…".
3. Select the file, ensure "ServerMonitor" target is checked, click Add.
4. Repeat for each missing file.
5. Verify the file shows up under "Build Phases → Compile Sources" of the
   ServerMonitor target.
6. Commit the `project.pbxproj` diff.

If switching to Xcode 16+ synchronized groups is desired (one-time effort,
removes this manual step forever), see `man xcodeproj-synchronized-groups`
or the Xcode 16 release notes; do this as a separate commit.

---

## Phase 4 — Build & install

Requires full Xcode (Command Line Tools is not enough — SwiftUI app bundles
need the macOS SDK from Xcode.app):

```bash
cd ~/ios_code/server_monitor
xcodebuild -project app/ServerMonitor/ServerMonitor.xcodeproj \
           -scheme ServerMonitor -configuration Release \
           build SYMROOT=build
cp -R build/Release/ServerMonitor.app /Applications/
open /Applications/ServerMonitor.app
```

For a signed/notarized DMG suitable for other machines: run
`scripts/build_release.sh` with `.env` populated per
`scripts/.env.example`.

---

## Phase 5 — Test plan

Run these in order. Each must pass before the next is attempted. The
healthcheck LaunchAgent stays running throughout so the auto-revert is the
backstop if any test wedges the network.

| # | Test | Pass criterion |
|---|------|----------------|
| 1 | Launch ServerMonitor.app | Menu-bar icon appears, no crashes |
| 2 | Click menu-bar icon, observe DarkmeshStatusView at top | Shows current verdict (probably 🟢 GO), four probe rows, no error text |
| 3 | Verify menu-bar icon tint reflects darkmesh state | Forcibly set status JSON `verdict: "NO-GO"` and confirm icon goes red; revert |
| 4 | Click Disconnect VPN button (while VPN connected) | VPN disconnects within 5s; status updates to IDLE within 10s |
| 5 | Click Connect VPN button | VPN connects within ~30s; healthcheck observes transition; verdict becomes GO |
| 6 | Click Probe now button | `~/Library/Logs/darkmesh/healthcheck.log` shows a fresh entry within 2s |
| 7 | Open ExpressVPN, Open Tailscale | Each app comes to the foreground |
| 8 | Reveal status JSON | Finder opens with `/tmp/darkmesh-status.json` selected |
| 9 | Emergency restore | Terminal opens running `emergency-restore-internet`; VPN disconnects, internet recovers |
| 10 | Auto-revert backstop | Force a NO-GO state (e.g. `tailscale set --accept-dns=true` while VPN connected); within ~25s, VPN auto-disconnects and view shows `auto_disconnected: true` for ~10 min sticky |

If any test fails, fix and re-run the entire sequence. Don't proceed to
Phase 6 with unresolved failures.

---

## Phase 6 — Retire SwiftBar

Only execute after every Phase 5 test passes on at least two consecutive runs.

```bash
# Stop SwiftBar
osascript -e 'quit app "SwiftBar"'

# Remove the plugin
rm -f "$HOME/Library/Application Support/SwiftBar/plugins/darkmesh.10s.sh"

# Uninstall the app
brew uninstall --cask swiftbar

# Clear the plugin folder preference
defaults delete com.ameba.SwiftBar PluginDirectory 2>/dev/null || true
```

Then in the `darkmesh-vpn-guard` repo:

1. Delete `swiftbar/darkmesh.10s.sh` (the source kept for posterity).
2. Remove the SwiftBar install block from `scripts/install-user-tools` (the
   `if [[ -d /Applications/SwiftBar.app ]]` block added in commit `8ac47c3`).
3. Update `README.md` to remove the SwiftBar section and point exclusively
   at server_monitor.
4. Add a final entry to `docs/investigation-log.md` noting the retirement
   with the date and a pointer to this roadmap.
5. Commit and push.

After the retirement commit lands, this `ROADMAP.md` can also be removed
(or moved to `docs/history/` for the record).

---

## Open questions / risks

- **Sandboxing**: if the Xcode project sets `com.apple.security.app-sandbox =
  true`, every Process() call in DarkmeshActions fails. Either disable
  sandboxing (the existing ServiceMonitor already invokes launchctl, so
  it's most likely off) or move the actions to an installed shell wrapper.
- **AppleScript permissions**: opening Terminal from inside server_monitor
  triggers a one-time macOS "Allow ServerMonitor to control Terminal?"
  prompt. Document this in the user-facing release notes.
- **launchAgent ownership of Tailscale accept-dns toggle**: the user's
  `darkmesh-healthcheck` LaunchAgent already toggles `tailscale set
  --accept-dns`. If a future server_monitor action does the same, the two
  could race. Keep the toggle in the LaunchAgent and have the app
  surface state only, not change Tailscale prefs.
- **Notarization**: if the user wants ServerMonitor.app on machines other
  than this one, the release needs Developer ID signing + Apple
  notarization. `scripts/build_release.sh` does this but requires Apple
  Developer credentials in `.env`.
