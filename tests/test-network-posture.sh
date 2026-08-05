#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d -t server-monitor-network-posture)"
trap 'rm -rf "$TMP"' EXIT

xcrun swiftc \
  "$ROOT/app/ServerMonitor/ServerMonitor/Models/NetworkPosture.swift" \
  "$ROOT/tests/NetworkPostureTests.swift" \
  -o "$TMP/test-network-posture"
"$TMP/test-network-posture"
