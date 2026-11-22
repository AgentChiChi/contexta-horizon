#!/bin/bash
# Builds and runs the screenshot tool of the tests (tests/glass-shot.swift): the app's own sources, with the app's
# entry point left out, plus that one file — a separate test program in dist/glass-shot/, never part of the app.
# It photographs the two Horizon windows over a striped test backdrop of its own and measures the result; nothing of
# the desktop or of another app is in the pictures. Made-up records in a temporary folder only.
#   bash tests/glass-shot.sh [folder for the pictures, default dist/evidence]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-dist/evidence}"
mkdir -p dist/glass-shot "$OUT"
sed '/^@main$/d' Sources/App.swift > dist/glass-shot/App.swift           # the app's sources as they are, minus the one line that makes it the program's start
[ "$(diff Sources/App.swift dist/glass-shot/App.swift | grep -c '^[<>]')" = 1 ]
swiftc -O -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macos13.0" -framework AppKit \
  -o dist/glass-shot/GlassShot Sources/Core.swift Sources/MailAdapter.swift Sources/Glyph.swift Sources/Simple.swift dist/glass-shot/App.swift Sources/SelfTest.swift tests/glass-shot.swift
dist/glass-shot/GlassShot "$OUT"
