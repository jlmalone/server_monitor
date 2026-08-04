import SwiftUI

struct NetworkStatusWindow: View {
    @ObservedObject var monitor: NetworkPostureMonitor
    @State private var pendingPosture: NetworkPostureChoice?
    @State private var confirmingPosture = false
    @State private var selectedProfileID = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Label("Network Status", systemImage: "point.3.connected.trianglepath.dotted").font(.headline); badge(monitor.posture); Spacer(); if let date = monitor.lastUpdated { Text("Updated \(date, style: .relative) ago").font(.caption).foregroundStyle(.secondary) }; Button { monitor.refresh() } label: { Image(systemName: "arrow.clockwise") } }.padding(12)
            Divider()
            if !monitor.configured { placeholder("Network Status is not configured", "Add ~/.config/server-monitor/network.json from config/network.example.json.") }
            else if let error = monitor.configurationError { placeholder("Configuration unavailable", error) }
            else { content }
        }
        .frame(minWidth: 680, minHeight: 520)
        .confirmationDialog("Apply network posture?", isPresented: $confirmingPosture, titleVisibility: .visible) { Button("Apply \(pendingPosture?.label ?? "posture")", role: .destructive) { if let choice = pendingPosture { monitor.setPosture(choice) }; pendingPosture = nil }; Button("Cancel", role: .cancel) { pendingPosture = nil } } message: { Text(pendingPosture?.degraded ?? "This runs the configured direct command. It may change network connectivity.") }
    }
    private var content: some View { ScrollView { VStack(alignment: .leading, spacing: 14) { picker; posture; topology; peers; healthProbes; diagnostics; if let result = monitor.actionResult { Text(result).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) } }.padding(14) } }
    @ViewBuilder private var picker: some View { if !monitor.choices.isEmpty { GroupBox("Desired posture") { VStack(alignment: .leading, spacing: 8) { Picker("Profile", selection: $selectedProfileID) { ForEach(monitor.choices) { Text($0.label).tag($0.id) } }.onAppear { selectedProfileID = monitor.snapshot?.desired ?? monitor.choices.first?.id ?? "" }.task(id: monitor.snapshot?.desired) { if let value=monitor.snapshot?.desired { selectedProfileID=value } }; HStack { if let choice = monitor.choices.first(where: { $0.id == selectedProfileID }) { Text(choice.degraded ?? "No consequence published").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Apply") { pendingPosture = choice; confirmingPosture = true }.disabled(monitor.runningActionID != nil || choice.transition?.apply == "refuse" || (choice.capabilities ?? [:]).values.contains(false)) }; }.padding(.top, 2) } } } }
    private var posture: some View { GroupBox("Posture") { Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) { row("Desired", monitor.snapshot?.desired ?? "unavailable"); row("Observed", monitor.snapshot?.observed?.compact ?? "unavailable"); row("Assessment", monitor.snapshot?.assessment.map { "\($0.severity) · \($0.reason)" } ?? "unknown"); row("Degradation", monitor.snapshot?.degradation.joined(separator: ", ") ?? "none"); if let stale = monitor.staleReason { row("Availability", stale) } }.padding(.top, 2) } }
    private var topology: some View { GroupBox("Local topology") { VStack(alignment: .leading, spacing: 7) { TopologyGraph(snapshot: monitor.snapshot).frame(height: 130); if let ts=monitor.snapshot?.localTailscale { Text("Tailscale: \(ts.backend ?? "unknown") · control \(ts.controlHealthy == true ? "healthy" : "unknown") · \(ts.selfAddresses?.joined(separator: ", ") ?? "no self address")").font(.caption); if !(ts.healthWarnings ?? []).isEmpty { Text(ts.healthWarnings!.joined(separator: ", ")).font(.caption).foregroundStyle(.yellow) } }; if monitor.snapshot?.interfaces.isEmpty != false { Text("No interface topology published").foregroundStyle(.secondary) }; ForEach(monitor.snapshot?.interfaces ?? []) { iface in HStack { Image(systemName: "network"); Text(iface.name).font(.body.monospaced()); Text(iface.state ?? "unknown").foregroundStyle(.secondary); Spacer(); Text((iface.addresses ?? []).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) } }; ForEach(monitor.snapshot?.routes ?? []) { route in HStack(spacing: 5) { Image(systemName: "arrow.right").foregroundStyle(.secondary); Text(route.destination).font(.caption.monospaced()); Text("via \(route.gateway ?? "?")").font(.caption).foregroundStyle(.secondary); Text(route.interface ?? "?").font(.caption.monospaced()).foregroundStyle(.secondary) } } }.padding(.top, 2) } }
    private var peers: some View { GroupBox("Tailscale peers") { VStack(alignment: .leading, spacing: 7) { if monitor.snapshot?.peers.isEmpty != false { Text("No peer data published").foregroundStyle(.secondary) }; ForEach(monitor.snapshot?.peers ?? []) { peer in VStack(alignment: .leading, spacing: 3) { HStack { Circle().fill(peer.online == true ? .green : .secondary).frame(width: 8, height: 8); Text(peer.name); Spacer(); tag(peer.pingPath ?? peer.relay ?? "no route"); Text(peer.lastSeen ?? "unknown").font(.caption).foregroundStyle(.secondary) }; Text("route \(peer.route?.interface ?? "?") · endpoint \(peer.directEndpoint ?? "none") · ping \(peer.ping ?? "not run") · tcp \(peer.tcp22 ?? "not run") · ssh \(peer.ssh ?? "not run")").font(.caption.monospaced()); if let report=peer.remoteReport { let failed=report.audit?.result?.checks?.filter { $0.ok == false }.compactMap(\.id) ?? []; Text("remote desired \(report.desiredProfile ?? "unknown") · \(report.observed?.compact ?? "state unavailable")").font(.caption.monospaced()); Text("audit \(report.audit?.ok == true ? "pass" : "fail")\(failed.isEmpty ? "" : " [\(failed.joined(separator: ", "))]") · transfer client \(report.transferReadiness?.transferSummary ?? "unknown")").font(.caption.monospaced()); if !(report.tailscale?.healthWarnings ?? []).isEmpty { Text(report.tailscale!.healthWarnings!.joined(separator: ", ")).font(.caption).foregroundStyle(.yellow) } } } } }.padding(.top, 2) } }
    private var healthProbes: some View {
        let results: [NetworkProbeResult] = monitor.probes
        return GroupBox("Read-only health probes") {
            VStack(alignment: .leading, spacing: 6) {
                HStack { Button("Run active peer probe") { monitor.runActiveProbe() }.disabled(monitor.runningActionID != nil); ForEach(monitor.configuredProbes) { probe in Button(probe.label) { monitor.runConfiguredProbe(probe) }.disabled(monitor.runningActionID != nil) } }
                Text(monitor.lastActiveProbeAt.map { "Active peer result cached from \($0.formatted()). Passive topology refresh is automatic while this window is open." } ?? "Active peer checks have not run. Passive topology refresh is automatic while this window is open.").font(.caption).foregroundStyle(.secondary)
                Text(results.map { "\($0.label) [\($0.required ? "required" : "optional")]: \($0.detail ?? label($0.outcome))" }.joined(separator: "\n"))
                    .font(.caption.monospaced()).textSelection(.enabled)
            }.padding(.top, 2)
        }
    }
    @ViewBuilder private var diagnostics: some View { if !monitor.diagnostics.isEmpty || !monitor.logSources.isEmpty { GroupBox("Diagnostics and logs") { VStack(alignment: .leading) { HStack { ForEach(monitor.diagnostics) { command in Button(command.label) { monitor.run(command) }.disabled(monitor.runningActionID != nil) }; ForEach(monitor.logSources) { source in Button("Refresh \(source.label)") { monitor.refreshLog(source) } }; Spacer() }; if !monitor.diagnosticLog.isEmpty { Text(monitor.diagnosticLog.joined(separator: "\n")).font(.caption.monospaced()).lineLimit(8).textSelection(.enabled) }; ForEach(monitor.logSources) { source in if let output = monitor.logOutput[source.id] { Text("\(source.label) · \(output.timestamp.formatted() )\n\(output.text)").font(.caption.monospaced()).lineLimit(8).textSelection(.enabled) } } }.padding(.top, 2) } } }
    private func row(_ title: String, _ value: String) -> some View { GridRow { Text(title).foregroundStyle(.secondary); Text(value).textSelection(.enabled) } }
    private func tag(_ text: String) -> some View { Text(text).font(.caption2).padding(.horizontal, 5).padding(.vertical, 2).background(.quaternary, in: Capsule()) }
    private func badge(_ status: NetworkPostureClass) -> some View { Text(label(status)).font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 3).foregroundStyle(color(status)).background(color(status).opacity(0.14), in: Capsule()) }
    private func label(_ status: NetworkPostureClass) -> String { switch status { case .healthy: return "OK"; case .degraded: return "DEGRADED"; case .failed: return "REQUIRED FAILED"; case .unavailable: return "UNAVAILABLE"; case .stale: return "STALE" } }
    private func color(_ status: NetworkPostureClass) -> Color { switch status { case .healthy: return .green; case .degraded: return .yellow; case .failed: return .red; case .unavailable, .stale: return .secondary } }
    private func placeholder(_ title: String, _ detail: String) -> some View { VStack(spacing: 10) { Image(systemName: "network.slash").font(.system(size: 34)).foregroundStyle(.secondary); Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 430) }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(40) }
}

private struct TopologyGraph: View {
    let snapshot: NetworkPostureSnapshot?
    var body: some View { Canvas { context, size in
        let routes=snapshot?.routes ?? []; let peers=snapshot?.peers ?? []
        let physicalRoute=routes.first { $0.destination == "physicalDefault" }; let internetRoute=routes.first { $0.destination == "internetEgress" }; let tailRoute=routes.first { $0.destination == "tailscaleSentinel" }
        let physical=physicalRoute?.available == true; let internet=snapshot?.observed?.internet == true; let vpn=snapshot?.observed?.vpn == true; let tail=snapshot?.localTailscale?.selfOnline == true && tailRoute?.available == true
        let pPhysical=CGPoint(x:45,y:size.height/2); let pVPN=CGPoint(x:160,y:28); let pInternet=CGPoint(x:275,y:28); let pTail=CGPoint(x:160,y:size.height-28)
        func edge(_ a:CGPoint,_ b:CGPoint,_ ok:Bool) { var path=Path(); path.move(to:a); path.addLine(to:b); context.stroke(path,with:.color(ok ? .green : .gray),lineWidth:2) }
        if vpn { edge(pPhysical,pVPN,physical); edge(pVPN,pInternet,internet) } else { edge(pPhysical,pInternet,physical && internet); edge(pPhysical,pVPN,false) }
        edge(pPhysical,pTail,tail)
        for (index,peer) in peers.prefix(3).enumerated() { let point=CGPoint(x:390,y:22+CGFloat(index)*42); edge(pTail,point,tail && peer.online == true && peer.route?.available != false); context.draw(Text(peer.name).font(.caption2),at:CGPoint(x:435,y:point.y)) }
        let physicalAddress=snapshot?.interfaces.first(where: { $0.name == physicalRoute?.interface })?.addresses?.first
        let nodes:[(CGPoint,String,Bool)]=[(pPhysical,[physicalRoute?.interface ?? "Physical",physicalAddress].compactMap{$0}.joined(separator:" · "),physical),(pVPN,"VPN · \(snapshot?.observed?.vpnState ?? "unknown")",vpn),(pInternet,"Internet · \(internetRoute?.interface ?? "?")",internet),(pTail,"Tailscale · \(tailRoute?.interface ?? "?")",tail)]
        for (point,label,ok) in nodes { context.fill(Path(ellipseIn:CGRect(x:point.x-8,y:point.y-8,width:16,height:16)),with:.color(ok ? .green : .gray)); context.draw(Text(label).font(.caption2),at:CGPoint(x:point.x,y:point.y+18)) }
    } }
}
