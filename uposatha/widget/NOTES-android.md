# Android widget: what was built (uposatha/android)

Package `gift.dhamma.uposatha`. Not committed, no CI. Builds: `:app:assembleDebug` and `:app:assembleRelease` both green, `:app:testDebugUnitTest` green.
APKs: `uposatha/android/app/build/outputs/apk/debug/app-debug.apk` (9.6 MB), `.../release/app-release-unsigned.apk` (6.2 MB).

## Files (all under `android/app/src/`)
main/java/gift/dhamma/uposatha/
- `DgWidgetPlugin.java` - Capacitor plugin `DgWidget.put({json})`: validates the JSON, stores it (SharedPreferences `dg_widget`, key `data`), redraws all widgets, re-plans updates. Registered in `MainActivity` (one line, after DgSharePlugin).
- `WidgetProvider.java` - the AppWidgetProvider: size class from launcher options, both themes drawn, RemoteViews, taps, the one alarm that plans redraws, per-widget layer (`layer_<id>` in the same prefs).
- `WidgetRenderer.java` - `render(Context, JSONObject, layer, widthDp, heightDp, dark, nowMs)` -> Bitmap (all three layers x three sizes, placeholder, moon with the double shadow, rim, edge darkening, dark-theme halo, `south` = 180 degrees). Everything in dp on a scaled canvas, designer's numbers from widget.html.
- `WidgetModel.java` - the data placed against "now" (current/next Uposatha, kala/vikala, part of the day, next event); `parse()` returns null = placeholder (no data, generatedAt older than 14 days, today not covered). No moon/sun maths.
- `WidgetText.java` (strings.json from `res/raw/widget_strings.json`, unchanged), `WidgetFormat.java` (pure helpers: counter "1 d 7 h", "1 h 34 min", kala line, dates, plurals).
main/res: `layout/widget_{s,m,l}.xml`, `widget_images.xml` (+ `layout-night/widget_images.xml`), `widget_grid.xml`, `widget_loading.xml`, `widget_preview.xml`; `xml/widget_info.xml`; `drawable/widget_preview.xml`; `drawable-nodpi/moon_nasa.png`; `raw/widget_strings.json`; `values/widget_dimens.xml`, `values{,-ru}/widget_strings.xml`; `assets/widget/lato-{400,600,700}.ttf` (the prod Lato woff2, converted with fontTools and cut to latin/cyrillic/Pali, ~190 KB each).
main/AndroidManifest.xml - one `<receiver .WidgetProvider>` (not exported; actions APPWIDGET_UPDATE, BOOT_COMPLETED, MY_PACKAGE_REPLACED, TIME_SET, TIMEZONE_CHANGED). DgAlarmReceiver untouched. No new permissions.
debug/ (NOT in release, checked in the release manifest): `AndroidManifest.xml`, `java/.../WidgetPreviewActivity.java`, `assets/widget-sample.json` (fixture-ru), `assets/widget-sample-en.json` (lang en, detail, place set).
test/java/.../WidgetFormatTest.java - JUnit for the pure helpers ("1 d 7 h", "20 h", "Kala until 12:41 · 1 h 34 min left", calendar, plurals).
Backups: `~/claudeBak/uposatha-MainActivity.java`, `uposatha-AndroidManifest.xml`, `uposatha-app-build.gradle` (build.gradle ended unchanged).

## How to test
- On an emulator/device (debug APK): `adb shell am start -n gift.dhamma.uposatha/.WidgetPreviewActivity` - scrolling list of 6 scenarios x size (s/m/l) x light/dark x layer. Filters: `--es size m --es theme dark --ei layer 1 --ei scenario 2`. PNGs of everything also go to `/sdcard/Android/data/gift.dhamma.uposatha/files/widget-previews/` (`adb pull`).
- Real widget: long-press the home screen, "Uposatha". Open the app once so the page calls `DgWidget.put`. Tap the dots to cycle, tap a day number in the month layer (medium/large) to open the calendar on `&day=`.
- Without a phone: `uposatha/widget/android-render/` holds the Robolectric (native graphics) render test I used here to look at every layer as PNG (`WidgetRenderTest.java.txt`, `sheet.py`). It is NOT in the build (needs `testImplementation org.robolectric:robolectric:4.14.1`, `testOptions.unitTests.includeAndroidResources = true`; on this aarch64 box it only ran with an x86_64 JDK 21 under qemu plus `-Xshare:off -XX:+UseSerialGC -XX:TieredStopAtLevel=1`). All the visual checks of this work were made with it (fixture-ru in 5 scenarios x 4 sizes x 3 layers x light/dark + placeholders).
- Build env on this box: `export QEMU_LD_PREFIX=/usr/x86_64-linux-gnu ANDROID_HOME=/opt/android-sdk JAVA_HOME=/usr/lib/jvm/java-21-openjdk-arm64` (Capacitor 8 needs JDK 21, I installed `openjdk-21-jdk-headless`; JDK 17 alone fails; aapt2 is x86_64, hence QEMU_LD_PREFIX). `android/local.properties` (sdk.dir) is gitignored; `npx cap sync android` was run (generated files are gitignored).

## Decisions where the spec was ambiguous
- Layer switching: dots strip = the bottom 48 dp (medium/small) / 64 dp (large) over the whole width, not the full "lower third" (on a 4x4 a third would swallow the list and the month). In the month layer the day cells sit above the strip and win where they overlap.
- Both themes are drawn and both images are in the RemoteViews; `layout-night/widget_images.xml` picks the one for the launcher's theme, so a theme switch needs no redraw. Cost: 2 bitmaps per widget (scale capped 2.6, <= 1.4 M px).
- Size class from the launcher's size (portrait: min width x max height; landscape: max width x min height): width < 280 dp small; else height >= 240 dp large; else medium. Real Android 4x2 is ~130 dp, not the design's 170: short medium widgets drop the second detail line, then the first, and move the dots lower; short large ones shrink the hero and show as many "next" rows (1-3) / parts (3 of the current half or all 6) as fit.
- Month grid: equal-weight rows; the click overlay's padding is set from the same `WidgetRenderer.monthGeo` numbers as the drawing. Months with 4/5 weeks hide the unused rows. Large rows max 33 dp. Small 2x2 month shows two weeks (the one with today and the next) as in the mock, one tap target.
- Uposatha cell colouring uses the data: a solid cell only when `start.ymd != day` (the evening before), the day as the light band joined to it; when `start.ymd == day` (the fixture, no place) the day is a single light pill. Counts "N Uposathas" = those in the data for the month (the data starts 2 days back, so early in a month past ones are not counted).
- "ends — Tue 27, dawn 07:31": the word "dawn/рассвет" is dropped when the page's `end` is after noon (it is an evening in the fixture); the page is the source of truth.
- "ещё 1 ч 34 мин" is drawn into the picture (no Chronometer), rounded up to a minute; refreshed every 15 min and at the counter's own hour flips. So it can be up to 15 min behind between redraws. Kala/vikala switch at noon / next aruna comes from an event alarm.
- Alarm: ONE chain; next = min(next quarter hour, the counter's next change, next event in the data: aruna/sunrise/noon/sunset, part borders, Uposatha start/end). RTC (not wake-up): a sleeping phone is not woken, the overdue alarm redraws on wake. `setAndAllowWhileIdle` for ticks; events use `setExactAndAllowWhileIdle` only if `canScheduleExactAlarms()` (USE_EXACT_ALARM already in the manifest for the reminders), else inexact. Nothing new in the manifest.
- Layer 2 (Day & night) needs the part of the day; right after midnight, if the data was made after midnight (days[0] = today, no yesterday), the part is unknown and layer 2 shows the placeholder until dawn (layer 1 and 3 still work: vikala until aruna[0]). Suggest the page starts `days` from yesterday.
- Placeholder texts (not in strings.json): "Open Uposatha" + "To set up the widget" / "The data is out of date"; ru: "Откройте Uposatha" + "Нужны данные для виджета" / "Данные устарели". Language: data's `settings.lang`, else the system language.
- No-place tap: spec says it should open the place setting; no such route exists, so it opens `tab=home`.
- Moon glow in dark: the design token mix is nearly invisible on #191919, so a faint warm light halo (alpha 5..25 % by illumination) is drawn.

## Known gaps
- Never seen on a real launcher/emulator by me (only Robolectric PNGs): please screenshot the debug activity and a real widget (RemoteViews `<include>` of a `<merge>`, `layout-night`, `setViewPadding` of the grid are the things to watch).
- Text does not follow the system font scale (fixed dp).
- `previewLayout`/`previewImage` are a simple static card (not a render of the real thing).
- Month day tap on an Uposatha day opens `&day=` only (the page decides about "details"); the page must read `?day=`.
- The data must come from `window.__upoWidgetData()` as in WIDGET.md; `aruna` is used for kala/vikala (falls back to sunrise if missing).
