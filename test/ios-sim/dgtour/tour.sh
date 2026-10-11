#!/usr/bin/env bash
# Dhamma.Gift's video tour on the booted iOS simulator (DgTourTests.swift): one recording around both tests, light then
# dark (<out>/dg-tour.mp4), and the screenshots the tests keep, exported as <out>/tour-NN-*.png. Run after drive.sh has
# installed the app with the library (build-app.yml, job ios-ui). For a person to look at, not a verdict: it reports
# what ran and exits 0 unless nothing could run at all.
#
#   test/ios-sim/dgtour/tour.sh <out-dir>        (from the repository root; Xcode, xcodegen, python3)
set -uo pipefail
OUT="${1:?usage: tour.sh <out-dir>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT"

UDID=$(xcrun simctl list devices booted | grep -o '[0-9A-F-]\{36\}' | head -1)
[ -n "$UDID" ] || { echo "dg-tour: no booted simulator"; exit 1; }
command -v xcodegen >/dev/null || brew install xcodegen >/dev/null 2>&1
(cd "$HERE" && xcodegen generate >/dev/null) || { echo "dg-tour: xcodegen failed"; exit 1; }
xcodebuild build-for-testing -project "$HERE/DgTourTests.xcodeproj" -scheme DgTourTests \
  -destination "id=$UDID" -derivedDataPath "$HERE/DerivedData" CODE_SIGNING_ALLOWED=NO > "$OUT/dg-tour-build.log" 2>&1 \
  || { echo "dg-tour: the tests did not build"; tail -40 "$OUT/dg-tour-build.log"; exit 1; }

xcrun simctl ui "$UDID" appearance light
xcrun simctl io "$UDID" recordVideo --codec h264 --force "$OUT/dg-tour.mp4" >/dev/null 2>&1 &
rec=$!
sleep 2

run() {
  rm -rf "$OUT/dg-tour-$1.xcresult"
  xcodebuild test-without-building -project "$HERE/DgTourTests.xcodeproj" -scheme DgTourTests \
    -destination "id=$UDID" -derivedDataPath "$HERE/DerivedData" \
    -only-testing:"DgTourTests/DgTourTests/$1" -resultBundlePath "$OUT/dg-tour-$1.xcresult" > "$OUT/dg-tour-$1.log" 2>&1
  echo "dg-tour: $1 exit $?"
  grep -E "error: -\[|failed -" "$OUT/dg-tour-$1.log" | head -5 | sed -E 's/^.*error: /  /'
  mkdir -p "$OUT/.att-$1"
  xcrun xcresulttool export attachments --path "$OUT/dg-tour-$1.xcresult" --output-path "$OUT/.att-$1" >/dev/null 2>&1 || true
  # The attachments come out under generated names; manifest.json says which is which (as dict/test/ios-sim/feature-tour.sh).
  python3 - "$OUT/.att-$1" "$OUT" <<'PY' || true
import json, os, shutil, sys
d, out = sys.argv[1], sys.argv[2]
try: m = json.load(open(os.path.join(d, 'manifest.json')))
except Exception: sys.exit(0)
for t in m:
    for a in t.get('attachments', []):
        name = (a.get('suggestedHumanReadableName') or a.get('name') or '').split('_')[0]
        src = os.path.join(d, a.get('exportedFileName', ''))
        if name and os.path.exists(src): shutil.copy(src, os.path.join(out, name if name.endswith('.png') else name + '.png'))
PY
}

run test1_Light
xcrun simctl ui "$UDID" appearance dark
sleep 2
run test2_Dark
sleep 1
kill -INT "$rec" 2>/dev/null; wait "$rec" 2>/dev/null
ls -la "$OUT"/dg-tour.mp4 "$OUT"/tour-*.png 2>/dev/null
[ -s "$OUT/dg-tour.mp4" ] || { echo "dg-tour: no video recorded"; exit 1; }
