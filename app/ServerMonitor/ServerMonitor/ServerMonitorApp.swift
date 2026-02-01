import SwiftUI

@main
struct ServerMonitorApp: App {
    @StateObject private var monitor = ServiceMonitor()
    @Environment(\.openWindow) var openWindow
    
    var body: some Scene {
        MenuBarExtra {
            VStack(spacing: 0) {
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
                    
                    Button(action: {
                        let current = LaunchAtLogin.observable.isEnabled
                        LaunchAtLogin.observable.isEnabled = !current
                    }) {
                        Label(LaunchAtLogin.observable.isEnabled ? "Unregister Login" : "Launch at Login", 
                              systemImage: LaunchAtLogin.observable.isEnabled ? "checkmark.square" : "square")
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
                .foregroundStyle(monitor.overallStatus.color)
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: monitor.overallStatus.icon)
                .symbolRenderingMode(.palette)
                .foregroundStyle(monitor.overallStatus.color)
        }
        .menuBarExtraStyle(.window)
        
        WindowGroup("Settings", id: "settings") {
            SettingsView(monitor: monitor)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 400)
    }
}
