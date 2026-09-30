#!/bin/bash
# Screens of the built Dhamma.Gift APK on an Android emulator (workflow android-screens.yml), so a
# change can be looked at on a real Android WebView before it reaches the owner or a store
# (owner, 2026-09-29: "сними себе сам ... проверь, пришли скриншоты").
# Usage: tools/emu-screens.sh <apk> <out-dir>
set -u
APK=$1; OUT=$2; PKG=${3:-gift.dhamma.mobile}
mkdir -p "$OUT"
adb install -r "$APK" || exit 1
if [ "$PKG" = gift.dhamma.uposatha ]; then
  # Uposatha: the long-press menu is dynamic shortcuts the page's bridge pushes, so what proves it is the
  # system's own list after one launch (and the version row the bridge fills in).
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null
  sleep 25; adb exec-out screencap -p > "$OUT/uposatha-home.png"
  adb shell input keyevent KEYCODE_HOME; sleep 3
  adb shell dumpsys shortcut "$PKG" > "$OUT/shortcuts.txt"
  # The page updates itself from the site (DgSite, files/site/): what arrived, and whether it is the current page.
  # run-as needs the debuggable APK; on a release one these two files stay empty.
  sleep 30
  adb shell run-as "$PKG" find files/site -type f > "$OUT/site-files.txt" 2>&1 || true
  adb shell run-as "$PKG" cat files/site/assets/js/uposatha-calendar.js > "$OUT/site-uposatha-calendar.js" 2>/dev/null || true
  adb logcat -d -t 400 > "$OUT/logcat.txt" 2>/dev/null || true
  grep -cE "Shortcut: *dg-|id=dg-" "$OUT/shortcuts.txt"; exit 0
fi
adb shell dumpsys package com.google.android.webview | grep -m1 versionName > "$OUT/webview-version.txt" || true
shot() { sleep "${2:-6}"; adb exec-out screencap -p > "$OUT/$1.png"; echo "shot $1"; }
# App Links (https://dhamma.gift/...), the way a tapped link arrives: explicit package, so no
# domain verification is needed on the emulator.
route() { adb shell am start -W -a android.intent.action.VIEW -d "https://dhamma.gift/$1" "$PKG" > /dev/null; }
up() { for i in $(seq 1 "$1"); do adb shell input swipe 540 1900 540 400 60; done; }

adb shell settings put system accelerometer_rotation 0
adb shell settings put system user_rotation 0
for theme in light dark; do
  if [ "$theme" = dark ]; then adb shell cmd uimode night yes; else adb shell cmd uimode night no; fi
  adb shell am force-stop "$PKG"
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null
  shot "$theme-1-home" 15
  # The first-run "download the offline library?" sheet: "Not now" (Pixel 7 coordinates).
  adb shell input tap 309 2184; sleep 2
  route metta;        shot "$theme-2-results" 10
  route mn8;          shot "$theme-3-reader" 10
  up 40;              shot "$theme-4-reader-end" 4
  route mn8
  adb shell settings put system user_rotation 1
  shot "$theme-5-reader-landscape" 8
  adb shell settings put system user_rotation 0
  sleep 3
done
adb logcat -d -t 400 > "$OUT/logcat.txt" 2>/dev/null || true
ls -la "$OUT"
