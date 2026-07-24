import ServiceManagement
import SwiftUI

@MainActor
final class BackgroundServiceManager: ObservableObject {
    static let agentPlistName = "vision.salient.InfrastructureAgent.plist"

    @Published private(set) var agentStatus: SMAppService.Status = .notRegistered
    @Published private(set) var loginStatus: SMAppService.Status = .notRegistered
    @Published private(set) var lastError: String?

    private let agent = SMAppService.agent(plistName: agentPlistName)
    private let loginItem = SMAppService.mainApp

    init(autoRegister: Bool = true) {
        refresh()
        if autoRegister { registerIfNeeded() }
    }

    var agentStatusText: String { description(agentStatus) }
    var loginStatusText: String { description(loginStatus) }
    var needsApproval: Bool { agentStatus == .requiresApproval || loginStatus == .requiresApproval }

    func registerIfNeeded() {
        var errors: [String] = []
        register(loginItem, named: "Login item", errors: &errors)
        register(agent, named: "Infrastructure agent", errors: &errors)
        lastError = errors.isEmpty ? nil : errors.joined(separator: " ")
        refresh()
    }

    func unregisterAgent() {
        do {
            try agent.unregister()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func refresh() {
        agentStatus = agent.status
        loginStatus = loginItem.status
    }

    private func register(_ service: SMAppService, named name: String, errors: inout [String]) {
        switch service.status {
        case .notRegistered, .notFound:
            do {
                try service.register()
            } catch {
                errors.append("\(name): \(error.localizedDescription)")
            }
        case .enabled, .requiresApproval:
            break
        @unknown default:
            errors.append("\(name): unsupported service status")
        }
    }

    private func description(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: return "Enabled"
        case .notRegistered: return "Not registered"
        case .requiresApproval: return "Approval required"
        case .notFound: return "Missing from app bundle"
        @unknown default: return "Unknown"
        }
    }
}
