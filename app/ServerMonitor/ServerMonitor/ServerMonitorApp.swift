import SwiftUI

@main
struct ServerMonitorApp: App {
    @StateObject private var monitor = ServiceMonitor()
    @StateObject private var darkmesh = DarkmeshStatusMonitor()
    @Environment(\.openWindow) var openWindow

    /// Combined menu-bar tint: red if either services or darkmesh is bad,
    /// yellow if degraded, otherwise the services color (green/secondary).
    /// "At a glance" the user sees the worst of the two systems.
    private var combinedTint: Color {
        if let v = darkmesh.status?.verdict, v == "NO-GO" { return .red }
        if monitor.overallStatus == .stopped                { return .red }
        if let v = darkmesh.status?.verdict, v == "DEGRADED" { return .yellow }
        return monitor.overallStatus.color
    }

    var body: some Scene {
        MenuBarExtra {
            VStack(spacing: 0) {
                DarkmeshStatusView(monitor: darkmesh)
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
