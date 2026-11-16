#!/bin/bash
# The Xcode project of one app carries the version in its version.properties (MARKETING_VERSION, for a build from Xcode on
# a Mac; CI passes the version to xcodebuild). Run by that app's first iOS job only: a wrong iOS version stops the iOS path,
# never Play (owner 2026-11-16: the unit job held this check and kept 1.21 out of Play).
# Usage: check-ios-version.sh <app dir: . | dict | uposatha>
set -euo pipefail
app=${1:?app dir}
v=$(sed -n 's/^ios=//p' "$app/version.properties")
[ -n "$v" ] || v=$(sed -n 's/^version=//p' "$app/version.properties")
[ -n "$v" ] || { echo "::error::$app/version.properties has no version="; exit 1; }
bad=$(grep -oE 'MARKETING_VERSION = [^;]+' "$app/ios/App/App.xcodeproj/project.pbxproj" | sort -u | grep -vxF "MARKETING_VERSION = $v" || true)
[ -z "$bad" ] || { echo "::error::$app: the Xcode project says '$bad', version.properties says $v"; exit 1; }
echo "$app: ios $v"
