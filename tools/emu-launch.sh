#!/bin/bash
# The launch check a store upload of the dictionary or Uposatha waits for (build-app.yml): the signed
# release APK is installed on an emulator, opened from the launcher, and must paint its page and still
# be running, with no crash of its process in the log. Not a test of what the app does — that is the
# browser checks of the bundle — only that the package that goes to the store starts at all.
# Usage: tools/emu-launch.sh <apk> <out-dir> <package>
set -u
APK=$1; OUT=$2; PKG=$3
REPO=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$OUT"; res="$OUT/launch-result.txt"; : > "$res"; fail=0
ok() { echo "PASS $*" >> "$res"; }; ko() { echo "FAIL $*" >> "$res"; fail=1; }
adb install -r "$APK" > "$OUT/install.txt" 2>&1 && ok "installed $(basename "$APK") as $PKG" || { ko "install: $(tail -1 "$OUT/install.txt")"; cat "$res"; exit 1; }
adb logcat -c
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
# A cold start on a CI emulator paints late (35-40 s seen for Uposatha); before that the WebView shows
# the window background, which tools/edge-pixels.py measures as no ink at all.
# body_ink, not ink_ratio: content against the body's own colour (a bare white WebView under dark system bars
# is all "ink" against the bar colour). Two shots in a row: one may still be the system splash's mark.
painted=""; inked=0
for i in $(seq 1 24); do
  sleep 5
  adb exec-out screencap -p > "$OUT/launch.png" 2>/dev/null
  if python3 "$REPO/tools/edge-pixels.py" "$OUT/launch.png" light "$OUT/launch.json" > /dev/null 2>&1 &&
     python3 -c "import json,sys; sys.exit(0 if json.load(open('$OUT/launch.json'))['body_ink'] > 0.01 else 1)"; then
    inked=$((inked + 1)); [ "$inked" -ge 2 ] && { painted=$((i * 5)); break; }
  else
    inked=0
  fi
done
[ -n "$painted" ] && ok "page painted after ${painted}s" || ko "page did not paint within 120s (launch.png)"
adb shell pidof "$PKG" > /dev/null 2>&1 && ok "still running" || ko "the process is gone"
adb logcat -d > "$OUT/logcat.txt" 2>/dev/null || true
if grep -A3 "FATAL EXCEPTION" "$OUT/logcat.txt" | grep -q "Process: $PKG"; then ko "crash in the log (logcat.txt)"; else ok "no crash in the log"; fi
cat "$res"
exit $fail
