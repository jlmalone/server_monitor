import Foundation

@main
struct NetworkPostureTests {
    static func main() throws {
        let profiles = #"{"schema":2,"kind":"darkmesh-posture-profiles","profiles":[{"id":"tailscale-required-vpn-preferred","title":"Tailscale required, VPN secondary-high","required":{"tailscale":true},"preferred":{"vpn":true},"forbidden":{},"priority":["internet","tailscale","vpn"],"degraded":"VPN absence is yellow.","transition":{"apply":"bounded","attemptSecondary":true}}]}"#
        let envelope = try JSONDecoder().decode(ProfilesEnvelope.self, from: Data(profiles.utf8))
        precondition(envelope.profiles.first?.priority == ["internet", "tailscale", "vpn"])
        let status = #"{"schema":2,"kind":"darkmesh-posture","desiredProfile":"tailscale-required-vpn-preferred","observed":{"available":true,"fresh":true,"reason":"ok","internet":true,"vpn":false,"vpnState":"Disconnected","tailscale":true,"transferSafety":true,"verdict":"GO","ageSeconds":1},"assessment":{"severity":"yellow","state":"degraded","reason":"preferred-unavailable","required":{"tailscale":true},"preferred":{"vpn":false},"forbidden":{}}}"#
        let snapshot = try JSONDecoder().decode(NetworkPostureSnapshot.self, from: Data(status.utf8))
        precondition(snapshot.assessment?.severity == "yellow" && snapshot.observed?.vpnState == "Disconnected")
        let topology = #"{"schema":2,"kind":"darkmesh-posture-topology","generatedAt":"2026-08-04T12:00:00Z","local":{"interfaces":[{"name":"en0","state":"active","addresses":["192.0.2.10"]}],"routes":{"physicalDefault":{"target":"default","interface":"en0","available":true},"tailscaleSentinel":{"target":"100.64.0.1","interface":"utun4","available":true}},"tailscale":{"backend":"Running","selfOnline":true,"controlHealthy":true,"selfAddresses":["100.100.100.1"],"healthWarnings":["warning"]}},"peers":[{"id":"host-a","target":"host-a","online":true,"active":true,"relay":"relay-a","directEndpoint":"192.0.2.2:41641","route":{"target":"100.100.100.2","interface":"utun4","available":true},"addresses":["100.100.100.2"],"tailscalePing":{"ok":true,"reason":"ok","output":"pong"},"tcp22":{"ok":true,"reason":"ok"},"ssh":{"available":true,"report":{"desiredProfile":"safe","observed":{"internet":true},"audit":{"ok":true,"code":0,"stdout":"checks","stderr":""},"transferReadiness":{"ok":true,"code":0,"stdout":"binding","stderr":""},"assessment":{"severity":"green","state":"healthy","reason":"ok","required":{},"preferred":{},"forbidden":{}}}}}]}"#
        let passive = try JSONDecoder().decode(NetworkPostureSnapshot.self, from: Data(topology.utf8))
        var merged = snapshot; merged.merge(topology: passive)
        precondition(merged.interfaces.first?.name == "en0" && merged.localTailscale?.controlHealthy == true && merged.peers.first?.route?.interface == "utun4" && merged.peers.first?.remoteReport?.audit?.stdout == "checks")
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
