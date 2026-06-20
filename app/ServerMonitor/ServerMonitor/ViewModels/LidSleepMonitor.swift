import Foundation
import SwiftUI

/// Controls whether this Mac keeps running when the lid is closed (or sits idle),
/// via macOS's `pmset disablesleep` flag. When the flag is on the machine never
/// sleeps — close the lid and every service keeps running at full steam; when it
/// is off the Mac sleeps on lid-close as usual.
///
/// Reading the current value (`pmset -g`) is unprivileged. Changing it needs
/// root, so the toggle runs `pmset` through an osascript "with administrator
/// privileges" call — that pops the native auth dialog. No background daemon, no
/// sudoers entry, no stored credentials: it asks only when you flip the switch.
///
/// Laptop-only. On a Mac with no battery the panel hides itself, since "keep
/// running with the lid shut" is meaningless on a desktop.
@MainActor
final class LidSleepMonitor: ObservableObject {
    /// `awake` == sleep is disabled (stays running with the lid closed).
    enum Mode { case awake, sleeps, unknown }

    @Published private(set) var mode: Mode = .unknown
    @Published private(set) var busy = false
    let isLaptop: Bool

    init() {
        self.isLaptop = Self.hasBattery()
        guard isLaptop else { return }
        refresh()
    }

    var stayingAwake: Bool { mode == .awake }

    var headline: String {
        if busy { return "working…" }
        switch mode {
        case .awake:   return "Stays Awake"
        case .sleeps:  return "Sleeps"
        case .unknown: return "unknown"
        }
    }

    var headlineColor: Color {
        if busy { return .orange }
        return mode == .awake ? .green : .secondary
    }

    var detail: String {
        switch mode {
        case .awake:   return "lid closed → keeps running (no sleep)"
        case .sleeps:  return "lid closed → this Mac sleeps"
        case .unknown: return "couldn’t read the power setting"
        }
    }

    /// Re-read the live `pmset` value — cheap and unprivileged, so the view calls
    /// it on every menu open instead of polling on a timer. Skipped while a change
    /// is in flight so the pending state doesn't flicker.
    func refresh() {
        guard isLaptop, !busy else { return }
        Task.detached {
            let m = Self.readMode()
            await MainActor.run { self.mode = m }
        }
    }

    func keepAwake()  { apply(awake: true) }
    func allowSleep() { apply(awake: false) }

    /// Flip `disablesleep` via an admin-authenticated `pmset`, then reflect ground
    /// truth by re-reading. If the user cancels the auth dialog, `pmset` never
    /// runs and the re-read leaves the prior state intact.
    private func apply(awake: Bool) {
        guard isLaptop, !busy else { return }
        busy = true
        Task.detached {
            _ = Self.setDisableSleep(awake ? 1 : 0)
            let m = Self.readMode()
            await MainActor.run {
                self.mode = m
                self.busy = false
            }
        }
    }

    // MARK: - shell

    /// A portable reports an `InternalBattery` power source; desktops don't.
    private nonisolated static func hasBattery() -> Bool {
        run(["/usr/bin/pmset", "-g", "batt"]).output.contains("InternalBattery")
    }

    private nonisolated static func readMode() -> Mode {
        let r = run(["/usr/bin/pmset", "-g"])
        guard r.status == 0 else { return .unknown }
        // `SleepDisabled` is printed only when overridden; absent ⇒ normal sleep.
        for line in r.output.split(separator: "\n") where line.contains("SleepDisabled") {
            let value = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).last
            return value == "1" ? .awake : .sleeps
        }
        return .sleeps
    }

    /// `value` is a literal 0/1 we control — nothing external is interpolated into
    /// the script — so the admin shell-out carries no injection surface.
    private nonisolated static func setDisableSleep(_ value: Int) -> Bool {
        let script = "do shell script \"/usr/bin/pmset -a disablesleep \(value)\" with administrator privileges"
        return run(["/usr/bin/osascript", "-e", script]).status == 0
    }

    /// Run argv directly (no shell), returning exit status + combined output.
    private nonisolated static func run(_ argv: [String]) -> (status: Int32, output: String) {
        guard let first = argv.first else { return (1, "") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: first)
        p.arguments = Array(argv.dropFirst())
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (127, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        return (p.terminationStatus, text)
    }
}
