#!/bin/bash
# Builds the icon from its source (the canonical path in Sources/Glyph.swift + Icon/make-icon.swift): mark.svg,
# icon.svg, menu-glyph.svg, menu-glyph.png (and @2x), AppIcon.icns (16 to 512 points, 1x and 2x) and icon-preview.png,
# all in this folder. Uses only swiftc and iconutil,
# which come with the Command Line Tools. Nothing is downloaded.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist/icon-build
swiftc -O -parse-as-library Sources/Glyph.swift Icon/make-icon.swift -o dist/icon-build/make-icon
dist/icon-build/make-icon dist/icon-build
iconutil -c icns dist/icon-build/AppIcon.iconset -o Icon/AppIcon.icns
cp dist/icon-build/mark.svg dist/icon-build/icon.svg dist/icon-build/menu-glyph.svg dist/icon-build/menu-glyph.png "dist/icon-build/menu-glyph@2x.png" dist/icon-build/icon-preview.png Icon/
echo "Icon/AppIcon.icns: $(stat -f %z Icon/AppIcon.icns) bytes"
