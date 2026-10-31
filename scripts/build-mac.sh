#!/bin/sh
# Build Touchline 23 for Apple silicon Macs.
#
#   ./scripts/build-mac.sh --nsp-dir "/path/to/fifa23"
#
# Options: see ./scripts/build-mac.sh --help (scripts/touchline_build.py).
# The App is written to Release/Touchline23.app unless --out names another path.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PYTHON=${PYTHON:-python3}
exec "$PYTHON" "$ROOT/scripts/touchline_build.py" --target mac "$@"
