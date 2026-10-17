#!/usr/bin/env bash
# The Dict.Dhamma.Gift Control Center control as iOS shows it, on a simulator: installs the app (so the control
# extension is registered), lets the UI test (controltest) open Control Center and its "Add a Control" gallery,
# find the control and add it, then collects the pictures and the extension's log/crash reports.
# Usage (after xcodegen in dict/test/ios-sim/controltest):  control-gallery.sh <App.app> <out-dir>
set -uo pipefail
APP="${1:?usage: control-gallery.sh <App.app> <out-dir>}"
OUT="${2:?usage: control-gallery.sh <App.app> <out-dir>}"
# Another app's control (Uposatha's from uposatha-widget-ios.yml): CONTROL_APP_ID, CONTROL_APPEX, CONTROL_KIND, CONTROL_SEARCH
BUNDLE="${CONTROL_APP_ID:-gift.dhamma.pali}"
APPEX="${CONTROL_APPEX:-DgDictControls}"
export TEST_RUNNER_CONTROL_APP_ID="$BUNDLE" TEST_RUNNER_CONTROL_KIND="${CONTROL_KIND:-gift.dhamma.pali.DgDictControl}" TEST_RUNNER_CONTROL_SEARCH="${CONTROL_SEARCH:-Dhamma}"
HERE="$(cd "$(dirname "$0")" && pwd)/controltest"
SHOTS=/tmp/dict-control-shots

[ -d "$APP" ] || { echo "control-gallery: no .app at $APP" >&2; exit 1; }
# A build with CODE_SIGNING_ALLOWED=NO carries only the linker's ad-hoc signature, whose identifier is not the bundle id: the
# App Intents daemon cannot map the control's intent to the app ("Failed to fetch metadata for ...") and WidgetKit stops
# generating the control with "Can't create CHSIntentReference" (an empty circle in the gallery, a tap that opens nothing).
# Ad-hoc signing binds the bundle id: the extensions first, then the app.
for x in "$APP"/PlugIns/*.appex; do codesign --force --sign - "$x"; done
codesign --force --sign - "$APP"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
rm -rf "$SHOTS"; mkdir -p "$SHOTS"

UDID=$(xcrun simctl list devices available | grep -E "iPhone" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$UDID" ] || { echo "control-gallery: no iPhone simulator available" >&2; exit 1; }
xcrun simctl list devices available | grep "$UDID" | tee "$OUT/device.txt"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl ui "$UDID" appearance dark
ls "$APP/PlugIns" 2>/dev/null | tee "$OUT/plugins.txt"
# prove the control extension is present in the bundle before driving the UI
test -d "$APP/PlugIns/$APPEX.appex" && echo "$APPEX.appex embedded: yes" | tee -a "$OUT/plugins.txt" \
  || { echo "control-gallery: $APPEX.appex is NOT embedded" | tee -a "$OUT/plugins.txt"; }
START=$(date '+%Y-%m-%d %H:%M:%S')

xcodebuild build-for-testing -project "$HERE/ControlTests.xcodeproj" -scheme ControlTests \
  -destination "id=$UDID" -derivedDataPath "$HERE/DerivedData" CODE_SIGNING_ALLOWED=NO > "$OUT/control-test-build.log" 2>&1 \
  || { echo "control-gallery: the test did not build"; tail -40 "$OUT/control-test-build.log"; exit 1; }

# the screen every few seconds too: the pictures of last resort if the test stops early
( i=0; while :; do i=$((i + 1)); xcrun simctl io "$UDID" screenshot "$OUT/$(printf 'loop-%03d.png' "$i")" >/dev/null 2>&1; sleep 4; done ) &
LOOP=$!
xcodebuild test-without-building -project "$HERE/ControlTests.xcodeproj" -scheme ControlTests \
  -destination "id=$UDID" -derivedDataPath "$HERE/DerivedData" > "$OUT/control-test.log" 2>&1
CODE=$?
kill "$LOOP" 2>/dev/null; wait "$LOOP" 2>/dev/null
echo "control-gallery: the test exit $CODE"
grep -E "error: -\[|failed -|Test Case .* (passed|failed)|app foreground after tap" "$OUT/control-test.log" | head -20

cp "$SHOTS"/* "$OUT"/ 2>/dev/null
xcrun simctl spawn "$UDID" log show --start "$START" --style compact \
  --predicate "process CONTAINS[c] \"$APPEX\" OR senderImagePath CONTAINS[c] \"$APPEX\" OR eventMessage CONTAINS[c] \"$BUNDLE\"" \
  > "$OUT/control-log.txt" 2>&1 || true
echo "control-gallery: $(ls "$OUT"/*.png 2>/dev/null | wc -l) screenshots"
ls -la "$OUT" | head -60
# The build-embed proof already passed earlier in CI; here the exit code reflects whether the control was found in the gallery.
[ "$CODE" -eq 0 ] || exit 1
