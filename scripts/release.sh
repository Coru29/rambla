#!/bin/bash
# Publishes the next release. The version comes from the Conventional Commits since the last v* tag
# (feat → minor, fix/perf → patch, "!" or BREAKING CHANGE → major; see CONTRIBUTING.md).
# Usage: scripts/release.sh [--dry-run] [notes.md]
set -euo pipefail
cd "$(dirname "$0")/.."
DRY=0
if [ "${1:-}" = "--dry-run" ]; then DRY=1; shift; fi
NOTES=$(mktemp)
NEXT=$(swift scripts/next-version.swift "$NOTES" 2>/dev/null | tail -1)
if [ "$NEXT" = "none" ]; then
  echo "No hay commits feat, fix ni perf desde el último release: no hay nada que publicar."
  exit 0
fi
if [ $# -gt 0 ]; then cp "$1" "$NOTES"; fi
echo "Próxima versión: $NEXT"
echo
cat "$NOTES"
[ $DRY = 1 ] && exit 0

[ -z "$(git status --porcelain)" ] || { echo "Hay cambios sin commitear." >&2; exit 1; }
scripts/test.sh >/dev/null || { echo "Fallan los tests." >&2; exit 1; }
if [ "$(tr -d '[:space:]' < VERSION)" != "$NEXT" ]; then
  echo "$NEXT" > VERSION
  git add VERSION
  git commit -q -m "chore(release): v$NEXT"
fi
scripts/dmg.sh
# Releases must carry the project's signing certificate: that is what lets installed copies verify and
# install the update, and what keeps the Accessibility permission. An ad-hoc build is never published.
codesign -d -r- build/Rambla.app 2>&1 | grep -q "certificate leaf" || { echo "El build no tiene la firma del proyecto (.signing/)." >&2; exit 1; }
git tag -a "v$NEXT" -F "$NOTES"
git push origin HEAD "v$NEXT"
gh release create "v$NEXT" build/Rambla.dmg --title "Rambla $NEXT" --notes-file "$NOTES"
echo "Publicado: https://github.com/Coru29/rambla/releases/tag/v$NEXT"
