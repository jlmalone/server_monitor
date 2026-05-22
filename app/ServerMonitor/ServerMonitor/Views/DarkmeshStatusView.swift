import SwiftUI

/// Compact "darkmesh protection" panel for the menu-bar dropdown.
///
/// Renders a one-line headline (verdict + emoji) plus a small grid of probe
/// indicators (Internet / DNS / Tailscale / the transfer client-via-VPN) and a
/// "last auto-disconnect" footnote when applicable. Tapping the row opens
/// the full status file in Finder for forensics.
struct DarkmeshStatusView: View {
    @ObservedObject var monitor: DarkmeshStatusMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header

            if let s = monitor.status {
                probeGrid(s)
                if s.autoDisconnected || !s.autoDisconnectAt.isEmpty {
                    autoDisconnectFootnote(s)
                }
            } else if monitor.fileMissing {
                Text("darkmesh healthcheck not installed (run install-user-tools)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if let err = monitor.parseError {
                Text("status file unreadable: \(err)")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("Darkmesh")
                .font(.headline)
            Spacer()
            if let s = monitor.status {
                Text("\(s.verdictEmoji) \(s.verdict)")
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(s.verdictColor.opacity(0.2))
                    .foregroundColor(s.verdictColor)
                    .cornerRadius(4)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func probeGrid(_ s: DarkmeshStatus) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            probeRow("ExpressVPN", value: s.expressvpnState, ok: s.expressvpnState == "Connected")
            probeRow("Internet",   value: s.internetOk ? "reachable" : "unreachable",   ok: s.internetOk)
            probeRow("DNS",        value: s.dnsOk ? "resolves" : "broken",              ok: s.dnsOk)
            probeRow("Tailscale",  value: s.tailscaleOk ? "DERP ok" : "unreachable",    ok: s.tailscaleOk)
        }
    }

    @ViewBuilder
    private func probeRow(_ label: String, value: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ok ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private func autoDisconnectFootnote(_ s: DarkmeshStatus) -> some View {
        if !s.autoDisconnectAt.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "bolt.shield")
                    .font(.caption2)
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Auto-disconnected at \(s.autoDisconnectAt)")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    if !s.autoDisconnectReason.isEmpty {
                        Text(s.autoDisconnectReason)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.top, 2)
        }
    }
}

#Preview {
    DarkmeshStatusView(monitor: DarkmeshStatusMonitor(pollInterval: 60))
        .frame(width: 320)
}
