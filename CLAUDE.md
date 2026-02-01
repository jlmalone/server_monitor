# Server Monitor - AI Instructions

## Project Goal
A macOS native solution to:
1. Run dev servers as persistent launchd services (survive reboots, crashes)
2. Monitor server health with visual status
3. Alert when services die
4. Easy start/stop/restart controls

## Architecture

### Phase 1: launchd Services (Current)
- Each server gets a `.plist` file in `~/Library/LaunchAgents/`
- launchd auto-restarts on crash
- Logs go to `~/ios_code/server_monitor/logs/`

### Phase 2: Menu Bar App (Future)
- SwiftUI menu bar app showing server status
- Green/red indicators
- Click to start/stop/view logs
- System notifications on failures

### Phase 3: iOS Companion (Future)
- Monitor servers from phone
- Push notifications on failures
- Remote start/stop

## Current Servers to Monitor

### redo-web-app HTTPS Server
- **Name:** `vision.salient.redo-https`
- **Port:** 3443
- **Command:** `node /Users/josephmalone/WebstormProjects/redo-web-app/https-server.js`
- **Health check:** `curl -sk https://localhost:3443`

### Add more servers as needed...

## File Structure
```
server_monitor/
├── CLAUDE.md           # This file
├── launchd/            # .plist templates
├── scripts/
│   ├── install.sh      # Install all services
│   ├── uninstall.sh    # Remove all services
│   ├── status.sh       # Check all services
│   └── monitor.sh      # Continuous monitoring with alerts
├── logs/               # Service logs
└── ServerMonitor/      # Future: Xcode project for menu bar app
```

## launchd Plist Structure
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>vision.salient.SERVICE_NAME</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/executable</string>
        <string>arg1</string>
    </array>
    <key>WorkingDirectory</key>
    <string>/path/to/workdir</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/Users/josephmalone/ios_code/server_monitor/logs/SERVICE_NAME.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/josephmalone/ios_code/server_monitor/logs/SERVICE_NAME.error.log</string>
</dict>
</plist>
```

## Commands Reference
```bash
# Load a service
launchctl load ~/Library/LaunchAgents/vision.salient.SERVICE.plist

# Unload a service  
launchctl unload ~/Library/LaunchAgents/vision.salient.SERVICE.plist

# Check if running
launchctl list | grep salient

# View logs
tail -f ~/ios_code/server_monitor/logs/SERVICE_NAME.log
```

## Why Servers Were Dying
Previous approach: Started as background processes (`&`) from Clawdbot exec sessions.
Problem: When exec session times out or Clawdbot restarts, orphaned processes may be killed.

Solution: launchd is the macOS init system - it manages services independently of any terminal or parent process. Services persist across:
- Terminal closes
- User logout/login  
- System reboots
- Parent process death

## Future Enhancements
- [x] Menu bar app with SwiftUI
- [] Ensure launchd services persist across reboots
- [] Ensure launchd services persist across user logout/login
- [] Ensure Play, Stop, Restart buttons use ps kill and launchctl to control services
- [ ] Slack/Discord webhook alerts
- [ ] iOS companion app
- [ ] Web dashboard
- [ ] Automatic SSL cert renewal monitoring
- [ ] Port conflict detection
