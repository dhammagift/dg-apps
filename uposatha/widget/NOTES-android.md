# Android widgets: v2 (2026-10-10) - seven widgets, each one design scaled to its cell

> This section is the current state. Everything below "Android widget: what was built" is the history of the first version (three sizes x three layers,
> WidgetRenderer, then w_l*_* layouts); its data flow, alarms and texts-from-strings.json parts still hold, its layouts and size classes are gone.

Mock-ups the owner approved: https://test.dhamma.gift/assets/shots/uposatha-widget-v2/index.html (source index.html in /var/www/html/assets/shots/uposatha-widget-v2/).
Why v2 (owner, 2026-10-10): the first version put three designs into one "super responsive" widget, the text differed between sizes, lines were cut with "...",
and a big cell showed small text on a white card. Reference the owner likes: Daff Moon (separate widgets, a widget stays itself when stretched).

## What it is
- Seven picker entries = `WidgetProvider.PROVIDERS` (WidgetPlan.MOON .. CAL): Moon 1x1, Moon + Uposatha 2x1, Uposatha 2x2 (`WidgetProviderSmall`), Uposatha 4x1,
  Uposatha 4x2 (`WidgetProviderMedium`), Day & night (2x2 by default), Calendar 4x4 (`WidgetProviderLarge`). Small/Medium/Large keep their class names: a widget
  of the first version that is on a screen stays and becomes the new one.
- Small widgets are one thing. The two big ones (4x2, 4x4) have three slides (Uposatha / Day & night / Calendar) with the switch strip at the bottom
  (left half back, right half forward; `layer_<id>` in the prefs; the 4x2 opens on Uposatha, the 4x4 on the calendar). Slides can be switched off per widget.
- ONE design per widget, written in "base dp" in `WidgetViews` (the sizes of the smallest cell it is meant for). For the cell the launcher gives, every line
  is measured with the real font (Lato via ResourcesCompat, `mw()`), the design's width and height are summed, and the whole design is scaled by
  `k = WidgetPlan.scale(...)`: text sizes, paddings, the moon. A bigger cell = the same widget, bigger; nothing is cut; spare height goes into the gaps (`WidgetPlan.gap`).
  The 2x2 has three arrangements of the SAME lines, chosen by what fits at k >= 1: the agreed wide one (1A / 1B: needs about 186 dp), stacked with date + time in
  one line, stacked in two lines (the owner's phone: a 5-column grid, a 2x2 is 145 x 215 dp).
- Real sizes come from the launcher (`OPTION_APPWIDGET_SIZES`, one RemoteViews per size; one size when the launcher refuses the map). No grid of guessed sizes any more.
- Layouts `res/layout/w2_*.xml` hold only the structure and are GENERATED: `python3 widget/tools/gen_android_res.py` (also the drawables in three colour sets and
  `widget_colors.xml`). Do not edit them by hand.
- Colours: theme "system" = colour resources with night variants, resolved by the launcher (instant on a theme switch; API 31+ also for run-time colours through
  `RemoteViews.setColor`); a forced theme (the widget's own setting) = fixed colours from `WidgetConfig.LIGHT_C / DARK_C` and the `_lt` / `_dk` drawables.
  The card is an ImageView (`w_bg`): its alpha is the widget's opacity, its colour filter the forced surface colour.
- Pictures: only the moon (`WidgetMoon`: earthshine night side instead of a black disc, the bitmap carries its own density so `wrap_content` shows it at the asked
  dp; hero pair light / dark by the alpha-dimen trick, `moon_x` for a forced theme; ONE neutral mini-moon for lists and calendar cells) and the day bar (`WidgetBar`).
- The widget's own settings: `WidgetConfigActivity` (`android:configure`, `reconfigurable|configuration_optional`: the launcher's gear; on Android 11 and older also
  when the widget is added). Theme, transparency of the card (slider), details and the kala line ("as in the app" / on / off), slides, the calendar's moon of every
  day and "next" list. Kept per widget id in the `dg_widget` prefs (`WidgetConfig`), removed in onDeleted. The real widget is shown on top and follows every choice.
- Calendar: tiles as in the app; an Uposatha's evening date = the number in a filled circle, its day = a light tile, today = the gold frame; mini-moons under
  Uposatha days (under every day with "moon of every day"; phases from the data's `moons`); the card of today; "Next" rows as the height allows
  (`WidgetPlan.cal`); the arrows turn the month inside the widget (0..+2 months, back to today the next day); a day opens the app's calendar on it.
- Wording: `design/strings.json` keys `w.*` (copied to `res/raw/widget_strings.json`); settings screen `cfg.*`.

## Lessons of the night (2026-10-10 / 11): what the owner found by hand and why nobody had seen it

Every one of these was on the owner's phone and in none of the "it passed" reports. The checks that find them now exist; run them.

- **A launcher redraws ONTO the views it has** (`RemoteViews.reapply`, when the layout id is the same). So whatever one state hides,
  colours or adds, the other state must set back. Three real bugs of this kind: the Moon's percent stayed hidden after it was turned on
  ("the percent does not work"); a forced theme left its background filter, its moon and its day bar after "System" was chosen again;
  and `addView` of the slides' switch into the card left ONE MORE COPY of the switch in the launcher on every redraw (4 copies after a
  minute of the flow test, ~100 a day). Now: `frame()` always sets the filter and the alpha, the switch goes into its own `sw_host`
  that is emptied first, `moon()` / `bar()` / the Moon set visibility both ways.
  Check without a phone: `widget/android-render/run.sh --reapply` (a redraw onto existing views must give the same picture and the
  same number of switches as a fresh widget, for a list of setting changes). On a device: `WidgetFlowTest` (`oneSwitchEach`, the Moon's percent).
- **The blank screen at launch** was the page waiting for fonts from the network. The page stays hidden until `load` + `fonts.ready`
  (`html.up-boot`, app-refresh.js); a file that is not in the bundle is fetched from dhamma.gift (`DgSitePlugin.proxy`). The site split
  Lato into per-script files, `tools/page-files.json` is a recording and did not follow: seven fonts came from the site on every launch
  (fast on a Test Lab emulator, a blank second or three on a phone on mobile data). Now `tools/bundle-from-repo.js` also copies what the
  bundled css (`url(...)`) and html (`href` / `src`) name, and fails if such a file is not in dg-node. Check on a device:
  `WidgetFlowTest` "launch: nothing is asked from the site" (reads logcat for requests to dhamma.gift).
- **A launcher may report a size the widget does not have.** A Motorola razr (owner's phone; razr plus 2024 in Test Lab) reports the
  cells of its OTHER screen: a 1 x 1 widget "82 x 68 dp" is 82 x 115 on the screen, a 4 x 4 "378 x 323" is 379 x 507. Every design was
  scaled for a cell 1.6-1.7 times lower than the real one: small in the middle of its card, no moons and no list in the calendar "although
  there is a lot of room". A Pixel is a little off too (a 4 x 4 "440" is 464: the gaps between the rows are left out).
  So on Android 12+ a widget is drawn for the reported size AND for taller ones (`WidgetPlan.TALLER`, 9 views in one
  `RemoteViews(Map<SizeF, RemoteViews>)`), and the launcher takes the biggest that fits the view it really has (it measures it itself).
  Costs 0.2-0.7 s per redraw on a razr, off the main thread. A tap on the slides' switch or a month arrow is answered faster: each
  size has its own intents (the data URI carries the height), so the tap says which size is on the screen, and only that one and the
  reported one are drawn; the next tick draws all again.
  The low wide arrangement of the strip (`w2_strip_w`) was made for the phantom "391 x 75" and stays for cells that really are low.
  Samsung One UI 8 (Galaxy S24, Android 16) is another case and needs nothing: it lays the widget out at the size it reports and
  shows the whole view 1.2 times smaller (the same factor both ways), so the design is whole, only smaller.
  Check on a device: `WidgetFlowTest.drawnForItsSize` (a debug build names the size on each widget: `sw_host`'s content description
  "drawn for WxH", compared with the view's real bounds). Numbers of any phone: the line at the bottom of the widget's settings screen
  (`size ... min ... max ... screen ... density ... font`) - but these are the REPORTED ones; the real size is only in a view dump.
- **The calendar: every date of an Uposatha looks the same, neighbours are one capsule** (owner, 2026-10-11; the page, the widget and
  the iOS code alike). The evening it begins on and its day used to differ (a filled circle / a dim tile) and read as two kinds of
  days. Now: a filled circle on each, and a band from the middle of a date to the middle of the next one through the edge of the cell;
  over a row break the band stops flat at the edge and goes on from the edge of the next row. Widget: `w2_cal_week` has the tile as its
  own layer (`g`), two halves behind the number (`hl`, `hr`, the same box and height as the circle) and today's translucent gold
  plaque with its frame on top (`o`, `w2_ring`). Page: the band is the two pseudo-elements of the chip `.n` (as date-range pickers
  do it), `data-up / data-pl / data-pr` on the cells, `.hl` = the plaque of today / of the chosen day over the capsule.
  The render samples (`debug/assets/widget-sample*.json`) are regenerated from the current builder: the old ones had no two-date
  Uposathas, no `lit`, 14 days.
- **Settings are applied the moment they are chosen** ("Saved" appears, the widget on the home screen is redrawn); Done only closes.
  He changed a setting, went back, and nothing had changed.
- **`WidgetFlowTest` can fail now.** It used to swallow every exception and pass; "the flow passed" said nothing. Steps that throw
  and `check(...)`s that do not hold are collected and the test fails with the list at the end.
- The widget's data: 31 days of sun (was 14), the moon's phase now is read between two middays of the page's daily table (the mean
  speed is half a day off after two weeks), data older than 30 days or of another time zone than the phone's (when the page follows the
  phone's zone, `settings.tzAuto`) is the "Open Uposatha" placeholder. The bridge hands the data over when the page is idle
  (`requestIdleCallback`): working it out takes the page's thread for up to a second on a phone.
- A route (`MainActivity`, extra `route`) is only a path of the app's own page (`WidgetPlan.ownPath`): the activity is exported and an
  address in the extra used to be loaded into the app's window.

## Lessons of the owner's phone (2026-10-10, evening)
- **One view per orientation, not a map of sizes.** `RemoteViews(landscape, portrait)`; the sizes are the classic options (portrait = min width x max
  height, landscape = max width x min height). With `RemoteViews(Map<SizeF, ..>)` the launcher takes "the biggest that fits" and, when none fits by
  its own measure, the smallest: a tall 5 x 6 widget was drawn with the view built for the low landscape cell (no moons, one row of the list, cut text).
- **A tap opens the app through `WidgetOpenActivity`** (Theme.NoDisplay): it leaves the route in a static and starts the launcher's own intent;
  MainActivity takes the route in onResume. An intent with an extra makes Android refuse the task snapshot and show a splash screen over the running
  app at every tap (ActivityRecord.allowTaskSnapshot): a white splash over the dark page.
- **The open page is not loaded again**: MainActivity asks `window.__upoRoute(route)` (uposatha-calendar.js) and loads the address only when the page
  has no such function (a cold start, an older bundle). Loading showed as "open - blank - open".
- **Widgets are drawn off the main thread**: `onReceive` goes `goAsync()` to one worker thread; `update()` is under one lock (the page's plugin
  thread and the settings screen draw too). Seven widgets x two orientations on the main thread held up the app's own start.
- **The Moon 1x1 is just the moon**; the percent is a setting of the widget (`cfg_pct_`).
- A release build made here is signed with this server's debug key: it installs over the debug build, and Play Protect warns about an unknown developer.

## How to look at it without a phone
`widget/android-render/` (see run.sh.txt): Robolectric renders `WidgetSheet.cases()` (debug source set: every widget x real cell sizes x scenarios x settings,
light and dark) to PNGs; about 6 s a picture on this box. The picker previews (`res/drawable-nodpi/widget_preview_*.png`) are written by the same run
(WIDGET_PREVIEW=1), i.e. they are the real render, not hand-made pictures.
On a device: debug `WidgetPreviewActivity` (`--es only '<regex>'`), androidTest `WidgetSheetTest` (the same PNGs) and `WidgetFlowTest` (the launcher: pin the big
widget, three slides, resize, day tap, the settings screen, then the other six widgets).
Unit tests: `WidgetPlanTest` (scale, arrangement, calendar rows, phase names), `WidgetFormatTest`.

## Not verified yet (2026-10-10)
- Verified on ONE virtual device (Test Lab MediumPhone.arm, API 34, Pixel launcher, 2026-10-10, two runs): WidgetFlowTest end to end (pin, slides, month arrows,
  the launcher's resize in all directions, the settings from the launcher's edit button, day tap, the other six widgets). Videos per case:
  https://test.dhamma.gift/assets/shots/uposatha-widget-v2/video/ . Lesson of the first run: `minResizeHeight` 300 dp made the launcher ignore the 4x4 target
  (it must not exceed the target in ANY orientation: landscape cells are ~66 dp) and place a 3x4; it is 245 dp now.
- Not on real phones yet (Samsung One UI, Motorola), not below API 31.
- `OPTION_APPWIDGET_SIZES` on Samsung / Motorola launchers; the scale is computed from what they report.
- Below API 31: a system theme switch shows after the next update (<= 15 min); the moon pair still follows at once.
- Android 15 generated previews (`setWidgetPreview`) are not used; the PNG previews are.

# Android widget: what was built (uposatha/android)

> The picture pipeline described in "Files" and "Decisions" below (WidgetRenderer, widget_images, w_img_*, Lato in assets) was REPLACED by real views, see the last section "Native views rewrite". What still holds from the old text: the data flow, the plan/alarms, the size lists, the texts, the Uposatha cell colouring rules.

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


## Native views rewrite (2026-10-10)

Why: the widget was one bitmap per size drawn by `WidgetRenderer` (Canvas). On a resize the launcher stretched the old picture (squeezed moon, squeezed text) until the new one arrived. Now everything is real views, which the launcher reflows to ANY size by itself; only the moon is a picture (and a square one, `fitCenter`, so it can never be distorted).

### What changed
- Deleted: `WidgetRenderer.java` (Painter, fonts from assets), `layout/widget_{s,m,l}.xml`, `widget_images.xml` (+ `layout-night`), `widget_grid.xml`, `w_img_*`, `values/widget_dimens.xml`, `assets/widget/lato-*.ttf`, `drawable-night/widget_bg.xml`, the old Robolectric `WidgetRenderTest`/`sheet.py`.
- New code (`java/gift/dhamma/uposatha/`): `WidgetViews` (builds the RemoteViews: texts, which rows exist, taps), `WidgetMoon` (the moon bitmap: photo + shade + rim, halo in the dark theme, square, disc = 80 % of the side for the halo), `WidgetPlan` (pure decisions: size class, rows that fit, cell shape, day-bar numbers; JVM-tested in `WidgetPlanTest`). `WidgetProvider` keeps the plan/alarms/CYCLE/size lists and calls `WidgetViews.build(...)` for every size of `OPTION_APPWIDGET_SIZES` (own decisions per size).
- Layouts (`res/layout/w_*.xml`, generated once, now plain XML): `w_l{1,2,3}_{s,m,l}` = layer x size class (9), `w_ph_{s,h}` (placeholder), includes `w_dots`, `w_counter`, `w_kala`, `w_daybar`, rows added with `RemoteViews.addView`: `w_row_next`, `w_row_upo`, `w_row_upo_s`, `w_row_part(_cur)`, `w_row_div`, `w_row_month_{s,st,m,l}` (a week of 7 cells). Allowed classes only (FrameLayout, LinearLayout, TextView, ImageView, ProgressBar).
- Resources: `values{,-night}/widget_colors.xml` (exact `Theme.th.*` values + the mixes), `values/widget_styles.xml`, `res/font/lato_{regular,semibold,bold}.ttf` (referenced directly with `android:fontFamily`), `drawable/w_cell_*` (month cells: solid/band x round/square-left/square-right/square, + today ring), `w_bar_*` (day bar), `w_dot_*`, `w_chev_*`, `w_plate`, `widget_bg` (now `@color/w_surface`).
- Size class changed: width < 200 dp = small (a 2- or 1-column widget, any height), else height >= 240 dp = large, else medium (so 3x2 and a 3x3 get the medium/large layouts instead of a cramped small one).

### Decisions
- Geometry is weights; `WidgetViews` only decides WHAT exists for the height the launcher reports (`avail()`): which detail lines/rows are shown (next Uposathas 1..6 rows of >= 33 dp, parts 6 or the 3 of the current half, month list rows, "today" block, ticks), and the counter's size. Rows from `addView` share the height (weight 1), so a tall widget gets taller rows, not an empty bottom (except a narrow tall small one, see below).
- Text sizes are dp (as before, not sp: the font scale does not enter; lines that can be long are `autoSizeText` single-line with an ellipsis as the last resort). Lato works in RemoteViews (checked on the Test Lab emulator, real home screen): the fonts are app resources, inflated in the launcher with the app's resources.
- Colours: text colours of dynamic things (kala green / vikala red, month cell text) go through `RemoteViews.setColor(id, "setTextColor", @ColorRes)` (API 31+), which the launcher resolves itself, so the system light/dark switch needs no update. Below API 31 the colour of the moment is used (a theme switch shows after the next update). Backgrounds (`setBackgroundResource`) and all static colours are resolved by the launcher. The kala line is therefore 4 TextViews (word, middle, time, "left"), not one span string (spans would be frozen in one theme).
- The moon: two bitmaps (light, with halo-less rim; dark, with halo) in two stacked ImageViews whose `android:alpha` is `@dimen/w_alpha_light/dark` (1/0 in `values`, 0/1 in `values-night`): the theme picks the visible one, no layout-night duplicates. Moon sizes: hero 96 (medium) / 112 (large) dp, list 28-32 dp, at the screen's density (cap 3).
- Day bar (no weights are settable on a RemoteViews at run time): six stacked ProgressBars `bar0..5` (bar k = filled from the left to the END of part k, as a share of the day, `setProgressBar`), the later ones lie over the earlier, so each part shows with its own proportional width; the 2 dp gap is the last 2 dp of each bar's drawable (`ScaleDrawable` so it moves with the level). The current part swaps its bar for `barc k` (solid accent). `bar_now` = the 2 dp "now" mark. All proportional to any width.
- Month: a week = a `RemoteViews` row of 7 cells (`c0..c6`, each its own `PendingIntent` to the calendar on that day), added with `addView`; weeks share the height; the pill is the cell's background drawable (max height 17/20/36 dp, centred). Week start from `WidgetModel.weekStart`.
- Not done: the "N h M min left" line is text refreshed by the existing 15 minute plan (a Chronometer cannot show "1 h 34 min" with the unit words).
- A fixed-width date column (92-104 dp) in the tables, the day / "in N d" columns take the rest (at < 340 dp the word "day" and the phase name are dropped from rows).

### How to test
- Build: `export QEMU_LD_PREFIX=/usr/x86_64-linux-gnu ANDROID_HOME=/opt/android-sdk JAVA_HOME=/usr/lib/jvm/java-21-openjdk-arm64; cd uposatha && node build.js && npx cap sync android && cd android && ./gradlew :app:assembleDebug :app:assembleDebugAndroidTest :app:testDebugUnitTest --no-daemon -q`.
- On a device: debug `WidgetPreviewActivity` (`adb shell am start -n gift.dhamma.uposatha/.WidgetPreviewActivity`, extras `--ei w 360 --ei h 430 --es theme dark --ei layer 1 --ei scenario 2`): the REAL RemoteViews (`WidgetViews.build` -> `RemoteViews.apply`, as a launcher does) in frames of fixed dp sizes (160x160, 130x110, 170x340, 250x110, 360x150, 360x300, 300x430, 360x430, 360x520), light and dark (a night configuration context), 6 scenarios; PNGs in `.../files/widget-previews/`.
- Test Lab (virtual, e.g. `MediumPhone.arm` API 34): `androidTest` has two tests in one run: `WidgetSheetTest` (the same frames as PNGs `sheet-*.png`, no launcher needed) and `WidgetFlowTest` (the real pinned widget on the launcher: layers, the launcher's resize handles - shorter, narrower, wider + taller - with all three layers shot after each resize, day tap). Command in `NOTES-testlab.md`; pull `/sdcard/Android/data/gift.dhamma.uposatha/files/shots`.
- (Older text; now `widget/android-render/run.sh`, see "Lessons of the night" above.) Without a phone: `widget/android-render/` (`WidgetRoboTest.java.txt`, `init.gradle.txt`, `run.sh.txt`): Robolectric (native graphics) renders the same sheets locally; it needs the x86_64 JDK 21 under qemu (see the old notes above) and is not in the build (an init script adds robolectric and a source dir). `WIDGET_ONLY='sheet-s1-L2-.*-dark'` filters; ~10 s a picture. It matched the emulator in every layer (fonts too).
- Unit tests: `WidgetFormatTest`, `WidgetPlanTest`.

### Known gaps
- A narrow TALL small widget (2x4: < 200 x 400 dp) is only filled for the month layer (the whole month); layers 1 and 2 keep their stack centred, so there is empty space above and below (a bigger moon would need `setViewLayoutWidth`, API 31+).
- Month cell rows get thin on a 4x2 of ~110 dp (6 weeks in 80 dp); text stays readable, the pill is 13-15 dp.
- Below API 31 text colours do not follow a theme switch until the next update (<= 15 min).
- Tested on the emulator launcher only (Pixel launcher): real Motorola / Samsung launchers may report other size lists; the layouts do not depend on exact sizes.
- Verification status: ONE Test Lab virtual run (MediumPhone.arm API 34, dark; `gs://test-lab-nr56tiywzh2yc-kz084y8hszdu6/2026-10-10_03:45:45.303463_VKRj/`): the real pinned widget on the Pixel launcher, all three layers, resized shorter / narrower / wider+taller with the launcher's handles (nothing stretched, text stays text), plus 238 `sheet-*.png`. The second run was refused (TEST_QUOTA_EXCEEDED, shared daily quota). The later changes (low 2x2 / 4x2 degradation, narrower dots strip, smaller numbers on a low month grid, size class < 200 dp) were checked only with the local Robolectric sheets (same output as the emulator in the earlier comparison), not on the launcher.
