import SwiftUI

/// Compact "darkmesh protection" panel for the menu-bar dropdown.
///
/// Renders a one-line headline (verdict + emoji) plus a small grid of probe
/// indicators (Internet / DNS / Tailscale / the transfer client-via-VPN) and a
/// "last auto-disconnect" footnote when applicable. Tapping the row opens
/// the full status file in Finder for forensics.
struct DarkmeshStatusView: View {
    @ObservedObject var monitor: DarkmeshStatusMonitor
    @ObservedObject var protection: ProtectionMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header

            if let s = monitor.status {
                probeGrid(s)
                recoveryState(s)
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

            integritySection
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("VPN Protection")
                .font(.headline)
            Spacer()
            if let s = monitor.status {
                Text(s.verdict == "GO" ? "Protected" : "\(s.verdictEmoji) \(s.verdict)")
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
            probeRow("VPN", value: s.vpnState, ok: s.vpnState == "Connected")
            let e2e = s.inetE2EOk ?? s.internetOk
            probeRow("Open internet", value: e2e ? "reachable" : "unreachable", ok: e2e)
            if let rawIP = s.inetIpOk {
                probeRow("Raw IP", value: rawIP ? "reachable" : "unreachable", ok: rawIP)
            }
            probeRow("DNS",        value: s.dnsOk ? "resolves" : "broken",              ok: s.dnsOk)
            probeRow("Tailscale",  value: s.tailscaleOk ? "DERP ok" : "unreachable",    ok: s.tailscaleOk)
            if s.crdRequired == true {
                probeRow("Remote access", value: s.crdOk == true ? "reachable" : (s.crdReason ?? "unreachable"),
                         ok: s.crdOk == true)
            } else if s.crdRequired == false {
                probeRow("Remote access", value: "not required", ok: nil)
            }
        }
    }

    @ViewBuilder
    private func probeRow(_ label: String, value: String, ok: Bool?) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ok.map { $0 ? Color.green : Color.red } ?? Color.secondary)
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
    private func recoveryState(_ s: DarkmeshStatus) -> some View {
        if !s.gaveUpFaults.isEmpty {
            Text("Recovery stopped: \(s.gaveUpFaults.joined(separator: ", "))")
                .font(.caption2.bold())
                .foregroundColor(.red)
        } else if s.dnsOverrideActive == true {
            Text("Temporary DNS recovery active")
                .font(.caption2)
                .foregroundColor(.orange)
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

    /// Compact fail-closed integrity row: an OK / AT RISK badge (distinct from
    /// the VPN verdict), the failing invariants, and a one-click Repair. Renders
    /// nothing unless a protection.json is configured.
    @ViewBuilder
    private var integritySection: some View {
        if protection.configured && protection.hasResults {
            Divider().padding(.vertical, 2)
            HStack(spacing: 8) {
                Image(systemName: protection.atRisk ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                    .font(.caption)
                    .foregroundColor(protection.badgeColor)
                Text("Protection")
                    .font(.caption)
                    .frame(width: 78, alignment: .leading)
                Text(protection.badgeText)
                    .font(.caption2.bold())
                    .foregroundColor(protection.badgeColor)
                Spacer()
                if protection.atRisk {
                    if protection.repairing {
                        Text("repairing…")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else if protection.failing.contains(where: { $0.repairable }) {
                        Button(action: { protection.repair() }) {
                            Label("Repair", systemImage: "wrench.and.screwdriver")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            if protection.atRisk {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(protection.failing) { f in
                        HStack(spacing: 6) {
                            Circle().fill(Color.red).frame(width: 5, height: 5)
                            Text(f.note.map { "\(f.label) · \($0)" } ?? f.label)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.leading, 2)
            }
        }
    }
}

#Preview {
    DarkmeshStatusView(monitor: DarkmeshStatusMonitor(pollInterval: 60),
                       protection: ProtectionMonitor(pollInterval: 60))
        .frame(width: 320)
}
