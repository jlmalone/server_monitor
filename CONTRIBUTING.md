# Contributing to Server Monitor

Thanks for your interest in contributing! 🎉

## Development Setup

1. Clone the repo:
   ```bash
   git clone https://github.com/YOUR_USERNAME/server-monitor.git
   cd server-monitor
   ```

2. Install CLI dependencies:
   ```bash
   cd cli
   npm install
   npm link  # Makes 'sm' command available globally
   ```

3. For the SwiftUI app:
   - Open `app/ServerMonitor/ServerMonitor.xcodeproj` in Xcode
   - Build and run

## Project Structure

```
server_monitor/
├── cli/                 # Node.js CLI tool
│   ├── src/
│   │   ├── commands/    # CLI command implementations
│   │   └── lib/         # Shared utilities
│   └── bin/sm           # CLI entry point
├── app/                 # SwiftUI menu bar app (macOS only)
│   └── ServerMonitor/
├── logs/                # Service logs (generated)
├── launchd/             # Generated plist files (macOS)
├── services.json        # Your service configuration (copy from services.example.json)
└── services.example.json # Example configuration template
```

## Making Changes

### CLI Changes
1. Edit files in `cli/src/`
2. Test with `sm <command>`
3. The CLI auto-reloads since it's linked

### SwiftUI App Changes
1. Open the Xcode project
2. Make changes
3. Build and run (⌘R)
4. The app reads from `services.json` for service list

### Adding a New CLI Command
1. Create `cli/src/commands/yourcommand.js`
2. Export an async function: `export async function yourCommand(options) { ... }`
3. Register in `cli/src/index.js`

## Code Style

- Use ESM (`import`/`export`)
- Use `chalk` for colored output
- Use `ora` for spinners
- Handle errors gracefully with user-friendly messages

## Testing

Currently manual testing. Run through common workflows:
```bash
sm list
sm status
sm start <name>
sm stop <name>
sm restart <name>
sm logs <name>
sm add --name "Test" --path ~/test --port 9999
sm remove test
```

## Pull Requests

1. Fork the repo
2. Create a branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Test thoroughly
5. Commit with clear messages
6. Push and open a PR

## Questions?

Open an issue or reach out!
