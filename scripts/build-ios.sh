#!/bin/sh
# Build the unsigned Touchline 23 IPA for iPhone and iPad.
#
#   ./scripts/build-ios.sh --nsp-dir "/path/to/fifa23"
#
# Options: see ./scripts/build-ios.sh --help (scripts/touchline_build.py).
# The IPA is written to Release/Touchline23.ipa unless --out names another
# path. It carries no game data: the game files are read from the folder the
# App is given on the device.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PYTHON=${PYTHON:-python3}
exec "$PYTHON" "$ROOT/scripts/touchline_build.py" --target ios "$@"
