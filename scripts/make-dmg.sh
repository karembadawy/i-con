#!/bin/zsh
# Builds a disk image for sharing i-con: dist/i-con-<version>.dmg
# It holds the app, a shortcut to Applications to drag it onto, and install instructions.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
DMG="dist/i-con-$VERSION.dmg"
WORK="$(mktemp -d)"
STAGING="$WORK/i-con"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$STAGING" dist
scripts/bundle.sh "$STAGING/i-con.app"
ln -s /Applications "$STAGING/Applications"
cp Resources/dmg-readme.txt "$STAGING/Read Me First.txt"

rm -f "$DMG"
diskutil image create from --format UDZO --volumeName "i-con $VERSION" "$STAGING" "$DMG" >/dev/null
echo "Created $DMG ($(du -h "$DMG" | cut -f1))"
