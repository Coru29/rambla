#!/bin/bash
# Fails when a text the app shows has no English translation in Packaging/en.lproj/Localizable.strings.
# Builds from scratch into its own folder: the compiler only lists the texts of the files it compiles, and the extra
# flags would otherwise invalidate the normal build.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$PWD/.build/localized-strings"
rm -rf "$OUT" .build/localization
mkdir -p "$OUT"
swift build --build-path .build/localization \
  -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$OUT" >/dev/null
swift scripts/check-localization.swift "$OUT" Packaging/en.lproj/Localizable.strings
