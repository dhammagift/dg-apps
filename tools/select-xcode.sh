#!/bin/bash
# Selects the Xcode every iOS job builds with: the newest Xcode 26 on the runner that is NOT a beta.
# By glob rather than an exact path, because the macos-26 image's set changes between releases and a
# hardcoded /Applications/Xcode_26.6.app would break the day it moves on. Betas are left out: Apple
# refuses App Store and external TestFlight builds made with a beta Xcode, and an image that adds
# Xcode_26.x_beta would otherwise be picked first by the version sort.
# The choice goes into the job summary, so which Xcode built a release is on the run page.
set -euo pipefail
XCODE=$( (ls -d /Applications/Xcode_26*.app 2>/dev/null || true) | (grep -vi beta || true) | sort -V | tail -1)
[ -n "$XCODE" ] || { echo "::error::no non-beta Xcode 26 on this runner"; ls -d /Applications/Xcode*.app; exit 1; }
echo "Using $XCODE"
sudo xcode-select -s "$XCODE"
xcodebuild -version
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '%s: %s (%s)\n\n' "${GITHUB_JOB:-job}" "$(basename "$XCODE")" "$(xcodebuild -version | tr '\n' ' ' | sed 's/ *$//')" >> "$GITHUB_STEP_SUMMARY"
fi
