#!/bin/bash
# Dhamma.Gift's iOS app on a Mac, as "Designed for iPad" runs it on Apple Silicon (owner 2026-11-07: «вы можете поднимать
# это на обычных макбуках» - the iOS apps install on a MacBook, so a Mac runner shows what breaks there). The same self-test
# as the simulator run (prepare-www.js bundle, test/ios-sim/selftest.js), judged by the same assert.js.
#
# The .app built for iphoneos is put into a wrapper the way macOS runs iOS apps (Name.app/Wrapper/App.app + WrappedBundle),
# ad-hoc signed, launched with `open`; its data lives in ~/Library/Containers/<bundle>/Data like any sandboxed Mac app.
#
# Usage: test/ios-sim/mac-drive.sh --app path/App.app --out DIR [--library DIR]
set -euo pipefail
APP="" OUT=".tmp/mac-ui" LIBRARY=""
BUNDLE="gift.dhamma.mobile"
WAIT_SECONDS="${DG_SELFTEST_TIMEOUT:-300}"
while [ $# -gt 0 ]; do
    case "$1" in
        --app) APP="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --library) LIBRARY="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
[ -d "$APP" ] || { echo "mac-drive: no .app at $APP" >&2; exit 1; }
mkdir -p "$OUT"

WRAP="$HOME/Applications/DhammaGiftTest.app"
rm -rf "$WRAP"
mkdir -p "$WRAP/Wrapper"
cp -R "$APP" "$WRAP/Wrapper/App.app"
ln -s "Wrapper/App.app" "$WRAP/WrappedBundle"
# ad-hoc: no team on a CI runner; restricted entitlements (App Group, Associated Domains) were left out at build time
codesign --force --deep --sign - "$WRAP/Wrapper/App.app"
codesign -dv "$WRAP/Wrapper/App.app" 2>&1 | head -5 || true

DATA="$HOME/Library/Containers/$BUNDLE/Data"
if [ -n "$LIBRARY" ]; then
    # where builds 170-215 downloaded to; DgDownloadPlugin migrates it (the simulator run does the same, drive.sh)
    mkdir -p "$DATA/Library/Application Support/dg-library"
    cp "$LIBRARY"/* "$DATA/Library/Application Support/dg-library/"
fi
rm -f "$DATA/Documents/selftest.json"

log stream --style compact --predicate "process == \"App\"" > "$OUT/app-console.log" 2>&1 &
LOGPID=$!
open "$WRAP" || { echo "mac-drive: open refused the app" >&2; kill $LOGPID 2>/dev/null; exit 1; }

REPORT=""
for i in $(seq 1 "$WAIT_SECONDS"); do
    if [ -f "$DATA/Documents/selftest.json" ]; then REPORT="$DATA/Documents/selftest.json"; break; fi
    if [ $((i % 30)) -eq 0 ]; then screencapture -x "$OUT/mac-wait-$i.png" 2>/dev/null || true; fi
    sleep 1
done
screencapture -x "$OUT/mac-window.png" 2>/dev/null || true
kill $LOGPID 2>/dev/null || true
if [ -z "$REPORT" ]; then
    echo "mac-drive: the app never wrote Documents/selftest.json within ${WAIT_SECONDS}s" >&2
    pgrep -fl "DhammaGiftTest|App.app" >&2 || echo "mac-drive: the app is not running" >&2
    ls -la "$DATA" "$DATA/Documents" 2>&1 | head -20 >&2 || true
    tail -60 "$OUT/app-console.log" >&2 || true
    exit 1
fi
cp "$REPORT" "$OUT/selftest.json"
echo "mac-drive: self-test report at $REPORT"
osascript -e 'tell application "System Events" to set frontmost of (first process whose name is "App") to true' 2>/dev/null || true
sleep 2
screencapture -x "$OUT/mac-done.png" 2>/dev/null || true
pkill -f "DhammaGiftTest.app" 2>/dev/null || true
ls -la "$OUT"
