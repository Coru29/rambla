#!/bin/bash
# Publishes a release: tests, signed DMG, git tag and GitHub release with build/Rambla.dmg attached.
# Usage: scripts/release.sh [release-notes.md]     (bump VERSION and commit before running it)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(tr -d '[:space:]' < VERSION)
TAG="v$VERSION"
[ -z "$(git status --porcelain)" ] || { echo "Hay cambios sin commitear." >&2; exit 1; }
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then echo "La versión $VERSION ya existe: subí VERSION." >&2; exit 1; fi
scripts/test.sh >/dev/null || { echo "Fallan los tests." >&2; exit 1; }
scripts/dmg.sh
# Releases must carry the project's signing certificate: that is what keeps users' Accessibility
# permission across updates. An ad-hoc fallback build is never published.
codesign -d -r- build/Rambla.app 2>&1 | grep -q "certificate leaf" || { echo "El build no tiene la firma del proyecto (.signing/)." >&2; exit 1; }
git tag -a "$TAG" -m "Rambla $VERSION"
git push origin HEAD "$TAG"
if [ $# -gt 0 ]; then
  gh release create "$TAG" build/Rambla.dmg --title "Rambla $VERSION" --notes-file "$1"
else
  gh release create "$TAG" build/Rambla.dmg --title "Rambla $VERSION" --generate-notes
fi
echo "Publicado: https://github.com/Coru29/rambla/releases/tag/$TAG"
