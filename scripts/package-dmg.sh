#!/bin/bash
# Compatibility entry point. The canonical pipeline signs before packaging.
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build_release.sh" "$@"
