#!/bin/bash
# Builds Paneful, replaces /Applications/Paneful.app and relaunches it.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh
pkill -x Paneful || true
rm -rf /Applications/Paneful.app
cp -R build/Paneful.app /Applications/
open /Applications/Paneful.app
