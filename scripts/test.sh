#!/bin/bash
# Usage: scripts/test.sh [--filter <regex>]
set -euo pipefail
cd "$(dirname "$0")/.."
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
DL=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
# Only the core library and its tests: the app target is not needed to run them.
swift build --product RamblaPackageTests >/dev/null 2>&1 || { swift build --product RamblaPackageTests; exit 1; }
BIN=$(swift build --show-bin-path)
RUNNER=.build/test-runner
if [ ! -x "$RUNNER" ] || [ scripts/test-runner.swift -nt "$RUNNER" ]; then
  swiftc -O scripts/test-runner.swift -F "$FW" -framework Testing \
    -Xlinker -rpath -Xlinker "$FW" -Xlinker -rpath -Xlinker "$DL" -o "$RUNNER"
fi
RAMBLA_TEST_BUNDLE="$BIN/RamblaPackageTests.xctest/Contents/MacOS/RamblaPackageTests" "$RUNNER" "$@"
