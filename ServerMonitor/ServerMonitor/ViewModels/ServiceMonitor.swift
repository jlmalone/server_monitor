import Foundation
import SwiftUI
import UserNotifications

@MainActor
class ServiceMonitor: ObservableObject {
    @Published var services: [Service] = [
        Service(name: "Redo HTTPS", identifier: "vision.salient.redo-https", port: 3000, healthCheckURL: "https://localhost:3000"),
        Service(name: "Universe", identifier: "vision.salient.universe", port: 3001, healthCheckURL: "http://localhost:3001"),
        Service(name: "Vision", identifier: "vision.salient.vision", port: 3002, healthCheckURL: "http://localhost:3002"),
        Service(name: "Numina", identifier: "vision.salient.numina", port: 3003, healthCheckURL: "http://localhost:3003"),
        Service(name: "Knomee", identifier: "vision.salient.knomee", port: 3004, healthCheckURL: "http://localhost:3004")
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
}
