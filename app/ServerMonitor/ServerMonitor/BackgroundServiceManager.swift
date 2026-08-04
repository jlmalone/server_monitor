import Foundation
import ServiceManagement
import SwiftUI

struct BackgroundRegistrationStamp {
    static func current(bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return "\(bundle.bundleURL.standardizedFileURL.path)|\(version)"
    }

    static func needsRefresh(stored: String?, current: String) -> Bool {
        stored != current
    }
}

@MainActor
final class BackgroundServiceManager: ObservableObject {
    static let agentPlistName = "vision.salient.InfrastructureAgent.plist"
    private static let registrationStampKey = "backgroundRegistrationStamp"

    @Published private(set) var agentStatus: SMAppService.Status = .notRegistered
    @Published private(set) var loginStatus: SMAppService.Status = .notRegistered
    @Published private(set) var lastError: String?

    private let agent = SMAppService.agent(plistName: agentPlistName)
    private let loginItem = SMAppService.mainApp
    private let defaults: UserDefaults
    private let registrationStamp: String

    init(
        autoRegister: Bool = true,
        defaults: UserDefaults = .standard,
        registrationStamp: String = BackgroundRegistrationStamp.current()
    ) {
        self.defaults = defaults
        self.registrationStamp = registrationStamp
        refresh()
        if autoRegister { reconcileRegistration() }
    }

    var agentStatusText: String { description(agentStatus) }
    var loginStatusText: String { description(loginStatus) }
    var needsApproval: Bool { agentStatus == .requiresApproval || loginStatus == .requiresApproval }

    func registerIfNeeded() {
        var errors: [String] = []
        registerServices(errors: &errors)
        finishRegistration(errors: errors)
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

    private func reconcileRegistration() {
        var errors: [String] = []
        let storedStamp = defaults.string(forKey: Self.registrationStampKey)
        if BackgroundRegistrationStamp.needsRefresh(stored: storedStamp, current: registrationStamp) {
            unregisterIfRegistered(agent, named: "Infrastructure agent", errors: &errors)
            unregisterIfRegistered(loginItem, named: "Login item", errors: &errors)
            refresh()
        }
        registerServices(errors: &errors)
        finishRegistration(errors: errors)
    }

    private func registerServices(errors: inout [String]) {
        register(loginItem, named: "Login item", errors: &errors)
        register(agent, named: "Infrastructure agent", errors: &errors)
    }

    private func unregisterIfRegistered(
        _ service: SMAppService,
        named name: String,
        errors: inout [String]
    ) {
        switch service.status {
        case .enabled, .requiresApproval:
            do {
                try service.unregister()
            } catch {
                errors.append("\(name) refresh: \(error.localizedDescription)")
            }
        case .notRegistered, .notFound:
            break
        @unknown default:
            errors.append("\(name) refresh: unsupported service status")
        }
    }

    private func finishRegistration(errors: [String]) {
        lastError = errors.isEmpty ? nil : errors.joined(separator: " ")
        refresh()
        if errors.isEmpty, registrationIsUsable {
            defaults.set(registrationStamp, forKey: Self.registrationStampKey)
        }
    }

    private var registrationIsUsable: Bool {
        [loginItem.status, agent.status].allSatisfy {
            $0 == .enabled || $0 == .requiresApproval
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
