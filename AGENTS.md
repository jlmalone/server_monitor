# AGENTS.md

Read the machine-level `AGENTS.md` first. This file is the repository authority.

Server Monitor manages user-defined macOS development services. `services.json` is the source of
truth; generated launchd plists must never be edited by hand. The app and CLI must agree on the
configuration schema and service lifecycle.

- Keep machine-specific paths, hosts, credentials, and service configuration untracked. Use the
  example configuration for tracked documentation. Follow
  [docs/TRUSTED_MACHINE_CONTEXT.md](docs/TRUSTED_MACHINE_CONTEXT.md) when another trusted machine
  needs the private overlay.
- Do not create new per-script LaunchAgents for infrastructure helpers; use the configured shared
  infrastructure agent model.
- Run focused CLI tests and the applicable Xcode build or tests after code changes. See
  [AI.md](AI.md) for component and lifecycle detail.

`CLAUDE.md` is a compatibility loader.
