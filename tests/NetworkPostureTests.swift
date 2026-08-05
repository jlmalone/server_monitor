import Foundation

@main
struct NetworkPostureTests {
    static func main() throws {
        let profiles = #"{"schema":2,"kind":"darkmesh-posture-profiles","profiles":[{"id":"tailscale-required-vpn-preferred","title":"Tailscale required, VPN secondary-high","required":{"tailscale":true},"preferred":{"vpn":true},"forbidden":{},"priority":["internet","tailscale","vpn"],"degraded":"VPN absence is yellow.","transition":{"apply":"bounded","attemptSecondary":true}}]}"#
        let envelope = try JSONDecoder().decode(ProfilesEnvelope.self, from: Data(profiles.utf8))
        precondition(envelope.profiles.first?.priority == ["internet", "tailscale", "vpn"])
        let descriptiveCapability = #"{"id":"supported","title":"Supported","capabilities":{"optionalTelemetry":false},"transition":{"apply":"bounded"},"consequence":"May reconnect the preferred tunnel."}"#
        let supported = try JSONDecoder().decode(NetworkPostureChoice.self, from: Data(descriptiveCapability.utf8))
        precondition(supported.canApply && supported.confirmationText == "May reconnect the preferred tunnel.")
        let refusedCapability = #"{"id":"strict","title":"Strict","capabilities":{"zeroGeneralEgressLeak":false},"transition":{"apply":"refuse"}}"#
        let refused = try JSONDecoder().decode(NetworkPostureChoice.self, from: Data(refusedCapability.utf8))
        precondition(!refused.canApply)
        let unknownTransition = #"{"id":"future","title":"Future","transition":{"apply":"future-policy"}}"#
        let unknown = try JSONDecoder().decode(NetworkPostureChoice.self, from: Data(unknownTransition.utf8))
        precondition(!unknown.canApply)
        precondition(NetworkPostureContract.profiles(from: Data(profiles.utf8))?.count == 1)
        precondition(NetworkPostureContract.profiles(from: Data("[]".utf8)) == nil)
        let status = #"{"schema":2,"kind":"darkmesh-posture","desiredProfile":"tailscale-required-vpn-preferred","observed":{"available":true,"fresh":true,"reason":"ok","internet":true,"vpn":false,"vpnState":"Disconnected","tailscale":true,"transferSafety":true,"verdict":"GO","ageSeconds":1},"assessment":{"severity":"yellow","state":"degraded","reason":"preferred-unavailable","required":{"tailscale":true},"preferred":{"vpn":false},"forbidden":{}}}"#
        precondition(NetworkPostureContract.snapshot(from: Data(status.utf8), kind: "darkmesh-posture") != nil)
        precondition(NetworkPostureContract.snapshot(from: Data(status.utf8), kind: "darkmesh-posture-topology") == nil)
        let snapshot = try JSONDecoder().decode(NetworkPostureSnapshot.self, from: Data(status.utf8))
        precondition(snapshot.assessment?.severity == "yellow" && snapshot.observed?.vpnState == "Disconnected")
        let topology = #"{"schema":2,"kind":"darkmesh-posture-topology","generatedAt":"2026-08-04T12:00:00Z","local":{"interfaces":[{"name":"en0","state":"active","addresses":["192.0.2.10"]}],"routes":{"physicalDefault":{"target":"default","interface":"en0","available":true},"tailscaleSentinel":{"target":"100.64.0.1","interface":"utun4","available":true}},"tailscale":{"backend":"Running","selfOnline":true,"controlHealthy":true,"selfAddresses":["100.100.100.1"],"healthWarnings":["warning"]}},"peers":[{"id":"host-a","target":"host-a","online":true,"active":true,"relay":"relay-a","directEndpoint":"192.0.2.2:41641","route":{"target":"100.100.100.2","interface":"utun4","available":true},"addresses":["100.100.100.2"],"tailscalePing":{"ok":true,"reason":"ok","output":"pong"},"tcp22":{"ok":true,"reason":"ok"},"ssh":{"available":true,"report":{"desiredProfile":"safe","observed":{"internet":true},"audit":{"ok":true,"code":0,"stdout":"checks","stderr":""},"transferReadiness":{"ok":false,"code":1,"stdout":"","stderr":"missing: TransferClient.ini","state":"unconfigured"},"assessment":{"severity":"green","state":"healthy","reason":"ok","required":{},"preferred":{},"forbidden":{}}}}}]}"#
        let passive = try JSONDecoder().decode(NetworkPostureSnapshot.self, from: Data(topology.utf8))
        var merged = snapshot; merged.merge(topology: passive)
        precondition(merged.interfaces.first?.name == "en0" && merged.localTailscale?.controlHealthy == true && merged.peers.first?.route?.interface == "utun4" && merged.peers.first?.remoteReport?.audit?.stdout == "checks")
        precondition(merged.routes.map(\.destination) == ["physicalDefault", "tailscaleSentinel"])
        precondition(merged.peers.first?.remoteReport?.transferReadiness?.transferSummary == "not configured")
        let legacyRemoteHealth = #"{"id":"host-b","reason":"cached","warnings":["relay only"],"remoteHealth":{"desiredProfile":"safe","assessment":{"severity":"green","state":"healthy","reason":"ok"}}}"#
        let legacyPeer = try JSONDecoder().decode(NetworkPeer.self, from: Data(legacyRemoteHealth.utf8))
        precondition(legacyPeer.reason == "cached" && legacyPeer.warnings == ["relay only"] && legacyPeer.remoteReport?.desiredProfile == "safe")
        let activeJSON = #"{"schema":2,"kind":"darkmesh-posture-probe","peers":[{"id":"host-a","target":"host-a","online":true,"tailscalePing":{"ok":true,"reason":"ok","path":"DERP(sea)","latencyMs":64},"tcp22":{"ok":true,"reason":"ok"},"ssh":{"available":true,"report":{"assessment":{"severity":"gray","state":"unavailable","reason":"profile-unselected"}}}}]}"#
        let active = try JSONDecoder().decode(NetworkPostureSnapshot.self, from: Data(activeJSON.utf8))
        merged.mergeActivePeers(active.peers)
        precondition(merged.peers.first?.ping == "64 ms via DERP(sea)" && merged.peers.first?.route?.interface == "utun4" && merged.peers.first?.remoteReport?.assessment?.severity == "gray")
        precondition(NetworkPostureClassifier.classify(snapshot: snapshot, stale: false, probes: []) == .degraded)
        precondition(NetworkPostureClassifier.classify(snapshot: snapshot, stale: true, probes: []) == .stale)
        let invalid = NetworkPostureConfig(schema: 2, pollSeconds: nil, statusFile: nil, profilesCommand: nil, statusCommand: nil, topologyCommand: nil, probeCommand: nil, activeProbeTimeoutSeconds: nil, applyCommand: nil, logSources: nil, maxStatusAgeSeconds: nil, probes: nil, diagnostics: nil, postures: nil)
        precondition(!invalid.isValid)
        precondition(NetworkArgv.applying(["tool", "apply", "{profile}"], profile: "safe") == ["tool", "apply", "safe"])
        precondition(NetworkArgv.applying(["tool", "apply"], profile: "safe") == nil)
        precondition(NetworkArgv.capped("a\u{0001}b", maximum: 8) == "a b")
        let optionalFailure = NetworkProbeResult(id: "optional", label: "Optional", required: false, outcome: .failed, detail: nil)
        let requiredFailure = NetworkProbeResult(id: "required", label: "Required", required: true, outcome: .failed, detail: nil)
        let greenStatus = status.replacingOccurrences(of: "\"yellow\"", with: "\"green\"").replacingOccurrences(of: "\"degraded\"", with: "\"healthy\"")
        let greenSnapshot = try JSONDecoder().decode(NetworkPostureSnapshot.self, from: Data(greenStatus.utf8))
        precondition(NetworkPostureClassifier.classify(snapshot: greenSnapshot, stale: false, probes: [optionalFailure]) == .degraded)
        precondition(NetworkPostureClassifier.classify(snapshot: greenSnapshot, stale: false, probes: [requiredFailure]) == .failed)
        print("NetworkPostureTests passed")
    }
}
