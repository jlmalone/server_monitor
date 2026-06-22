# Roadmap

Server Monitor's core is the `sm` CLI + the **Services** panel (launchd-managed
dev servers). Several **optional** menu-bar panels extend it; each reads its
machine-specific settings from untracked local config (see [CONFIG.md](./CONFIG.md))
so the public app stays generic — the app only ever runs configured commands and
reads their output/exit codes; it owns no policy and stores no host or tool names.

## VPN panel (read-only) — shipped

A compact status row that mirrors a local network-protection status file
(`/tmp/darkmesh-status.json`) written by a separate per-machine helper: a verdict
(GO / DEGRADED / NO-GO / IDLE) plus VPN / Internet / DNS / Tailscale probes and a
last-auto-disconnect footnote. The app only *reads* the file.

Follow-ups (kept generic):
- **Decode hardening** *(next)*: render "—/unknown" instead of a raw decode error
  when a status key is missing or renamed, so a schema change in the helper can
  never blank or crash the panel. (A key rename already caused one raw-error
  incident.)
- Inline VPN connect/disconnect + "probe now" controls, shelling out to a
  user-provided control binary whose path comes from local config.
- **Cannibalise + retire the darkmesh SwiftBar plugin** (lockstep with
  `darkmesh-vpn-guard/ROADMAP.md`): port the plugin's actions into this panel and
  surface the status-schema-2 fields (already decoded in `DarkmeshStatus.swift`).
  Each action just shells a documented helper. Once at parity, the plugin is
  deleted there.

## Protection panel (integrity + Repair) — shipped

A single **OK / AT RISK** badge (distinct from the VPN verdict) that continuously
verifies the machine's fail-closed invariants and offers one-click **Repair**. Each
invariant is a check command (exit 0 = OK) plus an optional repair command, defined
in untracked `~/.config/server-monitor/protection.json`. An at-risk state also pulls
the menu-bar tint off green.

Depth matters: a "loaded?" check only proves an agent exists — for a keep-alive loop
the check must assert it is **running and fresh**, not merely loaded (a loaded-but-dead
loop is the silent failure). Prefer one composite audit command (nonzero if anything
is missing/stale) over many shallow checks.

Follow-up:
- **Packet-filter (kill-switch) integrity** — verify the firewall is actually
  enforcing, not just that a guard agent is loaded. Blocked on the guard project
  publishing firewall state to its status file (or a root-readable surface) so the
  unprivileged app can poll it without a password; see
  `darkmesh-vpn-guard/docs/server-monitor-darkmesh-brief.md`. Config-only here once
  that lands.

## Transfers panel (live queue) — shipped

Active file transfers across one or more machines (per item: %, rate, ETA), read
from a queue CLI's `--json` output named in untracked
`~/.config/server-monitor/transfers.json`. Failed rows offer a one-click **Resume**
when a reprocess command is configured. Raw byte counters in; the panel derives
%/ETA.

## Transfer History + Transfer + Logs + Inventory + Reclaim window — History/Transfer/Logs shipped

A secondary **window** (opened from the dropdown) for the file-transfer tool's
records — distinct from the live queue:

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
