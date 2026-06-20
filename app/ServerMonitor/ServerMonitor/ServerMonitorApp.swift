import SwiftUI

@main
struct ServerMonitorApp: App {
    @StateObject private var monitor = ServiceMonitor()
    @StateObject private var darkmesh = DarkmeshStatusMonitor()
    @StateObject private var worker = WorkerStatusMonitor()
    @StateObject private var lidSleep = LidSleepMonitor()
    @StateObject private var transfers = TransfersMonitor()
    @StateObject private var protection = ProtectionMonitor()
    @Environment(\.openWindow) var openWindow

    /// Combined menu-bar tint. Green ONLY when darkmesh verdict is GO (VPN
    /// Connected + internet + DNS + Tailscale healthy) AND services are ok AND
    /// nothing needs attention; red if services or darkmesh are bad, yellow if
    /// degraded, the VPN is off, a guard is down, or a transfer has failed.
    private var combinedTint: Color {
        if let v = darkmesh.status?.verdict, v == "NO-GO" { return .red }
        if monitor.overallStatus == .stopped                { return .red }
        if let v = darkmesh.status?.verdict, v == "DEGRADED" { return .yellow }
        if protection.atRisk { return .yellow }   // a fail-closed guard is down — never show "all good"
        if transfers.failed > 0 { return .yellow } // an unresolved failed transfer needs attention — never show "all good"
        if darkmesh.status?.verdict == "GO" { return monitor.overallStatus.color }
        return .yellow   // no GO verdict (VPN off / IDLE / status missing): not protected
    }

    var body: some Scene {
        MenuBarExtra {
            VStack(spacing: 0) {
                DarkmeshStatusView(monitor: darkmesh, protection: protection)
                Divider()
                WorkerStatusView(monitor: worker)
                if lidSleep.isLaptop {
                    Divider()
                    LidSleepView(monitor: lidSleep)
                }
                Divider()
                TransfersView(monitor: transfers)
                HStack {
                    Spacer()
                    Button {
                        openWindow(id: "transfer-history")
                    } label: {
                        Label("Transfer History…", systemImage: "clock.arrow.circlepath")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                }
                Divider()
                MenuBarView(monitor: monitor)

                Divider()

                HStack {
                    Button(action: {
                        openWindow(id: "settings")
                    }) {
                        Label("Manage Services", systemImage: "gearshape")
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)

                    Spacer()

                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
            }
        } label: {
            Image(systemName: monitor.overallStatus.icon)
                .symbolRenderingMode(.palette)
                .foregroundStyle(combinedTint)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Settings", id: "settings") {
            SettingsView(monitor: monitor)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 400)

        WindowGroup("Transfer History", id: "transfer-history") {
            TransferHistoryWindow()
        }
        .defaultSize(width: 840, height: 560)
    }
}
