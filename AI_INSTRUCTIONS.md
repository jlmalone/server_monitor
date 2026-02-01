# Server Monitor - AI Instructions

## Project Goal
Build a native macOS menu bar app that monitors critical server processes and alerts when they die. The app should be lightweight, always-on, and provide instant visibility into system health.

## Requirements

### Core Features
1. **Menu Bar Icon**
   - Green: All services healthy
   - Yellow: One service down
   - Red: Multiple services down
   - Shows service count (e.g., "5/5" or "3/5")

2. **Dropdown Menu**
   - List of monitored services with status indicators
   - Click service name to view logs
   - "Restart" button for each service
   - "Restart All" option
   - Settings/configuration

3. **Alerts**
   - macOS notification when service dies
   - Option for sound alert
   - Option for persistent alert until acknowledged

4. **Auto-Recovery**
   - Configurable auto-restart on failure
   - Retry limits (don't restart infinitely)
   - Exponential backoff

### Monitored Services

```json
{
  "services": [
    {
      "name": "Clawdbot Gateway",
      "type": "launchd",
      "identifier": "com.clawdbot.gateway",
      "checkCommand": "launchctl list | grep com.clawdbot.gateway",
      "restartCommand": "launchctl stop com.clawdbot.gateway && launchctl start com.clawdbot.gateway",
      "logPath": "~/.clawdbot/logs/gateway.log",
      "critical": true
    },
    {
      "name": "Redo HTTPS Server",
      "type": "process",
      "processName": "https-server.js",
      "checkCommand": "pgrep -f https-server.js",
      "restartCommand": "cd ~/WebstormProjects/redo-web-app && node https-server.js &",
      "logPath": "~/WebstormProjects/redo-web-app/logs/https.log",
      "critical": true
    },
    {
      "name": "Redo Log Server",
      "type": "process",
      "processName": "log-server.j",
      "checkCommand": "pgrep -f log-server.j",
      "restartCommand": "cd ~/WebstormProjects/redo-web-app && node log-server.j &",
      "logPath": "~/WebstormProjects/redo-web-app/logs/log-server.log",
      "critical": false
    },
    {
      "name": "Redo Debug Server",
      "type": "process",
      "processName": "debug-server",
      "checkCommand": "pgrep -f debug-server",
      "restartCommand": "cd ~/WebstormProjects/redo-web-app && node debug-server &",
      "logPath": "~/WebstormProjects/redo-web-app/logs/debug-server.log",
      "critical": false
    }
  ],
  "checkInterval": 5,
  "alertOnDowntime": true,
  "autoRestart": true,
  "maxRestarts": 3,
  "restartBackoff": "exponential"
}
```

## Technical Stack

### Recommended: Swift + SwiftUI
**Why:** Native performance, menu bar integration, modern UI

```swift
// Key Components:
// 1. AppDelegate - Menu bar item management
// 2. ServiceMonitor - Health checking logic
// 3. NotificationManager - Alert handling
// 4. ConfigManager - Service definitions
// 5. LogViewer - Tail logs in separate window
```

### Alternative: Electron (if cross-platform later)
**Why:** Reusable web tech, easier for rapid prototyping

```javascript
// Key Modules:
// electron - Menu bar (Tray)
// node-notifier - Alerts
// chokidar - Log file watching
// systeminformation - Process monitoring
```

## Architecture

```
server_monitor/
├── src/
│   ├── main.swift              # App entry point
│   ├── AppDelegate.swift       # Menu bar management
│   ├── ServiceMonitor.swift    # Core monitoring logic
│   ├── NotificationManager.swift
│   ├── ConfigManager.swift     # Load services.json
│   ├── ProcessChecker.swift    # Execute check commands
│   ├── LogViewer.swift         # SwiftUI log viewer
│   └── Models/
│       ├── Service.swift
│       └── ServiceStatus.swift
├── config/
│   └── services.json           # Service definitions
├── Assets.xcassets/
│   ├── icon-green.png
│   ├── icon-yellow.png
│   └── icon-red.png
├── docs/
│   └── ARCHITECTURE.md
└── Package.swift / Xcode project
```

## Implementation Steps

### Phase 1: Core Monitoring (MVP)
1. Create Swift macOS app with menu bar icon
2. Load service definitions from config/services.json
3. Implement health check loop (every 5 seconds)
4. Update menu bar icon based on status
5. Show service list in dropdown menu
6. Send macOS notification on failure

### Phase 2: Management Features
1. Add "Restart" button per service
2. Implement restart commands execution
3. Add log viewer window (tail -f)
4. Track restart attempts and backoff
5. Add settings panel

### Phase 3: Stability & Polish
1. Auto-start on login (LaunchAgent)
2. Persist service states
3. Historical uptime tracking
4. Performance optimization (low CPU/memory)
5. Dark mode support

### Phase 4: Advanced (Optional)
1. Add new services via UI
2. Export/import configurations
3. Remote monitoring (webhook alerts)
4. Service dependency graphs
5. Resource usage graphs (CPU/memory per service)

## Key Classes/Structs

### Service Model
```swift
struct Service: Codable {
    let name: String
    let type: ServiceType
    let identifier: String?
    let processName: String?
    let checkCommand: String
    let restartCommand: String
    let logPath: String
    let critical: Bool
}

enum ServiceType: String, Codable {
    case launchd
    case process
}

enum ServiceStatus {
    case running
    case stopped
    case unknown
    case restarting
}
```

### ServiceMonitor
```swift
class ServiceMonitor: ObservableObject {
    @Published var services: [Service] = []
    @Published var statuses: [String: ServiceStatus] = [:]

    func startMonitoring(interval: TimeInterval = 5.0)
    func checkService(_ service: Service) -> ServiceStatus
    func restartService(_ service: Service)
    func stopMonitoring()
}
```

### NotificationManager
```swift
class NotificationManager {
    func sendAlert(title: String, message: String, critical: Bool)
    func playSound()
    func requestPermissions()
}
```

## Critical Implementation Details

### 1. Health Check Execution
```swift
func checkService(_ service: Service) -> ServiceStatus {
    let process = Process()
    process.launchPath = "/bin/bash"
    process.arguments = ["-c", service.checkCommand]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.launch()
    process.waitUntilExit()

    return process.terminationStatus == 0 ? .running : .stopped
}
```

### 2. Menu Bar Icon Updates
```swift
func updateMenuBarIcon(status: SystemStatus) {
    let icon: NSImage
    switch status {
    case .allHealthy:
        icon = NSImage(named: "icon-green")!
    case .someDown:
        icon = NSImage(named: "icon-yellow")!
    case .multipleDown:
        icon = NSImage(named: "icon-red")!
    }
    statusItem.button?.image = icon
}
```

### 3. Auto-Restart with Backoff
```swift
func attemptRestart(_ service: Service) {
    guard restartCounts[service.name, default: 0] < maxRestarts else {
        sendPersistentAlert("Service \(service.name) failed \(maxRestarts) times")
        return
    }

    let backoff = calculateBackoff(attempts: restartCounts[service.name, default: 0])
    DispatchQueue.main.asyncAfter(deadline: .now() + backoff) {
        self.executeRestart(service)
        self.restartCounts[service.name, default: 0] += 1
    }
}

func calculateBackoff(attempts: Int) -> TimeInterval {
    // Exponential: 2^attempts seconds (2s, 4s, 8s, 16s...)
    return pow(2.0, Double(attempts))
}
```

## Testing Strategy

1. **Unit Tests**
   - Service model parsing
   - Health check logic
   - Restart backoff calculation

2. **Integration Tests**
   - Check actual processes
   - Execute restart commands (in safe test env)

3. **Manual Testing**
   - Kill each service manually
   - Verify alerts appear
   - Verify auto-restart works
   - Check memory/CPU usage over 24h

## Performance Requirements

- **Memory**: < 50 MB
- **CPU**: < 1% average
- **Startup**: < 1 second
- **Check latency**: < 100ms per service

## Security Considerations

1. **Sudo/root access**: Don't require it
   - Use LaunchAgents (user-level)
   - Restart commands must work without sudo

2. **Log file access**: Handle permissions gracefully
   - Check readable before opening
   - Show error if denied

3. **Config file**: Validate thoroughly
   - Don't execute arbitrary commands
   - Whitelist allowed restart commands

## Distribution

1. **Development**: Xcode direct run
2. **Beta**: Export as .app, distribute via TestFlight or direct download
3. **Production**: Mac App Store or notarized DMG

## Future Enhancements

- [ ] Web dashboard (optional)
- [ ] Slack/Discord webhook alerts
- [ ] Service metrics (uptime %, crash frequency)
- [ ] Scheduled maintenance windows
- [ ] Multi-machine monitoring (agent model)
- [ ] iOS companion app
- [ ] Integration with clawdbot (AI can query service status)

## Getting Started

```bash
# Clone/create the project
cd ~/ios_code/server_monitor

# If using Xcode:
open ServerMonitor.xcodeproj

# If using SPM:
swift build
swift run

# If using Electron:
npm install
npm start
```

## AI Agent Development Instructions

When building this:
1. Start with Swift + SwiftUI for best macOS integration
2. Use `Process()` to execute shell commands
3. Use `NSStatusBar.system.statusItem()` for menu bar
4. Use `UNUserNotificationCenter` for alerts
5. Store config in `~/Library/Application Support/ServerMonitor/`
6. Create LaunchAgent plist for auto-start
7. Keep UI minimal - menu bar only, no dock icon
8. Use `@Published` properties for reactive UI updates

## Success Criteria

✅ App appears in menu bar with color-coded status
✅ Detects when any monitored service dies within 5 seconds
✅ Sends notification immediately
✅ Auto-restarts service if enabled
✅ Can manually restart from dropdown menu
✅ Can view logs for each service
✅ Uses < 50MB RAM and < 1% CPU
✅ Survives system sleep/wake
✅ Persists across user logout/login (LaunchAgent)

---

**Priority**: HIGH - Critical infrastructure monitoring
**Complexity**: Medium - Native macOS development
**Timeline**: 1-2 days for MVP, 1 week for polish
