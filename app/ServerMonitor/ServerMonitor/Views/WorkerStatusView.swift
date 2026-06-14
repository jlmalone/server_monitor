import SwiftUI

/// Compact "worker (this Mac)" panel for the menu-bar dropdown: shows whether a
/// machine-specific local worker node is running (and its current throughput)
/// with a Turn On / Turn Off button. What the worker *is* lives in untracked
/// local config (`config/worker.example.json`); this open-source app only knows
/// how to start/stop it and read its pid/log. Remote nodes are unaffected.
struct WorkerStatusView: View {
    @ObservedObject var monitor: WorkerStatusMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: monitor.running ? "cpu.fill" : "cpu")
                    .foregroundColor(monitor.headlineColor)
                Text("Worker (this Mac)")
                    .font(.headline)
                Spacer()
                Text(monitor.headline)
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(monitor.headlineColor.opacity(0.2))
                    .foregroundColor(monitor.headlineColor)
                    .cornerRadius(4)
            }

            if monitor.configured {
                HStack(spacing: 8) {
                    Text(monitor.running ? "local node · \(monitor.rate ?? "running")" : "local node stopped")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    if monitor.running {
                        Button(action: { monitor.stop() }) {
                            Label("Turn Off", systemImage: "stop.fill").font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.red)
                        .disabled(monitor.busy)
                    } else {
                        Button(action: { monitor.start() }) {
                            Label("Turn On", systemImage: "play.fill").font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.green)
                        .disabled(monitor.busy)
                    }
                }
            } else {
                Text("no local worker configured")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}

#Preview {
    WorkerStatusView(monitor: WorkerStatusMonitor(pollInterval: 60))
        .frame(width: 320)
}
