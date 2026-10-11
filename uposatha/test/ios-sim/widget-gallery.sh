#!/usr/bin/env bash
# The Uposatha widgets as iOS shows them, on a simulator: installs the app, lets the UI test (widgettest) open the widget gallery
# and put a widget on the Home Screen, then collects what the test pictured, the widget extension's log and its crash reports.
#
# Usage (from the repository root, after xcodegen in uposatha/test/ios-sim/widgettest):
#   uposatha/test/ios-sim/widget-gallery.sh <App.app> <out-dir>
set -uo pipefail

APP="${1:?usage: widget-gallery.sh <App.app> <out-dir>}"
OUT="${2:?usage: widget-gallery.sh <App.app> <out-dir>}"
BUNDLE=gift.dhamma.uposatha
HERE="$(cd "$(dirname "$0")" && pwd)/widgettest"
SHOTS=/tmp/upo-widget-shots   # the test writes here (WidgetGalleryTests.swift)

[ -d "$APP" ] || { echo "widget-gallery: no .app at $APP" >&2; exit 1; }
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
rm -rf "$SHOTS"; mkdir -p "$SHOTS"

UDID=$(xcrun simctl list devices available | grep -E "iPhone" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$UDID" ] || { echo "widget-gallery: no iPhone simulator available" >&2; exit 1; }
xcrun simctl list devices available | grep "$UDID" | tee "$OUT/device.txt"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant location "$BUNDLE" 2>/dev/null || true
xcrun simctl ui "$UDID" appearance dark   # the owner's phone
ls "$APP/PlugIns" 2>/dev/null | tee "$OUT/plugins.txt"
START=$(date '+%Y-%m-%d %H:%M:%S')

xcodebuild build-for-testing -project "$HERE/WidgetTests.xcodeproj" -scheme WidgetTests \
  -destination "id=$UDID" -derivedDataPath "$HERE/DerivedData" CODE_SIGNING_ALLOWED=NO > "$OUT/widget-test-build.log" 2>&1 \
  || { echo "widget-gallery: the test did not build"; tail -40 "$OUT/widget-test-build.log"; exit 1; }

# the screen every few seconds as well: the pictures of last resort when the test stops early
( i=0; while :; do i=$((i + 1)); xcrun simctl io "$UDID" screenshot "$OUT/$(printf 'loop-%03d.png' "$i")" >/dev/null 2>&1; sleep 4; done ) &
LOOP=$!
xcodebuild test-without-building -project "$HERE/WidgetTests.xcodeproj" -scheme WidgetTests \
  -destination "id=$UDID" -derivedDataPath "$HERE/DerivedData" > "$OUT/widget-test.log" 2>&1
CODE=$?
kill "$LOOP" 2>/dev/null; wait "$LOOP" 2>/dev/null
echo "widget-gallery: the test exit $CODE"
grep -E "error: -\[|failed -|Test Case .* (passed|failed)" "$OUT/widget-test.log" | sed -E 's/^.*error: /  /' | head -20

cp "$SHOTS"/* "$OUT"/ 2>/dev/null
# What the extension and the widget host said, and why the extension died if it did
xcrun simctl spawn "$UDID" log show --start "$START" --style compact \
  --predicate 'process == "UposathaWidget" OR senderImagePath CONTAINS[c] "UposathaWidget" OR (process == "chronod" AND eventMessage CONTAINS[c] "uposatha")' \
  > "$OUT/widget-log.txt" 2>&1
# The process that draws the archives (and whoever else names the widget): the reason an archive is refused is said there
xcrun simctl spawn "$UDID" log show --start "$START" --style compact --info \
  --predicate 'process CONTAINS[c] "WidgetRenderer" OR (process != "chronod" AND process != "UposathaWidget" AND eventMessage CONTAINS[c] "uposatha")' \
  > "$OUT/widget-renderer-log.txt" 2>&1
echo "widget-gallery: $(wc -l < "$OUT/widget-log.txt") log lines"
grep -iE "crash|fatal|terminat|exception|error" "$OUT/widget-log.txt" | head -40
CRASHES=0
for f in ~/Library/Logs/DiagnosticReports/*UposathaWidget*; do
  [ -f "$f" ] || continue
  CRASHES=$((CRASHES + 1)); cp "$f" "$OUT/"
done
echo "widget-gallery: $CRASHES crash report(s) of the widget extension" | tee "$OUT/widget-gallery.txt"
ls -la "$OUT" | head -80
[ "$CRASHES" -eq 0 ] || exit 1
[ "$CODE" -eq 0 ] || exit 1
