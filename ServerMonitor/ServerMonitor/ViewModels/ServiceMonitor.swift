import Foundation
import SwiftUI
import Combine
import UserNotifications

@MainActor
class ServiceMonitor: ObservableObject {
    @Published var services: [Service] = []
    @Published var isChecking = false
    @Published var lastUpdate: Date?
    
    private var timer: Timer?
    private let checkInterval: TimeInterval = 5.0
    
    var overallStatus: OverallStatus {
        if isChecking { return .checking }
        let running = services.filter { $0.status == .running }.count
        let total = services.count
        
        if total == 0 { return .checking }
        if running == total { return .allHealthy }
        if running == 0 { return .allDown }
        return .someDown
    }
    
    init() {
        loadDefaultServices()
        requestNotificationPermission()
        startMonitoring()
    }
    
    private func loadDefaultServices() {
        services = [
            Service(
                name: "Redo HTTPS Server",
                identifier: "com.jmalone.redo-https",
                port: 3443,
                healthCheckURL: "https://localhost:3443",
                critical: true
            ),
            Service(
                name: "Clawdbot Gateway",
                identifier: "com.clawdbot.gateway",
                port: 3333,
                healthCheckURL: "http://localhost:3333/health",
                critical: true
            )
        ]
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
    
    func startMonitoring() {
        checkAllServices()
        
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAllServices()
            }
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    func checkAllServices() {
        isChecking = true
        
        for i in services.indices {
            checkService(at: i)
        }
        
        isChecking = false
        lastUpdate = Date()
    }
    
    private func checkService(at index: Int) {
        let service = services[index]
        let previousStatus = service.status
        
        // Check via launchctl
        let result = runCommand("launchctl list | grep '\(service.identifier)'")
        
        if let output = result, !output.isEmpty {
            let components = output.split(separator: "\t")
            if components.count >= 1 {
                let pidString = String(components[0])
                if pidString != "-" && pidString != "0", let pid = Int(pidString) {
                    services[index].status = .running
                    services[index].pid = pid
                    services[index].errorMessage = nil
                } else {
                    services[index].status = .stopped
                    services[index].pid = nil
                    let exitCode = components.count >= 2 ? String(components[1]) : "unknown"
                    services[index].errorMessage = "Exit code: \(exitCode)"
                }
            }
        } else {
            services[index].status = .stopped
            services[index].pid = nil
            services[index].errorMessage = "Not loaded in launchd"
        }
        
        services[index].lastChecked = Date()
        
        // Send notification if status changed to stopped
        if previousStatus == .running && services[index].status == .stopped {
            sendNotification(for: services[index])
        }
    }
    
    private func runCommand(_ command: String) -> String? {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/zsh"
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
    
    func startService(_ service: Service) {
        _ = runCommand("launchctl start \(service.identifier)")
        
        // Wait a moment then recheck
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.checkAllServices()
        }
    }
    
    func stopService(_ service: Service) {
        _ = runCommand("launchctl stop \(service.identifier)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.checkAllServices()
        }
    }
    
    func restartService(_ service: Service) {
        _ = runCommand("launchctl stop \(service.identifier)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            _ = self.runCommand("launchctl start \(service.identifier)")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.checkAllServices()
            }
        }
    }
    
    private func sendNotification(for service: Service) {
        let content = UNMutableNotificationContent()
        content.title = "Service Down"
        content.body = "\(service.name) has stopped"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
}
