#!/usr/bin/env bash
# Uposatha, edge to edge on a real iOS simulator (dg-apps#41) — the proof the Android twin
# (android-screens.yml mode=edgetoedge) cannot give, because WKWebView is a different engine.
# Launches the built app and walks it through portrait/landscape x light/dark, one screenshot per
# combination, optionally the whole pass as a video (VIDEO=1 -> ios-flow.mp4 in the out dir).
#
# Rotation: simctl cannot rotate, so the XCUITest bundle in uposatha/test/ios-sim/rotatetest turns
# XCUIDevice's orientation (the mechanism the sharetest job already uses; AppleScript/System Events
# would need accessibility rights a runner does not grant). Every rotation is verified from the
# screenshot's own dimensions — a rotation that silently did not take must not be photographed as
# proof.
#
# Usage (from the repository root, after the simulator build and `xcodegen generate` in
# uposatha/test/ios-sim/rotatetest):
#   VIDEO=1 tools/ios-edgetoedge.sh <App.app> <out-dir> [bundle-id]
set -euo pipefail

APP="${1:?usage: ios-edgetoedge.sh <App.app> <out-dir> [bundle-id]}"
OUT="${2:?usage: ios-edgetoedge.sh <App.app> <out-dir> [bundle-id]}"
BUNDLE="${3:-gift.dhamma.uposatha}"
VIDEO="${VIDEO:-0}"
ROTATE_PROJ="uposatha/test/ios-sim/rotatetest/RotateTests.xcodeproj"

[ -d "$APP" ] || { echo "ios-edgetoedge: no .app at $APP" >&2; exit 1; }
[ -d "$ROTATE_PROJ" ] || { echo "ios-edgetoedge: $ROTATE_PROJ missing — run xcodegen in uposatha/test/ios-sim/rotatetest" >&2; exit 1; }
mkdir -p "$OUT"

DEVICES=$(xcrun simctl list devices available)
UDID=$(printf '%s\n' "$DEVICES" | grep -E "iPhone" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/') || true
[ -n "$UDID" ] || { echo "ios-edgetoedge: no iPhone simulator available" >&2; exit 1; }
echo "ios-edgetoedge: device $UDID"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
# No permission alert over the first paint, if the page asks for the place (the sunrise times).
xcrun simctl privacy "$UDID" grant location "$BUNDLE" 2>/dev/null || true
xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

REC=""
stop_recording() {
    [ -n "$REC" ] || return 0
    kill -INT "$REC" 2>/dev/null || true
    wait "$REC" 2>/dev/null || true
    REC=""
}
# Whatever happens next — a failed rotation, a missing screenshot — the video has to be closed, or
# the artifact is a 0-byte file beside a large ".sb-…" partial (run 444).
trap stop_recording EXIT
if [ "$VIDEO" = "1" ]; then
    xcrun simctl io "$UDID" recordVideo --codec h264 --force "$OUT/ios-flow.mp4" &
    REC=$!
    sleep 2
fi

shot() {
    xcrun simctl io "$UDID" screenshot "$OUT/$1" >/dev/null \
        || echo "ios-edgetoedge: screenshot $1 failed" >&2
}

# True when the current screenshot has the asked-for orientation.
oriented() {
    local want="$1" w h
    xcrun simctl io "$UDID" screenshot /tmp/dg-orient.png >/dev/null 2>&1 || return 1
    w=$(sips -g pixelWidth /tmp/dg-orient.png 2>/dev/null | awk '/pixelWidth/{print $2}')
    h=$(sips -g pixelHeight /tmp/dg-orient.png 2>/dev/null | awk '/pixelHeight/{print $2}')
    [ -n "${w:-}" ] && [ -n "${h:-}" ] || return 1
    if [ "$want" = landscape ]; then [ "$w" -gt "$h" ]; else [ "$h" -gt "$w" ]; fi
}

wait_orient() {
    for _ in $(seq 1 20); do
        oriented "$1" && return 0
        sleep 1
    done
    echo "ios-edgetoedge: the simulator never turned $1" >&2
    return 1
}

rotate() {
    local lower
    lower=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    # The real check is wait_orient; the test log is for the post-mortem.
    xcodebuild test \
        -project "$ROTATE_PROJ" \
        -scheme RotateTests \
        -destination "id=$UDID" \
        -derivedDataPath /tmp/dg-rotate-derived \
        -only-testing:"RotateTests/RotateTests/testRotate$1" \
        CODE_SIGNING_ALLOWED=NO > "$OUT/rotate-$1.log" 2>&1 || true
    tail -3 "$OUT/rotate-$1.log" || true
    wait_orient "$lower"
}

xcrun simctl launch "$UDID" "$BUNDLE"
# The calendar paints from the bundled snapshot; give the page and its theme the moment they need.
sleep 14
shot uposatha-ios-1-portrait-light.png

xcrun simctl ui "$UDID" appearance dark
sleep 4
shot uposatha-ios-2-portrait-dark.png

if rotate Landscape; then
    sleep 2
    shot uposatha-ios-3-landscape-dark.png

    xcrun simctl ui "$UDID" appearance light
    sleep 4
    shot uposatha-ios-4-landscape-light.png
else
    # Still worth the portrait shots and the video: say so in the artifact instead of failing the
    # job on the simulator's rotation (run 444 failed the whole step for exactly that).
    echo "ios-edgetoedge: landscape skipped — the simulator did not rotate" | tee -a "$OUT/ios-edgetoedge.txt"
fi

if rotate Portrait; then
    sleep 2
    # Back on portrait: the top bar must have stepped down by the inset again (the bridge re-reads
    # the inset on resize) — this shot is the check for that.
    shot uposatha-ios-5-portrait-light-again.png
fi
# The page itself: the top bar must be clear of the status bar / Dynamic Island. A screenshot with
# the page's own words under the clock is the failure this whole job exists to catch, so it is
# measured, not eyeballed (tools/edge-pixels.py reads the status bar rows).
for f in "$OUT"/uposatha-ios-*.png; do
    [ -f "$f" ] || continue
    python3 tools/edge-pixels.py "$f" light "${f%.png}.json" > /dev/null 2>&1 || true
    if python3 -c "import json,sys;d=json.load(open('${f%.png}.json'));sys.exit(0 if d['top_row_uniform'] and not d['empty_page'] else 1)" 2>/dev/null; then
        echo "PASS $(basename "$f"): the page is painted and nothing of it is under the status bar" | tee -a "$OUT/ios-edgetoedge.txt"
    else
        echo "FAIL $(basename "$f"): the page is empty or its content is under the status bar" | tee -a "$OUT/ios-edgetoedge.txt"
        FAILED=1
    fi
done
[ "${FAILED:-0}" = 0 ] || exit 1

stop_recording
ls -la "$OUT"
