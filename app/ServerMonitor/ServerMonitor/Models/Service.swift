import Foundation
import SwiftUI

enum ServiceStatus: String, Codable {
    case running
    case stopped
    case unknown
    case checking
    
    var color: Color {
        switch self {
        case .running: return .green
        case .stopped: return .red
        case .unknown: return .gray
        case .checking: return .orange
        }
    }
    
    var icon: String {
        switch self {
        case .running: return "circle.fill"
        case .stopped: return "circle.fill"
        case .unknown: return "questionmark.circle"
        case .checking: return "circle.dotted"
        }
    }
}

struct Service: Identifiable, Codable {
    var id: UUID
    var name: String
    var identifier: String  // launchd identifier
    var port: Int?
    var healthCheckURL: String?
    var critical: Bool
    
    // Config fields
    var path: String?
    var command: [String]?
    var enabled: Bool?
    var keepAlive: Bool?
    var environmentVariables: [String: String]?
    
    // Runtime state (not persisted)
    var status: ServiceStatus = .unknown
    var pid: Int?
    var lastChecked: Date?
    var errorMessage: String?
    
    init(id: UUID = UUID(), name: String, identifier: String, port: Int? = nil, healthCheckURL: String? = nil, critical: Bool = true, path: String? = nil, command: [String]? = nil, enabled: Bool = true, keepAlive: Bool = true) {
        self.id = id
        self.name = name
        self.identifier = identifier
        self.port = port
        self.healthCheckURL = healthCheckURL
        self.critical = critical
        self.path = path
        self.command = command
        self.enabled = enabled
        self.keepAlive = keepAlive
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, identifier, port, healthCheckURL, critical
        case path, command, enabled, keepAlive, environmentVariables
    }
}

enum OverallStatus {
    case allHealthy
    case someDown
    case allDown
    case checking
    
    var color: Color {
        switch self {
        case .allHealthy: return .green
        case .someDown: return .yellow
        case .allDown: return .red
        case .checking: return .orange
        }
    }
    
    var icon: String {
        switch self {
        case .allHealthy: return "checkmark.circle.fill"
        case .someDown: return "exclamationmark.triangle.fill"
        case .allDown: return "xmark.circle.fill"
        case .checking: return "arrow.triangle.2.circlepath"
        }
    }
}
