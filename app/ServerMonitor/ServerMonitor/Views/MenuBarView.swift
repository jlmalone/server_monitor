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
                Text("\(monitor.runningCount)/\(monitor.totalCount)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(monitor.overallStatus == .running ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                    .foregroundColor(monitor.overallStatus == .running ? .green : .red)
                    .cornerRadius(4)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            
            if let lastUpdate = monitor.lastUpdate {
                Text("Updated \(lastUpdate, style: .relative) ago")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            
            Divider()
            
            // Services list
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(monitor.services) { service in
                        ServiceRowView(service: service, monitor: monitor)
                    }
                }
            }
            .frame(maxHeight: 300)
            
            Divider()
            
            // Bulk actions
            HStack(spacing: 12) {
                Button(action: { monitor.startAll() }) {
                    Label("Start All", systemImage: "play.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(monitor.overallStatus == .running)
                
                Button(action: { monitor.stopAll() }) {
                    Label("Stop All", systemImage: "stop.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(monitor.runningCount == 0)
                
                Button(action: { monitor.restartAll() }) {
                    Label("Restart All", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            // Footer actions
            HStack {
                Button(action: { monitor.reloadConfig() }) {
                    Label("Reload Config", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                
                Spacer()
                
                Button("Refresh") {
                    monitor.checkAllServices()
                }
                .buttonStyle(.borderless)
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .frame(width: 320)
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
                            .foregroundColor(.blue)
                    }
                    
                    if service.status == .stopped {
                        Text("Stopped")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    if let error = service.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            Spacer()
            
            // Control buttons (always visible on hover)
            if isHovering {
                HStack(spacing: 4) {
                    if service.status == .running {
                        Button(action: { monitor.stopService(service) }) {
                            Image(systemName: "stop.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("Stop")
                        
                        Button(action: { monitor.restartService(service) }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(.borderless)
                        .help("Restart")
                    } else {
                        Button(action: { monitor.startService(service) }) {
                            Image(systemName: "play.fill")
                                .font(.caption)
                                .foregroundColor(.green)
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
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

#Preview {
    MenuBarView(monitor: ServiceMonitor())
}
