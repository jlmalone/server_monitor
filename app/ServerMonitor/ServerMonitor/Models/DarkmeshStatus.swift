import Foundation
import SwiftUI

/// Snapshot of darkmesh-vpn-guard's view of the machine's network protection
/// state. Mirrors `/tmp/darkmesh-status.json` written by `darkmesh-healthcheck`.
///
/// The healthcheck LaunchAgent polls every 10s. This model is read-only — the
/// menu bar shows what the healthcheck found, it doesn't make decisions.
struct DarkmeshStatus: Codable, Equatable {
    let timestamp: String
    let vpnState: String
    let internetOk: Bool
    let dnsOk: Bool
    let tailscaleOk: Bool
    let verdict: String           // "GO" | "DEGRADED" | "NO-GO" | "IDLE"
    let autoDisconnected: Bool
    let autoDisconnectReason: String
    let autoDisconnectAt: String

    // Added in status schema 2. Optional so older status files decode to nil and
    // a missing field never breaks the panel (tolerate-or-warn).
    let schema: Int?
    let desired: String?
    let servicesOk: Bool?
    let reconnect: Reconnect?
    let pf: PFState?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case vpnState                = "vpn_state"
        case internetOk              = "internet_ok"
        case dnsOk                   = "dns_ok"
        case tailscaleOk             = "tailscale_ok"
        case verdict
        case autoDisconnected        = "auto_disconnected"
        case autoDisconnectReason    = "auto_disconnect_reason"
        case autoDisconnectAt        = "auto_disconnect_at"
        case schema
        case desired
        case servicesOk              = "services_ok"
        case reconnect
        case pf
    }

    /// Recovery snapshot authored by the reconnect watchdog and merged into the
    /// status file by the healthcheck (status schema 2+).
    struct Reconnect: Codable, Equatable {
        let phase: String?
        let vpnState: String?
        let consecutiveFails: Int?
        let appRestarts: Int?
        let gaveUp: Bool?
        let tunnelIp: String?
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case phase
            case vpnState         = "vpn_state"
            case consecutiveFails = "consecutive_fails"
            case appRestarts      = "app_restarts"
            case gaveUp           = "gave_up"
            case tunnelIp         = "tunnel_ip"
            case updatedAt        = "updated_at"
        }
    }

    /// PF kill-switch state authored by vpn-guard and merged into the status file
    /// by the healthcheck (status schema 2+). `pfAnchorEvaluated` is the
    /// "is the kill-switch actually wired" signal — false means loaded-but-dead.
    struct PFState: Codable, Equatable {
        let pfEnabled: Bool?
        let pfAnchor: String?
        let pfAnchorEvaluated: Bool?
        let pfKillActive: Bool?
        let checkedAt: String?

        enum CodingKeys: String, CodingKey {
            case pfEnabled         = "pf_enabled"
            case pfAnchor          = "pf_anchor"
            case pfAnchorEvaluated = "pf_anchor_evaluated"
            case pfKillActive      = "pf_kill_active"
            case checkedAt         = "checked_at"
        }
    }

    /// False only when the status explicitly reports a keep-alive service down.
    var servicesHealthy: Bool { servicesOk ?? true }

    /// True only when the PF kill-switch is confirmed wired (anchor evaluated).
    /// nil when the status file predates the PF field (tolerate-or-warn).
    var pfKillSwitchWired: Bool? { pf?.pfAnchorEvaluated }

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
