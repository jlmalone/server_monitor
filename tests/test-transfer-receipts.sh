#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d -t server-monitor-transfer-receipts)"
trap 'rm -rf "$TMP"' EXIT

xcrun swiftc \
  "$ROOT/app/ServerMonitor/ServerMonitor/Models/TransferReceipt.swift" \
  "$ROOT/tests/TransferReceiptConsumerTests.swift" \
  -o "$TMP/test-transfer-receipts"
"$TMP/test-transfer-receipts"
