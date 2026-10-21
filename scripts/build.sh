#!/bin/bash
# Builds build/Rambla.app (release, arm64) and signs it.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(tr -d '[:space:]' < VERSION)
BUILD=$(date +%Y%m%d%H%M)
swift build -c release --product Rambla
BIN="$(swift build -c release --show-bin-path)/Rambla"
APP=build/Rambla.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Rambla"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Packaging/Info.plist > "$APP/Contents/Info.plist"
cp Packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Packaging/MenuBarIcon.png Packaging/MenuBarIcon@2x.png "$APP/Contents/Resources/"
scripts/sign.sh "$APP"
echo "$APP ($VERSION, build $BUILD)"
