#!/usr/bin/env bash
# The Uposatha reminders on a simulator: installs the app, lets the UI test (notifytest) press the settings' test reminder and
# wait for iOS's banner, with the app open and in the background; collects its pictures and the app's notification log lines.
#
# Usage (from the repository root, after xcodegen in uposatha/test/ios-sim/notifytest):
#   uposatha/test/ios-sim/notify.sh <App.app> <out-dir>
set -uo pipefail
APP="${1:?usage: notify.sh <App.app> <out-dir>}"
OUT="${2:?usage: notify.sh <App.app> <out-dir>}"
BUNDLE=gift.dhamma.uposatha
HERE="$(cd "$(dirname "$0")" && pwd)/notifytest"
SHOTS=/tmp/upo-notify-shots
[ -d "$APP" ] || { echo "notify: no .app at $APP" >&2; exit 1; }
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
rm -rf "$SHOTS"; mkdir -p "$SHOTS"
UDID=$(xcrun simctl list devices available | grep -E "iPhone" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$UDID" ] || { echo "notify: no iPhone simulator available" >&2; exit 1; }
xcrun simctl list devices available | grep "$UDID" | tee "$OUT/device.txt"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant location "$BUNDLE" 2>/dev/null || true
xcodebuild build-for-testing -project "$HERE/NotifyTests.xcodeproj" -scheme NotifyTests \
  -destination "id=$UDID" -derivedDataPath "$HERE/DerivedData" CODE_SIGNING_ALLOWED=NO > "$OUT/notify-test-build.log" 2>&1 \
  || { echo "notify: the test did not build"; tail -40 "$OUT/notify-test-build.log"; exit 1; }
( i=0; while :; do i=$((i + 1)); xcrun simctl io "$UDID" screenshot "$OUT/$(printf 'loop-%03d.png' "$i")" >/dev/null 2>&1; sleep 5; done ) &
LOOP=$!
xcrun simctl spawn "$UDID" log stream --level debug --predicate 'eventMessage CONTAINS "DgNotify" OR eventMessage CONTAINS "dg-uposatha" OR eventMessage CONTAINS "⚡️"' > "$OUT/notify-log.txt" 2>&1 &
LOG=$!
xcrun simctl launch "$UDID" "$BUNDLE" > /dev/null
xcodebuild test-without-building -project "$HERE/NotifyTests.xcodeproj" -scheme NotifyTests \
  -destination "id=$UDID" -derivedDataPath "$HERE/DerivedData" > "$OUT/notify-test.log" 2>&1
CODE=$?
kill "$LOOP" "$LOG" 2>/dev/null
cp "$SHOTS"/*.png "$OUT/" 2>/dev/null || true
grep -E "Test Case|error:|XCTAssert" "$OUT/notify-test.log" | head -20
echo "notify: the test exit $CODE"
exit $CODE
