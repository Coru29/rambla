#!/bin/bash
# Live end-to-end checks on the real app. Only the windows of a throwaway test app (TestHost) are
# managed, so nothing else on screen moves. Requires the app installed with the Accessibility permission.
# Usage: scripts/e2e.sh [--no-install]
set -euo pipefail
cd "$(dirname "$0")/.."
APP_NAME=Rambla
CHECK=.build/e2e-check
[ -x "$CHECK" ] && [ "$CHECK" -nt scripts/e2e-check.swift ] || swiftc -O scripts/e2e-check.swift -o "$CHECK"
HOST=$(scripts/build-testhost.sh)
CLI=/Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME
HOST_ID=io.github.coru29.TestHost

$CHECK host quit >/dev/null || true
if [ "${1:-}" != "--no-install" ]; then
  scripts/install.sh --only-bundle $HOST_ID >/dev/null
else
  pkill -x $APP_NAME 2>/dev/null || true
  open -a /Applications/$APP_NAME.app --args --only-bundle $HOST_ID
fi
open -n "$HOST" --args 4

$CHECK wait-columns 4
$CHECK settle
$CHECK check-tiles
$CHECK check-parked

# A new window opens right after the focused column.
$CLI focus-2; $CHECK settle
$CHECK check-focused-index 1
$CHECK host add
$CHECK wait-columns 5
$CHECK settle
$CHECK check-focused-index 2

# Focusing the ends scrolls them into view; parked windows keep a 1 pt sliver.
$CLI focus-last; $CHECK settle
$CHECK check-focused-visible
$CHECK check-parked
$CLI focus-first; $CHECK settle
$CHECK check-focused-visible
$CHECK check-parked
$CLI cycle-width; $CHECK settle
$CHECK check-tiles

# Hiding the app (⌘H) or minimizing a window keeps their columns: they come back to their places, not floating, even
# when macOS puts a parked window back on screen as it shows it again.
ORDER=$($CHECK column-order)
$CHECK host hide; sleep 1
$CHECK host unhide; $CHECK settle
$CHECK check-order "$ORDER"
$CHECK host "minimize 2"; sleep 1
$CHECK host "restore 2"; $CHECK settle
$CHECK check-order "$ORDER"
$CHECK check-tiles

# Another app moving a window (what Rectangle does) makes it float where it was put. (After the restore above, moves
# of that window count as macOS putting it back for 1.5 s.)
sleep 2
ID=$($CHECK window-at 1)
$CLI debug-external-move "$ID" 200 150 700 500
$CHECK settle
$CHECK check-floating "$ID"
$CHECK check-frame "$ID" 200 150
$CHECK wait-columns 4

# Pausing brings every window back on screen.
$CLI toggle-pause; $CHECK settle
$CHECK check-gathered
$CLI toggle-pause; $CHECK settle
$CHECK check-tiles

# Closing a window removes its column.
$CLI focus-first; $CHECK settle
$CLI close-window
$CHECK wait-columns 3

$CHECK host quit >/dev/null
echo "E2E OK"
