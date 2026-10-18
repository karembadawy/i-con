#!/bin/zsh
# Builds i-con, installs it to /Applications and launches it.
# It has to run from /Applications: macOS matches the menu bar allow-list against the copy
# LaunchServices knows for the bundle ID.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="/Applications/i-con.app"

# Compile first so the running copy keeps the menu bar tidy until the new one is ready.
swift build -c release
pkill -x i-con 2>/dev/null && sleep 0.5 || true

scripts/bundle.sh "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
open "$APP"
echo "Installed and launched $APP"
