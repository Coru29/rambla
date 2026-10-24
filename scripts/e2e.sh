#!/bin/bash
# Live end-to-end checks on the real app. Only the windows of a throwaway test app (TestHost) are
# managed, so nothing else on screen moves. Requires the app installed with the Accessibility permission.
# The last steps (stacked strips) restart Rambla with a layout file of the run's own, .build/e2e-state.json, never the
# user's, and put the pointer on the main display (a strip command given while nothing is focused goes by the pointer).
# Usage: scripts/e2e.sh [--no-install]
set -euo pipefail
cd "$(dirname "$0")/.."
APP_NAME=Rambla
CHECK=.build/e2e-check
[ -x "$CHECK" ] && [ "$CHECK" -nt scripts/e2e-check.swift ] || swiftc -O scripts/e2e-check.swift -o "$CHECK"
HOST=$(scripts/build-testhost.sh)
CLI=/Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME
HOST_ID=io.github.coru29.TestHost
STATE=$PWD/.build/e2e-state.json

# Quits Rambla as the installer does (it saves its layout on the way out) and waits until it is gone. It fails if
# Rambla is still there: the steps after it would be checking the old process.
quit_rambla() {
  pgrep -x $APP_NAME >/dev/null || return 0
  osascript -e 'tell application id "io.github.coru29.Rambla" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do pgrep -x $APP_NAME >/dev/null || return 0; sleep 0.1; done
  pkill -x $APP_NAME 2>/dev/null || true
  for _ in $(seq 1 30); do pgrep -x $APP_NAME >/dev/null || return 0; sleep 0.1; done
  echo "FAIL: $APP_NAME is still running after being asked to quit, and then killed" >&2
  return 1
}

# Waits until the test app has quit.
wait_host_gone() {
  for _ in $(seq 1 50); do pgrep -x TestHost >/dev/null || return 0; sleep 0.1; done
}

# Rambla's pause is a toggle, and its preferences keep a pause across launches (a reinstall does not undo it). So a run
# that fails while Rambla is paused resumes it on the way out, whatever stopped the run. PAUSED is 1 from before the
# toggle that pauses it until the one that resumes it is seen to work; the resume looks at the state before it toggles.
PAUSED=0
resume_on_exit() { [ "$PAUSED" = 0 ] || $CHECK resume || true; }
trap resume_on_exit EXIT
pause_rambla() {
  PAUSED=1
  $CLI toggle-pause
  $CHECK check-paused true
  $CHECK settle
}
resume_rambla() {
  $CLI toggle-pause
  $CHECK check-paused false
  PAUSED=0
  $CHECK settle
}

# Rambla starts with no layout file: what an earlier run saved must not come back onto the new test windows.
$CHECK host quit >/dev/null || true
wait_host_gone
if [ "${1:-}" != "--no-install" ]; then
  rm -f "$STATE"
  scripts/install.sh --only-bundle $HOST_ID --state-file "$STATE" >/dev/null
else
  quit_rambla
  rm -f "$STATE"
  open -a /Applications/$APP_NAME.app --args --only-bundle $HOST_ID --state-file "$STATE"
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
pause_rambla
$CHECK check-gathered
resume_rambla
$CHECK check-tiles

# Closing a window removes its column.
$CLI focus-first; $CHECK settle
$CLI close-window
$CHECK wait-columns 3

# A display beside the strip's (the laptop's own screen, opened next to a monitor): the windows parked on that side go
# to the other edge at once, and they come in and go out through their own side, never across the display.
for _ in 1 2 3; do $CHECK host add; done
$CHECK wait-columns 6
$CLI focus-first; $CHECK settle
LAST=$($CHECK window-at 5)
$CHECK watch-hidden "$LAST" debug-neighbor $($CHECK neighbor-right)
$CHECK check-parked
$CHECK watch-enters "$LAST" right focus-last
$CHECK check-parked
$CHECK watch-leaves "$LAST" right focus-first
$CHECK check-parked
$CHECK watch-hidden "$LAST" debug-neighbor
$CHECK check-parked
$CHECK check-tiles

# macOS moves windows while it changes the displays (one that spans two, one parked past an edge), after Rambla has
# laid them out: they must not float, and they go back to their places once it is done.
ORDER=$($CHECK column-order)
FIRST=$($CHECK window-at 0)
$CLI debug-neighbor $($CHECK neighbor-right); sleep 1
$CLI debug-external-move "$FIRST" 300 200 700 500; sleep 3
$CHECK settle
$CHECK check-columns "$ORDER"
$CHECK check-placed
$CLI debug-neighbor; sleep 1; $CHECK settle
$CHECK check-placed

# Stacked strips. They start on a fresh test app with four windows (so nothing the steps above left behind, like the
# window that floats, gets in the way), with the pointer on its display (a strip command given while nothing is focused,
# as from an empty strip, goes by the pointer) and the focus on the second column.
$CHECK host quit >/dev/null
wait_host_gone
open -n "$HOST" --args 4
$CHECK wait-columns 4
$CHECK settle
$CHECK pointer-to-display
$CLI focus-2; $CHECK settle
$CHECK check-tiles
$CHECK check-parked
$CHECK check-levels 1 0

# A new strip above, empty, comes into view; the four windows of the strip below go out of sight, parked on a side edge.
$CLI strip-up; $CHECK settle
$CHECK check-levels 2 1
$CHECK check-shelved 4

# Back down: the empty strip goes (nothing above has windows and it is no longer in view); the windows are in place.
$CLI strip-down; $CHECK settle
$CHECK check-levels 1 0
$CHECK check-placed

# A floating window goes with its strip: it is parked out of sight with it, and comes back to the same place with it.
FLOAT=$($CHECK window-at 2)
$CLI focus-3; $CHECK settle
$CLI toggle-float; $CHECK settle
$CHECK check-floating "$FLOAT"
FRAME=$($CHECK frame-of "$FLOAT")
$CLI strip-up; $CHECK settle
$CHECK check-levels 2 1
$CHECK check-float-parked "$FLOAT"
$CHECK check-shelved 4
$CLI strip-down; $CHECK settle
$CHECK check-levels 1 0
$CHECK check-frame-near "$FLOAT" $FRAME
$CHECK check-floating "$FLOAT"
$CHECK check-placed
# Floated back into the strip. The shortcut works on the focused window, so the test app gives that one the focus.
FLOAT_NUMBER=$($CHECK window-number "$FLOAT")
$CHECK host "focus $FLOAT_NUMBER"; $CHECK settle
$CLI toggle-float; $CHECK settle
$CHECK wait-columns 4
$CHECK check-not-floating "$FLOAT"
$CHECK check-placed

# Sending the focused window up: it goes alone to a new strip, which comes into view with it, and the other windows go
# out of sight. A second later, if the old app reports its focus late, the strip in view must not bounce back.
$CLI focus-2; $CHECK settle
BELOW=$($CHECK window-at 0)
SENT=$($CHECK window-at 1)
$CLI send-strip-up; sleep 1; $CHECK settle
$CHECK check-levels 2 1
$CHECK level-of "$SENT" 1
$CHECK check-placed
$CHECK check-shelved 3

# The app gives the focus to a window of the strip below. The test app must be in front already, so that this is no
# activation, just a move between its own windows, like a click on its sliver: that strip comes into view and the sent
# window goes out of sight.
BELOW_NUMBER=$($CHECK window-number "$BELOW")
$CHECK frontmost-is $HOST_ID
$CHECK host "focus $BELOW_NUMBER"; $CHECK settle
$CHECK check-levels 2 0
$CHECK check-focused-index 0
$CHECK check-focused-visible
$CHECK check-placed
$CHECK check-shelved 1
$CHECK level-of "$SENT" 1

# Another app moving a window that is out of sight (what Rectangle does, or an app restoring its own frame): it goes
# back to its parking spot, in its own strip, instead of floating.
$CLI debug-external-move "$SENT" 300 200 700 500; sleep 2; $CHECK settle
$CHECK check-shelved 1
$CHECK check-not-floating "$SENT"
$CHECK level-of "$SENT" 1
$CHECK check-levels 2 0

# Pausing brings every window back on screen, the ones out of sight too; resuming puts the strip above away again.
pause_rambla
$CHECK check-gathered
resume_rambla
$CHECK check-levels 2 0
$CHECK check-placed
$CHECK check-shelved 1

# A display beside the one with the strips: nothing out of sight shows on it, whichever strip is in view.
NEIGHBOR=$($CHECK neighbor-right)
$CLI debug-neighbor $NEIGHBOR; sleep 1; $CHECK settle
$CHECK check-shelved 1 $NEIGHBOR
$CLI strip-up; $CHECK settle
$CHECK check-levels 2 1
$CHECK check-shelved 3 $NEIGHBOR
$CLI strip-down; $CHECK settle
$CHECK check-levels 2 0
$CHECK check-shelved 1 $NEIGHBOR
$CLI debug-neighbor; sleep 1; $CHECK settle
$CHECK check-placed
$CHECK check-shelved 1

# Restarting Rambla with the strip above in view: both strips come back from the layout file, each window on its own
# level, and the one that was in view is in view again.
$CLI strip-up; $CHECK settle
$CHECK check-levels 2 1
quit_rambla
[ -s "$STATE" ] || { echo "FAIL: Rambla saved no layout in $STATE"; exit 1; }
open -g -a /Applications/$APP_NAME.app --args --only-bundle $HOST_ID --state-file "$STATE"
$CHECK check-levels 2 1 30
$CHECK settle
$CHECK level-of "$SENT" 1
$CHECK wait-columns 1
$CHECK check-placed
$CHECK check-shelved 3
# And the restored strips work: down to the one below.
$CLI strip-down; $CHECK settle
$CHECK check-levels 2 0
$CHECK wait-columns 3
$CHECK check-placed
$CHECK check-shelved 1

$CHECK host quit >/dev/null
echo "E2E OK"
