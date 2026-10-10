#!/bin/bash
# Screens of the built Dhamma.Gift APK on an Android emulator (workflow android-screens.yml), so a
# change can be looked at on a real Android WebView before it reaches the owner or a store
# (owner, 2026-09-29: "сними себе сам ... проверь, пришли скриншоты").
# Usage: tools/emu-screens.sh <apk> <out-dir> [package] [screens|shortcuts|edgetoedge|tray|widget]
set -u
APK=$1; OUT=$2; PKG=${3:-gift.dhamma.mobile}
REPO=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$OUT"
adb install -r "$APK" || exit 1
# Widget (Uposatha): the home-screen widget's renderer, looked at on a real Android. A launcher cannot be driven reliably
# from adb, so the debug build carries WidgetPreviewActivity, which draws every layer in every size, light and dark, with the
# very class the widget uses (WidgetRenderer) from a sample of the page's data. Needs the DEBUG apk.
if [ "$PKG" = gift.dhamma.uposatha ] && [ "${4:-}" = widget ]; then
  res="$OUT/widget-result.txt"; : > "$res"
  # One start per theme and size (the activity draws all of them on the UI thread: a slow emulator answered "not responding").
  # scenario 5 = the designer's mockup state in English. The sheets (card on a flat back, caption below) are pulled at the end.
  adb shell rm -rf /sdcard/Android/data/$PKG/files/widget-previews
  for theme in light dark; do
    adb shell cmd uimode night "$([ "$theme" = dark ] && echo yes || echo no)" > /dev/null 2>&1
    for sz in "170 170" "364 170" "364 382" "290 430" "364 430"; do
      set -- $sz
      adb shell am force-stop "$PKG"
      adb shell am start -n "$PKG/.WidgetPreviewActivity" --ei w $1 --ei h $2 --es theme $theme --ei scenario 5 > "$OUT/start-$theme-$1x$2.txt" 2>&1
      sleep 6
      if ! adb shell dumpsys activity activities | grep -q "WidgetPreviewActivity"; then echo "FAIL preview activity did not start ($theme $1x$2)" >> "$res"; fi
      adb exec-out screencap -p > "$OUT/screen-$theme-$1x$2.png" 2>/dev/null
    done
    adb logcat -d -s AndroidRuntime:E > "$OUT/crash-$theme.txt" 2>/dev/null
    if [ -s "$OUT/crash-$theme.txt" ] && grep -q "FATAL" "$OUT/crash-$theme.txt"; then echo "FAIL crash while drawing ($theme)" >> "$res"; else echo "PASS drawn without a crash ($theme)" >> "$res"; fi
  done
  mkdir -p "$OUT/sheets" && adb pull /sdcard/Android/data/$PKG/files/widget-previews/. "$OUT/sheets" > /dev/null 2>&1
  ls "$OUT/sheets" | wc -l >> "$res"
  adb shell cmd uimode night no > /dev/null 2>&1
  cat "$res"
  grep -q "^FAIL" "$res" && exit 1
  exit 0
fi
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
  # Wait until the page has really painted. A cold start on a CI emulator is slow (the first paint
  # came at ~35-40 s in runs 18 and 19; before it the WebView shows the window background), and a
  # screenshot of that background "passes" every edge test while proving nothing. What decides is
  # the screenshot itself: tools/edge-pixels.py reports the share of the screen that is not the
  # page's background, and a painted page is well above 1% (a blank one is 0.0).
  wait_page() {
    local i
    for i in $(seq 1 "${1:-30}"); do
      adb exec-out screencap -p > "$OUT/.wait.png" 2>/dev/null
      if python3 "$REPO/tools/edge-pixels.py" "$OUT/.wait.png" light "$OUT/.wait.json" > /dev/null 2>&1 &&
         python3 -c "import json,sys; sys.exit(0 if json.load(open('$OUT/.wait.json'))['ink_ratio'] > 0.01 else 1)"; then
        echo "page painted after $((i * 5))s"
        return 0
      fi
      sleep 5
    done
    echo "page did not paint within $(( ${1:-30} * 5 ))s"
    return 1
  }
  # Rotate the emulator. `settings put system user_rotation` alone did nothing on API 36 (the
  # screenshots of the "landscape" pass were 1080x2400, run 20), so the window manager is asked
  # directly, and the result is confirmed by the screenshot's own shape.
  rotate() { # $1 = 1 landscape, 0 portrait
    adb shell settings put system accelerometer_rotation 0 > /dev/null 2>&1
    adb shell settings put system user_rotation "$1" > /dev/null 2>&1
    adb shell cmd window user-rotation lock "$1" > /dev/null 2>&1
    local i
    for i in $(seq 1 10); do
      sleep 3
      adb exec-out screencap -p > "$OUT/.rot.png" 2>/dev/null
      local shape
      shape=$(python3 -c "from PIL import Image; im=Image.open('$OUT/.rot.png'); print('land' if im.width > im.height else 'port')" 2>/dev/null)
      if [ "$1" = 1 ] && [ "$shape" = land ]; then return 0; fi
      if [ "$1" = 0 ] && [ "$shape" = port ]; then return 0; fi
    done
    return 1
  }
  measure() { # $1 = name, $2 = light|dark, $3 = port|land (the orientation the shot must be)
    adb shell cmd uimode night "$([ "$2" = dark ] && echo yes || echo no)" > /dev/null 2>&1
    launch 8
    # Rotate AFTER the launch: a fresh activity start put the emulator back to portrait in run 24,
    # so a rotation taken before it was gone by the time the screenshot was made (the light
    # landscape shot there is 1080x2400 and passed only because a portrait shot skips the left/right
    # checks). The orientation is then part of the verdict, not an assumption.
    if [ "${3:-port}" = land ] && ! rotate 1; then ko "$1: the emulator never turned landscape"; fi
    wait_page 30 || ko "$1: the page never painted"
    sleep 3
    adb exec-out screencap -p > "$OUT/edge-$1.png"
    python3 "$REPO/tools/edge-pixels.py" "$OUT/edge-$1.png" "$2" "$OUT/edge-$1.json" > /dev/null
    eval "$(python3 - "$OUT/edge-$1.json" <<'PY'
import json, sys
v = json.load(open(sys.argv[1]))
for k in ("edge_to_edge", "frame_top", "frame_bottom", "top_color", "bottom_color", "page_bg",
          "top_matches_page", "bottom_matches_page", "top_row_uniform", "frame_left", "frame_right",
          "landscape", "text_top", "status_rows", "empty_page", "ink_ratio"):
    print("v_%s=%s" % (k, str(v[k]).lower()))   # booleans as the shell compares them
PY
)"
    echo "$1: page_bg=$v_page_bg status_bar_rows=$v_status_rows top_bar_text=$v_text_top ink=$v_ink_ratio" >> "$res"
    # 0. The screenshot must be the page, not its background: a blank page would satisfy every edge
    #    test below (the only ink on it is the status bar's own clock). A cold start on a CI emulator
    #    painted its first frame after ~40 s in run 18.
    [ "$v_empty_page" = false ] && ok "$1: the page has painted (content, not just the background)" || ko "$1: the screenshot is an empty page ($v_page_bg) — nothing to judge"
    # 1. The page must reach both edges: no flat painted band at the top or the bottom, and the very
    #    first row of the screen must be the page's own background.
    [ "$v_frame_top" = 0 ] && ok "$1: the page reaches the top edge (no painted strip)" || ko "$1: $v_frame_top px of a strip at the top (top_color $v_top_color, page $v_page_bg)"
    [ "$v_frame_bottom" = 0 ] && ok "$1: the page reaches the bottom edge" || ko "$1: $v_frame_bottom px of a strip at the bottom (bottom_color $v_bottom_color, page $v_page_bg)"
    [ "$v_top_matches_page" = true ] && ok "$1: the first row of the screen is the page's own background ($v_page_bg)" || ko "$1: the first row is $v_top_color, not the page's $v_page_bg"
    [ "$v_edge_to_edge" = true ] && ok "$1: edge to edge (page background $v_page_bg)" || ko "$1: not edge to edge"
    # 2. The status bar shows the page and nothing but the system's own glyphs: its top rows are one
    #    colour (the page's background) all the way across. Page content there — a heading, the search
    #    field of a top bar that ignored the inset — breaks that up, and the clock covers it.
    [ "$v_top_row_uniform" = true ] && ok "$1: nothing of the page is drawn inside the status bar" || ko "$1: the status bar rows are not uniform — page content is under the clock"
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
    # 3b. ... and not far below it either: the padding must be the status bar's height, not more
    #     (that is the owner's "отступ слишком большой" — the plugin had reported 52 CSS px for a
    #     22 px drawn bar). The bar's own text starts right under it: 10px of its padding plus the
    #     glyph's ascent, so a gap over ~45 device px means the page was over-padded.
    if [ -n "$v_text_top" ] && [ "$v_text_top" != None ] && [ -n "$v_status_rows" ]; then
      gap=$((v_text_top - v_status_rows))
      if [ "$gap" -le 45 ]; then
        ok "$1: the top bar sits right below the status bar (gap ${gap}px), not a strip lower"
      else
        ko "$1: the top bar starts ${gap}px below the status bar — over-padded"
      fi
    fi

    # 4. Landscape: the camera cutout is on a side there, so the left and right edges are checked
    #    too. A landscape pass whose screenshot is portrait is not evidence of anything: it is a
    #    failure of the rotation, never a pass.
    if [ "${3:-port}" = land ]; then
      if [ "$v_landscape" = true ]; then
        ok "$1: the shot really is landscape ($(python3 -c "from PIL import Image;im=Image.open('$OUT/edge-$1.png');print(f'{im.width}x{im.height}')"))"
        [ "$v_frame_left" = 0 ] && ok "$1: the page reaches the left edge (no cutout strip)" || ko "$1: $v_frame_left px of a strip at the left"
        [ "$v_frame_right" = 0 ] && ok "$1: the page reaches the right edge" || ko "$1: $v_frame_right px of a strip at the right"
      else
        ko "$1: the screenshot is NOT landscape — the emulator did not rotate, nothing was proved"
      fi
    fi
  }
  adb shell settings put system accelerometer_rotation 0 > /dev/null 2>&1
  adb shell cmd window user-rotation lock 0 > /dev/null 2>&1
  adb logcat -c 2>/dev/null || true
  adb shell settings put system accelerometer_rotation 0
  adb shell settings put system user_rotation 0
  adb shell pm clear "$PKG" > /dev/null 2>&1 || true   # first run: the default light theme, no stored state
  measure light light
  measure dark dark
  # Landscape, on the owner's word ("собери сразу с пейзаж портрет"): the wide layout is measured
  # again, sides included (a cutout or a side navigation bar moves the insets there).
  adb shell cmd uimode night no > /dev/null 2>&1
  measure landscape-light light land
  rotate 0 || true
  launch 8; wait_page 30 || true
  adb shell cmd uimode night yes > /dev/null 2>&1
  sleep 3
  measure landscape-dark dark land
  rotate 0 || true
  adb shell cmd uimode night no > /dev/null 2>&1
  #
  # The tablet case (owner: "а андроид с планшетный сможешь сделать?") is taken on THIS emulator by
  # resizing its display to a tablet's CSS size — 1600x2560 at density 2 (800x1280 CSS px is what a
  # 10" tablet gives a page). The pixel_tablet system image never came up on the runner twice (a
  # corrupt download, "Error on ZipFile unknown archive"), and the layout question is about the
  # page's CSS width, not about the machine.
  tablet_pass() {
    adb shell wm size 1600x2560 > /dev/null 2>&1
    adb shell wm density 320 > /dev/null 2>&1
    sleep 6
    measure tablet-light light
    # the burger menu at tablet width: the same page's-own-numbers check as on the phone
    adb shell am force-stop "$PKG"
    adb shell am start -W -n "$PKG/gift.dhamma.uposatha.MainActivity" -a android.intent.action.MAIN --es route "/?drawer=1" > /dev/null
    wait_page 30 || true
    sleep 3
    adb exec-out screencap -p > "$OUT/edge-tablet-drawer.png"
    adb shell run-as "$PKG" cat files/site/dg-edgetoedge.json > "$OUT/dg-edgetoedge-tablet.json" 2>/dev/null || true
    if [ -s "$OUT/dg-edgetoedge-tablet.json" ]; then
      if python3 - "$OUT/dg-edgetoedge-tablet.json" <<'TEOF' | tee -a "$res"
import json, sys
d = json.load(open(sys.argv[1]))
ok = True
def check(cond, text):
    global ok
    print(("PASS " if cond else "FAIL ") + text)
    ok = ok and cond
check(d.get("drawerOpen") is True, "tablet: the burger menu is really open")
# dg-apps#54: the inset reaches the page only where SystemBars passes it through (WebView 140+); on an older
# WebView the window is padded natively and the page rightly gets 0 (the pixel checks above see the bar clear
# of the clock either way). What must hold in both: the menu's content is not above the inset the page has.
top, drawer = d.get("topInset"), d.get("drawerContentTop")
check(top == 0 or (top or 0) >= 20, "tablet: the page's inset is the status bar's or none (window padded): %s px" % top)
check(drawer is not None and top is not None and drawer >= top,
      "tablet: the drawer's content starts at %s px, at or below the inset %s px" % (drawer, top))
sys.exit(0 if ok else 1)
TEOF
      then :; else fail=1; fi
    else
      ko "tablet: no report from the page"
    fi
    adb shell wm size reset > /dev/null 2>&1
    adb shell wm density reset > /dev/null 2>&1
    sleep 4
  }
  tablet_pass || ko "tablet: the resized pass did not run"
  TABLET=yes

  # A short tour for the video: the app layer, a tab, then the dark theme (the page follows the
  # system appearance through prefers-color-scheme, so the same path a reader takes is exercised).
  launch 8; wait_page 30 || true
  adb shell input tap 250 1790; sleep 4     # the Calendar tab
  adb shell input swipe 540 700 540 1500 300; sleep 3
  adb shell cmd uimode night yes > /dev/null 2>&1; sleep 3
  adb exec-out screencap -p > "$OUT/edge-light-to-dark.png"
  launch 8; wait_page 30 || true
  adb shell input tap 250 1790; sleep 4     # the Calendar tab, on the dark page
  adb shell input keyevent KEYCODE_HOME; sleep 2
  stop_rec
  [ -s "$OUT/flow.mp4" ] && echo "video: flow.mp4 ($(du -h "$OUT/flow.mp4" | cut -f1))" >> "$res"
  echo "tablet_profile=$TABLET" >> "$res"
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
# The library download in the background (issue #62): start it, send the app away, and read the foreground service's own
# notification while the page cannot run. PASS when the byte count grows between samples (or the "downloaded" message
# appears) with the app in the background; the app is then reopened so the import by the page can be seen.
if [ "${4:-}" = download ] && [ "$PKG" = gift.dhamma.mobile ]; then
  res="$OUT/download-result.txt"; : > "$res"; fail=0
  ok() { echo "PASS $*" >> "$res"; }; ko() { echo "FAIL $*" >> "$res"; fail=1; }
  adb logcat -c
  adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS 2>/dev/null
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null; sleep 18
  adb exec-out screencap -p > "$OUT/download-0-consent.png"
  adb shell input tap 768 2184; sleep 3                       # "Download" on the offline-library sheet
  adb shell input keyevent KEYCODE_HOME; sleep 2              # the app is in the background from here on
  state() { adb shell dumpsys notification --noredact | grep -oE "(Downloading the offline library[^\"]*|The library is downloaded[^\"]*)" | tail -1; }
  prev=""; grew=0; finished=0
  # Up to 6 minutes in the background: long enough for the whole archive on a CI emulator, so the closing notification shows too.
  for i in $(seq 1 36); do
    sleep 10; cur=$(state); echo "t+$((i*10+5))s background: ${cur:-<no notification>}" >> "$res"
    case "$cur" in *downloaded*) finished=1; break ;; esac
    mb=$(echo "$cur" | grep -oE "[0-9]+ of" | grep -oE "[0-9]+"); pmb=$(echo "$prev" | grep -oE "[0-9]+ of" | grep -oE "[0-9]+")
    if [ -n "$mb" ] && [ -n "$pmb" ] && [ "$mb" -gt "$pmb" ]; then grew=1; fi
    prev="$cur"
  done
  adb shell cmd statusbar expand-notifications; sleep 2; adb exec-out screencap -p > "$OUT/download-1-shade-in-background.png"
  adb shell cmd statusbar collapse
  if [ "$grew" = 1 ]; then ok "the download goes on with the app in the background"; else ko "no progress in the background"; fi
  if [ "$finished" = 1 ]; then ok "the closing notification (\"The library is downloaded\") arrived with the app in the background"; else ko "no closing notification within 6 minutes"; fi
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null; sleep 45
  adb exec-out screencap -p > "$OUT/download-2-reopened.png"
  # The page unpacks the archive into its storage; when it is done the notification says the library is ready.
  ready=0
  for i in $(seq 1 24); do
    sleep 10; cur=$(adb shell dumpsys notification --noredact | grep -oE "(Unpacking and applying[^\"]*|The library is ready[^\"]*|damaged[^\"]*)" | tail -1)
    echo "after reopening +$((i*10))s: ${cur:-<none>}" >> "$res"
    case "$cur" in *ready*) ready=1; break ;; *damaged*) break ;; esac
  done
  adb exec-out screencap -p > "$OUT/download-3-ready.png"
  if [ "$ready" = 1 ]; then ok "the library was installed and the notification says it is ready"; else ko "no 'The library is ready' notification (see the lines above)"; fi
  adb logcat -d | grep -iE "dg-offline|DgDownload|FATAL" | tail -40 > "$OUT/download-logcat.txt"
  grep -qi "FATAL" "$OUT/download-logcat.txt" && ko "a crash is in the log" || ok "no crash in the log"
  cat "$res"; exit $fail
fi
if [ "${4:-}" = tray ] && [ "$PKG" = gift.dhamma.mobile ]; then
  # The notification player (Pause / Play on the shade) end to end, on the debug APK (tools/emu-tray.js reads the page over DevTools).
  adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS > /dev/null 2>&1
  adb logcat -c
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null; sleep 20
  adb shell input tap 309 2184; sleep 2
  adb shell am start -W -a android.intent.action.VIEW -d "https://dhamma.gift/sn56.11" "$PKG" > /dev/null; sleep 14
  pid=$(adb shell pidof "$PKG" | tr -d '\r' | awk '{print $1}')
  adb forward tcp:9222 "localabstract:webview_devtools_remote_${pid}"
  adb shell cat /proc/net/unix | grep -o 'webview_devtools_remote_[0-9]*' | head -3 > "$OUT/sockets.txt"
  adb exec-out screencap -p > "$OUT/tray-start.png"
  if [ "${TRAY_ENGINE:-audio}" = switch ]; then node "$REPO/tools/emu-switch.js" "$OUT"; code=$?   # another sutta opened in place while reading
  else node "$REPO/tools/emu-tray.js" "$OUT" "${TRAY_ENGINE:-audio}"; code=$?; fi
  adb logcat -d -s Capacitor/Console:* Capacitor:* DgTts:* > "$OUT/logcat.txt" 2>/dev/null || true
  adb logcat -d | grep -iE "DgTts|MEDIA_|mediasession|NotificationService.*dg|gift.dhamma.mobile.*(Exception|FATAL)" | head -60 > "$OUT/logcat-tray.txt" || true
  exit $code
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
  # The site pages the app carries itself (not the SPA): they must clear the status and gesture bars, in step with the theme.
  route memo/;               shot "$theme-8-memo" 8
  route login/;              shot "$theme-9-login" 8
  route assets/diff/;        shot "$theme-10-compare" 8
  route 4as;                 shot "$theme-11-quick-window" 8
  # The burger drawer over the home page: the clock and notification icons must stay on the strip (docs/ANDROID_INSETS.md).
  adb shell am force-stop "$PKG"; adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null
  sleep 12; adb shell input tap 309 2184; sleep 2
  adb shell input tap 990 203;  shot "$theme-12-drawer" 3
done
adb logcat -d -t 400 > "$OUT/logcat.txt" 2>/dev/null || true
ls -la "$OUT"
