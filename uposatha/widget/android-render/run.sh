#!/bin/bash
# The real widgets drawn without a phone (the app's own code builds the RemoteViews, Android's own classes inflate and draw them).
#   run.sh '<regex of case names, a full match>' [light|dark]   PNGs of WidgetSheet.cases() into $WIDGET_OUT (default: out/ here)
#   run.sh --reapply                                            the check that a redraw onto existing views equals a fresh widget
# Needs ANDROID_HOME and a JDK; Robolectric and its Android jar come from the Gradle cache (the first run downloads them).
here="$(cd "$(dirname "$0")" && pwd)"
export WIDGET_ROBO_DIR="$here"
if [ "$1" = "--reapply" ]; then export WIDGET_ONLY=none WIDGET_REAPPLY=1; else export WIDGET_ONLY="$1" WIDGET_THEME="$2"; fi
cd "$here/../../android" && ./gradlew -I "$here/init.gradle" :app:testDebugUnitTest ${WIDGET_GRADLE_ARGS:---offline} -q 2>&1 | grep -v "^\s*at " | grep -i "FAILED\|error:\|exception\|RENDERED\|REAPPLY" | cut -c1-2000
