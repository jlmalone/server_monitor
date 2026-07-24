#!/bin/bash
# Compatibility entry point. Builds a Developer ID-signed app and DMG.
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build_release.sh" "$@"
