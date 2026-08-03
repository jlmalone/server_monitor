# Roadmap

Server Monitor's core is the `sm` CLI + the **Services** panel (launchd-managed
dev servers). Several **optional** menu-bar panels extend it; each reads its
machine-specific settings from untracked local config (see [CONFIG.md](./CONFIG.md))
so the public app stays generic — the app only ever runs configured commands and
reads their output/exit codes; it owns no policy and stores no host or tool names.

## VPN panel (read-only) — shipped

A compact status row that mirrors a local network-protection status file
(`/tmp/darkmesh-status.json`) written by a separate per-machine helper: a verdict
plus VPN / raw-IP / open-internet / DNS / Tailscale / optional remote-access probes,
VPN-bound public-client gate state, temporary DNS recovery state, per-fault circuit
breakers, and a last-auto-disconnect footnote. An active VPN-client gate pulls the
combined tint off green even when broader network health is good. It does not mean
private LAN or Tailscale transfers are blocked. The app only *reads* the file.

The menu extra is owned by an AppKit `NSStatusItem` and `NSPopover`, with the
panel content still rendered in SwiftUI. This avoids the system
`MenuBarExtra(.window)` failure mode where the icon remains visible and accepts
clicks but no window is presented. The SwiftUI panel tree is created on click
and released when the popover closes, keeping off-screen monitor updates from
performing needless layout work. Manager and Settings release their hosted views
when their windows close for the same reason.

Follow-ups (kept generic):
- Decode hardening is shipped: schema mismatch, parse failure, missing file, or a
  snapshot older than 60 seconds clears the prior value and fails closed.
- **Cannibalise + retire the darkmesh SwiftBar plugin** (lockstep with
  `darkmesh-vpn-guard/ROADMAP.md`): port the plugin's actions into this panel and
  surface the remaining status details. Schema 3 probe/breaker/override fields are
  decoded and rendered, including signed-supervisor health. Policy actuation stays
  outside the read-only polling UI.

## Protection panel (read-only integrity) — shipped

A single **OK / AT RISK** badge (distinct from the VPN verdict) that verifies the
machine's fail-closed invariants with bounded, directly executed check argv. It
never repairs or schedules work. Invalid/empty config, timeout, nonzero exit, or
an unfinished first audit all pull the menu-bar tint off green.

Depth matters: a "loaded?" check only proves an agent exists — for a keep-alive loop
the check must assert it is **running and fresh**, not merely loaded (a loaded-but-dead
loop is the silent failure). Prefer one composite audit command (nonzero if anything
is missing/stale) over many shallow checks.

Failed checks preserve the bounded runner's first diagnostic line and the
last-audit time. Configuration drift, such as a moved executable, is visible
instead of presenting an unexplained yellow menu-bar icon.

Follow-up:
- **Packet-filter (kill-switch) integrity** — verify the firewall is actually
  enforcing, not just that a guard agent is loaded. Blocked on the guard project
  publishing firewall state to its status file (or a root-readable surface) so the
  unprivileged app can poll it without a password; see
  `darkmesh-vpn-guard/docs/server-monitor-darkmesh-brief.md`. Config-only here once
  that lands.

## Transfers panel (live queue) — shipped

Active file transfers across one or more machines (per item: %, rate, ETA). Local
sources prefer an atomically replaced status JSON, avoiding a JVM/CLI spawn on
every poll; bounded direct-command fallback remains for remote sources. This
compact panel is deliberately read-only. Raw byte counters in; the panel derives
%/ETA.

Optional per-source heartbeat files detect a dead idle queue producer without
misclassifying an old-but-valid idle snapshot. A running or pending queue instead
uses its bounded `generatedAt` age as direct liveness proof, so a long supervised
transfer is not marked stale merely because its scheduler invocation is still in
progress. Either failure is rendered inline and pulls the combined tint off green.

## Signed infrastructure agent — shipped

One `SMAppService` LaunchAgent bundled and signed with Server Monitor owns the
infrastructure stack. It supervises foreground helpers, runs distinct scheduled
jobs concurrently without overlapping an individual job, handles native network
path change wakeups, publishes a fresh status contract, reloads atomic config,
and terminates its work during shutdown. Component installers merge only the IDs
they own, so the one registration replaces per-script background items without
coupling their release cycles.

## Active + Transfer History + Transfer + Logs + Inventory + Reclaim window — History/Transfer/Logs shipped

A secondary **window** (opened from the dropdown) for the file-transfer tool's live
queue and records:

- **Active** *(roadmap)*: the full live view of the transfer queue inside the window,
  the triage counterpart to the compact dropdown Transfers panel. Lists every item
  that is running, pending, stalled, failed, or paused (read from the queue CLI's
  `--json`), each row with: **Resume** a failed / stalled / paused item (configured
  reprocess/reset argv), **Stop** a running or pending one (cancel argv), and
  **Delete**, which only enables after a Stop and asks for confirmation, removing the
  queue entry, not the transferred files (the menu bar still never deletes data). All
  actions run configured argv from untracked `transfers.json`, the same generic
  pattern as every other panel.
- **History** *(shipped)*: browse past sync operations from the tool's history
  log (timestamp, repositories, route, status, files, bytes, errors), newest first,
  with search + status filter (defaults to **Failed** for triage) and click-to-drill
  detail (duration, average rate, raw fields). Reads a JSON-lines history log via the
  untracked `history` key in `transfers.json` — same generic pattern as the other
  panels. Opened from the "Transfer History…" link under the Transfers panel; useful
  immediately for spotting failure spikes.
- **Transfer** *(shipped)*: drag a title onto a machine chip to copy or move it
  there. A confirm dialog shows the title, the `src → dst` route, and how much is
  moving (file count + size from the dragged row, or an exact files/folders breakdown
  when `describeCommand` is set), with **Copy** / **Move** / **Cancel** (Move only when
  a `moveCommand` is configured). Driven by the untracked `transfer` block — the app
  only runs the configured argv with `{title}`/`{src}`/`{dst}` filled in.
- **Logs** *(shipped)*: every launched transfer streams its combined output to a
  per-operation log; this tab live-tails the selected one so you can watch the
  low-level work in real time and inspect failures. Failures retry with **bounded
  exponential backoff** (2/4/8/16 … up to `maxAttempts`, then stop — never a runaway)
  with **Retry Now** / **Stop** / **Retry** controls. The History tab gains a **Clean**
  button (when `history.clearCommand` is set) to prune the log.
- **Inventory** *(when the tool exposes it as JSON)*: for each title, which machines
  hold it and whether a verified copy exists elsewhere.
- **Reclaim** *(when the tool exposes it as JSON)*: what's safely reclaimable locally
  and how much space — **read-only / dry-run only in the app**. Destructive reclaim
  stays a deliberate CLI action with live re-verification; the menu bar never deletes.

Window UX follow-ups:
- **Single-instance + foreground**: opening the Manager when it is already open
  raises and focuses the existing window instead of spawning a second, and brings it
  to the front on every open (exactly one Manager window, frontmost when invoked).
- **Finder-style multi-select**: shift/cmd-click to select multiple files and folders
  in a pane and drag the whole selection onto a destination chip in a single drop
  (today each drag carries one item).

Consumer requirements for the transfer tool (stable versioned JSON schemas, `--json`
on every queryable command, per-item "why-not-reclaimable" reasons, and a 0/nonzero
exit-code contract) are tracked in that tool's own roadmap.

## Worker panel (start/stop) — shipped

Start/stop a machine-specific background worker node and show its throughput. Which
directory / script / pid / log it drives comes entirely from
`~/.config/server-monitor/worker.json` (untracked). With no config present, the
panel is inert.

## Longer-term

- **Control API twin**: expose a local `/control/{state,schema,action}` surface so an
  agent (or the user) can query and drive the panels programmatically instead of
  screen-scraping the menu bar. A dedicated phase, not bundled with panel work.

## Notes

- Machine-specific operational detail (host roster, vendor/tool specifics) is kept in
  **untracked local notes/config**, not in this repo.
- Binaries are distributed via **GitHub Releases**, never committed to the tree.
- Branch: `master`.
