# Local configuration

Server Monitor's core (the `sm` CLI + Services panel) needs no special setup —
`services.json` is generated on first run.

Two **optional** menu-bar panels are machine-specific and read their settings
from **untracked** local files that are **never committed** to this repo:

| Panel | What it shows | Local config |
|-------|---------------|--------------|
| **VPN** | Read-only network-protection status from a local status file (`/tmp/darkmesh-status.json`) written by a separate helper on your machine. | none in this repo — the helper is configured separately |
| **Worker** | Start/stop + throughput of a local background worker node. | `~/.config/server-monitor/worker.json` |
| **Transfers** | Active file transfers (per item: %, rate, ETA) read from a queue CLI's JSON, across one or more machines. | `~/.config/server-monitor/transfers.json` |

## Worker config

Copy the example and fill in your machine's real values:

```bash
mkdir -p ~/.config/server-monitor
cp config/worker.example.json ~/.config/server-monitor/worker.json
$EDITOR ~/.config/server-monitor/worker.json
```

Schema (`config/worker.example.json`):

| Key | Meaning |
|-----|---------|
| `repoDir` | working directory the launch script runs in |
| `script` | launch script in `repoDir` (invoked as `./<script> <action> <arg>`) |
| `arg` | argument passed to the script (e.g. a node label) |
| `pidPath` | file holding the running node's PID |
| `logPath` | log to tail for the throughput line |
| `ratePattern` | regex selecting the throughput substring shown in the panel |

With no `worker.json` present, the Worker panel reports **"not configured"** and
its controls stay hidden — the app stays fully generic.

## Transfers config

Point it at a file-transfer CLI that can print its queue as JSON, on one or more
machines:

```bash
cp config/transfers.example.json ~/.config/server-monitor/transfers.json
$EDITOR ~/.config/server-monitor/transfers.json
```

Schema (`config/transfers.example.json`):

| Key | Meaning |
|-----|---------|
| `pollSeconds` | optional poll interval (default 60) |
| `sources[].label` | machine label shown on each transfer row |
| `sources[].command` | argv that prints the queue JSON (run via a login shell); for a remote machine prefix with `ssh <host> nice -n 19 …` |

The command must print JSON shaped like
`{ "queue": [ { "id","source","dest","status","mode","bytesTransferred","bytesTotal","filesDone","filesTotal","rateBytesPerSec","currentFile" } ], "summary": { "running","pending","failed" } }`
— **raw byte counters**; the panel computes % and ETA itself. With no
`transfers.json`, the Transfers panel is inert.

## Why these live outside git

These files carry **per-machine paths and operational specifics** that are
intentionally kept out of the public repository. They are synced across your own
machines **out-of-band** (e.g. via your file-transfer tooling), **not** through
git. Treat them like `.env`: local, private, and never staged. The repo's
`.gitignore` already excludes `*.local.*` and `config/worker.json` as a backstop.
