#!/usr/bin/env bash
# The Dictionary's feature tour on an iOS simulator (test/ios-sim/featuretest): each XCUI test is one case, run on its own
# with the simulator's video recorded around it (<out>/NN-case.mp4); the screenshots the tests keep are exported next to it.
# Then what only a picture shows is judged here: the strip under the clock once the page is scrolled (it must be the page's
# own colour, no text running under the clock), and blank frames in the pull-to-refresh video. PASS/FAIL per case in
# <out>/results.txt; exits 1 if any case failed.
#
#   test/ios-sim/feature-tour.sh <App.app> <out-dir>        (from dict/; Xcode, xcodegen, python3 with Pillow, ffmpeg)
set -uo pipefail
APP="${1:?usage: feature-tour.sh <App.app> <out-dir>}"
OUT="${2:?usage: feature-tour.sh <App.app> <out-dir>}"
BUNDLE=gift.dhamma.pali
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT"
: > "$OUT/results.txt"

# An iPhone with the Dynamic Island (the status bar that ran over the page), the newest the runtime has.
UDID=$(xcrun simctl list devices available | grep -E "iPhone 1[5-9] Pro \(" | tail -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$UDID" ] || UDID=$(xcrun simctl list devices available | grep -E "iPhone" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
echo "feature-tour: device $(xcrun simctl list devices | grep "$UDID" | sed -E 's/^ *//')"
# The software keyboard, not the Mac's: the letters row lives on it.
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false 2>/dev/null || true
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
sleep 8

(cd "$HERE/featuretest" && xcodegen generate >/dev/null) || { echo "feature-tour: xcodegen failed"; exit 1; }
xcodebuild build-for-testing -project "$HERE/featuretest/DictFeatureTests.xcodeproj" -scheme DictFeatureTests \
  -destination "id=$UDID" -derivedDataPath "$HERE/featuretest/DerivedData" > "$OUT/tests-build.log" 2>&1 \
  || { echo "feature-tour: the tests did not build"; tail -40 "$OUT/tests-build.log"; exit 1; }

FAILED=0
CASES=$(grep -oE 'func (test[0-9]+_[A-Za-z]+)' "$HERE/featuretest/Tests/DictFeatureTests.swift" | awk '{print $2}')
for c in $CASES; do
  name=$(echo "$c" | sed -E 's/^test([0-9]+)_(.*)$/\1-\2/')
  echo "=== $name"
  case "$c" in *Dark*) xcrun simctl ui "$UDID" appearance dark; sleep 2 ;; *QuickActions*) xcrun simctl ui "$UDID" appearance light ;; esac
  xcrun simctl io "$UDID" recordVideo --codec h264 --force "$OUT/$name.mp4" >/dev/null 2>&1 &
  rec=$!
  sleep 2
  rm -rf "$OUT/$name.xcresult"
  xcodebuild test-without-building -project "$HERE/featuretest/DictFeatureTests.xcodeproj" -scheme DictFeatureTests \
    -destination "id=$UDID" -derivedDataPath "$HERE/featuretest/DerivedData" \
    -only-testing:"DictFeatureTests/DictFeatureTests/$c" -resultBundlePath "$OUT/$name.xcresult" > "$OUT/$name.log" 2>&1
  code=$?
  sleep 1
  kill -INT "$rec" 2>/dev/null; wait "$rec" 2>/dev/null
  mkdir -p "$OUT/att-$name"
  xcrun xcresulttool export attachments --path "$OUT/$name.xcresult" --output-path "$OUT/att-$name" >/dev/null 2>&1 || true
  # The attachments come out under generated names; manifest.json says which is which.
  python3 - "$OUT/att-$name" "$OUT" <<'PY' || true
import json, os, shutil, sys
d, out = sys.argv[1], sys.argv[2]
try: m = json.load(open(os.path.join(d, 'manifest.json')))
except Exception: sys.exit(0)
for t in m:
    for a in t.get('attachments', []):
        name = (a.get('suggestedHumanReadableName') or a.get('name') or '').split('_')[0]
        src = os.path.join(d, a.get('exportedFileName', ''))
        if name and os.path.exists(src):
            ext = os.path.splitext(src)[1] or '.png'
            shutil.copy(src, os.path.join(out, name if name.endswith(ext) else name + ext))
PY
  why=$(grep -E "error: -\[|XCTAssert|failed -|: error:" "$OUT/$name.log" | head -3 | sed -E 's/^.*error: //' | tr '\n' ' ')
  if [ $code -eq 0 ]; then echo "PASS $name" | tee -a "$OUT/results.txt"
  else echo "FAIL $name: ${why:-xcodebuild exit $code}" | tee -a "$OUT/results.txt"; FAILED=1; fi
done

# The strip under the clock, scrolled: the band between the Dynamic Island and the bottom of the status bar must be one colour
# (the page's own strip), not lines of text passing under it.
if [ -f "$OUT/04-scrolled.png" ]; then
  python3 - "$OUT/04-scrolled.png" <<'PY' | tee -a "$OUT/results.txt" || FAILED=1
import sys
from PIL import Image, ImageStat
im = Image.open(sys.argv[1]).convert('L'); w, h = im.size
s = w / 393.0                                  # points to pixels (an iPhone Pro is 393 pt wide)
band = im.crop((int(w * 0.08), int(40 * s), int(w * 0.92), int(52 * s)))
sd = ImageStat.Stat(band).stddev[0]
ok = sd < 6
print(('PASS' if ok else 'FAIL') + ' 04-strip-under-the-clock: luminance spread %.1f under the status bar (text there reads > 6)' % sd)
sys.exit(0 if ok else 1)
PY
fi

# The caret after scrolling down and back up: the blue caret (iOS's tint) must be inside the search box's frame. The box's frame
# comes from the test as text, in points; the screenshots are in pixels (3x on an iPhone Pro). The caret blinks, so any of the
# four screenshots that shows it counts.
if ls "$OUT"/06-caret-*.png >/dev/null 2>&1; then
  FRAME=$(cat "$OUT/att-06-CaretAfterScrollingDownAndUp"/*.txt 2>/dev/null | head -1)
  python3 - "$FRAME" "$OUT"/06-caret-*.png <<'PY' | tee -a "$OUT/results.txt" || FAILED=1
import sys
from PIL import Image
try: x1, y1, x2, y2 = map(float, sys.argv[1].split())
except Exception: print('FAIL 06-caret-in-the-box: no box frame from the test'); sys.exit(1)
seen = []
for f in sys.argv[2:]:
    im = Image.open(f).convert('RGB'); w, h = im.size; s = float(round(w / 400.0))   # the screen's scale: 3 on every iPhone Pro
    px = im.load(); pts = [(x, y) for y in range(0, int(h * 0.3)) for x in range(0, w, 1) if (lambda r, g, b: b > 200 and r < 90 and 90 < g < 170)(*px[x, y])]
    if pts:
        xs = [p[0] / s for p in pts]; ys = [p[1] / s for p in pts]
        seen.append((min(xs), min(ys), max(xs), max(ys)))
if not seen: print('FAIL 06-caret-in-the-box: no caret in the screenshots'); sys.exit(1)
cx1, cy1, cx2, cy2 = seen[0]
ok = x1 - 2 <= cx1 and cx2 <= x2 + 2 and y1 - 2 <= cy1 and cy2 <= y2 + 2
print(('PASS' if ok else 'FAIL') + ' 06-caret-in-the-box: caret at %.0f,%.0f-%.0f,%.0f pt, box %.0f,%.0f-%.0f,%.0f pt' % (cx1, cy1, cx2, cy2, x1, y1, x2, y2))
sys.exit(0 if ok else 1)
PY
fi

# Pull to refresh: no blank frame. A frame is blank when the page area (below the status bar) is all one colour.
if [ -f "$OUT/05-PullToRefresh.mp4" ] && command -v ffmpeg >/dev/null; then
  rm -rf "$OUT/.frames" && mkdir -p "$OUT/.frames"
  ffmpeg -loglevel error -i "$OUT/05-PullToRefresh.mp4" -vf "fps=30,scale=200:-1" "$OUT/.frames/%04d.png"
  python3 - "$OUT/.frames" <<'PY' | tee -a "$OUT/results.txt" || FAILED=1
import glob, sys
from PIL import Image, ImageStat
fs = sorted(glob.glob(sys.argv[1] + '/*.png'))
blank = []
for i, f in enumerate(fs):
    im = Image.open(f).convert('L'); w, h = im.size
    sd = ImageStat.Stat(im.crop((0, int(h * 0.12), w, int(h * 0.9)))).stddev[0]
    if sd < 3: blank.append(i)
ok = not blank
print(('PASS' if ok else 'FAIL') + ' 05-refresh-no-blank-frame: %d of %d frames blank%s' % (len(blank), len(fs), (' (at %s)' % blank[:10]) if blank else ''))
sys.exit(0 if ok else 1)
PY
fi

echo; cat "$OUT/results.txt"
[ $FAILED = 0 ] || { echo "::error::dictionary iOS feature tour: some cases failed (results.txt)"; exit 1; }
