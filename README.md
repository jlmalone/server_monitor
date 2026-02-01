# Server Monitor 🖥️

[![macOS](https://img.shields.io/badge/macOS-13+-blue?logo=apple)](https://www.apple.com/macos/)
[![Node.js](https://img.shields.io/badge/Node.js-18+-green?logo=node.js)](https://nodejs.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](./CONTRIBUTING.md)

A lightweight macOS dev server manager using native `launchd` for reliable, persistent services.

## ✨ Features

- **🔧 CLI Tool (`sm`)** - Manage services from the terminal
- **📱 Menu Bar App** - Quick status view and controls from your menu bar
- **🔄 Auto-restart** - launchd automatically restarts crashed services
- **📊 Health Checks** - HTTP health monitoring for each service
- **📝 Centralized Logs** - All service logs in one configurable location
- **🚀 JSON-first Config** - Single source of truth in `services.json`
- **🔒 Boot Persistence** - Services start automatically at login

## 🚀 Installation

### Option 1: Download DMG (Recommended)

1. Download the latest `ServerMonitor-x.x.x.dmg` from [GitHub Releases](https://github.com/yourusername/server-monitor/releases)
2. Open the DMG and drag **Server Monitor** to Applications
3. Launch Server Monitor from Applications

### Option 2: Build from Source

```bash
git clone https://github.com/yourusername/server-monitor.git
cd server-monitor

# Build the app
cd app/ServerMonitor
xcodebuild -scheme ServerMonitor -configuration Release build

# Install CLI
cd ../../cli
npm install
npm link
```

## 🖥️ CLI Setup

Add the CLI to your PATH for easy access:

```bash
# After npm link in cli/, or add manually:
export PATH="$PATH:/path/to/server-monitor/cli/bin"
```

## ⚡ Quick Start

### GUI
1. Launch **Server Monitor** from Applications
2. Click the menu bar icon (server tray icon)
3. Add services via the "+" button or edit `services.json`

### CLI
```bash
# List all services
sm list

# Check detailed status
sm status

# Start/stop/restart
sm start my-app
sm stop my-app
sm restart --all

# View logs
sm logs my-app
sm logs my-app --error

# Add a new service
sm add --name "My App" --path ~/projects/myapp --port 3000 --cmd "npm run dev"
```

## 📋 Configuration

Services are defined in `services.json` (auto-generated on first run):

```json
{
    "version": "2.0.0",
    "settings": {
        "logDir": "./logs",
        "identifierPrefix": "com.servermonitor"
    },
    "services": [
        {
            "name": "My App",
            "identifier": "com.servermonitor.my-app",
            "path": "/path/to/your/project",
            "command": ["npm", "run", "dev"],
            "port": 3000,
            "healthCheck": "http://localhost:3000",
            "enabled": true
        }
    ]
}
```

### Service Options

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Display name for the service |
| `identifier` | string | Unique launchd identifier (e.g., `com.servermonitor.my-app`) |
| `path` | string | Working directory for the service |
| `command` | array | Command and arguments to run |
| `port` | number | Port the service listens on |
| `healthCheck` | string | URL for health check endpoint |
| `enabled` | boolean | Whether service is managed by launchd |
| `env` | object | (Optional) Environment variables |

## 📋 CLI Commands

| Command | Description |
|---------|-------------|
| `sm list` | List all services with status |
| `sm status [name]` | Detailed health check |
| `sm start <name\|--all>` | Start service(s) |
| `sm stop <name\|--all>` | Stop service(s) |
| `sm restart <name\|--all>` | Restart service(s) |
| `sm logs <name>` | Tail service stdout logs |
| `sm logs <name> --error` | Tail service stderr logs |
| `sm add [options]` | Add new service |
| `sm remove <name>` | Remove a service |
| `sm edit` | Open services.json in editor |

## 🏗️ Architecture

```
server_monitor/
├── app/                 # SwiftUI Menu Bar App
│   └── ServerMonitor/
├── cli/                 # Node.js CLI tool
│   ├── src/commands/    # Command implementations
│   └── src/lib/         # Core utilities
├── logs/                # Service stdout/stderr (gitignored)
├── launchd/             # Auto-generated plists (gitignored)
├── services.json        # Your service configuration (gitignored)
├── services.example.json # Example configuration
└── scripts/             # Build and release scripts
```

### How It Works

1. **services.json** is the single source of truth
2. CLI/App reads config and generates launchd plists automatically
3. `launchctl` manages the actual processes
4. Services survive terminal close, system sleep, and auto-restart on crash

## 🔧 Manual launchd Commands

```bash
# List managed services
launchctl list | grep servermonitor

# Stop/start a service manually
launchctl stop com.servermonitor.my-app
launchctl start com.servermonitor.my-app

# Unload completely (stops KeepAlive)
launchctl unload ~/Library/LaunchAgents/com.servermonitor.my-app.plist
```

## 🐛 Troubleshooting

### Service won't start
```bash
# Check error log
sm logs <name> --error

# Check if port is in use
lsof -i :<port>
```

### Service keeps restarting
```bash
# Check exit code (0 = ok, non-zero = crash)
launchctl list | grep <identifier>

# View error log
sm logs <name> --error
```

### CLI command not found
```bash
cd cli && npm link
# Or add to PATH: export PATH="$PATH:$(pwd)/cli/bin"
```

### Health check failing
```bash
# Test endpoint manually
curl -s http://localhost:<port>/health

# Check if service is actually running
sm status <name>
```

## 📄 License

MIT © jlmalone

## 🙏 Contributing

PRs welcome! See [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines.

---

**Built with ❤️ for developers who need reliable local services.**
