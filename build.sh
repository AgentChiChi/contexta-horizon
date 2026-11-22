#!/bin/bash
# Builds dist/contexta-horizon.app on this Mac, writes the example mailbox (dist/Examples), runs the static checks, the
# synthetic self-test and the check of the example. Nothing is downloaded, installed, published or copied anywhere else.
set -euo pipefail
cd "$(dirname "$0")"
if [ "${1:-}" = "install" ]; then echo "The app is not installed by this script. It stays in dist/contexta-horizon.app."; exit 1; fi
APP="dist/contexta-horizon.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macos13.0" -framework AppKit \
  -o "$APP/Contents/MacOS/ContextaHorizon" Sources/Core.swift Sources/MailAdapter.swift Sources/Simple.swift Sources/App.swift Sources/SelfTest.swift
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null
echo "Built: $(pwd)/$APP"
echo
# The example mailbox is written fresh on every build, dated relative to today (see Examples/README.txt).
bash Examples/make-sample.sh
rm -rf dist/Examples && mkdir -p dist/Examples && cp Examples/sample-mail.mbox Examples/make-sample.sh Examples/README.txt dist/Examples/
echo
bash tests/static-checks.sh
echo
"$APP/Contents/MacOS/ContextaHorizon" --self-test
echo
"$APP/Contents/MacOS/ContextaHorizon" --check-sample dist/Examples/sample-mail.mbox
