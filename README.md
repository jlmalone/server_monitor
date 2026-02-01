# Server Monitor 🖥️

[![macOS](https://img.shields.io/badge/macOS-14+-blue?logo=apple)](https://www.apple.com/macos/)
[![Node.js](https://img.shields.io/badge/Node.js-18+-green?logo=node.js)](https://nodejs.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](./CONTRIBUTING.md)

A lightweight macOS dev server manager using native `launchd` for reliable, persistent services.

## ✨ Features

- **🔧 CLI Tool (`sm`)** - Manage services from the terminal
- **📱 Menu Bar App** - Quick status view and controls
- **🤖 LLM Integration** - Natural language server management
- **🔄 Auto-restart** - launchd automatically restarts crashed services
- **📊 Health Checks** - HTTP health monitoring
- **📝 Centralized Logs** - All logs in one place

## 🚀 Quick Start

### Install CLI

```bash
cd ~/ios_code/server_monitor/cli
npm install
npm link
```

### Basic Usage

```bash
# List all services
sm list

# Check detailed status
sm status

# Start/stop/restart
sm start universe
sm stop numina
sm restart --all

# View logs
sm logs universe
sm logs knomee --error

# Add a new service
sm add --name "My App" --path ~/myproject --port 5000
```

## 📸 Screenshots

### CLI Output
```
┌────────────┬──────┬───────────┬───────┬───────────────────────────┐
│ Service    │ Port │ Status    │ PID   │ Identifier                │
├────────────┼──────┼───────────┼───────┼───────────────────────────┤
│ Universe   │ 4001 │ ● Running │ 37695 │ vision.salient.universe   │
│ Vision     │ 4002 │ ● Running │ 37700 │ vision.salient.vision     │
│ Numina     │ 4003 │ ● Running │ 37685 │ vision.salient.numina     │
│ Knomee     │ 4004 │ ● Running │ 37680 │ vision.salient.knomee     │
└────────────┴──────┴───────────┴───────┴───────────────────────────┘

✓ All 4 services running
```

### Menu Bar App
The SwiftUI menu bar app shows service status at a glance with hover controls for quick start/stop/restart.

## 📋 Commands

| Command | Description |
|---------|-------------|
| `sm list` | List all services with status |
| `sm status [name]` | Detailed health check |
| `sm start <name\|--all>` | Start service(s) |
| `sm stop <name\|--all>` | Stop service(s) |
| `sm restart <name\|--all>` | Restart service(s) |
| `sm logs <name>` | Tail service logs |
| `sm add [options]` | Add new service |
| `sm remove <name>` | Remove a service |

### Add Options
```bash
sm add \
  --name "My Server" \
  --path ~/project \
  --port 4005 \
  --cmd "npm run dev" \
  --health "http://localhost:4005/health"
```

## 🏗️ Architecture

```
server_monitor/
├── cli/                 # Node.js CLI tool (sm command)
│   ├── src/commands/    # Command implementations
│   └── src/lib/         # Config, launchd, health utilities
├── app/                 # SwiftUI menu bar app
│   └── ServerMonitor/
├── skill/               # Clawdbot LLM integration
│   ├── SKILL.md         # LLM instructions
│   └── examples.md      # Usage examples
├── launchd/             # Generated plist files
├── logs/                # Service stdout/stderr logs
├── services.json        # Central service registry
└── scripts/             # Legacy shell scripts
```

## ⚙️ Configuration

Services are defined in `services.json`:

```json
{
  "version": "2.0.0",
  "settings": {
    "logDir": "/path/to/logs",
    "identifierPrefix": "vision.salient"
  },
  "services": [
    {
      "name": "My App",
      "identifier": "vision.salient.my-app",
      "path": "/path/to/project",
      "command": ["npx", "vite", "--port", "4001"],
      "port": 4001,
      "healthCheck": "http://localhost:4001",
      "enabled": true
    }
  ]
}
```

## 🍎 Why launchd?

Unlike background processes started from terminals:

- ✅ **Survives terminal close** - Services keep running
- ✅ **Survives logout** - Optional: can run as system daemon
- ✅ **Auto-restart** - Crashed services restart automatically
- ✅ **Boot persistence** - Services start at login
- ✅ **Native macOS** - No third-party process managers

## 🤖 LLM Integration

The `skill/` directory enables natural language server management:

- "What servers are running?"
- "Stop the universe server"
- "Show me the logs for numina"
- "Add a dev server for ~/myproject on port 4005"

See [skill/SKILL.md](./skill/SKILL.md) for integration details.

## 🔧 Manual launchd Commands

```bash
# List managed services
launchctl list | grep salient

# Stop a service
launchctl stop vision.salient.universe

# Start a service
launchctl start vision.salient.universe

# Unload completely
launchctl unload ~/Library/LaunchAgents/vision.salient.universe.plist

# View logs
tail -f ~/ios_code/server_monitor/logs/universe.log
```

## 🐛 Troubleshooting

### Service won't start
```bash
# Check error log
sm logs <name> --error

# Validate plist
plutil ~/Library/LaunchAgents/vision.salient.<name>.plist

# Check port in use
/usr/sbin/lsof -i :<port>
```

### Service keeps restarting
Check the error log - the process is likely crashing:
```bash
sm logs <name> --error
```

### CLI command not found
```bash
cd ~/ios_code/server_monitor/cli && npm link
```

## 📄 License

MIT © Joseph Malone

## 🙏 Contributing

PRs welcome! See [CONTRIBUTING.md](./CONTRIBUTING.md).
