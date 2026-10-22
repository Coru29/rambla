#!/bin/bash
# Runs the RamblaCore tests (Swift Testing).
# Usage: scripts/test.sh [--filter <regex>]
# With only the Command Line Tools, some toolchains build the tests but `swift test` runs none of them;
# in that case the built test bundle is loaded by scripts/test-runner.swift instead.
set -uo pipefail
cd "$(dirname "$0")/.."
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
DL=/Library/Developer/CommandLineTools/Library/Developer/usr/lib

OUT=$(swift test "$@" 2>&1)
STATUS=$?
if printf '%s\n' "$OUT" | grep -q "Test run with"; then
  printf '%s\n' "$OUT" | grep -E "✔|✘|Test run with|error:|recorded an issue" | tail -n 400
  exit $STATUS
fi
# Nothing ran because the build failed: show the compiler errors instead of hiding them behind the fallback.
if printf '%s\n' "$OUT" | grep -q ": error:"; then
  printf '%s\n' "$OUT" | grep -E ": error:|: warning:" | head -n 80 >&2
  exit 1
fi

# Fallback: build the test product and load it with the custom runner.
swift build --product RamblaPackageTests >/dev/null 2>&1 || { swift build --product RamblaPackageTests; exit 1; }
BUNDLE=$(find .build -type f -path "*RamblaPackageTests.xctest/Contents/MacOS/RamblaPackageTests" -not -path "*.dSYM*" -print0 2>/dev/null \
  | xargs -0 ls -t 2>/dev/null | head -n 1)
if [ -z "$BUNDLE" ]; then
  echo "No se encontró el bundle de tests. Contenido de .build:" >&2
  find .build -maxdepth 5 -name "*PackageTests*" >&2
  exit 1
fi
RUNNER=.build/test-runner
if [ ! -x "$RUNNER" ] || [ scripts/test-runner.swift -nt "$RUNNER" ]; then
  swiftc -O scripts/test-runner.swift -F "$FW" -framework Testing \
    -Xlinker -rpath -Xlinker "$FW" -Xlinker -rpath -Xlinker "$DL" -o "$RUNNER" || exit 1
fi
RAMBLA_TEST_BUNDLE="$PWD/$BUNDLE" "$RUNNER" "$@"
