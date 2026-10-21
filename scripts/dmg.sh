#!/bin/bash
# Builds the app and packages it as build/Rambla-<version>.dmg (app + Applications alias).
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build.sh
VERSION=$(tr -d '[:space:]' < VERSION)
STAGE=$(mktemp -d)
cp -R build/Rambla.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
# Stable name so https://github.com/Coru29/rambla/releases/latest/download/Rambla.dmg always works.
DMG="build/Rambla.dmg"
rm -f "$DMG"
hdiutil create -volname "Rambla" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
echo "$DMG"
