#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d -t infrastructure-agent-watchdog)"
AGENT_PID=""
trap '[[ -n "$AGENT_PID" ]] && kill -TERM "$AGENT_PID" 2>/dev/null || true; rm -rf "$TMP"' EXIT
HOME_DIR="$TMP/home"
mkdir -p "$HOME_DIR/.config/server-monitor"

cat > "$TMP/stuck-child" <<'EOF'
#!/bin/bash
trap '' TERM
printf 'start %s\n' "$$"
printf '%s\n' "$$" >> "${WATCHDOG_STARTS:?}"
kill -STOP $$
sleep 300
EOF
chmod +x "$TMP/stuck-child"

cat > "$HOME_DIR/.config/server-monitor/infrastructure-agent.json" <<EOF
{
  "schema": 1,
  "statusFile": "$HOME_DIR/status.json",
  "persistentChildren": [{
    "id": "stuck",
    "command": ["$TMP/stuck-child"],
    "restartDelaySeconds": 1,
    "maxSilenceSeconds": 10
  }],
  "scheduledJobs": []
}
EOF

xcrun swiftc -framework Network \
  "$ROOT/app/ServerMonitor/InfrastructureAgent/main.swift" \
  "$ROOT/app/ServerMonitor/ServerMonitor/Support/ProcessRunner.swift" \
  -o "$TMP/InfrastructureAgent"

started="$(date +%s)"
CFFIXED_USER_HOME="$HOME_DIR" HOME="$HOME_DIR" WATCHDOG_STARTS="$TMP/starts" \
  "$TMP/InfrastructureAgent" &
AGENT_PID=$!

agent_nice=""
for _ in {1..20}; do
  agent_nice="$(ps -o ni= -p "$AGENT_PID" | tr -d ' ')"
  [[ "$agent_nice" == "19" ]] && break
  sleep 0.1
done
[[ "$agent_nice" == "19" ]] || {
  echo "FAIL: infrastructure agent priority is $agent_nice, expected 19" >&2
  exit 1
}

for _ in {1..350}; do
  [[ -f "$TMP/starts" ]] && [[ "$(wc -l < "$TMP/starts" | tr -d ' ')" -ge 2 ]] && break
  sleep 0.1
done
elapsed=$(( $(date +%s) - started ))
starts="$(wc -l < "$TMP/starts" 2>/dev/null | tr -d ' ' || echo 0)"
[[ "$starts" -ge 2 ]] || { echo "FAIL: stopped child was not restarted" >&2; exit 1; }
[[ "$elapsed" -lt 30 ]] || { echo "FAIL: recovery took ${elapsed}s" >&2; exit 1; }

log="$HOME_DIR/Library/Logs/ServerMonitor/InfrastructureAgent/agent.log"
grep -q 'silent for .*; command=' "$log" || { echo "FAIL: missing silence evidence" >&2; exit 1; }
grep -q 'ignored SIGTERM for 5s; sending SIGKILL' "$log" || { echo "FAIL: missing SIGKILL escalation" >&2; exit 1; }
python3 - "$HOME_DIR/status.json" <<'PY'
import json, sys
d=json.load(open(sys.argv[1]))
assert d["schema"] == 2
assert d["children"][0]["responsive"] is True
PY

kill -TERM "$AGENT_PID"
wait "$AGENT_PID"
AGENT_PID=""
echo "PASS: low-priority agent force-kills and restarts an unresponsive child"
