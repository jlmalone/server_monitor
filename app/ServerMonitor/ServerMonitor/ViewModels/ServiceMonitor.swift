import Foundation
import SwiftUI
import UserNotifications

@MainActor
class ServiceMonitor: ObservableObject {
    @Published var services: [Service] = []
    
    @Published var lastUpdate: Date?
    private var timer: Timer?
    private var lastStatuses: [String: ServiceStatus] = [:]
    
    init() {
        loadServicesFromConfig()
        requestNotificationPermission()
        startMonitoring()
    }

    func loadServicesFromConfig() {
        // Try multiple locations for services.json
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let currentDir = FileManager.default.currentDirectoryPath

        let paths = [
            // 1. Current directory (if running from project)
            URL(fileURLWithPath: currentDir).appendingPathComponent("services.json"),
            URL(fileURLWithPath: currentDir).appendingPathComponent("../services.json"),
            URL(fileURLWithPath: currentDir).appendingPathComponent("../../services.json"),

            // 2. Application Support directory
            homeDir.appendingPathComponent("Library/Application Support/ServerMonitor/services.json"),

            // 3. Example file as fallback
            URL(fileURLWithPath: currentDir).appendingPathComponent("services.example.json"),
            URL(fileURLWithPath: currentDir).appendingPathComponent("../services.example.json"),
            URL(fileURLWithPath: currentDir).appendingPathComponent("../../services.example.json")
        ]

        for path in paths {
            if let data = try? Data(contentsOf: path),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let servicesArray = json["services"] as? [[String: Any]] {

                services = servicesArray.compactMap { dict in
                    guard let name = dict["name"] as? String,
                          let identifier = dict["identifier"] as? String,
                          let port = dict["port"] as? Int,
                          let healthCheck = dict["healthCheck"] as? String,
                          let enabled = dict["enabled"] as? Bool,
                          enabled else { return nil }

                    return Service(name: name, identifier: identifier, port: port, healthCheckURL: healthCheck)
                }

                if !services.isEmpty {
                    return
                }
            }
        }

        // If no config found, use empty list
        print("⚠️ No services.json found. Please copy services.example.json to services.json")
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    func startMonitoring() {
        checkAllServices()
        timer = Timer.scheduledTimer(withTimeInterval: 45.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAllServices()
            }
        }
    }
    
    func checkAllServices() {
        for i in services.indices {
            let service = services[i]
            let (status, pid) = checkService(service.identifier)
            
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
        let (status, _) = checkService(service.identifier)

        // If not loaded, load the plist first
        if status == .stopped {
            let plistPath = "\(NSHomeDirectory())/Library/LaunchAgents/\(service.identifier).plist"
            let loadTask = Process()
            loadTask.launchPath = "/bin/launchctl"
            loadTask.arguments = ["load", plistPath]
            try? loadTask.run()
            loadTask.waitUntilExit()

            // Wait a moment for load to complete
            Thread.sleep(forTimeInterval: 0.5)
        }

        // Now start the service
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["start", service.identifier]
        try? task.run()
        task.waitUntilExit()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.checkAllServices() }
    }
    
    func stopService(_ service: Service) {
        // Get PID before stopping
        let (_, pid) = checkService(service.identifier)

        // Method 1: Unload the service (prevents KeepAlive from restarting)
        let plistPath = "\(NSHomeDirectory())/Library/LaunchAgents/\(service.identifier).plist"
        let unloadTask = Process()
        unloadTask.launchPath = "/bin/launchctl"
        unloadTask.arguments = ["unload", plistPath]
        try? unloadTask.run()
        unloadTask.waitUntilExit()

        // Method 2: Kill PID directly as backup
        if let pid = pid {
            let killTask = Process()
            killTask.launchPath = "/bin/kill"
            killTask.arguments = ["\(pid)"]
            try? killTask.run()
            killTask.waitUntilExit()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.checkAllServices() }
    }
    
    func restartService(_ service: Service) {
        stopService(service)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.startService(service) }
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
        if services.allSatisfy({ $0.status == .running }) { return .running }
        else if services.contains(where: { $0.status == .stopped }) { return .stopped }
        return .unknown
    }
    
    var runningCount: Int {
        services.filter { $0.status == .running }.count
    }
    
    var totalCount: Int {
        services.count
    }
    
    func startAll() {
        for service in services where service.status != .running {
            startService(service)
        }
    }
    
    func stopAll() {
        for service in services where service.status == .running {
            stopService(service)
        }
    }
    
    func restartAll() {
        for service in services {
            restartService(service)
        }
    }
    
    func reloadConfig() {
        // For now, just refresh statuses
        checkAllServices()
    }
    
    func add(service: Service) {
        services.append(service)
        saveServices()
        // Try to start it
        startService(service)
    }
    
    func remove(service: Service) {
        stopService(service)
        services.removeAll { $0.id == service.id }
        saveServices()
    }
    
    private func saveServices() {
        // Standardize on Application Support for GUI edits
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let appSupport = homeDir.appendingPathComponent("Library/Application Support/ServerMonitor")
        let configPath = appSupport.appendingPathComponent("services.json")
        
        do {
            if !FileManager.default.fileExists(atPath: appSupport.path) {
                try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            }
            
            let servicesData = services.map { service -> [String: Any] in
                var dict: [String: Any] = [
                    "name": service.name,
                    "identifier": service.identifier,
                    "enabled": service.enabled ?? true
                ]
                if let port = service.port { dict["port"] = port }
                if let health = service.healthCheckURL { dict["healthCheck"] = health }
                if let path = service.path { dict["path"] = path }
                if let cmd = service.command { dict["command"] = cmd }
                return dict
            }
            
            let settings: [String: Any] = [
                "logDir": "./logs", // Default
                "identifierPrefix": "com.servermonitor"
            ]
            
            let json: [String: Any] = [
                "version": "2.0.0",
                "settings": settings,
                "services": servicesData
            ]
            
            let data = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
            try data.write(to: configPath)
            
            print("✅ Saved config to \(configPath.path)")
        } catch {
            print("❌ Failed to save config: \(error)")
        }
    }
}
