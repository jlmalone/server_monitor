import Foundation

struct NetworkPostureConfig: Decodable, Equatable {
    let schema: Int
    var pollSeconds: Double?
    var statusFile: String?
    var profilesCommand: [String]?
    var statusCommand: [String]?
    var topologyCommand: [String]?
    var probeCommand: [String]?
    var activeProbeTimeoutSeconds: Double?
    var applyCommand: [String]?
    var logSources: [NetworkLogSource]?
    var maxStatusAgeSeconds: Double?
    var probes: [NetworkProbeConfig]?
    var diagnostics: [NetworkCommandConfig]?
    var postures: [NetworkPostureChoice]?
    var isValid: Bool {
        schema == 1 && ((statusFile?.isEmpty == false) || !(statusCommand ?? []).isEmpty)
            && [profilesCommand, statusCommand, topologyCommand, probeCommand, applyCommand].allSatisfy { ($0 ?? []).allSatisfy { !$0.isEmpty } }
            && (applyCommand == nil || applyCommand?.contains(where: { $0.contains("{profile}") }) == true)
            && (activeProbeTimeoutSeconds ?? 1) > 0
            && (probes ?? []).allSatisfy(\.isValid) && (diagnostics ?? []).allSatisfy(\.isValid)
            && (postures ?? []).allSatisfy(\.isValid) && (logSources ?? []).allSatisfy(\.isValid)
    }
}
struct NetworkProbeConfig: Codable, Equatable, Identifiable { let id: String; let label: String; let command: [String]; var required: Bool?; var timeoutSeconds: Double?; var isRequired: Bool { required ?? true }; var isValid: Bool { !id.isEmpty && !label.isEmpty && !command.isEmpty && (timeoutSeconds ?? 1) > 0 } }
struct NetworkCommandConfig: Codable, Equatable, Identifiable { let id: String; let label: String; let command: [String]; var timeoutSeconds: Double?; var isValid: Bool { !id.isEmpty && !label.isEmpty && !command.isEmpty && (timeoutSeconds ?? 1) > 0 } }
struct NetworkLogSource: Codable, Equatable, Identifiable { let id: String; let label: String; var path: String?; var command: [String]?; var timeoutSeconds: Double?; var isValid: Bool { !id.isEmpty && !label.isEmpty && (path?.isEmpty == false || !(command ?? []).isEmpty) } }

struct NetworkPostureChoice: Decodable, Equatable, Identifiable {
    let id: String
    let label: String
    let setCommand: [String]
    var timeoutSeconds: Double?
    var title: String?
    var required: [String: Bool]?
    var preferred: [String: Bool]?
    var forbidden: [String: Bool]?
    var priority: [String]?
    var degraded: String?
    var transition: NetworkTransition?
    var capabilities: [String: Bool]?
    var consequence: String?

    var isValid: Bool {
        !id.isEmpty && !label.isEmpty
            && ((setCommand.isEmpty && title != nil) || !setCommand.isEmpty)
            && (timeoutSeconds ?? 1) > 0
    }

    // The producer owns capability policy. A false capability is descriptive
    // unless the versioned transition explicitly refuses application.
    var canApply: Bool {
        switch transition?.apply {
        case nil, "bounded": return true
        case "refuse": return false
        default: return false
        }
    }
    var confirmationText: String {
        consequence ?? degraded ?? "This may change network connectivity."
    }

    enum CodingKeys: String, CodingKey { case id, label, title, setCommand = "set_command", timeoutSeconds = "timeout_seconds", required, preferred, forbidden, priority, degraded, transition, capabilities, consequence }
    init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); id = try c.decode(String.self, forKey: .id); title = try c.decodeIfPresent(String.self, forKey: .title); label = try c.decodeIfPresent(String.self, forKey: .label) ?? title ?? id; setCommand = try c.decodeIfPresent([String].self, forKey: .setCommand) ?? []; timeoutSeconds = try c.decodeIfPresent(Double.self, forKey: .timeoutSeconds); required = try c.decodeIfPresent([String: Bool].self, forKey: .required); preferred = try c.decodeIfPresent([String: Bool].self, forKey: .preferred); forbidden = try c.decodeIfPresent([String: Bool].self, forKey: .forbidden); priority = try c.decodeIfPresent([String].self, forKey: .priority); degraded = try c.decodeIfPresent(String.self, forKey: .degraded); transition = try c.decodeIfPresent(NetworkTransition.self, forKey: .transition); capabilities = try c.decodeIfPresent([String: Bool].self, forKey: .capabilities); consequence = try c.decodeIfPresent(String.self, forKey: .consequence) }
}
struct NetworkTransition: Decodable, Equatable { var apply: String? }
struct NetworkOutput: Equatable { let text: String; let timestamp: Date; let stale: Bool }
enum NetworkArgv { static func applying(_ template: [String], profile: String) -> [String]? { guard !template.isEmpty, template.contains(where: { $0.contains("{profile}") }) else { return nil }; return template.map { $0.replacingOccurrences(of: "{profile}", with: profile) } }; static func capped(_ value: String, maximum: Int = 4_096) -> String { let clean = String(value.unicodeScalars.map { $0.value < 32 && $0 != "\n" && $0 != "\t" ? " " : Character(String($0)) }); return clean.count > maximum ? String(clean.suffix(maximum)) : clean } }

struct NetworkAssessment: Decodable, Equatable {
    var severity: String; var state: String; var reason: String; var required: [String: Bool?]; var preferred: [String: Bool?]; var forbidden: [String: Bool?]
    enum CodingKeys: String, CodingKey { case severity, state, reason, required, preferred, forbidden }
    init(from decoder: Decoder) throws { let c=try decoder.container(keyedBy:CodingKeys.self); severity=try c.decode(String.self,forKey:.severity); state=try c.decode(String.self,forKey:.state); reason=try c.decode(String.self,forKey:.reason); required=try c.decodeIfPresent([String:Bool?].self,forKey:.required) ?? [:]; preferred=try c.decodeIfPresent([String:Bool?].self,forKey:.preferred) ?? [:]; forbidden=try c.decodeIfPresent([String:Bool?].self,forKey:.forbidden) ?? [:] }
}
struct NetworkObserved: Decodable, Equatable {
    var available: Bool?; var fresh: Bool?; var reason: String?; var internet: Bool?; var vpn: Bool?; var vpnState: String?; var tailscale: Bool?; var transferSafety: Bool?; var verdict: String?; var ageSeconds: Double?
    enum CodingKeys: String, CodingKey { case available, fresh, reason, internet, vpn, vpnState, tailscale, transferSafety, verdict, ageSeconds }
    var compact: String { let value=[internet.map { "internet=\($0)" }, vpnState.map { "vpn=\($0)" }, tailscale.map { "tailscale=\($0)" }, transferSafety.map { "transfer=\($0)" }, fresh.map { "fresh=\($0)" }].compactMap { $0 }.joined(separator: " · "); return value.isEmpty ? (reason ?? "unavailable") : value }
}
struct NetworkPostureSnapshot: Decodable, Equatable {
    var schema: Int?; var kind: String?; var generatedAt: String?; var desired: String?; var observed: NetworkObserved?; var convergence: String?; var degradation: [String]; var interfaces: [NetworkInterface]; var routes: [NetworkRoute]; var peers: [NetworkPeer]; var assessment: NetworkAssessment?; var localTailscale: TailscaleLocal?
    enum CodingKeys: String, CodingKey { case schema, kind, generatedAt, generated_at, timestamp, desiredProfile, desired, observed, convergence, degradation, profile, assessment, local, peers, interfaces, routes }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self); schema = try c.decodeIfPresent(Int.self, forKey: .schema); kind = try c.decodeIfPresent(String.self,forKey:.kind); generatedAt = try c.decodeIfPresent(String.self, forKey: .generatedAt) ?? c.decodeIfPresent(String.self, forKey: .generated_at) ?? c.decodeIfPresent(String.self, forKey: .timestamp); desired = try c.decodeIfPresent(String.self, forKey: .desiredProfile) ?? c.decodeIfPresent(String.self, forKey: .desired); observed = try c.decodeIfPresent(NetworkObserved.self, forKey: .observed); convergence = try c.decodeIfPresent(String.self, forKey: .convergence); assessment = try c.decodeIfPresent(NetworkAssessment.self, forKey: .assessment); degradation = (try? c.decodeIfPresent([String].self, forKey: .degradation)) ?? ((try? c.decodeIfPresent(String.self, forKey: .degradation)).map { [$0] } ?? []); interfaces = try c.decodeIfPresent([NetworkInterface].self, forKey: .interfaces) ?? []; routes = try c.decodeIfPresent([NetworkRoute].self, forKey: .routes) ?? []; peers = try c.decodeIfPresent([NetworkPeer].self, forKey: .peers) ?? []; localTailscale = nil
        if let local = try c.decodeIfPresent(NetworkTopologyLocal.self, forKey: .local) { interfaces = local.interfaces; routes = local.routes; localTailscale = local.tailscale }
    }
    mutating func merge(topology: NetworkPostureSnapshot) { if !topology.interfaces.isEmpty { interfaces = topology.interfaces }; if !topology.routes.isEmpty { routes = topology.routes }; if !topology.peers.isEmpty { peers = topology.peers }; if let value=topology.localTailscale { localTailscale=value }; if generatedAt == nil { generatedAt = topology.generatedAt } }
    mutating func mergeActivePeers(_ activePeers: [NetworkPeer]) { guard !activePeers.isEmpty else { return }; if peers.isEmpty { peers=activePeers; return }; peers=peers.map { passive in guard let active=activePeers.first(where: { $0.id == passive.id }) else { return passive }; var merged=passive; merged.mergeProbe(active); return merged } }
}
struct NetworkTopologyLocal: Decodable {
    var interfaces: [NetworkInterface]
    var routes: [NetworkRoute]
    var tailscale: TailscaleLocal

    enum CodingKeys: String, CodingKey { case interfaces, routes, tailscale }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        interfaces = try c.decodeIfPresent([NetworkInterface].self, forKey: .interfaces) ?? []
        tailscale = try c.decodeIfPresent(TailscaleLocal.self, forKey: .tailscale) ?? TailscaleLocal()
        let map = try c.decodeIfPresent([String: NetworkRoute].self, forKey: .routes) ?? [:]
        routes = map.keys.sorted().compactMap { key in
            guard var value = map[key] else { return nil }
            value.destination = key
            return value
        }
    }
}
struct TailscaleLocal: Decodable, Equatable { var selfOnline: Bool?; var healthWarnings: [String]?; var backend: String?; var controlHealthy: Bool?; var selfAddresses: [String]?; init() {}; enum CodingKeys:String,CodingKey { case selfOnline, healthWarnings, warnings, backend, controlHealthy, selfAddresses }; init(from decoder:Decoder) throws { let c=try decoder.container(keyedBy:CodingKeys.self); selfOnline=try c.decodeIfPresent(Bool.self,forKey:.selfOnline); healthWarnings=try c.decodeIfPresent([String].self,forKey:.healthWarnings) ?? c.decodeIfPresent([String].self,forKey:.warnings); backend=try c.decodeIfPresent(String.self,forKey:.backend); controlHealthy=try c.decodeIfPresent(Bool.self,forKey:.controlHealthy); selfAddresses=try c.decodeIfPresent([String].self,forKey:.selfAddresses) } }
struct NetworkInterface: Codable, Equatable, Identifiable { let name: String; var state: String?; var addresses: [String]?; var id: String { name } }
struct NetworkRoute: Decodable, Equatable, Identifiable { var destination: String; var gateway: String?; var interface: String?; var kind: String?; var available: Bool?; var id: String { [destination,gateway ?? "",interface ?? ""].joined(separator:"|") }; enum CodingKeys: String, CodingKey { case destination, target, gateway, interface, kind, available }; init(from decoder: Decoder) throws { let c=try decoder.container(keyedBy:CodingKeys.self); destination=try c.decodeIfPresent(String.self,forKey:.destination) ?? c.decodeIfPresent(String.self,forKey:.target) ?? "route"; gateway=try c.decodeIfPresent(String.self,forKey:.gateway); interface=try c.decodeIfPresent(String.self,forKey:.interface); kind=try c.decodeIfPresent(String.self,forKey:.kind); available=try c.decodeIfPresent(Bool.self,forKey:.available) } }
struct NetworkPeer: Decodable, Equatable, Identifiable { let name: String; var online: Bool?; var active: Bool?; var relay: String?; var directEndpoint: String?; var route: NetworkRoute?; var directRoute: Bool?; var latencyMs: Double?; var pingPath: String?; var lastSeen: String?; var routes: [String]?; var reason: String?; var warnings: [String]?; var addresses: [String]?; var ping: String?; var tcp22: String?; var ssh: String?; var remoteReport: RemoteReport?; var id: String { name }
    enum CodingKeys: String, CodingKey { case id, name, target, online, active, relay, route, directRoute = "direct_route", directEndpoint, latencyMs = "latency_ms", lastSeen, routes, reason, warnings, addresses, tailscalePing, tcp22, ssh, remoteHealth }
    init(from decoder: Decoder) throws { let c=try decoder.container(keyedBy:CodingKeys.self); name=try c.decodeIfPresent(String.self,forKey:.id) ?? c.decodeIfPresent(String.self,forKey:.name) ?? c.decodeIfPresent(String.self,forKey:.target) ?? "peer"; online=try c.decodeIfPresent(Bool.self,forKey:.online); active=try c.decodeIfPresent(Bool.self,forKey:.active); relay=try? c.decodeIfPresent(String.self,forKey:.relay); directEndpoint=try c.decodeIfPresent(String.self,forKey:.directEndpoint); route=try c.decodeIfPresent(NetworkRoute.self,forKey:.route); directRoute=try c.decodeIfPresent(Bool.self,forKey:.directRoute); let pingValue=try? c.decodeIfPresent(NetworkCheck.self,forKey:.tailscalePing); latencyMs=try c.decodeIfPresent(Double.self,forKey:.latencyMs) ?? pingValue?.latencyMs; pingPath=pingValue?.path; lastSeen=try c.decodeIfPresent(String.self,forKey:.lastSeen); routes=try c.decodeIfPresent([String].self,forKey:.routes); reason=try c.decodeIfPresent(String.self,forKey:.reason); warnings=try c.decodeIfPresent([String].self,forKey:.warnings); addresses=try c.decodeIfPresent([String].self,forKey:.addresses); ping=pingValue?.summary; tcp22=try? c.decodeIfPresent(NetworkCheck.self,forKey:.tcp22)?.summary; let sshValue=try? c.decodeIfPresent(RemoteCheck.self,forKey:.ssh); ssh=sshValue.map { $0.available == true ? "ok" : ($0.reason ?? "unavailable") }; remoteReport=sshValue?.report ?? (try? c.decodeIfPresent(RemoteReport.self,forKey:.remoteHealth)) }
    mutating func mergeProbe(_ value:NetworkPeer) { online=value.online ?? online; active=value.active ?? active; relay=value.relay ?? relay; latencyMs=value.latencyMs ?? latencyMs; pingPath=value.pingPath ?? pingPath; ping=value.ping ?? ping; tcp22=value.tcp22 ?? tcp22; ssh=value.ssh ?? ssh; reason=value.reason ?? reason; warnings=value.warnings ?? warnings; remoteReport=value.remoteReport ?? remoteReport; if !(value.addresses ?? []).isEmpty { addresses=value.addresses } }
}
struct NetworkCheck: Decodable { var ok: Bool?; var reason: String?; var output: String?; var path: String?; var latencyMs: Double?; var summary: String { if ok == true { return [latencyMs.map { "\(Int($0)) ms" },path].compactMap { $0 }.joined(separator:" via ").nilIfEmpty ?? "ok" }; return reason ?? "unavailable" } }
struct RemoteCheck: Decodable { var available: Bool?; var reason: String?; var report: RemoteReport? }
struct RemoteReport: Decodable, Equatable { var desiredProfile: String?; var observed: NetworkObserved?; var assessment: NetworkAssessment?; var tailscale: TailscaleLocal?; var audit: RemoteCommandResult?; var transferReadiness: RemoteCommandResult? }
struct RemoteCommandResult: Decodable, Equatable {
    var ok: Bool?; var code: Int?; var stdout: String?; var stderr: String?; var result: RemoteAuditResult?; var state: String?
    var transferSummary: String {
        switch state {
        case "ready": return "ready"
        case "unconfigured": return "not configured"
        case "blocked": return "blocked"
        default:
            if ok == true { return "ready" }
            let detail = "\(stdout ?? "")\n\(stderr ?? "")".lowercased()
            return detail.contains("missing:") || detail.contains("not configured") ? "not configured" : "blocked"
        }
    }
}
struct RemoteAuditResult: Decodable, Equatable { var ok: Bool?; var checks: [RemoteAuditCheck]?; var verdict: String? }
struct RemoteAuditCheck: Decodable, Equatable { var id: String?; var ok: Bool?; var detail: String? }
struct ProfilesEnvelope: Decodable { let schema: Int; let kind: String; let profiles: [NetworkPostureChoice] }
enum NetworkPostureContract {
    static func snapshot(from data: Data, kind expectedKind: String) -> NetworkPostureSnapshot? {
        guard let value = try? JSONDecoder().decode(NetworkPostureSnapshot.self, from: data),
              value.schema == 2,
              value.kind == expectedKind else {
            return nil
        }
        return value
    }

    static func profiles(from data: Data) -> [NetworkPostureChoice]? {
        guard let envelope = try? JSONDecoder().decode(ProfilesEnvelope.self, from: data),
              envelope.schema == 2,
              envelope.kind == "darkmesh-posture-profiles" else {
            return nil
        }
        return envelope.profiles.filter(\.isValid)
    }
}
enum NetworkPostureClass: Equatable { case healthy, degraded, failed, unavailable, stale }
struct NetworkProbeResult: Identifiable, Equatable { let id: String; let label: String; let required: Bool; let outcome: NetworkPostureClass; let detail: String? }
enum NetworkPostureClassifier { static func classify(snapshot: NetworkPostureSnapshot?, stale: Bool, probes: [NetworkProbeResult]) -> NetworkPostureClass { if stale { return .stale }; if probes.contains(where: { $0.required && $0.outcome != .healthy }) { return .failed }; let producer:NetworkPostureClass; if let severity=snapshot?.assessment?.severity { switch severity { case "green": producer = .healthy; case "yellow": producer = .degraded; case "red": producer = .failed; default: producer = .unavailable } } else { producer = .unavailable }; if producer == .healthy && probes.contains(where: { !$0.required && $0.outcome != .healthy }) { return .degraded }; return producer } }

private extension String { var nilIfEmpty:String? { isEmpty ? nil : self } }
