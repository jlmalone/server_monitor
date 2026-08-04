#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d -t server-monitor-resource-guard)"
trap 'rm -rf "$TMP"' EXIT

xcrun swiftc \
  "$ROOT/app/ServerMonitor/ServerMonitor/Support/ResourceGuardPolicy.swift" \
  "$ROOT/tests/ResourceGuardPolicyTests.swift" \
  -o "$TMP/test-resource-guard-policy"
"$TMP/test-resource-guard-policy"

xcrun swiftc \
  "$ROOT/app/ServerMonitor/ServerMonitor/Support/ResourceGuardPolicy.swift" \
  "$ROOT/app/ServerMonitor/ServerMonitor/Support/AppResourceGuard.swift" \
  "$ROOT/tests/AppResourcePriorityTests.swift" \
  -o "$TMP/test-app-resource-priority"
"$TMP/test-app-resource-priority"
