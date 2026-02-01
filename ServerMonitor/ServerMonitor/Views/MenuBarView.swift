import SwiftUI

struct MenuBarView: View {
    @ObservedObject var monitor: ServiceMonitor
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Server Monitor")
                    .font(.headline)
                Spacer()
                if let lastUpdate = monitor.lastUpdate {
                    Text(lastUpdate, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            
            Divider()
            
            // Services list
            ForEach(monitor.services) { service in
                ServiceRowView(service: service, monitor: monitor)
            }
            
            Divider()
            
            // Actions
            HStack {
                Button("Refresh") {
                    monitor.checkAllServices()
                }
                .buttonStyle(.borderless)
                
                Spacer()
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .frame(width: 300)
    }
}

struct ServiceRowView: View {
    let service: Service
    @ObservedObject var monitor: ServiceMonitor
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(service.status.color)
                .frame(width: 10, height: 10)
            
            // Service info
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .font(.system(size: 13, weight: .medium))
                
                HStack(spacing: 8) {
                    if let pid = service.pid {
                        Text("PID: \(pid)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let port = service.port {
                        Text(":\(port)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let error = service.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            Spacer()
            
            // Control buttons
            if isHovering {
                HStack(spacing: 4) {
                    if service.status == .running {
                        Button(action: { monitor.stopService(service) }) {
                            Image(systemName: "stop.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Stop")
                        
                        Button(action: { monitor.restartService(service) }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Restart")
                    } else {
                        Button(action: { monitor.startService(service) }) {
                            Image(systemName: "play.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Start")
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(isHovering ? Color.gray.opacity(0.1) : Color.clear)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

#Preview {
    MenuBarView(monitor: ServiceMonitor())
}
