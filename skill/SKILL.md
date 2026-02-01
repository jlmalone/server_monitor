# Server Monitor Skill

Manage macOS development servers through the `sm` CLI. All services run via launchd for reliability.

## Commands

```bash
# List all services with status
sm list

# Detailed status (with health checks)
sm status
sm status <name>

# Start/stop/restart
sm start <name>     # Start specific service
sm start --all      # Start all services
sm stop <name>
sm stop --all
sm restart <name>
sm restart --all

# View logs
sm logs <name>           # Tail stdout
sm logs <name> --error   # Tail stderr
sm logs <name> -n 100    # Show last 100 lines

# Add new service
sm add --name "My App" --path ~/project --port 5000
sm add --name "Custom" --path ~/app --port 8000 --cmd "python -m http.server 8000"

# Remove service
sm remove <name>
```

## Current Services

| Name       | Port | Identifier                |
|------------|------|---------------------------|
| Redo HTTPS | 3000 | vision.salient.redo-https |
| Universe   | 4001 | vision.salient.universe   |
| Vision     | 4002 | vision.salient.vision     |
| Numina     | 4003 | vision.salient.numina     |
| Knomee     | 4004 | vision.salient.knomee     |

## Configuration

Central config: `~/ios_code/server_monitor/services.json`

## Tips

- Use partial names: `sm stop uni` matches "Universe"
- Health checks: HTTP request to the configured health URL
- Logs: stdout/stderr in `~/ios_code/server_monitor/logs/`
- Auto-restart: launchd automatically restarts crashed services

## Error Handling

If a service won't start:
1. Check logs: `sm logs <name> --error`
2. Verify path exists and command is correct
3. Check port isn't already in use: `/usr/sbin/lsof -i :<port>`
4. Reinstall: `sm remove <name>` then `sm add ...`
