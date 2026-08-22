# Trusted-machine context

Server Monitor's public repository contains portable source, neutral examples,
and the configuration contract. Operator names, private hosts, filesystem paths,
credentials, network topology, and integration history must remain outside Git.

## Private overlay

Keep durable, non-secret operator notes in ignored files such as
`docs/INTEGRATION.local.md`. Store runtime configuration under
`~/.config/server-monitor/` and keep the repository's `services.json` untracked.
Use the tracked examples as the schema reference.

Secrets should live in the platform credential store or a separately protected
directory such as `~/.config/secrets`, not in the notes overlay. Server Monitor
does not store secret values. It can copy that directory to other trusted
machines over SSH on the private overlay.

Copy `config/secrets-sync.example.json` to
`~/.config/server-monitor/secrets-sync.json` and list SSH targets there. Run
`sm secrets-sync` (or `--dry-run`) from this repository's CLI. The command
prints host success or failure only. Optional: add a uniquely named scheduled
job in `~/.config/server-monitor/infrastructure-agent.json` so the signed
infrastructure agent owns the cadence.

## Moving to another trusted machine

1. Clone the public repository and check out its canonical branch.
2. Transfer only the required ignored notes and runtime configuration over an
   authenticated, encrypted channel. Operator secrets use `sm secrets-sync`,
   not git.
3. Preserve restrictive permissions on private files.
4. Replace machine-specific paths and executable locations for the destination.
5. Validate JSON against the tracked examples, run the CLI tests, and start with
   read-only status checks before enabling controls.

Do not commit the copied overlay. Before pushing any branch, inspect ignored
files with `git status --ignored` and scan tracked changes for hostnames, private
addresses, personal paths, credentials, and operator-specific project names.
