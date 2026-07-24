#!/bin/bash
# Compatibility entry point. The canonical pipeline builds, signs, and notarizes
# one internally consistent artifact.
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build_release.sh" --notarize "$@"
