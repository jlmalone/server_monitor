import SwiftUI

@main
struct ServerMonitorApp: App {
    @StateObject private var monitor = ServiceMonitor()
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView(monitor: monitor)
        } label: {
            Image(systemName: monitor.overallStatus.icon)
                .symbolRenderingMode(.palette)
                .foregroundStyle(monitor.overallStatus.color)
        }
        .menuBarExtraStyle(.window)
    }
}
