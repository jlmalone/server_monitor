# Local configuration

Server Monitor's core (the `sm` CLI + Services panel) needs no special setup —
`services.json` is generated on first run.

Several **optional** menu-bar panels are machine-specific and read their settings
from **untracked** local files that are **never committed** to this repo:

| Panel | What it shows | Local config |
|-------|---------------|--------------|
| **VPN** | Read-only network-protection status from a local status file (`/tmp/darkmesh-status.json`) written by a separate helper on your machine. | none in this repo — the helper is configured separately |
| **Worker** | Start/stop + throughput of a local background worker node. | `~/.config/server-monitor/worker.json` |
| **Transfers** | Active file transfers (per item: %, rate, ETA), preferably from an atomically written local status file. | `~/.config/server-monitor/transfers.json` |
| **Protection** | Read-only fail-closed integrity: one **OK / AT RISK** badge from bounded audit commands. | `~/.config/server-monitor/protection.json` |
| **Infrastructure Agent** | One signed registration that supervises persistent helpers, scheduled one-shot jobs, and network-change wakeups. | `~/.config/server-monitor/infrastructure-agent.json` |
| **Network Status** | Compact desired/observed network posture, topology, peer state, and bounded health probes. | `~/.config/server-monitor/network.json` |

## Network Status config

Copy `config/network.example.json` to `~/.config/server-monitor/network.json`. It is
optional: without it, Network Status remains inert. `schema` is currently `1`.

Darkmesh command sources use its schema-2 envelopes: `profiles` contains the profile
array; `show` returns desired profile, observed status, and producer assessment;
`topology` returns passive local interfaces, routes, Tailscale health, and cached peer
state; `probe` is the explicit active peer check. Unknown fields are ignored, but an
unsupported envelope is unavailable rather than treated as healthy.

`probeCommand`, `probes`, and `diagnostics` are bounded direct argv arrays. Probes must be read-only;
use them for peer posture, health, VPN, SSH, and transfer-readiness checks. A failed
required probe is red; failed optional probes and producer degradation are yellow.
`postures[].set_command` and `applyCommand` are the only mutating hooks, and both
always present an explicit confirmation before execution. No command is
shell-interpolated. Set only values
appropriate for the local trusted machine, and do not commit this file.

Command-driven producers may instead supply `profilesCommand`, `statusCommand`,
`topologyCommand`, and `probeCommand`, each a bounded direct argv array. The periodic window refresh runs
only local status/topology sources; SSH, remote health, deep audits, and logs are
explicit user actions. `applyCommand` is one argv template and must include a whole
`{profile}` element or substring; replacement is per argv element, never shell text.
Profiles may carry `id`, `title`, required/preferred/forbidden maps, priority,
degraded state, capabilities, and a connectivity consequence. `logSources` read a
capped local-file tail or run a bounded log command only after Refresh.
Capability maps are descriptive producer telemetry. The versioned
`transition.apply: "refuse"` field is the authoritative apply gate, so an unrelated
false capability does not disable an otherwise supported profile.

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
| `sources[].statusFile` | preferred local source: an atomically replaced queue-status JSON file; reading it does not spawn the queue runtime |
| `sources[].command` | optional bounded argv fallback that prints queue JSON, primarily for remote sources; it executes directly, not through a shell |
| `sources[].healthFile` | optional file whose modification time proves the queue producer or scheduler is alive |
| `sources[].maxHealthAgeSeconds` | heartbeat age limit (default 240 seconds, minimum 10) |
| `sources[].maxActiveSnapshotAgeSeconds` | maximum age of `generatedAt` while queue work is running or pending (default 30 seconds, minimum 10) |
| `sources[].receiptFile` | optional local atomic JSON file containing one `choam.transfer-receipt.v1` receipt or a `choam.transfer-receipts.v1` envelope |
| `sources[].receiptCommand` | optional bounded argv fallback that prints the same receipt JSON directly; used only when `receiptFile` is absent |
| `history.command` | optional argv that prints the **past-transfers** log as JSON-lines (one record per line); enables the **History** tab in the **Manager** window (opened from the dropdown). Omit to leave it unconfigured. |
| `history.clearCommand` | optional argv that prunes the history log (e.g. drop FAILED entries); enables a **Clean** button in the History tab. Omit to leave history read-only |
| `manager.machines` | machines shown in each pane's switcher. Each entry: `label`, optional `local: true` (browse via the local filesystem), `ssh: "user@host"` (preferred remote target), optional ordered `sshFallbacks: ["user@alternate-host"]`, and `start` (initial directory) |
| `manager.transferCommand` | argv that performs a transfer, with `{mode}`/`{srcMachine}`/`{srcPath}`/`{dstMachine}`/`{dstPath}` placeholders the app fills in (substituted per-element, never into a shell string). Enables the **Files** tab's drag-to-transfer |
| `manager.moveEnabled` | when `true`, the drop dialog offers **Move** (copy then delete the source) next to **Copy**. Defaults to Copy-only |
| `manager.chickletsPath` | optional JSON file persisting the pinned **chicklet** shortcuts (machine + path) shown above both panes |
| `manager.logDir` | optional directory for per-operation logs (default `~/.config/server-monitor/transfer-logs`) |
| `manager.maxAttempts` | optional total tries (incl. the first) before a launched transfer gives up (default 5, min 1) |
| `manager.backoffBaseSeconds` | optional first-retry delay; doubles each attempt: 2, 4, 8, 16 (default 2) |

The command must print JSON shaped like
`{ "queue": [ { "id","source","dest","status","mode","bytesTransferred","bytesTotal","filesDone","filesTotal","rateBytesPerSec","currentFile" } ], "summary": { "running","pending","failed" } }`
— **raw byte counters**; the panel computes % and ETA itself. With no
`transfers.json`, the Transfers panel is inert.

A missing or stale heartbeat, unreadable queue source, or stale active snapshot is
shown inline and pulls the menu-bar tint off green. A fresh active snapshot is
itself the authoritative liveness signal because a scheduler heartbeat may remain
unchanged throughout one long transfer. An idle queue snapshot may be old without
being wrong; configure `healthFile` to distinguish that normal case from a dead
queue producer.

### Optional delivery receipts V1

For a producer that publishes the additive CHOAM receipt contract, configure one
of `receiptFile` or `receiptCommand` on the matching source. The consumer retains
only opaque transfer, attempt, and optional queue-entry IDs plus the lifecycle
state. It never renders routes, paths, hosts, accounts, proof material, hashes,
or failure details.

The app is intentionally **not** a destination-evidence verifier. It maps
`COMMAND_ACCEPTED`, `QUEUE_ADMITTED`, and `DEFERRED` to pending; `ACTIVE` and
the verification/commit states to in progress; and `FAILED`/`CANCELLED` to
attention. Even a receipt whose producer state is `COMPLETED` displays as
**destination evidence required**, never delivered. An unreadable, unsupported,
or malformed receipt source is shown as receipt unavailable/malformed; an
unverified `COMPLETED` receipt is likewise attention-required. Both pull the
menu-bar transfer status off green. This is fail-closed: it supplies no
delivery evidence and does not change the legacy queue snapshot behavior when no
receipt source is configured.

The Manager window's **History** tab reads `history.command`, which must print **one
JSON object per line**, each shaped like `{ "id","repositories":[…],"sourceMachine",
"targetMachine","startTime","endTime","status","filesTransferred","bytesTransferred","errors" }`.
Only `id`/`startTime`/`status` are required; the rest degrade gracefully. The
window is searchable, status-filterable (defaults to **Failed** for triage) and
newest-first, with click-to-drill detail. It also carries **Inventory** and
**Reclaim** tabs that activate once the tool exposes those as JSON (Reclaim is
read-only / dry-run only — the app never deletes).

With a `manager` block configured, the window's **Files** tab is a dual-pane browser.
Each pane lists a chosen machine's directory (locally, or via `ssh ls` for a remote).
When `sshFallbacks` are configured, unreachable SSH targets are tried in order.
Navigate by double-clicking folders or the up button. **Drag a row from one
pane onto a folder (or the path bar) of the other** to transfer it *into that exact
directory*; a dialog shows the source, the `from → into` route, and **Copy**, **Move**
(only when `moveEnabled`), and **Cancel**. **Chicklets** are pinned root shortcuts
shown identically above both panes: right-click a folder (or use the path-bar bookmark)
to make one, click it to send a pane straight there, persisted to `chickletsPath`.

Each launched transfer streams its combined output to a per-operation log under
`manager.logDir`; the **Logs** tab live-tails the selected one so you can watch the
low-level commands and inspect failures. A failed transfer **retries with exponential
backoff** (2, 4, 8, 16 seconds) up to `manager.maxAttempts` and then stops, so it can
never become a runaway loop, and you can **Retry Now**, **Stop**, or **Retry** a
finished one. An exit-zero Manager command means only that its configured process
exited zero; it is not delivery proof. The app only ever runs the argv you configure (plus a generic `ls`
against an ssh target you supply): no host names or tool specifics live in this repo.

## Protection config

Verify the machine's fail-closed invariants without mutating them. Each check is
a directly executed argv with a shared deadline; **exit 0 = OK, nonzero, timeout,
or invalid configuration = AT RISK**.

```bash
cp config/protection.example.json ~/.config/server-monitor/protection.json
$EDITOR ~/.config/server-monitor/protection.json
```

Schema (`config/protection.example.json`):

| Key | Meaning |
|-----|---------|
| `pollSeconds` | optional poll interval (minimum 10; use a slow cadence such as 300 for deep audits) |
| `timeoutSeconds` | deadline applied to each check (default 30) |
| `checks[].id` | stable identifier for the invariant |
| `checks[].label` | name shown in the panel |
| `checks[].check` | argv executed directly; exit 0 = OK, every other result = AT RISK |
| `checks[].note` | optional hint shown when the check is failing (e.g. "needs admin") |

The panel shows a single **Protection: OK / AT RISK** badge (distinct from the VPN
verdict) and lists failing invariants. With no `protection.json`, the panel is
inert. If the file exists but is invalid, empty, or still awaiting its first result,
the app fails closed and will not show the combined menu-bar state as green.
Failed checks include the bounded runner's first diagnostic line and the most
recent audit time, so a missing executable or timeout is distinguishable from a
failed invariant. Prefer a command name resolvable through `PATH` over an
installation-prefix-specific absolute path when a package manager owns the tool.

**Check depth matters.** `launchctl print …` only proves an agent is *loaded*. For
a watchdog loop, also assert it is *running* (has a pid) and its status output is
*fresh* — a loaded-but-dead loop is the silent failure mode. The simplest robust
approach is one **composite audit** command that returns nonzero if anything in the
stack is missing/stale (e.g. darkmesh's `darkmesh-audit`), plus a binding check
(`transfer-vpn-doctor --check`: exit `3` = stale). A failing check turns the
menu-bar dot **off green** via the existing combined tint — so "green requires every
keep-alive service running" needs no app code, just these checks.

For darkmesh schema 3, use its composite read-only `darkmesh-audit` check. The
audit also fails when the signed supervisor/children/jobs are stale, a persistent
recovery breaker gives up, or the fail-closed packet-filter state is invalid.

## Infrastructure agent config

The bundled LaunchAgent is registered through `SMAppService` and is the single
background-activity owner for infrastructure automation. Copy
`config/infrastructure-agent.example.json` to the untracked config directory, or
let the component installers merge the entries they own.

| Key | Meaning |
|-----|---------|
| `schema` | configuration contract version; currently `1` |
| `statusFile` | atomically replaced supervisor health report |
| `persistentChildren[]` | foreground helpers to supervise and restart; each has a unique `id`, direct `command`, optional restart delay, and optional `maxSilenceSeconds` output watchdog |
| `scheduledJobs[]` | non-overlapping one-shot work; each has a unique `id`, direct `command`, interval, deadline, and optional run-at-start flag |
| `watchNetworkChanges` | use the native network path monitor to wake children that declare `networkChangeSignal` |
| `watchPaths[]` | optional file-metadata fallback for network configuration files |

The agent validates the whole file before applying it, writes status schema 2 every
30 seconds, keeps distinct jobs concurrent while preventing a second instance of
the same job, and terminates its children/jobs during shutdown. A persistent
child with `maxSilenceSeconds` must write progress to stdout or stderr. When its
log remains unchanged past that deadline, the agent sends `SIGTERM`, escalates to
`SIGKILL` after five seconds, and applies the normal restart delay. Configuration
updates are atomic and preserve entries owned by other ecosystem components. An
explicit operator `SIGUSR2` request recycles persistent children without
interrupting scheduled work; polling code never sends it.

## Versions config

Surface the version and build of the app itself plus the tools it monitors, in a
compact **Versions** section at the bottom of the menu. The app's own version and
build come straight from its bundle and are always shown, so this file is only for
the external tools.

```bash
cp config/versions.example.json ~/.config/server-monitor/versions.json
$EDITOR ~/.config/server-monitor/versions.json
```

Schema (`config/versions.example.json`):

| Key | Meaning |
|-----|---------|
| `components[].label` | name shown in the list |
| `components[].command` | bounded argv executed directly; the first non-empty stdout line is the version |
| `components[].enabled` | optional; set `false` to skip a component |

The first non-empty line of stdout becomes the version string; a nonzero exit or
empty output shows as `unavailable` in red. Commands run **lazily**: the first time
you expand the Versions section and whenever you click **Refresh**, then cached.
They never run on a status poll, so a heavyweight probe (a JVM CLI, `brew`, an
`ssh` to another host) costs nothing until you actually look. As with the other
panels the app only runs the configured argv positionally (no interpolation, so
paths with spaces or metacharacters cannot inject) and reads stdout; no tool names
or host paths live in tracked source. With no `versions.json` only the app's own
version is shown.

Good version sources: a brew package (`brew list --versions <name> | awk '{print
$NF}'`), a checkout's revision (`git -C <path> describe --tags --always --dirty`),
or a tool's native `--version`.

## Why these live outside git

These files carry **per-machine paths and operational specifics** that are
intentionally kept out of the public repository. They are synced across your own
machines **out-of-band** (e.g. via your file-transfer tooling), **not** through
git. Treat them like `.env`: local, private, and never staged. The repo's
`.gitignore` already excludes `*.local.*` and `config/worker.json` as a backstop.
