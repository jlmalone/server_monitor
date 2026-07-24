#!/bin/bash
# Compatibility entry point. Rebuilds before signing/notarizing so nested code is
# always sealed in the correct order.
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build_release.sh" --notarize "$@"
