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
  # 90 s in the foreground: DgSite stores the update only after every file has come, and a backgrounded WebView stops.
  sleep 90; adb exec-out screencap -p > "$OUT/uposatha-home.png"
  adb shell input keyevent KEYCODE_HOME; sleep 3
  adb shell dumpsys shortcut "$PKG" > "$OUT/shortcuts.txt"
  # The page updates itself from the site (DgSite, files/site/): what arrived, and whether it is the current page.
  # run-as needs the debuggable APK; on a release one these two files stay empty.
  # Opened again: the page must now be the downloaded one. The screen's own text (uiautomator reads a WebView too).
  adb shell am force-stop "$PKG"; adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null
  sleep 25; adb exec-out screencap -p > "$OUT/uposatha-reopened.png"
  adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1; adb shell cat /sdcard/ui.xml > "$OUT/ui-reopened.xml" 2>/dev/null || true
  adb shell run-as "$PKG" find files/site -type f > "$OUT/site-files.txt" 2>&1 || true
  adb shell run-as "$PKG" cat files/site/assets/js/uposatha-calendar.js > "$OUT/site-uposatha-calendar.js" 2>/dev/null || true
  adb logcat -d -s Capacitor/Console:* Capacitor:* > "$OUT/logcat.txt" 2>/dev/null || true
  grep -cE "Shortcut: *dg-|id=dg-" "$OUT/shortcuts.txt"; exit 0
fi
if [ "${4:-}" = shortcuts ]; then
  # Dhamma.Gift launcher shortcuts, end to end, with a verdict (owner, 2026-09-30: "не работают шорткаты
  # в андроид ... авто тесты"). Reads texts, leaves the app (that is when the page pushes its list),
  # then asks the system what it holds and launches each shortcut the way the launcher does.
  # Writes $OUT/shortcuts-result.txt; exits 1 when a check fails, so the workflow run goes red.
  fail=0; res="$OUT/shortcuts-result.txt"; : > "$res"
  ok() { echo "PASS $*" >> "$res"; }; ko() { echo "FAIL $*" >> "$res"; fail=1; }
  screen_has() { adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1; adb shell cat /sdcard/ui.xml | grep -qi "$1"; }
  adb logcat -c
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null; sleep 15
  adb shell input tap 309 2184; sleep 2
  for r in mn8 metta sn56.11 dukkha dn22; do adb shell am start -W -a android.intent.action.VIEW -d "https://dhamma.gift/$r" "$PKG" > /dev/null; sleep 10; done
  adb shell run-as "$PKG" true 2>/dev/null && echo "(debuggable)" >> "$res"
  adb shell input keyevent KEYCODE_HOME; sleep 5
  adb shell dumpsys shortcut "$PKG" > "$OUT/shortcuts.txt"
  grep -q "favorites_history" "$OUT/shortcuts.txt" && ok "static shortcut favorites_history declared" || ko "static shortcut favorites_history missing"
  n=$(grep -oE "id=dg-recent[-a-z0-9]*" "$OUT/shortcuts.txt" | sort -u | wc -l)
  [ "$n" -ge 1 ] && ok "dynamic recent-text shortcuts: $n" || ko "no dynamic recent-text shortcuts pushed"
  # Launch them the way the launcher does: the static one (MAIN + route extra), one recent text (SHORTCUT action).
  adb shell am force-stop "$PKG"
  adb shell am start -W -n "$PKG/gift.dhamma.mobile.MainActivity" -a android.intent.action.MAIN --es route /4as > /dev/null; sleep 12
  adb shell input tap 309 2184; sleep 2   # "Not now" on the offline-library sheet a force-stop brings back
  adb exec-out screencap -p > "$OUT/shortcut-static.png"
  screen_has "Favorites\|Избранное\|History\|История" && ok "static shortcut opens Favorites & History" || ko "static shortcut: Favorites & History not on screen"
  adb shell cat /sdcard/ui.xml > "$OUT/ui-history.xml"
  # Searches (not only texts) must be in the history too (owner, 2026-09-30: "поиски не сохраняются в историю").
  for q in metta dukkha; do grep -q "text=\"$q" "$OUT/ui-history.xml" && ok "search '$q' is in the history" || ko "search '$q' missing from the history"; done
  adb shell am force-stop "$PKG"
  adb shell am start -W -n "$PKG/gift.dhamma.mobile.MainActivity" -a gift.dhamma.mobile.SHORTCUT --es route /sn56.11 > /dev/null; sleep 12
  adb shell input tap 309 2184; sleep 2
  adb exec-out screencap -p > "$OUT/shortcut-recent.png"
  screen_has "Dhammacakkappavattana\|sn56.11" && ok "recent-text shortcut opens sn56.11" || ko "recent-text shortcut: sn56.11 not on screen"
  adb logcat -d -s Capacitor/Console:* Capacitor:* > "$OUT/logcat.txt" 2>/dev/null || true
  grep -iE "dg-shortcuts|Uncaught|TypeError|ReferenceError" "$OUT/logcat.txt" | head -20 >> "$res"
  cat "$res"; exit $fail
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
  # Settings (the Cloud row). The Uposatha calendar is not bundled here: the app opens it on the site.
  route settings/;           shot "$theme-6-settings" 10
  up 2;                      shot "$theme-7-settings-scrolled" 4
done
adb logcat -d -t 400 > "$OUT/logcat.txt" 2>/dev/null || true
ls -la "$OUT"
