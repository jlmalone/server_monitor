# Server Monitor for macOS

A lightweight system to run development servers as persistent launchd services with health monitoring.

## 🎯 Why?

Development servers started from terminals or background processes die when:
- Terminal closes
- Parent process times out
- System reboots

**Solution:** Use macOS `launchd` - the proper way to run persistent services.

## 🚀 Quick Start

```bash
cd ~/ios_code/server_monitor

# Install all services
./scripts/install.sh

# Check status
./scripts/status.sh

# Monitor continuously (with alerts)
./scripts/monitor.sh &

# Uninstall when done
./scripts/uninstall.sh
```

## 📋 Currently Monitored Services

| Service | Port | LaunchD ID |
|---------|------|------------|
| Redo HTTPS Server | 3443 | `com.servermonitor.redo-https` |
| Clawdbot Gateway | 3333 | `com.clawdbot.gateway` |

## 📁 Project Structure

```
server_monitor/
├── CLAUDE.md           # AI instructions
├── README.md           # This file
├── config/
│   └── services.json   # Service definitions
├── launchd/            # Plist templates
│   └── com.servermonitor.redo-https.plist
├── scripts/
│   ├── install.sh      # Install services to launchd
│   ├── uninstall.sh    # Remove services
│   ├── status.sh       # Check all services
│   └── monitor.sh      # Continuous monitoring with alerts
├── logs/               # Service logs
└── ServerMonitor/      # (Future) SwiftUI menu bar app
```

## 🛠️ Scripts

### install.sh
Copies plist files to `~/Library/LaunchAgents/` and loads them into launchd.

```bash
./scripts/install.sh
```

### uninstall.sh
Stops and removes all managed services.

```bash
./scripts/uninstall.sh           # Remove services and archive logs
./scripts/uninstall.sh --keep-logs  # Keep log files
```

### status.sh
Shows status of all monitored services with health checks.

```bash
./scripts/status.sh
```

Output includes:
- Running/stopped status with PIDs
- Port listening status
- HTTP health check results
- Log file locations and sizes
- Summary of all services

### monitor.sh
Runs a continuous monitoring loop with macOS notifications.

```bash
./scripts/monitor.sh &    # Run in background
```

Features:
- 5-second check interval
- macOS desktop notifications on failures
- Auto-restart attempts
- State tracking (only alerts on change)

## 📝 Adding New Services

### 1. Create a plist file

Create `launchd/com.servermonitor.YOUR-SERVICE.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.servermonitor.YOUR-SERVICE</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/node</string>
        <string>/path/to/your-server.js</string>
    </array>
    <key>WorkingDirectory</key>
    <string>/path/to/project</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardOutPath</key>
    <string>/Users/jlmalone/ios_code/server_monitor/logs/YOUR-SERVICE.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/jlmalone/ios_code/server_monitor/logs/YOUR-SERVICE.error.log</string>
</dict>
</plist>
```

### 2. Update status.sh

Add your service to the check list in `scripts/status.sh`:

```bash
check_launchd_service "com.servermonitor.YOUR-SERVICE" "Your Service Name" "PORT" "http://localhost:PORT/health"
```

### 3. Reinstall

```bash
./scripts/install.sh
```

## 🔧 Manual launchd Commands

```bash
# List all jmalone services
launchctl list | grep jmalone

# Stop a service
launchctl stop com.servermonitor.redo-https

# Start a service
launchctl start com.servermonitor.redo-https

# Unload (remove from launchd)
launchctl unload ~/Library/LaunchAgents/com.servermonitor.redo-https.plist

# Load (add to launchd)
launchctl load ~/Library/LaunchAgents/com.servermonitor.redo-https.plist

# View logs
tail -f ~/ios_code/server_monitor/logs/redo-https.log
```

## ⚡ Key launchd Features

- **KeepAlive:** Auto-restart on crash
- **RunAtLoad:** Start automatically at login
- **ThrottleInterval:** Wait 10s between restart attempts
- **WorkingDirectory:** Set the cwd for the process
- **EnvironmentVariables:** Set PATH, NODE_ENV, etc.

## 🔮 Future Plans

- [ ] SwiftUI menu bar app with status indicators
- [ ] One-click start/stop/restart
- [ ] Log viewer in the app
- [ ] iOS companion app with push notifications
- [ ] Slack/Discord webhook alerts

## 📊 Logs

All service logs go to `~/ios_code/server_monitor/logs/`:
- `redo-https.log` - stdout
- `redo-https.error.log` - stderr
- `monitor.log` - monitoring script output

## 🐛 Troubleshooting

### Service won't start
```bash
# Check for syntax errors in plist
plutil ~/Library/LaunchAgents/com.servermonitor.redo-https.plist

# Check launchd status
launchctl list | grep redo-https

# Check error log
cat ~/ios_code/server_monitor/logs/redo-https.error.log
```

### Service keeps restarting
Check the exit code in `launchctl list` - a non-zero exit means the process is crashing. Check error logs.

### Port already in use
```bash
# Find what's using the port
lsof -i :3443

# Or use netstat
netstat -an | grep 3443
```

---

**Status:** ✅ Operational
**Last Updated:** 2026-01-31
