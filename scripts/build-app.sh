#!/bin/bash
# Builds build/Paneful.app from the SwiftPM package and signs it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Paneful
BIN="$(swift build -c release --show-bin-path)/Paneful"
APP=build/Paneful.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Paneful"
cp Resources/Info.plist "$APP/Contents/Info.plist"

IDENTITY="Paneful Dev"
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "warning: '$IDENTITY' certificate not found; ad-hoc signing. Accessibility permission will reset on every rebuild. Run scripts/make-signing-cert.sh once." >&2
  codesign --force --sign - "$APP"
fi
echo "Built $APP"
