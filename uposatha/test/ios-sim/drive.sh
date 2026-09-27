#!/usr/bin/env bash
# Drives Uposatha on a simulator for the App Store screenshot tour: install, launch, take a picture every time
# the page (test/ios-sim/tour.js) announces a new stage via Documents/stage.txt, flip to dark appearance partway
# through (WebKit's prefers-color-scheme follows it live, no relaunch), and stop.
#
# Usage: test/ios-sim/drive.sh --app <path to .app> --out <dir> --device "<simulator name>"
set -euo pipefail

APP=""
OUT=".tmp/ios-tour"
DEVICE="iPhone 17 Pro Max"
BUNDLE="gift.dhamma.uposatha"
DARK_AFTER="keys"   # the stage after which the simulator flips to dark appearance

while [ $# -gt 0 ]; do
    case "$1" in
        --app) APP="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --device) DEVICE="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

[ -d "$APP" ] || { echo "drive: no .app at $APP" >&2; exit 1; }
mkdir -p "$OUT"

# grep -F, not -E: device names carry parentheses ("iPad Pro 13-inch (M5)"), a regex metacharacter.
DEVICES=$(xcrun simctl list devices available)
UDID=$(printf '%s\n' "$DEVICES" | grep -F "$DEVICE (" | tail -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/') || true
[ -n "$UDID" ] || { echo "drive: no available simulator named '$DEVICE'" >&2; printf '%s\n' "$DEVICES" >&2; exit 1; }
echo "drive: device $DEVICE = $UDID"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl ui "$UDID" appearance light
xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

DATA_DIR=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null || true)
[ -n "$DATA_DIR" ] || { echo "drive: could not find the app's data container" >&2; exit 1; }
rm -f "$DATA_DIR/Documents/stage.txt"

xcrun simctl launch --console-pty "$UDID" "$BUNDLE" > "$OUT/app-console.log" 2>&1 &

THEME="light"
LAST=""
for i in $(seq 1 180); do
    S=$(cat "$DATA_DIR/Documents/stage.txt" 2>/dev/null || true)
    if [ -n "$S" ] && [ "$S" != "$LAST" ]; then
        LAST="$S"
        echo "drive: stage $S ($THEME)"
        if [ "$S" = "done" ]; then break; fi
        sleep 1
        xcrun simctl io "$UDID" screenshot "$OUT/ios-$S-$THEME.png" >/dev/null \
            || echo "drive: screenshot for stage $S failed" >&2
        if [ "$S" = "$DARK_AFTER" ]; then
            xcrun simctl ui "$UDID" appearance dark
            THEME="dark"
            sleep 2
        fi
    fi
    sleep 1
done

echo "drive: screenshots in $OUT"
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
ls -la "$OUT"
