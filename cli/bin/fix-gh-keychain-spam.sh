#!/usr/bin/env bash
# Stop gh/git Keychain prompt storms: widen ACL once, or rely on GH_TOKEN only.
set -euo pipefail

SERVICE="gh:github.com"
PARTITIONS="apple-tool:,apple:,com.apple.security:"

pkill -9 -f "security find-generic-password.*${SERVICE}" 2>/dev/null || true

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "macOS only."
  exit 0
fi

if security find-generic-password -s "$SERVICE" >/dev/null 2>&1; then
  echo "Updating Keychain ACL for ${SERVICE} (enter login password if prompted once)..."
  security set-generic-password-partition-list -s "$SERVICE" -S "$PARTITIONS" 2>/dev/null || true
else
  echo "No Keychain item for ${SERVICE}; gh will use GH_TOKEN from ~/.config/secrets/github_pat."
fi

echo "Ensure shells load: . ${HOME}/.config/secrets/github_env.sh"
