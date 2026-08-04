#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d -t server-monitor-registration-stamp)"
trap 'rm -rf "$TMP"' EXIT

xcrun swiftc \
  "$ROOT/app/ServerMonitor/ServerMonitor/BackgroundServiceManager.swift" \
  "$ROOT/tests/BackgroundRegistrationStampTests.swift" \
  -o "$TMP/test-background-registration-stamp"
"$TMP/test-background-registration-stamp"
