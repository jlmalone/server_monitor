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

/// Compact "Transfers" panel: active file transfers (per item: title, %, rate,
/// ETA) plus an aggregate headline. Data + config live in `TransfersMonitor`;
/// this view is pure presentation. Inert when no `transfers.json` is configured.
struct TransfersView: View {
    @ObservedObject var monitor: TransfersMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: monitor.running > 0 ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .foregroundColor(monitor.headlineColor)
                Text("Transfers")
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

            if !monitor.configured {
                Text("no transfers source configured")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if monitor.rows.isEmpty {
                Text("no active transfers")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                ForEach(monitor.rows.prefix(6)) { row in
                    rowView(row)
                }
                if monitor.rows.count > 6 {
                    Text("+\(monitor.rows.count - 6) more")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func rowView(_ row: TransferRow) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Circle()
                    .fill(dotColor(row.status))
                    .frame(width: 6, height: 6)
                Text(row.title)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let pct = row.pctText {
                    Text(pct).font(.caption2).foregroundColor(.secondary)
                }
            }
            HStack(spacing: 8) {
                Text(row.machine).font(.caption2).foregroundColor(.secondary)
                if let rate = row.rateText {
                    Text(rate).font(.caption2).foregroundColor(.secondary)
                }
                if let eta = row.etaText {
                    Text(eta).font(.caption2).foregroundColor(.secondary)
                }
                if row.rateText == nil {
                    Text(row.status).font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
            }
        }
    }

    private func dotColor(_ status: String) -> Color {
        switch status {
        case "running": return .green
        case "failed": return .red
        default: return .secondary
        }
    }
}

#Preview {
    TransfersView(monitor: TransfersMonitor())
        .frame(width: 320)
}
