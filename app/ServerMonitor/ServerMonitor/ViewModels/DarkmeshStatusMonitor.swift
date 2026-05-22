import Foundation
import SwiftUI

/// Observable that mirrors `/tmp/darkmesh-status.json` for the menu-bar UI.
///
/// The source of truth is `darkmesh-healthcheck` (a LaunchAgent in the
/// darkmesh-vpn-guard project). This class is a read-only consumer: it polls
/// the JSON file every `pollInterval` seconds and republishes the latest
/// status to SwiftUI views.
///
/// No network policy is implemented here. If the file doesn't exist, `status`
/// stays nil and the UI should render a "darkmesh not installed" hint.
@MainActor
final class DarkmeshStatusMonitor: ObservableObject {
    @Published private(set) var status: DarkmeshStatus?
    @Published private(set) var lastReadAt: Date?
    @Published private(set) var fileMissing: Bool = false
    @Published private(set) var parseError: String?

    private let statusFileURL = URL(fileURLWithPath: "/tmp/darkmesh-status.json")
    private let pollInterval: TimeInterval
    private var timer: Timer?
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    init(pollInterval: TimeInterval = 5) {
        self.pollInterval = pollInterval
        readNow()
        start()
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.readNow() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func readNow() {
        guard FileManager.default.fileExists(atPath: statusFileURL.path) else {
            fileMissing = true
            status = nil
            return
        }
        fileMissing = false

        do {
            let data = try Data(contentsOf: statusFileURL)
            let decoded = try decoder.decode(DarkmeshStatus.self, from: data)
            status = decoded
            lastReadAt = Date()
            parseError = nil
        } catch {
            parseError = String(describing: error)
        }
    }
}
