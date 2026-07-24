#!/bin/bash
# Compatibility entry point. The underscore-named script is canonical.
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build_release.sh" --notarize "$@"
