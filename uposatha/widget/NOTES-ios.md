# Uposatha iOS widget: notes for the lead / CI / owner

Status: written without a compiler (Linux). Nothing was compiled; CI (macOS) is the first real build. Static self-check:
`python3 -I uposatha/widget/tools/check_ios_widget.py` (0 errors now; 3 warnings = files `cap sync` creates).

## What was built
- **App target** (`ios/App/App/`)
  - `DgApp.swift`: `DgWidgetPlugin` (jsName `DgWidget`, `put({json})` -> App Group `group.gift.dhamma.uposatha` UserDefaults key `data` -> `WidgetCenter.reloadAllTimelines()`), registered next to the other plugins; `import WidgetKit`.
    `DgShortcutsPlugin.deliver(url:)`: turns a `gift.dhamma.uposatha://open?tab=home|parts|cal|list[&day=YYYY-MM-DD]` (or `://route?path=/uposatha-calendar...`) into the quick-action route `/uposatha-calendar?app=1&tab=..[&day=..]&w=<unix>` (the page/bridge already take `tab=`; the `w=` tail only makes the bridge's "same route, do nothing" check never swallow a tap). Cold start: waits in `pendingRoute` for `launchRoute()`; running app: `shortcut` event. Same path as Home Screen quick actions.
  - `SceneDelegate.swift`: hands `connectionOptions.urlContexts` (cold start) and `openURLContexts` (running) to it.
  - `Info.plist`: `CFBundleURLTypes` scheme `gift.dhamma.uposatha`. `App.entitlements`: App Group added (time-sensitive key kept).
- **Extension** `ios/App/UposathaWidget/` (target `UposathaWidget`, `gift.dhamma.uposatha.widget`, no Capacitor):
  `UposathaWidget.swift` (@main bundle, provider, timeline), `WidgetModel.swift` (Codable data, store, calendar maths, kala/parts/counter, timeline dates),
  `WidgetViews.swift` (small/medium/large, three layers), `WidgetLockViews.swift` (rectangular / circular / inline, iOS 16+), `MoonView.swift` (photo + `MoonShade` Path, same geometry as `shadePath`),
  `SwitchLayerIntent.swift` (iOS 17 AppIntent), `WidgetTheme.swift` (tokens, dynamic light/dark), `WidgetStrings.swift` (GENERATED), `widget-sample.json` (copy of `fixture-ru.json`), `Assets.xcassets/moon.imageset/moon.png` (moon-nasa-420), `Info.plist`, `UposathaWidget.entitlements`.
- `App.xcodeproj/project.pbxproj`: target, Sources/Frameworks/Resources, product `.appex`, "Embed Foundation Extensions" (dstSubfolderSpec 13) in App, target dependency + proxy, Debug/Release configs (deployment 15.0, MARKETING_VERSION 1.0 and CURRENT_PROJECT_VERSION 1 identical to the app, SKIP_INSTALL, automatic signing, no DEVELOPMENT_TEAM: like the app, it comes from the command line). 35 new ids `E7B1D0F1xxxxxxxx0072D4E8`.
- Tools: `widget/tools/gen_ios_strings.py` (strings.json -> WidgetStrings.swift, plus a few extra keys: until, kalaShort, vikalaShort, dayN, openApp, month names, plurals), `widget/tools/check_ios_widget.py`.
- Backups of modified files: `~/claudeBak/uposatha-ios-{DgApp.swift,SceneDelegate.swift,Info.plist,App.entitlements,project.pbxproj}`.

## Behaviour (decisions)
- Layers per spec: 1 Uposatha+kala (-> tab home), 2 Day & night (-> parts), 3 Month (-> cal). Month cells in medium/large are `Link`s to `tab=cal&day=<ymd>`; small = one target. Lock screen: rectangular 2 layers (vertical dots), circular 3 (tap on the circle: counter -> kala ring -> date), inline one line.
- (superseded by the owner round below: segments + chevrons, left/right halves) Dots = one `Button(intent: SwitchLayerIntent)` over the whole bottom strip (iOS 17+, `#available`). **Layer state is per widget SIZE** (App Group key `layer.small|medium|large|accessoryRectangular|accessoryCircular`): iOS gives no per-instance id without a configuration, so two widgets of one size share a layer. iOS 15/16: layer 1 only, no dots.
- Timeline (24 h): now + every 30 min + dawn/aruna/noon/sunset + part borders + Uposatha start/end + the counter's hours counted back from its target (so "1 d 7 h" flips on time) + coverage end; ~50 entries; policy `.after(last)`. Layer is read once per timeline (the intent triggers a reload). Spec said hourly; 30 min keeps the "now" tick of the day scale honest.
- No data / generatedAt older than 14 days / now outside `days` (needs a following day for vikala's end) -> "Open Uposatha" (ru/en by the device language), no times. Placeholder/gallery: the bundled sample, rendered at its own `generatedAt`.
- Language = `settings.lang`. Kala = aruna..noon, vikala = noon..next aruna (WIDGET.md); "until dawn" shows the next aruna `hm`. No place (`placeSet:false`): the kala row of layer 1 is replaced by "times assumed: 18:00 and 06:00" (as in the mock-up); layers 2 and lock screen still show kala/vikala (lock screen shows "no place set" instead).
- "N min left" is `Text(date, style: .relative)` (live, system-formatted): it follows the DEVICE language, not the app's, and reads "1 hr, 34 min" style. `Text(timerInterval:)` is iOS 16 only and only prints h:mm:ss, so it was not used.
- Part borders (`parts` have only HH:MM) are placed by cumulative durations from the sunrise moment; the place's UTC offset is taken from the data's own ms/ymd/hm (no tz database). A DST change inside one night could shift the later parts' borders by an hour (display uses the app's own HH:MM, only "which part is now" would be off).
- Font: Lato exists on the box only as `.woff2` (iOS cannot load it from UIAppFonts). The widget uses the system font through one function, `dgFont()` in `WidgetTheme.swift`; to switch bundle Lato TTFs, add them to UIAppFonts and change that function.

## Owner-test round (2026-10-10, same changes as Android)
- Data: `days` starts yesterday; the part/kala lookup takes the last day with sunrise <= now, so the night before dawn is found in `days[0]` and never falls to the placeholder. `uposathas[].day` is the Uposatha's own day. `settings.weekStart` (0 Sunday / 1 Monday; absent: ru 1, en 0) drives header names, column offsets and rows (grid and the small widget's two-week strip).
- Month grid: solid = `start.ymd`, light = `day`; one strip when `day == start+1` and both sit in one row (breaks at the row's last column, not "Sunday"; `StripShape` drops the inner corners); on a shared date solid wins and the strip runs through it (back-to-back 14th/15th both render). Cells now touch (no 2 pt gaps), 1 pt inset each.
- Labels (Next rows, month list, captions, circular date, "in N d") use `start.ymd`; `lite.from`/span already used start.
- Moons: layer-1 hero (and lock-screen moons) = `today.moon + (now - generatedAt)/29.530588853 d` mod 1 (`WSnap.heroPhase`); list rows use `WUposatha.listPhase` (15th full .5 / new 0, 8th .25 / .75, 14th .375 waxing / .875).
- Halo (dark mode, every moon incl. new, not on the mono lock screen): blurred disk #E9E4DC alpha .26+.22*illumination, blur (3+3.5*illumination)/100 of the size, plus a .8/100 rim #E9E4DC alpha .45; light mode keeps the navy rim. It is drawn outside the moon's frame, so a moon at a widget's edge may have its halo clipped.
- Layer switch: three 22x6 segments (gap 6, current `dgAccent`, others `dgBorderStrong`) between two chevrons; the strip is 44 pt high and full width, left half = `SwitchLayerIntent(step: -1)`, right half = `step: +1` (iOS 17+; before that, one layer, no switch). On small/medium text layers the strip overlaps the bottom ~18 pt of the content (a tap there switches instead of opening the app); the month layer and large widget keep clear of it (the medium month cells shrank to 13 pt high, font 11). Lock screen keeps the vertical dots / whole-circle tap (step +1). iOS 17's own 16 pt content margins plus the 44 pt strip make the medium widget tight: check it on a device.

## Tables and the large size (2026-10-10)
- `UpoTable`: every Uposatha list (layer 1 "Next", the month layer's list) is a table: moon | date it begins on | day ("8th") | right-aligned "in N d" ("now" for one that is on). Date and day columns are as wide as the widest entry (measured with `UIFont`, so rows line up; text scales down to 0.8 if a system font differs). Medium month list: short dates ("Sat 17"), no "in N d" column.
- Large, layer 1: `UpoNext` lists up to 6 rows, as many as the height left under the hero allows (GeometryReader, 25 pt per row).
- Large, layer 3: grid cells 24 pt; under it `MonthBottom`: up to 4 rows (on + next), and a `TodayBlock` (moon waxing/waning + % lit from the clock-advanced `today.moon`, dawn / noon / sunset of today) only if 54 pt are still free. On iOS 17 (44 pt switch reserve) it will rarely fit: expect it on a 5-row month with few Uposathas, or on iOS 16.
- Strip: a cell is square only on the side that joins its neighbour (the 14th/15th shared date joins both sides); the today ring is a capsule inset 2 pt.

## Risks / not verified
- Never compiled. Likely trouble spots if CI fails: `Text + Text` chains (KalaRow, Caption, Counter), `@available` guards in ViewBuilders (DotsStrip, LockScreenView), the AppIntent (`@Parameter` + `init()`), the pbxproj hand edit. The checker proves graph/brace/key consistency, not types.
- iOS 18 tinted / accented rendering is not designed (colours become one tint; kala vs vikala differ by the word, as the spec says). The moon image is not marked for accented mode.
- A `reloadAllTimelines()` call per `put` (the bridge debounces and only sends changed JSON).
- The page must understand `&day=` on `/uposatha-calendar` (the bridge reads only `tab=`); `w=` is ignored by it. Tap on the "no place" note opens Home, not the place setting (no known route).
- Dots' tap area is the strip (full width x 32 pt), not a full third of the widget.

## What the lead / CI / owner must do
1. Apple Developer portal (owner): register App Group `group.gift.dhamma.uposatha`; App ID `gift.dhamma.uposatha` gets the App Groups capability; new App ID `gift.dhamma.uposatha.widget` with App Groups (same group). With `-allowProvisioningUpdates` and the ASC API key, automatic signing may create all of it by itself if the key's role allows (Admin); if the Archive step says "No profile for gift.dhamma.uposatha.widget" / "App Group not available", create them by hand and re-run.
2. Workflow `.github/workflows/build-app.yml`: **no change required.** Archive (`-scheme App -configuration Release -allowProvisioningUpdates ... CURRENT_PROJECT_VERSION=<the app's build number> DEVELOPMENT_TEAM=<secret>`) builds and signs the embedded appex too (the command-line overrides reach every target, so the versions stay identical); the export uses `signingStyle automatic`, which also resolves the second profile, so `ExportOptions.plist` needs no `provisioningProfiles` map. The simulator job (`CODE_SIGNING_ALLOWED=NO`, scheme App) builds the extension as a dependency; no new `-scheme`. If a manual-signing export is ever used, add `provisioningProfiles` for both bundle ids.
3. The CI-free check before pushing: `python3 -I uposatha/widget/tools/check_ios_widget.py`.
4. TestFlight device test: add the widget from the Home Screen gallery (small/medium/large) and the Lock Screen (iOS 16+); open the app once so `DgWidget.put` writes the data; tap dots (iOS 17), a month cell, the big area; check the app opens the right tab.
5. After changing `widget/design/strings.json`: `python3 uposatha/widget/tools/gen_ios_strings.py`.
