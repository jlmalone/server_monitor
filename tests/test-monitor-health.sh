#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d -t server-monitor-health)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

let missing = ProcessRunner.run(["/definitely/missing/server-monitor-check"])
require(missing.status == 127, "missing executable must return status 127")
require(missing.failureSummary()?.contains("executable not found") == true,
        "missing executable detail must survive for the UI")

let now = Date(timeIntervalSince1970: 1_800_000_000)
let oldTimestamp = ISO8601DateFormatter().string(from: now.addingTimeInterval(-301))
require(SnapshotFreshness.staleReason(
    timestamp: oldTimestamp,
    filePath: nil,
    maxAge: 300,
    label: "queue",
    now: now
)?.contains("stale") == true, "old queue timestamp must be stale")

let freshTimestamp = ISO8601DateFormatter().string(from: now.addingTimeInterval(-20))
require(SnapshotFreshness.staleReason(
    timestamp: freshTimestamp,
    filePath: nil,
    maxAge: 30,
    label: "queue",
    now: now
) == nil, "fresh queue timestamp must pass")

require(SnapshotFreshness.staleReason(
    timestamp: "not-a-date",
    filePath: nil,
    maxAge: 30,
    label: "queue",
    now: now
) == "queue timestamp unavailable", "malformed timestamp must be explicit")

print("PASS: monitoring diagnostics and freshness contracts")
SWIFT

xcrun swiftc \
  "$ROOT/app/ServerMonitor/ServerMonitor/Support/ProcessRunner.swift" \
  "$TMP/main.swift" \
  -o "$TMP/test-monitor-health"
"$TMP/test-monitor-health"
