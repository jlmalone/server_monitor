# Server Monitor - AI Development Guide

**Description**: Development guide for the Server Monitor macOS ecosystem.

## Architecture Overview

Server Monitor manages development servers as persistent background services using macOS's native `launchd` system.

### Core Principle: JSON-First Architecture

**`services.json` is the single source of truth.** All launchd plists are auto-generated from this file.

```
services.json → CLI/App reads → Generates plist → launchctl loads
```

Never edit plists directly - they're regenerated on any service change.

## Key Components

### 1. Configuration (`services.json`)
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
      "path": "/absolute/path/to/project",
      "command": ["npm", "run", "dev"],
      "port": 3000,
      "healthCheck": "http://localhost:3000",
      "enabled": true
    }
  ]
}
```

### 2. CLI (`cli/`)
- Node.js ES Modules
- Entry: `cli/src/index.js`
- Commands in `cli/src/commands/`
- Core libs in `cli/src/lib/`:
  - `config.js` - Read/write services.json
  - `launchd.js` - Generate plists, interact with launchctl
  - `health.js` - HTTP health checks

### 3. Menu Bar App (`app/ServerMonitor/`)
- SwiftUI macOS app
- MVVM architecture
- `ServiceMonitor.swift` - Main ViewModel (reads services.json, manages state)
- `MenuBarView.swift` - UI components
- `Service.swift` - Data model

### 4. File Locations

| Item | Location |
|------|----------|
| Config | `./services.json` (gitignored, user-specific) |
| Example config | `./services.example.json` |
| Generated plists | `./launchd/` (gitignored) |
| Logs | `./logs/` (gitignored) |
| CLI source | `./cli/src/` |
| App source | `./app/ServerMonitor/ServerMonitor/` |

## Service Lifecycle

### Starting a Service
1. Read service from `services.json`
2. Generate plist from template with service config
3. Write plist to `launchd/{identifier}.plist`
4. `launchctl load <plist>`
5. `launchctl start <identifier>`

### Stopping a Service
1. `launchctl stop <identifier>` (graceful)
2. `launchctl unload <plist>` (removes KeepAlive)
3. Optionally kill PID if still running

### Status Check
1. `launchctl list | grep <identifier>`
2. Parse: PID (or `-`), ExitStatus, Label
3. HTTP health check if `healthCheck` URL defined

## Development Guide

### Adding a CLI Command
1. Create `cli/src/commands/mycommand.js`:
```javascript
export const command = 'mycommand <arg>';
export const describe = 'Description here';
export const builder = { /* yargs options */ };
export async function handler(argv) { /* implementation */ }
```
2. Import and register in `cli/src/index.js`
3. Test: `node cli/src/index.js mycommand`

### Adding App Functionality
1. Add method to `ServiceMonitor` class (ViewModel)
2. Add UI in `MenuBarView.swift`
3. Keep Views simple - logic goes in ViewModel

### Plist Template
Generated plists include:
- `Label`: The service identifier
- `ProgramArguments`: The command array
- `WorkingDirectory`: Service path
- `StandardOutPath`/`StandardErrorPath`: Log files
- `KeepAlive`: Auto-restart on crash
- `RunAtLoad`: Start on login

## Common Tasks

### Debug a Service
```bash
# Check launchd status (PID, exit code)
launchctl list | grep <identifier>

# View logs
sm logs <name>
sm logs <name> --error

# Check if port is blocked
lsof -i :<port>
```

### Test Config Changes
```bash
# Validate JSON
cat services.json | jq .

# Dry-run plist generation
sm status --verbose
```

### Build Release
```bash
# Full release build (app + CLI + DMG)
./scripts/build_release.sh

# Just the app
cd app/ServerMonitor && xcodebuild -scheme ServerMonitor -configuration Release

# Just sign and notarize
./scripts/sign_and_notarize.sh
```

## Testing

```bash
# CLI tests
cd cli && npm test

# Manual integration test
sm add --name "Test" --path /tmp --port 9999 --cmd "python3 -m http.server 9999"
sm start Test
curl localhost:9999
sm stop Test
sm remove Test
```

## Exit Codes (launchd)

| Code | Meaning |
|------|---------|
| 0 | Success |
| 78 | Configuration error |
| Other | Process crashed with that exit code |

## Important Notes

- **Branch**: Use `master` (not main)
- **Config is user-specific**: `services.json` is gitignored
- **Plists are ephemeral**: Regenerated from JSON on changes
- **Paths**: Use absolute paths in services.json for reliability
