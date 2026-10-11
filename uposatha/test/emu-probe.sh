#!/bin/bash
# What kills the CI emulator when Uposatha starts (dg-apps, 2026-10-11): the emulator's own process died a few seconds after the
# app was opened, with no crash in the guest's log, on debug and release builds alike. One opening of the app under one variant of
# the emulator (.github/workflows/uposatha-emu-probe.yml runs the variants side by side); the verdict is how long adb kept answering.
# Usage: uposatha/test/emu-probe.sh <apk> <out-dir> [route, e.g. "/uposatha-calendar?app=1&tab=parts"]
set -u
APK=$1; OUT=$2; ROUTE=${3:-}; PKG=gift.dhamma.uposatha
mkdir -p "$OUT"; res="$OUT/probe-result.txt"; : > "$res"
A() { timeout 20 adb "$@"; }
A install -r "$APK" > "$OUT/install.txt" 2>&1 || { echo "FAIL install: $(tail -1 "$OUT/install.txt")" | tee -a "$res"; exit 1; }
A logcat -c
adb logcat > "$OUT/logcat-live.txt" 2> /dev/null &
if [ -n "$ROUTE" ]; then A shell "am start -n $PKG/.MainActivity --es route '$ROUTE'" > /dev/null 2>&1
else A shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1; fi
for i in $(seq 1 14); do
  sleep 5
  if [ "$(A get-state 2> /dev/null)" != device ]; then echo "DIED: the emulator stopped answering within $((i * 5)) s of the launch (route '${ROUTE:-none}')" | tee -a "$res"; exit 1; fi
  A exec-out screencap -p > "$OUT/shot.png" 2> /dev/null && [ -s "$OUT/shot.png" ] && cp "$OUT/shot.png" "$OUT/shot-last-good.png"
done
A shell pidof "$PKG" > /dev/null 2>&1 && echo "ALIVE: 70 s after the launch the emulator answers and the app runs (route '${ROUTE:-none}')" | tee -a "$res" || { echo "FAIL: the emulator lives, the app's process is gone" | tee -a "$res"; exit 1; }
