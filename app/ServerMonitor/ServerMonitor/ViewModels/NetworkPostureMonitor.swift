import Foundation
import SwiftUI

@MainActor
final class NetworkPostureMonitor: ObservableObject {
    @Published private(set) var configured = false
    @Published private(set) var configurationError: String?
    @Published private(set) var snapshot: NetworkPostureSnapshot?
    @Published private(set) var staleReason: String?
    @Published private(set) var probes: [NetworkProbeResult] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var actionResult: String?
    @Published private(set) var diagnosticLog: [String] = []
    @Published private(set) var runningActionID: String?
    @Published private(set) var profiles: [NetworkPostureChoice] = []
    @Published private(set) var logOutput: [String: NetworkOutput] = [:]
    @Published private(set) var refreshInProgress = false
    @Published private(set) var lastActiveProbeAt: Date?
    private var config: NetworkPostureConfig?
    private var timer: Timer?
    private var activeProbePeers: [NetworkPeer] = []

    init() {}
    deinit { timer?.invalidate() }

    var posture: NetworkPostureClass { NetworkPostureClassifier.classify(snapshot: snapshot, stale: staleReason != nil, probes: probes) }
    var choices: [NetworkPostureChoice] { profiles.isEmpty ? (config?.postures ?? []) : profiles }
    var diagnostics: [NetworkCommandConfig] { config?.diagnostics ?? [] }
    var configuredProbes: [NetworkProbeConfig] { config?.probes ?? [] }

    func start() { loadConfiguration() }
    func stop() { timer?.invalidate(); timer = nil; runningActionID = nil }

    func loadConfiguration() {
        timer?.invalidate(); timer = nil; snapshot = nil; probes = []; activeProbePeers = []; lastActiveProbeAt = nil; staleReason = nil
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".config/server-monitor/network.json")
        guard FileManager.default.fileExists(atPath: path) else { configured = false; configurationError = nil; config = nil; return }
        do {
            let decoded = try JSONDecoder().decode(NetworkPostureConfig.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
            guard decoded.isValid else { throw CocoaError(.fileReadCorruptFile) }
            config = decoded; profiles = decoded.postures ?? []; configured = true; configurationError = nil; refreshProfiles(); refresh()
            let interval = max(10, decoded.pollSeconds ?? 30)
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in Task { @MainActor [weak self] in self?.refresh() } }
        } catch { configured = true; configurationError = "Invalid network.json: \(error.localizedDescription)"; config = nil }
    }

    func refresh() {
        guard let config, !refreshInProgress else { return }
        refreshInProgress = true
        let statusPath = config.statusFile.map { ($0 as NSString).expandingTildeInPath }
        let cachedActivePeers = activeProbePeers
        Task.detached { [weak self] in
            var decoded: NetworkPostureSnapshot?; var stale: String?
            if let statusPath {
                do {
                    decoded = try JSONDecoder().decode(NetworkPostureSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: statusPath)))
                    if let generated = decoded?.generatedAt, let age = SnapshotFreshness.age(of: generated), age > max(10, config.maxStatusAgeSeconds ?? 90) { stale = "status stale (\(Int(age))s old)" }
                } catch { stale = "status unavailable" }
            }
            if let command = config.statusCommand, !command.isEmpty {
                let run = ProcessRunner.run(command, timeout: 15)
                if run.succeeded, let fresh = try? JSONDecoder().decode(NetworkPostureSnapshot.self, from: run.data), fresh.schema == 2, fresh.kind == "darkmesh-posture" { decoded = fresh; stale = nil } else { stale = run.failureSummary() ?? "status contract unavailable" }
            }
            if let command = config.topologyCommand, !command.isEmpty {
                let run = ProcessRunner.run(command, timeout: 15)
                if run.succeeded, let topology = try? JSONDecoder().decode(NetworkPostureSnapshot.self, from: run.data), topology.schema == 2, topology.kind == "darkmesh-posture-topology" {
                    if decoded == nil { decoded = topology } else { decoded?.merge(topology: topology) }
                    decoded?.mergeActivePeers(cachedActivePeers)
                } else if !run.succeeded && decoded == nil {
                    stale = run.failureSummary()
                }
            }
            let finalSnapshot = decoded
            let finalStale = stale
            await MainActor.run { [weak self] in self?.snapshot = finalSnapshot; self?.staleReason = finalStale; self?.lastUpdated = Date(); self?.refreshInProgress = false }
        }
    }

    func refreshProfiles() {
        guard let command = config?.profilesCommand, !command.isEmpty else { return }
        Task.detached { [weak self] in
            let run = ProcessRunner.run(command, timeout: 15)
            let envelope = try? JSONDecoder().decode(ProfilesEnvelope.self, from: run.data)
            let producerValues = (envelope?.schema == 2 && envelope?.kind == "darkmesh-posture-profiles") ? envelope?.profiles : nil
            let legacyValues = try? JSONDecoder().decode([NetworkPostureChoice].self, from: run.data)
            let values = (producerValues ?? legacyValues ?? []).filter(\.isValid)
            guard let self else { return }
            await MainActor.run { self.profiles = values; self.actionResult = run.succeeded ? nil : run.failureSummary() }
        }
    }

    func run(_ command: NetworkCommandConfig) { execute(id: command.id, argv: command.command, timeout: command.timeoutSeconds ?? 15) }
    func runConfiguredProbe(_ probe: NetworkProbeConfig) {
        guard runningActionID == nil, !probe.command.isEmpty else { return }
        runningActionID = "probe-\(probe.id)"
        Task.detached { [weak self] in
            let result = ProcessRunner.run(probe.command, timeout: probe.timeoutSeconds ?? 15)
            let outcome: NetworkPostureClass = result.succeeded ? .healthy : .failed
            let value = NetworkProbeResult(id: probe.id, label: probe.label, required: probe.isRequired, outcome: outcome, detail: NetworkArgv.capped(result.output, maximum: 1_024))
            guard let self else { return }
            await MainActor.run { self.probes = self.probes.filter { $0.id != probe.id } + [value]; self.runningActionID = nil }
        }
    }
    func setPosture(_ choice: NetworkPostureChoice) {
        guard choice.transition?.apply != "refuse", (choice.capabilities ?? [:]).values.allSatisfy({ $0 }) else { actionResult = "\(choice.label): required capability unavailable"; return }
        let argv = config?.applyCommand.flatMap { NetworkArgv.applying($0, profile: choice.id) } ?? choice.setCommand
        guard !argv.isEmpty else { actionResult = "\(choice.label): apply command unavailable"; return }
        execute(id: choice.id, argv: argv, timeout: choice.timeoutSeconds ?? 360)
    }
    func refreshLog(_ source: NetworkLogSource) {
        Task.detached { [weak self] in
            let text: String
            if let path = source.path {
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                let data: Data
                if let handle = try? FileHandle(forReadingFrom: url), let size = try? handle.seekToEnd() {
                    try? handle.seek(toOffset: size > 32_768 ? size - 32_768 : 0)
                    data = (try? handle.readToEnd()) ?? Data(); try? handle.close()
                } else { data = Data() }
                text = String(data: data, encoding: .utf8) ?? "unavailable"
            }
            else { let run = ProcessRunner.run(source.command ?? [], timeout: source.timeoutSeconds ?? 15); text = run.output }
            guard let self else { return }
            await MainActor.run { self.logOutput[source.id] = NetworkOutput(text: NetworkArgv.capped(text), timestamp: Date(), stale: false) }
        }
    }
    var logSources: [NetworkLogSource] { config?.logSources ?? [] }
    func runActiveProbe() {
        guard let command = config?.probeCommand, !command.isEmpty else { actionResult = "Active peer probe is not configured"; return }
        guard runningActionID == nil else { return }; runningActionID = "active-peer-probe"
        let timeout = config?.activeProbeTimeoutSeconds ?? 120
        Task.detached { [weak self] in
            let run = ProcessRunner.run(command, timeout: timeout)
            let envelope = try? JSONDecoder().decode(NetworkPostureSnapshot.self, from: run.data)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if run.succeeded, let envelope, envelope.schema == 2, envelope.kind == "darkmesh-posture-probe" { self.activeProbePeers = envelope.peers; if self.snapshot == nil { self.snapshot = envelope } else { self.snapshot?.mergeActivePeers(envelope.peers) }; self.lastActiveProbeAt = Date(); self.lastUpdated = Date(); self.actionResult = "active-peer-probe: completed" }
                else { self.actionResult = "active-peer-probe: \(run.failureSummary() ?? "failed")" }
                self.runningActionID = nil
            }
        }
    }
    private func execute(id: String, argv: [String], timeout: Double) {
        guard runningActionID == nil else { return }
        guard !argv.isEmpty, !argv[0].isEmpty else { actionResult = "\(id): command unavailable"; return }
        runningActionID = id
        Task.detached { [weak self] in
            let run = ProcessRunner.run(argv, timeout: max(1, timeout))
            await MainActor.run { [weak self] in
                let detail = NetworkArgv.capped(run.output, maximum: 2_048)
                let line = run.succeeded ? "\(id): completed\n\(detail)" : "\(id): \(run.failureSummary() ?? "failed")\n\(detail)"
                self?.actionResult = line
                self?.diagnosticLog = (self?.diagnosticLog ?? []).suffix(19) + ["\(ISO8601DateFormatter().string(from: Date())) \(line)"]
                self?.runningActionID = nil
                self?.refresh()
            }
        }
    }
}
