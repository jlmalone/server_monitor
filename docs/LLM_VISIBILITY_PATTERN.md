# LLM Visibility Pattern for Web Development

## The Problem

When LLMs assist with web application development, they operate "blind":

1. **No access to browser state** - LLMs can't see what's rendered, what data is loaded, what errors appear
2. **Console logs are invisible** - Browser DevTools console is inaccessible to terminal-based LLMs
3. **Network requests are opaque** - Can't see API responses, failures, or timing
4. **User must manually describe** - "I see an error" requires screenshots, copy-paste, guessing

This leads to:
- Slow debugging cycles
- Miscommunication about visual state
- Inability to verify fixes
- Frustrating back-and-forth

## The Solution: Debug Server Trio

Expose browser state via HTTP endpoints that LLMs can query directly.

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Browser (Web App)                    │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ console.log  │  │ App State    │  │ Network Req  │  │
│  │ → POST /log  │  │ → POST /data │  │ → Intercepted│  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  │
└─────────┼─────────────────┼─────────────────┼──────────┘
          │                 │                 │
          ▼                 ▼                 ▼
┌─────────────────────────────────────────────────────────┐
│                    Debug Server Trio                     │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ Log Server   │  │ Diagnostics  │  │ Debug API    │  │
│  │ :3002        │  │ :3001        │  │ :3009        │  │
│  │              │  │              │  │              │  │
│  │ GET /logs    │  │ GET /state   │  │ GET /snapshot│  │
│  │ GET /errors  │  │ POST /audit  │  │ POST /exec   │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────┘
          │                 │                 │
          ▼                 ▼                 ▼
┌─────────────────────────────────────────────────────────┐
│                   LLM (Terminal/Agent)                   │
│                                                          │
│  curl http://localhost:3002/logs | jq                   │
│  curl http://localhost:3009/api/debug/snapshot | jq     │
│  curl -X POST http://localhost:3001/api/audit/task/123  │
│                                                          │
│  → Full visibility into browser state!                   │
└─────────────────────────────────────────────────────────┘
```

### The Three Servers

#### 1. Log Server (port 3002)

**Purpose:** Capture and expose browser console output

**Implementation:**
```javascript
// In browser - override console methods
const originalLog = console.log;
console.log = (...args) => {
  fetch('http://localhost:3002/log', {
    method: 'POST',
    body: JSON.stringify({ level: 'log', args, timestamp: Date.now() })
  });
  originalLog.apply(console, args);
};

// Server endpoint
app.get('/logs', (req, res) => {
  res.json(logs.slice(-100)); // Last 100 entries
});

app.get('/errors', (req, res) => {
  res.json(logs.filter(l => l.level === 'error'));
});
```

**LLM Usage:**
```bash
# See recent console output
curl -s http://localhost:3002/logs | jq '.[-10:]'

# Check for errors
curl -s http://localhost:3002/errors | jq
```

#### 2. Diagnostics Server (port 3001)

**Purpose:** Query and manipulate app state

**Implementation:**
```javascript
// Expose localStorage, sessionStorage, app state
app.get('/localStorage', (req, res) => {
  // Injected script fetches and returns localStorage
});

app.post('/audit/task/:taskId', (req, res) => {
  // Run audit on specific task, return results
});

app.get('/state', (req, res) => {
  // Return current app state (Redux, Zustand, etc.)
});
```

**LLM Usage:**
```bash
# Audit a specific task
curl -X POST http://localhost:3001/api/audit/task/abc123

# Get current app state
curl -s http://localhost:3001/state | jq
```

#### 3. Debug API Server (port 3009)

**Purpose:** Deep inspection and validation

**Implementation:**
```javascript
// Full state snapshot
app.get('/api/debug/snapshot', (req, res) => {
  res.json({
    tasks: getAllTasks(),
    nodes: getAllNodes(),
    syncStatus: getSyncStatus(),
    validation: runValidation()
  });
});

// Execute commands in browser context
app.post('/api/debug/exec', (req, res) => {
  // Queue command for browser to execute
});

// Validate specific data
app.post('/api/debug/validate', (req, res) => {
  // Run validation rules on provided data
});
```

**LLM Usage:**
```bash
# Get full snapshot
curl -s http://localhost:3009/api/debug/snapshot | jq

# Validate data
curl -X POST http://localhost:3009/api/debug/validate \
  -H "Content-Type: application/json" \
  -d '{"node": {...}}'
```

## Benefits

### For LLMs
- **Direct observation** - No need to ask user "what do you see?"
- **Programmatic debugging** - Add console markers, check results
- **Verification** - Confirm fixes work without user intervention
- **Context building** - Understand full app state before suggesting changes

### For Developers
- **Faster cycles** - LLM can debug independently
- **Less context-switching** - No need to screenshot, copy-paste
- **Better suggestions** - LLM has full picture, not guesses
- **Audit trail** - Log history available for review

## Implementation Checklist

For each web project, implement:

- [ ] **Log Server** (capture console.log/warn/error)
  - [ ] Console override in browser
  - [ ] Log storage (file or memory)
  - [ ] GET /logs endpoint
  - [ ] GET /errors endpoint
  - [ ] Optional: WebSocket for real-time

- [ ] **Diagnostics Server** (app state inspection)
  - [ ] GET /state endpoint
  - [ ] GET /localStorage endpoint
  - [ ] POST /audit/:id for specific item inspection
  - [ ] Framework-specific state access (Redux, Zustand, etc.)

- [ ] **Debug API** (deep inspection)
  - [ ] GET /snapshot for full state dump
  - [ ] POST /validate for data validation
  - [ ] POST /exec for browser command execution
  - [ ] Schema validation utilities

## Port Convention

| Service | Port | Purpose |
|---------|------|---------|
| Dev Server | 3000/4000+ | Main application |
| Diagnostics | 3001 | State inspection |
| Log Server | 3002 | Console capture |
| Debug API | 3009 | Deep debugging |

## Security Notes

⚠️ **Development only!** These servers expose internal state.

- Bind to localhost only
- Never deploy to production
- Add to .gitignore if credentials exposed
- Consider auth for shared dev environments

## Example: Redo Web App

The redo-web-app project implements this pattern:

```
~/WebstormProjects/redo-web-app/
├── diagnostics-server.js  # Port 3001
├── log-server.js          # Port 3002  
├── debug-server.js        # Port 3009
└── src/
    └── components/
        └── LogServerHealthCheck.tsx  # Browser integration
```

See `~/redo-testing/LLM_IMPLEMENTATION_GUIDE.md` for detailed API documentation.

## Adapting to Other Frameworks

### React (Vite)
- Add debug servers as separate Node.js processes
- Use Vite's proxy config to route debug requests
- Inject console overrides in main.tsx

### Vue/Nuxt
- Similar approach, add to nuxt.config.js devServer
- Use Pinia/Vuex devtools export for state

### Svelte/SvelteKit
- Add to vite.config.js
- Export stores via window for debugging

### Angular
- Add to angular.json serve config
- Expose NgRx state via debug endpoint

## Future Enhancements

- [ ] Browser extension for automatic integration
- [ ] VS Code extension for log viewing
- [ ] Unified debug dashboard
- [ ] Cross-project log aggregation
- [ ] AI-suggested debug queries

---

*This pattern emerged from practical LLM-assisted development on the REDO project (2026). It transformed debugging from "describe what you see" to "let me look directly."*
