#!/bin/bash
# Builds .build/TestHost.app (bundle id io.github.coru29.TestHost) for scripts/e2e.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=.build/TestHost.app
if [ ! -x "$APP/Contents/MacOS/TestHost" ] || [ scripts/testhost.swift -nt "$APP/Contents/MacOS/TestHost" ]; then
  mkdir -p "$APP/Contents/MacOS"
  swiftc -O scripts/testhost.swift -o "$APP/Contents/MacOS/TestHost" 2>/dev/null
  cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TestHost</string><key>CFBundleIdentifier</key><string>io.github.coru29.TestHost</string>
<key>CFBundleName</key><string>TestHost</string><key>CFBundlePackageType</key><string>APPL</string><key>NSPrincipalClass</key><string>NSApplication</string></dict></plist>
PLIST
  codesign --force --sign - "$APP" >/dev/null 2>&1
fi
echo "$APP"
