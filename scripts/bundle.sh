#!/bin/zsh
# Builds i-con in release mode and puts together a signed app bundle at the given path.
# Usage: scripts/bundle.sh path/to/i-con.app
set -euo pipefail

cd "$(dirname "$0")/.."

APP="$1"
IDENTITY="i-con Local"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/ICon"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/i-con"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# A stable certificate keeps the Accessibility and Screen Recording permissions across rebuilds
# (and across updates on a friend's Mac). Without one, the app is signed ad hoc and macOS asks
# again after every build.
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "note: no \"$IDENTITY\" certificate found; signing ad hoc (permissions reset on every rebuild)"
    codesign --force --sign - "$APP"
fi
