import Foundation
import SwiftUI

/// Snapshot of darkmesh-vpn-guard's view of the machine's network protection
/// state. Mirrors `/tmp/darkmesh-status.json` written by `darkmesh-healthcheck`.
///
/// The healthcheck LaunchAgent polls every 10s. This model is read-only — the
/// menu bar shows what the healthcheck found, it doesn't make decisions.
struct DarkmeshStatus: Codable, Equatable {
    let timestamp: String
    let expressvpnState: String
    let internetOk: Bool
    let dnsOk: Bool
    let tailscaleOk: Bool
    let verdict: String           // "GO" | "DEGRADED" | "NO-GO" | "IDLE"
    let autoDisconnected: Bool
    let autoDisconnectReason: String
    let autoDisconnectAt: String

    enum CodingKeys: String, CodingKey {
        case timestamp
        case expressvpnState         = "expressvpn_state"
        case internetOk              = "internet_ok"
        case dnsOk                   = "dns_ok"
        case tailscaleOk             = "tailscale_ok"
        case verdict
        case autoDisconnected        = "auto_disconnected"
        case autoDisconnectReason    = "auto_disconnect_reason"
        case autoDisconnectAt        = "auto_disconnect_at"
    }

    /// Color cue for the menu-bar status row.
    var verdictColor: Color {
        switch verdict {
        case "GO":       return .green
        case "DEGRADED": return .yellow
        case "NO-GO":    return .red
        case "IDLE":     return .secondary
        default:         return .gray
        }
    }

    /// One-glance emoji for the menu-bar icon and headlines.
    var verdictEmoji: String {
        switch verdict {
        case "GO":       return "🟢"
        case "DEGRADED": return "🟡"
        case "NO-GO":    return "🔴"
        case "IDLE":     return "⚪️"
        default:         return "❔"
        }
    }
}
