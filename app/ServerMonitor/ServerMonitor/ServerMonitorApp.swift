import SwiftUI

@main
struct ServerMonitorApp: App {
    @StateObject private var monitor = ServiceMonitor()
    @StateObject private var darkmesh = DarkmeshStatusMonitor()
    @StateObject private var worker = WorkerStatusMonitor()
    @Environment(\.openWindow) var openWindow

    /// Combined menu-bar tint. Green ONLY when darkmesh verdict is GO (VPN
    /// Connected + internet + DNS + Tailscale healthy) AND services are ok;
    /// red if services or darkmesh are bad, yellow if degraded OR the VPN is off.
    private var combinedTint: Color {
        if let v = darkmesh.status?.verdict, v == "NO-GO" { return .red }
        if monitor.overallStatus == .stopped                { return .red }
        if let v = darkmesh.status?.verdict, v == "DEGRADED" { return .yellow }
        if darkmesh.status?.verdict == "GO" { return monitor.overallStatus.color }
        return .yellow   // no GO verdict (VPN off / IDLE / status missing): not protected
    }

    var body: some Scene {
        MenuBarExtra {
            VStack(spacing: 0) {
                DarkmeshStatusView(monitor: darkmesh)
                Divider()
                WorkerStatusView(monitor: worker)
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
    }
}
