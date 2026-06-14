# Distribution Guide

To release "Server Monitor" as a respectable macOS app, you have two main paths. 

> [!IMPORTANT]
> **Recommendation**: Choose **Path A (Direct Distribution)**. 
> The current architecture (cli wrapping `launchctl`) is strictly forbidden on the Mac App Store due to App Sandbox rules.

## Path A: Website / GitHub Release (Recommended)
This is how apps like VS Code, Docker, and Chrome are distributed.
1. **Build**: Run `./scripts/build_installer.sh`. This creates `ServerMonitor.dmg`.
2. **Signing (Required for "respectable" apps)**:
   - You need an Apple Developer Account ($99/year).
   - Sign the App: `codesign --sign "Developer ID Application: Your Name" ...`
   - Sign the DMG: `codesign --sign "Developer ID Application: Your Name" ...`
3. **Notarization (Required to avoid "Malware" warnings)**:
   - Submit the DMG to Apple: `xcrun notarytool submit ServerMonitor.dmg ...`
   - Staple the ticket: `xcrun stapler staple ServerMonitor.dmg`
   - *Without this, users will see "Cannot be opened because Apple cannot check it for malicious software".*

## Path B: Mac App Store
This requires a major rewrite.
1. **Architecture Change**: You cannot use `launchctl` CLI commands. You must use the `SMAppService` API entirely.
2. **Sandbox**: The app must be Sandboxed. It cannot touch files outside its container unless explicitly granted by the user (Open Panel).
3. **Review**: Apple reviews every update.
4. **Benefit**: Easy installation for users, visibility.

## What I've Built for You
I have set up the **Path A** pipeline.
- The `build_installer.sh` script creates a standard `.dmg` file.
- Users open the DMG and drag `Server Monitor.app` to their Applications folder.
- The App includes the `sm` CLI tool inside itself (`Contents/Resources/cli/sm`).
