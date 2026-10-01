#!/bin/bash
# Screens of the built Dhamma.Gift APK on an Android emulator (workflow android-screens.yml), so a
# change can be looked at on a real Android WebView before it reaches the owner or a store
# (owner, 2026-09-29: "сними себе сам ... проверь, пришли скриншоты").
# Usage: tools/emu-screens.sh <apk> <out-dir> [package] [screens|shortcuts|edgetoedge]
set -u
APK=$1; OUT=$2; PKG=${3:-gift.dhamma.mobile}
REPO=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$OUT"
adb install -r "$APK" || exit 1
# Edge to edge (dg-apps#41): the Uposatha app must run UNDER the transparent system bars instead of
# showing the painted strips the DgBars plugin used to draw. Only a real device answers whether it
# does — the WebView's own env(safe-area-inset-*), the status bar's transparency and the window
# background are all native — so the question is settled here, by looking at the pixels of a
# screenshot, and the whole pass is recorded as flow.mp4 (workflow input "video").
if [ "$PKG" = gift.dhamma.uposatha ] && [ "${4:-}" = edgetoedge ]; then
  res="$OUT/edgetoedge-result.txt"; : > "$res"; fail=0
  ok() { echo "PASS $*" >> "$res"; }; ko() { echo "FAIL $*" >> "$res"; fail=1; }
  # screenrecord stops at 180 s: restarted in a loop while the flag file exists, joined at the end.
  [ "${VIDEO:-0}" = 1 ] && touch "$OUT/.rec"
  ( i=0; while [ -f "$OUT/.rec" ]; do adb shell screenrecord --bit-rate 4000000 --time-limit 170 "/sdcard/rec-$i.mp4"; i=$((i+1)); done ) &
  RECPID=$!
  stop_rec() {
    [ "${VIDEO:-0}" = 1 ] || return 0
    rm -f "$OUT/.rec"; adb shell pkill -2 screenrecord; sleep 4; wait "$RECPID" 2>/dev/null
    for f in $(adb shell ls /sdcard/ | tr -d '\r' | grep '^rec-.*\.mp4$' | sort -V); do adb pull "/sdcard/$f" "$OUT/$f" > /dev/null; echo "file '$f'" >> "$OUT/rec.txt"; done
    (cd "$OUT" && ffmpeg -loglevel error -y -f concat -safe 0 -i rec.txt -c copy flow.mp4 && rm -f rec-*.mp4 rec.txt) || true
  }
  launch() { adb shell am force-stop "$PKG"; adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null; sleep "${1:-14}"; }
  # The status bar's height, straight from the window manager (the device's own value, not a guess).
  sbar() { adb shell dumpsys window displays 2>/dev/null | grep -m1 -o "statusBars[^}]*frame=\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]" | grep -o "\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]" | tr -d '[]' | awk -F, '{print $4}' | head -1; }
  measure() { # $1 = name, $2 = light|dark, $3 = seconds to let the page paint
    adb shell cmd uimode night "$([ "$2" = dark ] && echo yes || echo no)" > /dev/null 2>&1
    launch "${3:-14}"
    adb exec-out screencap -p > "$OUT/edge-$1.png"
    python3 "$REPO/tools/edge-pixels.py" "$OUT/edge-$1.png" "$2" "$OUT/edge-$1.json" > /dev/null
    eval "$(python3 - "$OUT/edge-$1.json" <<'PY'
import json, sys
v = json.load(open(sys.argv[1]))
for k in ("edge_to_edge", "frame_top", "frame_bottom", "top_color", "bottom_color", "page_bg", "top_matches_page", "bottom_matches_page", "text_top"):
    print("v_%s=%s" % (k, "true" if v[k] is True else v[k]))
PY
)"
    bar=$(sbar)
    # 1. The page must reach both edges: no flat painted band at the top or the bottom, and the very
    #    first row of the screen must be the page's own background.
    [ "$v_frame_top" = 0 ] && ok "$1: the page reaches the top edge (no painted strip)" || ko "$1: $v_frame_top px of a strip at the top (top_color $v_top_color, page $v_page_bg)"
    [ "$v_frame_bottom" = 0 ] && ok "$1: the page reaches the bottom edge" || ko "$1: $v_frame_bottom px of a strip at the bottom (bottom_color $v_bottom_color, page $v_page_bg)"
    [ "$v_top_matches_page" = true ] && ok "$1: the first row of the screen is the page's own background ($v_page_bg)" || ko "$1: the first row is $v_top_color, not the page's $v_page_bg"
    [ "$v_edge_to_edge" = true ] && ok "$1: edge to edge (page background $v_page_bg)" || ko "$1: not edge to edge"
    # 2. The top bar must sit BELOW the status bar, not behind it: its first text is at least the
    #    status bar's own height down (text higher than that is covered by the clock).
    if [ -n "$bar" ] && [ -n "$v_text_top" ] && [ "$v_text_top" != None ]; then
      [ "$v_text_top" -ge "$bar" ] && ok "$1: the top bar starts below the status bar (text at ${v_text_top}px, status bar ${bar}px)" \
                                  || ko "$1: the top bar text is at ${v_text_top}px, inside the status bar (${bar}px) — the clock covers it"
    else
      ko "$1: could not read the status-bar height ($bar) or the top bar's text ($v_text_top)"
    fi
    # 3. The status bar area carries the page's own colour: its white by day, its #111111 at night
    #    (the old build painted the navy #1b2836 there). The screenshot rounds 8-bit colours, so the
    #    comparison allows a few levels.
    case "$2" in
      light) want="#ffffff";;
      dark)  want="#111111";;
    esac
    python3 - "$v_top_color" "$want" <<'PY' && ok "$1: the status bar strip is the page's $want ($v_top_color)" || ko "$1: the status bar strip is $v_top_color, not $want"
import sys
c = [int(sys.argv[1][i:i+2], 16) for i in (1, 3, 5)]
w = [int(sys.argv[2][i:i+2], 16) for i in (1, 3, 5)]
sys.exit(0 if all(abs(a - b) <= 8 for a, b in zip(c, w)) else 1)
PY
    [ "$v_bottom_matches_page" = true ] && ok "$1: the bottom edge is the page's own background too" || ko "$1: the bottom edge is $v_bottom_color, not the page's $v_page_bg"
  }
  adb logcat -c 2>/dev/null || true
  adb shell settings put system accelerometer_rotation 0
  adb shell settings put system user_rotation 0
  adb shell pm clear "$PKG" > /dev/null 2>&1 || true   # first run: the default light theme, no stored state
  measure light light 16
  measure dark dark 8
  adb shell cmd uimode night no > /dev/null 2>&1; launch 8
  # A short tour for the video: the app layer, a tab, then the dark theme (the page follows the
  # system appearance through prefers-color-scheme, so the same path a reader takes is exercised).
  adb shell input tap 250 1790; sleep 4     # the Calendar tab
  adb shell input swipe 540 700 540 1500 300; sleep 3
  adb shell cmd uimode night yes > /dev/null 2>&1; sleep 3
  adb exec-out screencap -p > "$OUT/edge-light-to-dark.png"
  launch 8
  adb shell input tap 250 1790; sleep 4     # the Calendar tab, on the dark page
  adb shell input keyevent KEYCODE_HOME; sleep 2
  stop_rec
  [ -s "$OUT/flow.mp4" ] && echo "video: flow.mp4 ($(du -h "$OUT/flow.mp4" | cut -f1))" >> "$res"
  adb logcat -d -s Capacitor/Console:* Capacitor:* > "$OUT/logcat.txt" 2>/dev/null || true
  grep -iE "Uncaught|TypeError|ReferenceError" "$OUT/logcat.txt" | head -5 >> "$res" || true
  cat "$res"; exit $fail
fi
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
  # The whole scenario as a video (owner: "запиши весь ролик"). screenrecord stops at 180 s, so it is
  # restarted in a loop while the flag file exists, and the parts are joined at the end.
  # Only when asked for (VIDEO=1, the workflows' "video" input): the screenshots are the default.
  [ "${VIDEO:-0}" = 1 ] && touch "$OUT/.rec"
  ( i=0; while [ -f "$OUT/.rec" ]; do adb shell screenrecord --bit-rate 4000000 --time-limit 170 "/sdcard/rec-$i.mp4"; i=$((i+1)); done ) &
  RECPID=$!
  stop_rec() {
    [ "${VIDEO:-0}" = 1 ] || return 0
    rm -f "$OUT/.rec"; adb shell pkill -2 screenrecord; sleep 4; wait "$RECPID" 2>/dev/null
    for f in $(adb shell ls /sdcard/ | tr -d '\r' | grep '^rec-.*\.mp4$' | sort -V); do adb pull "/sdcard/$f" "$OUT/$f" > /dev/null; echo "file '$f'" >> "$OUT/rec.txt"; done
    (cd "$OUT" && ffmpeg -loglevel error -y -f concat -safe 0 -i rec.txt -c copy flow.mp4 && rm -f rec-*.mp4 rec.txt) || true
  }
  ok() { echo "PASS $*" >> "$res"; }; ko() { echo "FAIL $*" >> "$res"; fail=1; }
  # The page is a WebView: uiautomator sees no text inside a release build, so the screen is read with OCR.
  screen_has() { adb exec-out screencap -p > "$OUT/ocr.png"; tesseract "$OUT/ocr.png" - 2>/dev/null | tee -a "$OUT/ocr.txt" | grep -qiE "$1"; }
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
  # The last five opened were dn22, dukkha, sn56.11, metta, mn8: the three slots must hold a search too.
  grep -qiE "shortLabel=(dukkha|metta)" "$OUT/shortcuts.txt" && ok "a recent search is among the shortcuts" || ko "no recent search among the shortcuts"
  # The launcher's own long-press menu, as the reader sees it: open the app drawer, long-press the icon,
  # screenshot, and read the menu (the launcher is native, so uiautomator sees its text).
  adb shell input keyevent KEYCODE_HOME; sleep 2
  # The swipe up to the app drawer does not always take on the first try: up to three.
  for try in 1 2 3; do
  adb shell input swipe 540 2000 540 500 $((300 * try)); sleep 3
  adb shell uiautomator dump /sdcard/l.xml > /dev/null 2>&1; adb shell cat /sdcard/l.xml > "$OUT/launcher.xml"
  xy=$(python3 - "$OUT/launcher.xml" << 'PY'
import re, sys
x = open(sys.argv[1], encoding='utf-8', errors='ignore').read()
for label in ('DGift', 'Dhamma.gift', 'Dhamma.Gift'):
    m = re.search(r'text="%s"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"' % re.escape(label), x)
    if m:
        a, b, c, d = map(int, m.groups()); print((a + c) // 2, (b + d) // 2); break
PY
)
  [ -n "$xy" ] && break
  adb shell input keyevent KEYCODE_HOME; sleep 2
  done
  if [ -n "$xy" ]; then
    adb shell input swipe $xy $xy 1500; sleep 2
    adb exec-out screencap -p > "$OUT/launcher-menu.png"
    adb shell uiautomator dump /sdcard/m.xml > /dev/null 2>&1; adb shell cat /sdcard/m.xml > "$OUT/launcher-menu.xml"
    grep -qiE 'text="(dukkha|metta)' "$OUT/launcher-menu.xml" && ok "launcher menu shows a recent search" || ko "launcher menu: no recent search"
    grep -qi 'text="Favorites' "$OUT/launcher-menu.xml" && ok "launcher menu shows Favorites & History" || ko "launcher menu: no Favorites & History"
    adb shell input keyevent KEYCODE_BACK; adb shell input keyevent KEYCODE_HOME
  else
    ko "launcher: app icon not found in the drawer"
  fi
  # Launch them the way the launcher does: the static one (MAIN + route extra), one recent text (SHORTCUT action).
  adb shell am force-stop "$PKG"
  adb shell am start -W -n "$PKG/gift.dhamma.mobile.MainActivity" -a android.intent.action.MAIN --es route /4as > /dev/null; sleep 12
  adb shell input tap 309 2184; sleep 2   # "Not now" on the offline-library sheet a force-stop brings back
  adb exec-out screencap -p > "$OUT/shortcut-static.png"
  screen_has "Favorites|History" && ok "static shortcut opens Favorites & History" || ko "static shortcut: Favorites & History not on screen"
  cp "$OUT/ocr.png" "$OUT/history.png"; tesseract "$OUT/history.png" - 2>/dev/null > "$OUT/history.txt"
  # Searches (not only texts) must be in the history too (owner, 2026-09-30: "поиски не сохраняются в историю").
  for q in metta dukkha; do grep -qi "$q" "$OUT/history.txt" && ok "search '$q' is in the history" || ko "search '$q' missing from the history"; done
  adb shell am force-stop "$PKG"
  adb shell am start -W -n "$PKG/gift.dhamma.mobile.MainActivity" -a gift.dhamma.mobile.SHORTCUT --es route /sn56.11 > /dev/null; sleep 12
  adb shell input tap 309 2184; sleep 2
  adb exec-out screencap -p > "$OUT/shortcut-recent.png"
  screen_has "sn56.11|Samyutta|Saṁyutta" && ok "recent-text shortcut opens sn56.11" || ko "recent-text shortcut: sn56.11 not on screen"
  adb logcat -d -s Capacitor/Console:* Capacitor:* > "$OUT/logcat.txt" 2>/dev/null || true
  grep -iE "dg-shortcuts|Uncaught|TypeError|ReferenceError" "$OUT/logcat.txt" | head -20 >> "$res"
  # Favorites from the history, then the quick window reopened a few times, for the video
  # (owner, 2026-10-01: in a favorite's row the subscribe bell turned into a trash can or a pencil
  # ~0.3 s after the window opened, on a phone; builds 427 and 430).
  for r in mn7 mn9 mn10 mn11 mn12; do adb shell am start -W -a android.intent.action.VIEW -d "https://dhamma.gift/$r" "$PKG" > /dev/null; sleep 8; done
  open_quick() {
    adb shell am force-stop "$PKG"
    adb shell am start -W -n "$PKG/gift.dhamma.mobile.MainActivity" -a android.intent.action.MAIN --es route /4as > /dev/null; sleep 10
    adb shell input tap 309 2184; sleep 2
  }
  # A history row's star sits at the right edge; its height is found with OCR (the page is a WebView,
  # uiautomator sees no text in a release build). The LAST match is the history row: favorites come first.
  star_of() {
    adb exec-out screencap -p > "$OUT/fav-ocr.png"
    tesseract "$OUT/fav-ocr.png" - tsv 2>/dev/null | awk -F'\t' -v t="$1" 'NR > 1 && $12 == t { y = $8 + int($10 / 2) } END { if (y) print y }'
  }
  open_quick
  for t in mn9 mn11 mn12; do
    y=$(star_of "$t")
    if [ -n "$y" ]; then adb shell input tap 930 "$y"; sleep 2; ok "favorite added from the history: $t"; else ko "history row not found on screen: $t"; fi
  done
  adb exec-out screencap -p > "$OUT/fav-after-adding.png"
  for n in 1 2 3; do
    adb shell input keyevent KEYCODE_BACK; sleep 2
    open_quick
    for d in 0 1 3; do sleep "$d"; adb exec-out screencap -p > "$OUT/fav-open-$n-${d}s.png"; done
  done
  # A basic flow on top, for the video: settings, then home.
  adb shell am start -W -a android.intent.action.VIEW -d "https://dhamma.gift/settings/" "$PKG" > /dev/null; sleep 8
  adb shell input swipe 540 1900 540 600 400; sleep 3
  adb shell input keyevent KEYCODE_HOME; sleep 2
  stop_rec
  [ -s "$OUT/flow.mp4" ] && echo "video: flow.mp4 ($(du -h "$OUT/flow.mp4" | cut -f1))" >> "$res"
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
