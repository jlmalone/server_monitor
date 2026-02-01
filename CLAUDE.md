# Server Monitor - AI Skill Instructions

**Description**: Managing the Server Monitor ecosystem (macOS App, CLI, and launchd services).

## Project Overview
A comprehensive macOS solution for managing development servers (Next.js, Node.js, etc.) as persistent background services. It includes a native Menu Bar App, a CLI tool, and an Installer.

## Architecture
- **Core**: Uses native `launchd` (LaunchAgents) for service management. Survives reboots/crashes.
- **CLI**: Node.js tool (`sm`) compiled to a binary. Manages config (`services.json`) and interacts with `launchctl`.
- **App**: SwiftUI Menu Bar App. visualizes status, toggles services, and edit configuration.
- **Config**: JSON-based configuration at `~/Library/Application Support/ServerMonitor/services.json` (primary) or local project paths.

## Key Capabilities

### 1. Service Management
Services are defined by a unique `identifier` (e.g., `com.servermonitor.myapp`).
- **Start**: Load plist -> `launchctl load` -> `launchctl start`
- **Stop**: `launchctl unload` (stops KeepAlive) or `launchctl stop` + `kill PID`
- **Monitor**: Check `launchctl list` for PID and Exit Status.

### 2. Configuration (`services.json`)
```json
{
  "services": [
    {
      "name": "My App",
      "identifier": "com.user.my-app",
      "path": "/absolute/path/to/project",
      "command": ["npm", "run", "dev"],
      "port": 3000,
      "healthCheck": "http://localhost:3000",
      "enabled": true
    }
  ]
}
```

### 3. Packaging & Distribution
- **Scripts**: Located in `scripts/`.
- **Build**: `./scripts/build_installer.sh` creates `ServerMonitor.pkg` (App + CLI).
- **Uninstall**: `./scripts/uninstall.sh` removes App and CLI.

## Common Tasks

### Adding a New Command/Feature
1. **CLI**: Add to `cli/src/commands/`. Register in `cli/src/index.js`.
2. **App**: Add to `ServiceMonitor.swift` (ViewModel) and UI in `ServerMonitorApp.swift`.
3. **Parity**: Ensure both CLI and App can perform the action.

### Debugging Services
- **Logs**: Check `~/ios_code/server_monitor/logs/` (or configured logDir).
- **Status**: Run `sm status` or check the Menu Bar App.
- **Launchd**: `launchctl list | grep <identifier>`

## Development Guidelines
- **Swift**: Use MVVM. Keep Views simple. Logic goes in `ServiceMonitor` or `LaunchAtLogin`.
- **Node.js**: Use ES Modules. Use `execSync` for system calls. Keep logic platform-agnostic where possible (though this is a macOS tool).
- **Testing**: `npm test` in `cli/`. Use `test:ci` for CI environments.

## Skill Routines
If asked to "add a feature", verify:
1. Does it need `launchd` changes? (e.g. Env vars, StandardOutPath)
2. Does the CLI support it?
3. Does the GUI support it?
4. Is it persistent?

If asked to "debug":
1. Check `sm logs <service> --error`
2. Check `launchctl list` status code (0 = ok, 78 = config error, etc)
