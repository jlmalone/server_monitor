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
- **🧩 One Signed Supervisor** - Infrastructure helpers and scheduled jobs share one Developer ID-signed background registration
- **⏱️ Bounded Polling** - Read-only checks execute directly with deadlines; local transfer status uses an atomic file
- **🔋 Resource Guard** - Sustained UI CPU or memory runaway triggers bounded app recovery instead of draining battery indefinitely
- **📝 Centralized Logs** - All service logs in one configurable location
- **🚀 JSON-first Config** - Single source of truth in `services.json`
- **🔒 Boot Persistence** - Services start automatically at login
- **💡 Lid Close (laptops)** - One-click toggle to keep the Mac running with the lid shut (`pmset disablesleep`), so background services don't pause when you close it

## 🚀 Installation

### Option 1: Homebrew (Recommended)

```bash
brew install --cask jlmalone/tap/server-monitor
```

Installs **ServerMonitor.app** into `/Applications` (double-click to launch).
Version 1.1+ releases use the canonical Developer ID signing and notarization
pipeline described below. An older cask remains the older build until that
release is published; update afterward with `brew upgrade --cask server-monitor`.

### Option 2: Download DMG

1. Download the latest `ServerMonitor-x.x.x.dmg` from [GitHub Releases](https://github.com/jlmalone/server_monitor/releases)
2. Open the DMG and drag **Server Monitor** to Applications
3. Launch Server Monitor from Applications

### Option 3: Build from Source

```bash
git clone https://github.com/jlmalone/server_monitor.git
cd server-monitor

# Build the app
cd app/ServerMonitor
xcodebuild -scheme ServerMonitor -configuration Release build

# Build a Developer ID-signed app + DMG (add --notarize for distribution)
cd ../..
./scripts/build_release.sh

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
        "identifierPrefix": "vision.salient"
    },
    "services": [
        {
            "name": "My App",
            "identifier": "vision.salient.my-app",
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
| `identifier` | string | Unique launchd identifier (e.g., `vision.salient.my-app`) |
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
│   └── ServerMonitor/   # App + embedded InfrastructureAgent
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

Infrastructure automation follows a separate path: the app registers one signed
LaunchAgent through `SMAppService`; that agent supervises configured foreground
helpers and scheduled one-shot jobs. macOS therefore shows one attributable
background activity instead of one unidentified row per script. The agent lowers
itself to nice 19 before starting work, and its child processes inherit that
low CPU priority.

The menu-bar UI is expected to remain nearly idle between bounded polls. A
low-frequency in-process guard samples its own resource use every 30 seconds. It
relaunches the UI after three consecutive samples at or above 25% of one CPU core
or 192 MiB resident memory. A second breach within 30 minutes exits instead of
creating a restart loop. Managed services and the signed InfrastructureAgent are
separate processes and continue under launchd if the UI recovers or exits.

## 🔧 Manual launchd Commands

```bash
# List managed services
launchctl list | grep vision.salient

# Stop/start a service manually
launchctl stop vision.salient.my-app
launchctl start vision.salient.my-app

# Unload completely (stops KeepAlive)
launchctl unload ~/Library/LaunchAgents/vision.salient.my-app.plist
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

## 🔒 Local configuration

Optional panels and the infrastructure supervisor read machine-specific values
from **untracked** files under `~/.config/server-monitor/`; see [CONFIG.md](./CONFIG.md)
and [the trusted-machine context guide](docs/TRUSTED_MACHINE_CONTEXT.md)
and the examples in [`config/`](./config). These files are never committed; with
no config present, the corresponding surfaces stay generic and inert.

## 📄 License

MIT © Salient Vision Technologies, LLC

## 🙏 Contributing

PRs welcome! See [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines.

---

**Built with ❤️ for developers who need reliable local services.**
