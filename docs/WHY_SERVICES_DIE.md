# Why Services Are Dying & How to Fix It

## Current Issues

### 1. Clawdbot Gateway Restarts Frequently
**Symptoms:** Heartbeat starts every few hours, services reconnect

**Root Causes:**
- **Memory pressure**: 7.6GB/8GB RAM usage (96% full)
- **Multiple Claude sessions**: Competing for resources
- **Unhandled errors**: Fetch failures, WhatsApp connection drops
- **Node.js issues**: Old v16 interference, module conflicts

**Solutions:**
✅ Add more RAM (8GB → 16GB+)
✅ Close unused Claude Code sessions
✅ Fix Node.js PATH issues (done)
✅ Add proper error handling in clawdbot config
✅ Monitor with server_monitor app

### 2. Web Servers Running as Subprocess
**Problem:** When you close terminal or Claude session, servers die

**Current State:**
```bash
josephmalone  26320  node log-server.j kill_retry_time=100
josephmalone  26353  node debug-server kill_retry_time=100
josephmalone  31870  node https-server.js
```

These are **child processes** of terminal/IDE sessions. If parent dies, they die.

**Solutions:**

#### Option A: Convert to LaunchAgents (Recommended)
Make them independent system services that survive logouts.

**Create: `~/Library/LaunchAgents/com.redo.https-server.plist`**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.redo.https-server</string>

    <key>ProgramArguments</key>
    <array>
        <string>/Users/josephmalone/.nvm/versions/node/v24.13.0/bin/node</string>
        <string>/Users/josephmalone/WebstormProjects/redo-web-app/https-server.js</string>
    </array>

    <key>WorkingDirectory</key>
    <string>/Users/josephmalone/WebstormProjects/redo-web-app</string>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/Users/josephmalone/WebstormProjects/redo-web-app/logs/https.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/josephmalone/WebstormProjects/redo-web-app/logs/https.err.log</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/Users/josephmalone/.nvm/versions/node/v24.13.0/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>NODE_ENV</key>
        <string>production</string>
    </dict>
</dict>
</plist>
```

**Load it:**
```bash
launchctl load ~/Library/LaunchAgents/com.redo.https-server.plist
launchctl start com.redo.https-server
```

**Benefits:**
- ✅ Survives terminal/IDE closures
- ✅ Auto-starts on boot
- ✅ Auto-restarts on crash
- ✅ Proper logging
- ✅ Runs as user (no sudo)

#### Option B: Use PM2 Process Manager
```bash
npm install -g pm2

# Start servers with PM2
cd ~/WebstormProjects/redo-web-app
pm2 start https-server.js --name "redo-https"
pm2 start log-server.j --name "redo-logs"
pm2 start debug-server --name "redo-debug"

# Save configuration
pm2 save

# Auto-start on boot
pm2 startup
```

**Benefits:**
- ✅ Easy process management
- ✅ Built-in monitoring
- ✅ Log aggregation
- ✅ Cluster mode support
- ✅ Web dashboard

#### Option C: Docker Containers
Ultimate isolation and reliability.

```dockerfile
FROM node:24-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 443
CMD ["node", "https-server.js"]
```

```bash
docker-compose up -d
```

## Common Failure Patterns

### Pattern 1: Parent Process Dies
**Symptom:** Server stops when you close IDE/terminal
**Fix:** Use LaunchAgent or PM2 (not subprocess)

### Pattern 2: Port Already in Use
**Symptom:** Server fails to start with "EADDRINUSE"
**Fix:**
```bash
# Find process using port
lsof -i :443
# Kill it
kill -9 <PID>
# Or use different port
```

### Pattern 3: Out of Memory
**Symptom:** Process killed by system (OOM)
**Fix:**
- Increase Node.js heap: `--max-old-space-size=4096`
- Fix memory leaks
- Add swap space
- Upgrade RAM

### Pattern 4: Unhandled Promise Rejection
**Symptom:** Node process crashes on async errors
**Fix:**
```javascript
// Add global handlers
process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection:', reason);
  // Don't exit, just log
});

process.on('uncaughtException', (error) => {
  console.error('Uncaught Exception:', error);
  // Optional: restart gracefully
});
```

### Pattern 5: File Descriptor Exhaustion
**Symptom:** "EMFILE: too many open files"
**Fix:**
```bash
# Check limits
ulimit -n

# Increase (temporary)
ulimit -n 10240

# Permanent: Edit /etc/launchd.conf
echo "limit maxfiles 10240 unlimited" | sudo tee -a /etc/launchd.conf
```

## Recommended Architecture

### Current (Fragile):
```
Terminal/IDE
  └─> node https-server.js  ❌ Dies with parent
  └─> node log-server.j     ❌ Dies with parent
  └─> node debug-server     ❌ Dies with parent

LaunchAgent (com.clawdbot.gateway)
  └─> clawdbot-gateway      ✅ Survives, but restarts
```

### Recommended (Robust):
```
LaunchAgent (com.redo.https-server)
  └─> node https-server.js  ✅ Independent, auto-restart

LaunchAgent (com.redo.log-server)
  └─> node log-server.j     ✅ Independent, auto-restart

LaunchAgent (com.redo.debug-server)
  └─> node debug-server     ✅ Independent, auto-restart

LaunchAgent (com.clawdbot.gateway)
  └─> clawdbot-gateway      ✅ Independent, monitored
```

**Monitor All with Server Monitor App** 📊

## Immediate Action Plan

1. **Create LaunchAgents** for all web servers
   ```bash
   # Use the templates in this doc
   # Create 3 plist files:
   # - com.redo.https-server.plist
   # - com.redo.log-server.plist
   # - com.redo.debug-server.plist
   ```

2. **Stop current processes**
   ```bash
   pkill -f https-server.js
   pkill -f log-server.j
   pkill -f debug-server
   ```

3. **Load LaunchAgents**
   ```bash
   launchctl load ~/Library/LaunchAgents/com.redo.*.plist
   ```

4. **Build Server Monitor app**
   - Follow AI_INSTRUCTIONS.md
   - Monitor all 4 services
   - Get alerts when anything dies

5. **Upgrade System Resources**
   - Add more RAM (critical!)
   - Close unused apps
   - Monitor with Activity Monitor

## Health Check Commands

```bash
# Check clawdbot
launchctl list | grep clawdbot

# Check web servers
pgrep -fl "https-server|log-server|debug-server"

# Check ports
lsof -i :443 -i :3000 -i :8080

# Check logs
tail -f ~/.clawdbot/logs/gateway.err.log
tail -f ~/WebstormProjects/redo-web-app/logs/*.log

# System resources
top -l 1 | head -10
```

## Monitoring Strategy

### Level 1: Server Monitor App (Real-time)
- 5-second health checks
- Instant notifications
- Auto-restart on failure

### Level 2: Log Monitoring
```bash
# Watch for errors
tail -f *.log | grep -i error
```

### Level 3: Resource Monitoring
```bash
# CPU/Memory per service
top -pid $(pgrep clawdbot-gateway)
```

### Level 4: Uptime Tracking
```bash
# Service uptime
ps -p $(pgrep clawdbot-gateway) -o etime
```

## Success Metrics

After implementing:
- ✅ Services survive terminal/IDE closures
- ✅ Automatic restart on crash
- ✅ < 1 minute downtime before recovery
- ✅ Visible status in menu bar
- ✅ Alert notifications working
- ✅ No manual intervention needed for 24h+

## Next Steps

1. Create this monitoring app (follow AI_INSTRUCTIONS.md)
2. Convert web servers to LaunchAgents
3. Add memory monitoring
4. Set up automated health reports
5. Consider cloud monitoring (optional)
