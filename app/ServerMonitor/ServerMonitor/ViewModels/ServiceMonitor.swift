import Foundation
import SwiftUI
import UserNotifications

/// Configuration structure matching services.json
struct ServicesConfig: Codable {
    let version: String?
    let settings: Settings?
    let services: [ServiceConfig]
    
    struct Settings: Codable {
        let logDir: String?
        let identifierPrefix: String?
    }
    
    struct ServiceConfig: Codable {
        let name: String
        let identifier: String
        let path: String?
        let command: [String]?
        let port: Int?
        let healthCheck: String?
        let enabled: Bool?
    }
}

@MainActor
class ServiceMonitor: ObservableObject {
    @Published var services: [Service] = []
    @Published var lastUpdate: Date?
    private var timer: Timer?
    private var lastStatuses: [String: ServiceStatus] = [:]
    
    private let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("ios_code/server_monitor/services.json")
    
    init() {
        loadServicesFromConfig()
        requestNotificationPermission()
        startMonitoring()
    }
    
    /// Load services from the central services.json config file
    func loadServicesFromConfig() {
        do {
            let data = try Data(contentsOf: configPath)
            let config = try JSONDecoder().decode(ServicesConfig.self, from: data)
            
            services = config.services.map { svc in
                Service(
                    name: svc.name,
                    identifier: svc.identifier,
                    port: svc.port,
                    healthCheckURL: svc.healthCheck,
                    critical: true
                )
            }
            
            print("Loaded \(services.count) services from config")
        } catch {
            print("Failed to load services from config: \(error)")
            // Fallback to hardcoded services
            services = [
                Service(name: "Redo HTTPS", identifier: "vision.salient.redo-https", port: 3000, healthCheckURL: "https://localhost:3000"),
                Service(name: "Universe", identifier: "vision.salient.universe", port: 4001, healthCheckURL: "http://localhost:4001"),
                Service(name: "Vision", identifier: "vision.salient.vision", port: 4002, healthCheckURL: "http://localhost:4002"),
                Service(name: "Numina", identifier: "vision.salient.numina", port: 4003, healthCheckURL: "http://localhost:4003"),
                Service(name: "Knomee", identifier: "vision.salient.knomee", port: 4004, healthCheckURL: "http://localhost:4004")
            ]
        }
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    func startMonitoring() {
        checkAllServices()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAllServices()
            }
        }
    }
    
    func reloadConfig() {
        loadServicesFromConfig()
        checkAllServices()
    }
    
    func checkAllServices() {
        for i in services.indices {
            let service = services[i]
            let (status, pid) = checkService(service.identifier)
            
            // Check for status change and notify
            if let lastStatus = lastStatuses[service.identifier],
               lastStatus == .running && status == .stopped {
                sendNotification(serviceName: service.name)
            }
            lastStatuses[service.identifier] = status
            
            services[i].status = status
            services[i].pid = pid
        }
        lastUpdate = Date()
    }
    
    func checkService(_ identifier: String) -> (ServiceStatus, Int?) {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["list", identifier]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            if task.terminationStatus == 0 && !output.contains("Could not find") {
                // Parse PID from launchctl list output
                if let pidMatch = output.range(of: #"\"PID\" = (\d+)"#, options: .regularExpression) {
                    let pidStr = output[pidMatch].replacingOccurrences(of: "\"PID\" = ", with: "")
                    if let pid = Int(pidStr) {
                        return (.running, pid)
                    }
                }
                return (.running, nil)
            }
        } catch {}
        
        return (.stopped, nil)
    }
    
    func startService(_ service: Service) {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["start", service.identifier]
        try? task.run()
        task.waitUntilExit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.checkAllServices()
        }
    }
    
    func stopService(_ service: Service) {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["stop", service.identifier]
        try? task.run()
        task.waitUntilExit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.checkAllServices()
        }
    }
    
    func restartService(_ service: Service) {
        stopService(service)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.startService(service)
        }
    }
    
    func startAll() {
        for service in services {
            if service.status == .stopped {
                startService(service)
            }
        }
    }
    
    func stopAll() {
        for service in services {
            if service.status == .running {
                stopService(service)
            }
        }
    }
    
    func restartAll() {
        for service in services {
            restartService(service)
        }
    }
    
    func sendNotification(serviceName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Service Down"
        content.body = "\(serviceName) has stopped running"
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    var overallStatus: ServiceStatus {
        if services.allSatisfy({ $0.status == .running }) {
            return .running
        } else if services.contains(where: { $0.status == .stopped }) {
            return .stopped
        }
        return .unknown
    }
    
    var runningCount: Int {
        services.filter { $0.status == .running }.count
    }
    
    var totalCount: Int {
        services.count
    }
}
