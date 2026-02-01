# Server Monitor Examples

## Common Requests → Commands

### Checking status
- "What servers are running?" → `sm list`
- "Is universe running?" → `sm status universe`
- "Show me the server status" → `sm status`
- "Check the health of my dev servers" → `sm status`

### Starting/stopping
- "Start the universe server" → `sm start universe`
- "Stop numina" → `sm stop numina`
- "Restart knomee" → `sm restart knomee`
- "Start all servers" → `sm start --all`
- "Stop everything" → `sm stop --all`
- "Restart all dev servers" → `sm restart --all`

### Viewing logs
- "Show me the logs for vision" → `sm logs vision`
- "What's in the numina error log?" → `sm logs numina --error`
- "Show last 200 lines of universe logs" → `sm logs universe -n 200`

### Adding services
- "Add a dev server for ~/myproject on port 4005" →
  `sm add --name "My Project" --path ~/myproject --port 4005`
  
- "Add a server that runs 'npm start' in ~/webapp on port 3001" →
  `sm add --name "Web App" --path ~/webapp --port 3001 --cmd "npm start"`

- "Add ~/api with a Python server on 8000" →
  `sm add --name "API" --path ~/api --port 8000 --cmd "python -m http.server 8000"`

### Removing services
- "Remove the test server" → `sm remove test`
- "Delete my-app from the server list" → `sm remove my-app`

## Output Interpretation

### `sm list` output
```
┌────────────┬──────┬───────────┬───────┬───────────────────────────┐
│ Service    │ Port │ Status    │ PID   │ Identifier                │
├────────────┼──────┼───────────┼───────┼───────────────────────────┤
│ Universe   │ 4001 │ ● Running │ 12345 │ vision.salient.universe   │
│ Vision     │ 4002 │ ○ Stopped │ -     │ vision.salient.vision     │
└────────────┴──────┴───────────┴───────┴───────────────────────────┘
```
- ● Running = Service is active
- ○ Stopped = Service is not running
- ○ Not installed = Service is in config but not loaded into launchd

### `sm status` statuses
- **Healthy** = Running + port listening + health check passing
- **Running** = Process running but no health check configured
- **Starting** = Process running but port not yet listening
- **Unhealthy** = Running but health check failing
- **Stopped** = Not running
- **Not installed** = Not loaded into launchd

## Troubleshooting

### "Service won't start"
```bash
# Check error logs
sm logs <name> --error

# Verify the path exists
ls -la <service-path>

# Check if port is in use
/usr/sbin/lsof -i :<port>
```

### "Service keeps restarting"
The process is crashing. Check the error log:
```bash
sm logs <name> --error
```

### "Command not found: sm"
```bash
# Reinstall CLI globally
cd ~/ios_code/server_monitor/cli && npm link
```
