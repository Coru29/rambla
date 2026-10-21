#!/bin/bash
# Builds, replaces /Applications/Rambla.app and relaunches it. Extra arguments are passed to the app.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build.sh
if pgrep -x Rambla >/dev/null; then
  osascript -e 'tell application id "io.github.coru29.Rambla" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do pgrep -x Rambla >/dev/null || break; sleep 0.1; done
  pkill -x Rambla 2>/dev/null || true
fi
rm -rf /Applications/Rambla.app
ditto build/Rambla.app /Applications/Rambla.app
if [ $# -gt 0 ]; then open -a /Applications/Rambla.app --args "$@"; else open -a /Applications/Rambla.app; fi
echo "Installed /Applications/Rambla.app"
