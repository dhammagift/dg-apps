#!/usr/bin/env bash
# Uposatha, edge to edge on a real iOS simulator (dg-apps#41) — the proof the Android twin
# (android-screens.yml mode=edgetoedge) cannot give, because WKWebView is a different engine.
# Launches the built app and walks it through portrait/landscape x light/dark, one screenshot per
# combination, optionally the whole pass as a video (VIDEO=1 -> ios-flow.mp4 in the out dir).
#
# Rotation: simctl cannot rotate, so the XCUITest bundle in uposatha/test/ios-sim/rotatetest turns
# XCUIDevice's orientation (the mechanism the sharetest job already uses; AppleScript/System Events
# would need accessibility rights a runner does not grant). The test HOLDS the orientation while the
# screenshots are taken, because the simulator goes back to portrait the moment its session ends
# (run 445 rotated, and every "landscape" screenshot came out portrait).
#
# The verdict — "nothing of the app is under the clock" — is the PAGE's own numbers, written into
# the app's Documents by the DEBUG DgSelfTest plugin (the bridge reports the inset it applied and
# where its top bar starts). A screenshot cannot be trusted for it: the system clock is ink on the
# page's background too, and reading one that way was wrong twice in run 444. The screenshots are
# only required to show a painted page; they are what a human looks at.
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
xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
# No permission alert over the first paint, if the page asks for the place (the sunrise times). After
# the install: before it, the grant has no app to grant to.
xcrun simctl privacy "$UDID" grant location "$BUNDLE" 2>/dev/null || true

REC=""
ROT_PID=""
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

# The UI-test bundle is built ONCE, up front: rotate_hold then runs it with test-without-building,
# which takes seconds. Building it inside the first rotation cost more than the wait allowed (run
# 446 never rotated at all: the log ends in BUILD INTERRUPTED when the wait gave up).
xcodebuild build-for-testing \
    -project "$ROTATE_PROJ" \
    -scheme RotateTests \
    -destination "id=$UDID" \
    -derivedDataPath /tmp/dg-rotate-derived \
    CODE_SIGNING_ALLOWED=NO > "$OUT/rotate-build.log" 2>&1 \
    || echo "ios-edgetoedge: could not prebuild the rotation test (will build on first use)" >&2

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
    local want="$1" tries="${2:-20}"
    for _ in $(seq 1 "$tries"); do
        oriented "$want" && { echo "ios-edgetoedge: the simulator is $want"; return 0; }
        sleep 1
    done
    echo "ios-edgetoedge: the simulator never turned $want" >&2
    return 1
}

# The UI test runs in the background and holds the orientation (RotateTests sleeps) until
# rotate_release; the log is for the post-mortem.
rotate_hold() { # $1 = Landscape|Portrait
    local lower
    lower=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    xcodebuild test-without-building \
        -project "$ROTATE_PROJ" \
        -scheme RotateTests \
        -destination "id=$UDID" \
        -derivedDataPath /tmp/dg-rotate-derived \
        -only-testing:"RotateTests/RotateTests/testRotate$1" \
        CODE_SIGNING_ALLOWED=NO > "$OUT/rotate-$1.log" 2>&1 &
    ROT_PID=$!
    wait_orient "$lower" 90
}

rotate_release() {
    [ -n "$ROT_PID" ] || return 0
    kill "$ROT_PID" 2>/dev/null || true
    wait "$ROT_PID" 2>/dev/null || true
    ROT_PID=""
    sleep 2
}

xcrun simctl launch "$UDID" "$BUNDLE"
# Wait for the page itself, not the clock: the window background is what shows before the first
# paint, and a screenshot of it would pass every check while proving nothing.
for _ in $(seq 1 12); do
    sleep 5
    shot .wait-portrait.png
    if python3 -c "
import json,subprocess,sys
subprocess.run(['python3','tools/edge-pixels.py','$OUT/.wait-portrait.png','light','$OUT/.wait-portrait.json'],capture_output=True)
sys.exit(0 if json.load(open('$OUT/.wait-portrait.json'))['ink_ratio'] > 0.01 else 1)
" 2>/dev/null; then echo "ios-edgetoedge: the page painted"; break; fi
done
shot uposatha-ios-1-portrait-light.png

xcrun simctl ui "$UDID" appearance dark
# A system banner (iCloud/Apple Intelligence) can land over the page in the first seconds and it is
# not part of the app: give it time, and re-shoot while the top of the screen still has a large
# light panel on the dark page.
sleep 10
shot uposatha-ios-2-portrait-dark.png
if python3 -c "
import json,subprocess,sys
subprocess.run(['python3','tools/edge-pixels.py','$OUT/uposatha-ios-2-portrait-dark.png','dark','/tmp/dg-banner.json'],capture_output=True)
try:
    d = json.load(open('/tmp/dg-banner.json'))
except Exception:
    sys.exit(1)   # no Pillow: nothing to judge, keep the shot
sys.exit(0 if (d.get('ink_ratio') or 0) < 0.45 else 1)
" 2>/dev/null; then :; else sleep 8; shot uposatha-ios-2-portrait-dark.png; fi

if rotate_hold Landscape; then
    sleep 2
    shot uposatha-ios-3-landscape-dark.png

    xcrun simctl ui "$UDID" appearance light
    sleep 4
    shot uposatha-ios-4-landscape-light.png
    rotate_release
else
    # Still worth the portrait shots and the video: say so in the artifact instead of failing the
    # job on the simulator's rotation (run 444 failed the whole step for exactly that).
    rotate_release
    echo "ios-edgetoedge: landscape skipped — the simulator did not rotate" | tee -a "$OUT/ios-edgetoedge.txt"
fi

if rotate_hold Portrait; then
    sleep 2
    # Back on portrait: the top bar must have stepped down by the inset again (the bridge re-reads
    # the inset on resize) — this shot is the check for that.
    shot uposatha-ios-5-portrait-light-again.png
fi
rotate_release

FAILED=0
# The screenshots must at least show the page: a blank one proves nothing.
for f in "$OUT"/uposatha-ios-*.png; do
    [ -f "$f" ] || continue
    if ! python3 tools/edge-pixels.py "$f" light "${f%.png}.json" > /dev/null 2>&1; then
        echo "SKIP $(basename "$f"): not measured (tools/edge-pixels.py needs Pillow on this runner)" | tee -a "$OUT/ios-edgetoedge.txt"
        continue
    fi
    if python3 -c "import json,sys;sys.exit(0 if not json.load(open('${f%.png}.json'))['empty_page'] else 1)" 2>/dev/null; then
        echo "PASS $(basename "$f"): the page is painted" | tee -a "$OUT/ios-edgetoedge.txt"
    else
        echo "FAIL $(basename "$f"): blank screenshot (the window background, not the page)" | tee -a "$OUT/ios-edgetoedge.txt"
        FAILED=1
    fi
done

# The verdict on "nothing of the app under the clock": the page's own numbers, written into the
# app's Documents by the DEBUG DgSelfTest plugin (the bridge reports the inset it applied and where
# its top bar starts).
CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null || true)
REPORT="$CONTAINER/Documents/dg-edgetoedge.json"
if [ -n "$CONTAINER" ] && [ -f "$REPORT" ]; then
    cp "$REPORT" "$OUT/dg-edgetoedge.json"
    if python3 - "$REPORT" <<'PY' | tee -a "$OUT/ios-edgetoedge.txt"
import json, sys
d = json.load(open(sys.argv[1]))
ok = True
def check(cond, text):
    global ok
    print(("PASS " if cond else "FAIL ") + text)
    ok = ok and cond
check(d.get("viewportFit") is True, "the page carries viewport-fit=cover (without it the inset never reaches it)")
check((d.get("topInset") or 0) >= 20, "the page received the status bar's height: %s px" % d.get("topInset"))
check((d.get("barTop") or -1) >= (d.get("topInset") or 0),
      "the page's top bar starts at %s px, at or below the inset %s px — nothing under the clock" % (d.get("barTop"), d.get("topInset")))
sys.exit(0 if ok else 1)
PY
    then :; else FAILED=1; fi
else
    echo "FAIL no report from the app at $REPORT — the DEBUG proof plugin did not answer" | tee -a "$OUT/ios-edgetoedge.txt"
    FAILED=1
fi

stop_recording
ls -la "$OUT"
[ "$FAILED" = 0 ] || exit 1
