# Distribution Guide

Server Monitor is distributed directly as a Developer ID-signed, hardened, and
notarized macOS app. The app bundle contains both the menu-bar executable and the
single infrastructure LaunchAgent payload registered through `SMAppService`.

## Prerequisites

- A valid `Developer ID Application` certificate in the login keychain.
- The matching 10-character Apple Developer Team ID.
- For notarization, either a `notarytool` keychain profile or Apple ID app-specific
  password credentials. Copy `scripts/.env.example` to an ignored `.env` file if
  environment variables are inconvenient.

## Canonical release

```bash
./scripts/build_release.sh --notarize
```

The pipeline:

1. Builds a universal (`arm64` + `x86_64`) Release configuration without implicit
   Xcode signing.
2. Verifies the app, both executable architectures, embedded executable,
   LaunchAgent plist, icon metadata, version, and bundle ID.
3. Signs `InfrastructureAgent` first, then seals `ServerMonitor.app` with hardened
   runtime and a secure timestamp—no `codesign --deep` shortcut.
4. Verifies both signatures carry the expected Team ID.
5. Creates and signs `dist/ServerMonitor-<version>.dmg`.
6. Submits the DMG to Apple, staples the ticket, and performs Gatekeeper validation.

Run without `--notarize` for a local Developer ID-signed QA artifact. It is not a
publishable release until notarization succeeds.

If the local Xcode build service is unavailable, dispatch the manual
`Unsigned macOS release` workflow. Download and expand its
`ServerMonitor.app.zip` artifact, then feed the app into the same local signing
pipeline:

```bash
./scripts/build_release.sh --unsigned-app /absolute/path/ServerMonitor.app --notarize
```

The hosted job has read-only repository permissions and receives no signing or
notarization credentials. The local pipeline still performs architecture,
bundle, nested-payload, signature, team, notarization, staple, and Gatekeeper
checks.

The older release-script names remain thin compatibility wrappers around this one
pipeline; they no longer contain independent versions, bundle IDs, or signing logic.

## Install and background registration

Copy the finished app to `/Applications`, launch it once, and approve its background
activity in System Settings if macOS requests consent. The app registers:

- itself as a login item, for the menu bar;
- `vision.salient.InfrastructureAgent` as the one infrastructure background item.

Machine-specific commands are not embedded in the signed bundle. They live in the
untracked `~/.config/server-monitor/infrastructure-agent.json` and component
installers merge only the entries they own.

## Mac App Store

The current service-management and arbitrary local-command features are designed
for direct distribution. A Mac App Store build would need a separate sandboxed
product design and is not produced by this pipeline.
