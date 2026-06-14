# Roadmap

Server Monitor's core is the `sm` CLI + the **Services** panel (launchd-managed
dev servers). Two **optional** menu-bar panels extend it; both read their
machine-specific settings from untracked local config (see [CONFIG.md](./CONFIG.md))
so the public app stays generic.

## VPN panel (read-only)

A compact status row that mirrors a local network-protection status file
(`/tmp/darkmesh-status.json`) written by a separate per-machine helper: a verdict
(GO / DEGRADED / NO-GO / IDLE) plus VPN / Internet / DNS / Tailscale probes and a
last-auto-disconnect footnote. The app only *reads* the file — it makes no network
policy decisions.

Possible follow-ups (kept generic):
- Inline VPN connect/disconnect + "probe now" controls, shelling out to a
  user-provided control binary whose path comes from local config.
- A "protection integrity" badge that flags when an expected guard agent isn't
  loaded, with a one-click re-arm.

## Worker panel (start/stop)

Start/stop a machine-specific background worker node and show its throughput.
Which directory / script / pid / log it drives comes entirely from
`~/.config/server-monitor/worker.json` (untracked). With no config present, the
panel is inert.

## Notes

- Machine-specific operational detail (host roster, vendor/tool specifics) is kept
  in **untracked local notes**, not in this repo.
- Binaries are distributed via **GitHub Releases**, never committed to the tree.
- Branch: `master`.
