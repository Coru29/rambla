#!/bin/bash
# Live test of a MacBook beside a monitor, run by hand (it needs someone to close and open the lid): the Mac's screen
# must be on, to the side of the monitor, when it starts. The test windows say (on screen and aloud) when to close the
# lid and when to open it again. Only the windows of the test app are managed, as in scripts/e2e.sh.
# Usage: scripts/e2e-lid.sh
set -euo pipefail
cd "$(dirname "$0")/.."
CHECK=.build/e2e-check
[ -x "$CHECK" ] && [ "$CHECK" -nt scripts/e2e-check.swift ] || swiftc -O scripts/e2e-check.swift -o "$CHECK"
HOST=$(scripts/build-testhost.sh)
CLI=/Applications/Rambla.app/Contents/MacOS/Rambla
HOST_ID=io.github.coru29.TestHost
ask() {
  echo ">> $1"
  $CHECK host "label $1" >/dev/null
  say "$1" &
}

$CHECK wait-displays 2 5
$CHECK host quit >/dev/null || true
scripts/install.sh --only-bundle $HOST_ID >/dev/null
open -n "$HOST" --args 6
$CHECK wait-columns 6
$CLI focus-first; $CHECK settle

# Beside the Mac's screen: every window where the strip puts it, and the ones beyond that side come and go through it.
$CHECK check-placed
$CHECK check-parked
LAST=$($CHECK window-at 5)
$CHECK watch-enters "$LAST" right focus-last; $CHECK settle
$CHECK check-placed
$CHECK watch-leaves "$LAST" right focus-first; $CHECK settle
$CHECK check-placed

# A window on the Mac's screen, on a second strip of its own (the strips above the first go through the lid too).
LAPTOP=$($CHECK other-display)
$CLI focus-2; $CHECK settle
SENT=$($CHECK window-at 1)
$CLI send-next-display
$CHECK wait-columns-on "$LAPTOP" 1
$CHECK settle
$CHECK check-placed
$CLI send-strip-up; sleep 1; $CHECK settle
$CHECK check-levels-on "$LAPTOP" 2 1
$CHECK level-of "$SENT" 1
$CHECK check-placed

# Closing the lid: that window joins the monitor's strips within a few seconds, on the same second strip, out of sight.
ask "Cerrá la tapa"
$CHECK wait-displays 1
$CHECK check-levels 2 0 15
$CHECK wait-columns 5
$CHECK level-of "$SENT" 1
$CHECK settle
$CHECK check-placed
$CHECK check-shelved 1

# Opening it: the windows parked on that side go to the other edge without crossing the monitor, whatever macOS moves
# goes back to its place, and the window that was on the Mac's screen (parked on the monitor's second strip now) goes
# back to it, to its second strip, without crossing the monitor either.
$CLI focus-first; $CHECK settle
PARKED=$($CHECK window-at 4)
$CHECK watch-until-displays 2 sliver "$PARKED" & WATCH_PARKED=$!
$CHECK watch-until-displays 2 half "$SENT" & WATCH_BACK=$!
sleep 0.5
ask "Abrí la tapa"
wait $WATCH_PARKED
wait $WATCH_BACK
$CHECK host "label Listo, gracias" >/dev/null
sleep 2; $CHECK settle
$CHECK check-placed
$CHECK wait-columns-on "$LAPTOP" 1 20
$CHECK settle
$CHECK check-placed
$CHECK level-of "$SENT" 1
$CHECK check-levels-on "$LAPTOP" 2 1
$CHECK check-levels 1 0

$CHECK host quit >/dev/null
echo "LID E2E OK"
