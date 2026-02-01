import Foundation
import SwiftUI
import UserNotifications

@MainActor
class ServiceMonitor: ObservableObject {
    @Published var services: [Service] = [
        // Main dev servers
        Service(name: "Redo HTTPS", identifier: "vision.salient.redo-https", port: 3000, healthCheckURL: "https://localhost:3000"),
        Service(name: "Universe", identifier: "vision.salient.universe", port: 4001, healthCheckURL: "http://localhost:4001"),
        Service(name: "Vision", identifier: "vision.salient.vision", port: 4002, healthCheckURL: "http://localhost:4002"),
        Service(name: "Numina", identifier: "vision.salient.numina", port: 4003, healthCheckURL: "http://localhost:4003"),
        Service(name: "Knomee", identifier: "vision.salient.knomee", port: 4004, healthCheckURL: "http://localhost:4004"),
        
        // Redo LLM Debug Tools
        Service(name: "Redo Diagnostics", identifier: "vision.salient.redo-diagnostics", port: 3001, healthCheckURL: "http://localhost:3001"),
        Service(name: "Redo Log Server", identifier: "vision.salient.redo-logserver", port: 3002, healthCheckURL: "http://localhost:3002"),
        Service(name: "Redo Debug API", identifier: "vision.salient.redo-debug", port: 3009, healthCheckURL: "http://localhost:3009")
    ]
    
    @Published var lastUpdate: Date?
    private var timer: Timer?
    private var lastStatuses: [String: ServiceStatus] = [:]
    
    init() {
        requestNotificationPermission()
        startMonitoring()
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
}
