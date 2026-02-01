import Foundation
import SwiftUI
import UserNotifications

@MainActor
class ServiceMonitor: ObservableObject {
    @Published var services: [Service] = []
    
    @Published var lastUpdate: Date?
    private var timer: Timer?
    private var lastStatuses: [String: ServiceStatus] = [:]
    
    // Settings loaded from config
    private var logDir: String = "./logs"
    private var identifierPrefix: String = "com.servermonitor"
    
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

                // Load settings if present
                if let settings = json["settings"] as? [String: Any] {
                    if let logDirSetting = settings["logDir"] as? String {
                        self.logDir = logDirSetting
                    }
                    if let prefixSetting = settings["identifierPrefix"] as? String {
                        self.identifierPrefix = prefixSetting
                    }
                }

                services = servicesArray.compactMap { dict in
                    guard let name = dict["name"] as? String,
                          let identifier = dict["identifier"] as? String else { return nil }
                    
                    // enabled defaults to true if not specified
                    let enabled = dict["enabled"] as? Bool ?? true
                    // Load but don't filter - show disabled services in GUI
                    
                    let port = dict["port"] as? Int
                    let healthCheck = dict["healthCheck"] as? String
                    let path = dict["path"] as? String
                    let command = dict["command"] as? [String]
                    // keepAlive can be bool or object like { "SuccessfulExit": false }
                    let keepAlive: Bool
                    if let keepAliveValue = dict["keepAlive"] as? Bool {
                        keepAlive = keepAliveValue
                    } else if let _ = dict["keepAlive"] as? [String: Any] {
                        // If it's an object (e.g., {"SuccessfulExit": false}), treat as true (keeping alive)
                        keepAlive = true
                    } else {
                        keepAlive = true // default
                    }
                    let envVars = dict["environmentVariables"] as? [String: String]

                    var service = Service(
                        name: name,
                        identifier: identifier,
                        port: port,
                        healthCheckURL: healthCheck,
                        critical: true,
                        path: path,
                        command: command,
                        enabled: enabled,
                        keepAlive: keepAlive
                    )
                    service.environmentVariables = envVars
                    return service
                }

                if !services.isEmpty {
                    print("✅ Loaded \(services.count) services from \(path.path)")
                    print("   Log directory: \(logDir)")
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
    
    // MARK: - Plist Generation
    
    /// Escape XML special characters
    private func escapeXML(_ str: String) -> String {
        str.replacingOccurrences(of: "&", with: "&amp;")
           .replacingOccurrences(of: "<", with: "&lt;")
           .replacingOccurrences(of: ">", with: "&gt;")
           .replacingOccurrences(of: "\"", with: "&quot;")
    }
    
    /// Resolve log directory path (expand ~ and relative paths)
    private func resolveLogDir() -> String {
        var resolved = logDir
        if resolved.hasPrefix("~") {
            resolved = NSHomeDirectory() + String(resolved.dropFirst())
        } else if resolved.hasPrefix("./") || !resolved.hasPrefix("/") {
            // Relative to Application Support
            let homeDir = FileManager.default.homeDirectoryForCurrentUser
            let appSupport = homeDir.appendingPathComponent("Library/Application Support/ServerMonitor")
            if resolved.hasPrefix("./") {
                resolved = appSupport.appendingPathComponent(String(resolved.dropFirst(2))).path
            } else {
                resolved = appSupport.appendingPathComponent(resolved).path
            }
        }
        return resolved
    }
    
    /// Generate launchd plist XML from service configuration
    /// - Parameter service: Service object with configuration
    /// - Returns: Valid plist XML string matching Node.js output format
    func generatePlistXML(service: Service) -> String {
        let label = escapeXML(service.identifier)
        let resolvedLogDir = resolveLogDir()
        
        // Extract short name for log files (last component of identifier)
        let shortName = service.identifier.split(separator: ".").last.map(String.init) ?? service.identifier
        
        // Build ProgramArguments from command array
        var programArgsXML = ""
        if let command = service.command, !command.isEmpty {
            let argsXML = command.map { "        <string>\(escapeXML($0))</string>" }.joined(separator: "\n")
            programArgsXML = """
                <key>ProgramArguments</key>
                <array>
            \(argsXML)
                </array>
            """
        }
        
        // Build WorkingDirectory if path is set
        var workingDirXML = ""
        if let path = service.path {
            var resolvedPath = path
            if resolvedPath.hasPrefix("~") {
                resolvedPath = NSHomeDirectory() + String(resolvedPath.dropFirst())
            }
            workingDirXML = """
                <key>WorkingDirectory</key>
                <string>\(escapeXML(resolvedPath))</string>
            """
        }
        
        // Build EnvironmentVariables
        let nodePath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin"
        var envDict = ["PATH": nodePath]
        if let customEnv = service.environmentVariables {
            for (key, value) in customEnv {
                envDict[key] = value
            }
        }
        let envEntries = envDict.map { key, value in
            """
                    <key>\(escapeXML(key))</key>
                    <string>\(escapeXML(value))</string>
            """
        }.joined(separator: "\n")
        let envXML = """
            <key>EnvironmentVariables</key>
            <dict>
        \(envEntries)
            </dict>
        """
        
        // Build KeepAlive based on service setting
        let keepAliveXML: String
        if service.keepAlive ?? true {
            keepAliveXML = """
            <key>KeepAlive</key>
            <dict>
                <key>SuccessfulExit</key>
                <false/>
            </dict>
        """
        } else {
            keepAliveXML = """
            <key>KeepAlive</key>
            <false/>
        """
        }
        
        // Ensure log directory exists
        try? FileManager.default.createDirectory(atPath: resolvedLogDir, withIntermediateDirectories: true)
        
        // Generate the full plist XML
        let plist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>\(label)</string>
    \(programArgsXML)
    \(workingDirXML)
    <key>RunAtLoad</key>
    <true/>
    \(keepAliveXML)
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>StandardOutPath</key>
    <string>\(escapeXML(resolvedLogDir))/\(escapeXML(shortName)).log</string>
    <key>StandardErrorPath</key>
    <string>\(escapeXML(resolvedLogDir))/\(escapeXML(shortName)).error.log</string>
    \(envXML)
</dict>
</plist>
"""
        return plist
    }
    
    /// Write plist atomically (temp file then rename)
    private func writePlistAtomically(xml: String, to path: String) throws {
        let tempPath = path + ".tmp"
        try xml.write(toFile: tempPath, atomically: true, encoding: .utf8)
        
        // Remove existing file if present
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
        
        try FileManager.default.moveItem(atPath: tempPath, toPath: path)
    }
    
    func startService(_ service: Service) {
        let plistPath = "\(NSHomeDirectory())/Library/LaunchAgents/\(service.identifier).plist"
        let uid = getuid()
        let domain = "gui/\(uid)"
        
        // 1. Generate plist XML if we have command configuration
        if service.command != nil && !service.command!.isEmpty {
            let plistXML = generatePlistXML(service: service)
            do {
                try writePlistAtomically(xml: plistXML, to: plistPath)
                print("✅ Generated plist at \(plistPath)")
            } catch {
                print("❌ Failed to write plist: \(error)")
            }
        }
        
        // 2. Check if already loaded
        let (status, _) = checkService(service.identifier)
        
        if status == .stopped {
            // 3. Use modern launchctl bootstrap (not deprecated load)
            let bootstrapTask = Process()
            bootstrapTask.launchPath = "/bin/launchctl"
            bootstrapTask.arguments = ["bootstrap", domain, plistPath]
            
            let pipe = Pipe()
            bootstrapTask.standardError = pipe
            
            do {
                try bootstrapTask.run()
                bootstrapTask.waitUntilExit()
                
                if bootstrapTask.terminationStatus != 0 {
                    let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMsg = String(data: errorData, encoding: .utf8) ?? ""
                    
                    // If already loaded (error 37), use kickstart instead
                    if errorMsg.contains("37") || errorMsg.contains("already loaded") {
                        print("ℹ️ Service already loaded, using kickstart")
                        kickstartService(identifier: service.identifier, domain: domain)
                    } else {
                        print("⚠️ Bootstrap failed: \(errorMsg)")
                    }
                }
            } catch {
                print("❌ Failed to run bootstrap: \(error)")
            }
        } else {
            // Already loaded, use kickstart to restart
            kickstartService(identifier: service.identifier, domain: domain)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.checkAllServices() }
    }
    
    /// Use launchctl kickstart to start/restart a loaded service
    private func kickstartService(identifier: String, domain: String) {
        let kickTask = Process()
        kickTask.launchPath = "/bin/launchctl"
        kickTask.arguments = ["kickstart", "-k", "\(domain)/\(identifier)"]
        try? kickTask.run()
        kickTask.waitUntilExit()
    }
    
    func stopService(_ service: Service) {
        let uid = getuid()
        let domain = "gui/\(uid)"
        let serviceTarget = "\(domain)/\(service.identifier)"
        
        // Get PID before stopping (for fallback)
        let (_, pid) = checkService(service.identifier)

        // Method 1: Use modern launchctl bootout (not deprecated unload)
        let bootoutTask = Process()
        bootoutTask.launchPath = "/bin/launchctl"
        bootoutTask.arguments = ["bootout", serviceTarget]
        
        let pipe = Pipe()
        bootoutTask.standardError = pipe
        
        do {
            try bootoutTask.run()
            bootoutTask.waitUntilExit()
            
            if bootoutTask.terminationStatus != 0 {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorMsg = String(data: errorData, encoding: .utf8) ?? ""
                print("⚠️ Bootout warning: \(errorMsg)")
                
                // Fallback: try kill -9 if bootout failed
                if let pid = pid {
                    print("ℹ️ Using kill as fallback")
                    let killTask = Process()
                    killTask.launchPath = "/bin/kill"
                    killTask.arguments = ["-9", "\(pid)"]
                    try? killTask.run()
                    killTask.waitUntilExit()
                }
            }
        } catch {
            print("❌ Failed to run bootout: \(error)")
            
            // Fallback: Kill PID directly
            if let pid = pid {
                let killTask = Process()
                killTask.launchPath = "/bin/kill"
                killTask.arguments = ["-9", "\(pid)"]
                try? killTask.run()
                killTask.waitUntilExit()
            }
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
        // Try to start it if enabled
        if service.enabled ?? true {
            startService(service)
        }
    }
    
    func update(service: Service) {
        guard let index = services.firstIndex(where: { $0.id == service.id }) else {
            print("⚠️ Service not found for update: \(service.identifier)")
            return
        }
        
        let wasRunning = services[index].status == .running
        let wasEnabled = services[index].enabled ?? true
        let nowEnabled = service.enabled ?? true
        
        // Stop the old service if it was running
        if wasRunning {
            stopService(services[index])
        }
        
        // Remove old plist if identifier changed (shouldn't happen but be safe)
        if services[index].identifier != service.identifier {
            let oldPlistPath = "\(NSHomeDirectory())/Library/LaunchAgents/\(services[index].identifier).plist"
            try? FileManager.default.removeItem(atPath: oldPlistPath)
        }
        
        // Update the service
        services[index] = service
        saveServices()
        
        // Restart if it was running or if we're enabling a previously disabled service
        if wasRunning || (!wasEnabled && nowEnabled) {
            if nowEnabled {
                startService(service)
            }
        }
    }
    
    func remove(service: Service) {
        // Stop the service
        stopService(service)
        
        // Remove plist file
        let plistPath = "\(NSHomeDirectory())/Library/LaunchAgents/\(service.identifier).plist"
        do {
            if FileManager.default.fileExists(atPath: plistPath) {
                try FileManager.default.removeItem(atPath: plistPath)
                print("✅ Removed plist: \(plistPath)")
            }
        } catch {
            print("⚠️ Failed to remove plist: \(error)")
        }
        
        // Remove from services list
        services.removeAll { $0.id == service.id }
        saveServices()
    }
    
    private func saveServices() {
        // Standardize on Application Support for GUI edits
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let appSupport = homeDir.appendingPathComponent("Library/Application Support/ServerMonitor")
        let configPath = appSupport.appendingPathComponent("services.json")
        let tempPath = appSupport.appendingPathComponent("services.json.tmp")
        
        do {
            if !FileManager.default.fileExists(atPath: appSupport.path) {
                try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            }
            
            let servicesData = services.map { service -> [String: Any] in
                var dict: [String: Any] = [
                    "name": service.name,
                    "identifier": service.identifier,
                    "enabled": service.enabled ?? true,
                    "keepAlive": service.keepAlive ?? true
                ]
                if let port = service.port { dict["port"] = port }
                if let health = service.healthCheckURL { dict["healthCheck"] = health }
                if let path = service.path { dict["path"] = path }
                if let cmd = service.command { dict["command"] = cmd }
                if let env = service.environmentVariables, !env.isEmpty { dict["environmentVariables"] = env }
                return dict
            }
            
            let settings: [String: Any] = [
                "logDir": logDir,
                "identifierPrefix": identifierPrefix
            ]
            
            let json: [String: Any] = [
                "version": "2.0.0",
                "settings": settings,
                "services": servicesData
            ]
            
            // Atomic write: write to temp file, then rename
            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: tempPath)
            
            // Remove existing file if present
            if FileManager.default.fileExists(atPath: configPath.path) {
                try FileManager.default.removeItem(at: configPath)
            }
            
            try FileManager.default.moveItem(at: tempPath, to: configPath)
            
            print("✅ Saved config to \(configPath.path)")
        } catch {
            print("❌ Failed to save config: \(error)")
            // Clean up temp file if it exists
            try? FileManager.default.removeItem(at: tempPath)
        }
    }
}
