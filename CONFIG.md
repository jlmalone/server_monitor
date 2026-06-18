# Local configuration

Server Monitor's core (the `sm` CLI + Services panel) needs no special setup —
`services.json` is generated on first run.

Several **optional** menu-bar panels are machine-specific and read their settings
from **untracked** local files that are **never committed** to this repo:

| Panel | What it shows | Local config |
|-------|---------------|--------------|
| **VPN** | Read-only network-protection status from a local status file (`/tmp/darkmesh-status.json`) written by a separate helper on your machine. | none in this repo — the helper is configured separately |
| **Worker** | Start/stop + throughput of a local background worker node. | `~/.config/server-monitor/worker.json` |
| **Transfers** | Active file transfers (per item: %, rate, ETA) read from a queue CLI's JSON, across one or more machines. | `~/.config/server-monitor/transfers.json` |
| **Protection** | Fail-closed integrity: one **OK / AT RISK** badge plus one-click **Repair**, from a list of check/repair commands you define. | `~/.config/server-monitor/protection.json` |

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
| `sources[].runCommand` | optional argv that reprocesses failed/pending transfers; when set, failed rows show a one-click **Resume** that runs it detached (survives the menu closing). Omit to keep the source read-only. |
| `history.command` | optional argv that prints the **past-transfers** log as JSON-lines (one record per line); enables the **Transfer History** window (opened from the dropdown). Omit to leave that window unconfigured. |

The command must print JSON shaped like
`{ "queue": [ { "id","source","dest","status","mode","bytesTransferred","bytesTotal","filesDone","filesTotal","rateBytesPerSec","currentFile" } ], "summary": { "running","pending","failed" } }`
— **raw byte counters**; the panel computes % and ETA itself. With no
`transfers.json`, the Transfers panel is inert.

The **Transfer History** window reads `history.command`, which must print **one
JSON object per line**, each shaped like `{ "id","repositories":[…],"sourceMachine",
"targetMachine","startTime","endTime","status","filesTransferred","bytesTransferred","errors" }`.
Only `id`/`startTime`/`status` are required; the rest degrade gracefully. The
window is searchable, status-filterable (defaults to **Failed** for triage) and
newest-first, with click-to-drill detail. It also carries **Inventory** and
**Reclaim** tabs that activate once the tool exposes those as JSON (Reclaim is
read-only / dry-run only — the app never deletes).

## Protection config

Continuously verify the machine's fail-closed invariants and re-arm them with one
click. Each check is a shell command (argv); **exit 0 = OK, nonzero = AT RISK**.

```bash
cp config/protection.example.json ~/.config/server-monitor/protection.json
$EDITOR ~/.config/server-monitor/protection.json
```

Schema (`config/protection.example.json`):

| Key | Meaning |
|-----|---------|
| `pollSeconds` | optional poll interval (default 10) |
| `checks[].id` | stable identifier for the invariant |
| `checks[].label` | name shown in the panel |
| `checks[].check` | argv run via a login shell; exit 0 = OK, nonzero = AT RISK |
| `checks[].repair` | optional argv that re-arms the invariant when you click **Repair** |
| `checks[].note` | optional hint shown when the check is failing (e.g. "needs admin") |

The panel shows a single **Protection: OK / AT RISK** badge (distinct from the VPN
verdict), lists any failing invariants, and offers a one-click **Repair** that runs
the `repair` argv for each failing check. With no `protection.json`, the panel is
inert. As with the others, the app only runs the configured argv and reads exit
codes — no host names or tool specifics live in tracked source.

**Check depth matters.** `launchctl print …` only proves an agent is *loaded*. For
a watchdog loop, also assert it is *running* (has a pid) and its status output is
*fresh* — a loaded-but-dead loop is the silent failure mode. The simplest robust
approach is one **composite audit** command that returns nonzero if anything in the
stack is missing/stale (e.g. darkmesh's `darkmesh-audit`), plus a binding check
(`transfer-vpn-doctor --check`: exit `3` = stale). A failing check turns the
menu-bar dot **off green** via the existing combined tint — so "green requires every
keep-alive service running" needs no app code, just these checks.

## Why these live outside git

These files carry **per-machine paths and operational specifics** that are
intentionally kept out of the public repository. They are synced across your own
machines **out-of-band** (e.g. via your file-transfer tooling), **not** through
git. Treat them like `.env`: local, private, and never staged. The repo's
`.gitignore` already excludes `*.local.*` and `config/worker.json` as a backstop.
