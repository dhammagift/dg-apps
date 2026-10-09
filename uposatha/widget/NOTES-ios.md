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
- Dots = one `Button(intent: SwitchLayerIntent)` over the whole bottom strip (iOS 17+, `#available`). **Layer state is per widget SIZE** (App Group key `layer.small|medium|large|accessoryRectangular|accessoryCircular`): iOS gives no per-instance id without a configuration, so two widgets of one size share a layer. iOS 15/16: layer 1 only, no dots.
- Timeline (24 h): now + every 30 min + dawn/aruna/noon/sunset + part borders + Uposatha start/end + the counter's hours counted back from its target (so "1 d 7 h" flips on time) + coverage end; ~50 entries; policy `.after(last)`. Layer is read once per timeline (the intent triggers a reload). Spec said hourly; 30 min keeps the "now" tick of the day scale honest.
- No data / generatedAt older than 14 days / now outside `days` (needs a following day for vikala's end) -> "Open Uposatha" (ru/en by the device language), no times. Placeholder/gallery: the bundled sample, rendered at its own `generatedAt`.
- Language = `settings.lang`. Kala = aruna..noon, vikala = noon..next aruna (WIDGET.md); "until dawn" shows the next aruna `hm`. No place (`placeSet:false`): the kala row of layer 1 is replaced by "times assumed: 18:00 and 06:00" (as in the mock-up); layers 2 and lock screen still show kala/vikala (lock screen shows "no place set" instead).
- "N min left" is `Text(date, style: .relative)` (live, system-formatted): it follows the DEVICE language, not the app's, and reads "1 hr, 34 min" style. `Text(timerInterval:)` is iOS 16 only and only prints h:mm:ss, so it was not used.
- Part borders (`parts` have only HH:MM) are placed by cumulative durations from the sunrise moment; the place's UTC offset is taken from the data's own ms/ymd/hm (no tz database). A DST change inside one night could shift the later parts' borders by an hour (display uses the app's own HH:MM, only "which part is now" would be off).
- Font: Lato exists on the box only as `.woff2` (iOS cannot load it from UIAppFonts). The widget uses the system font through one function, `dgFont()` in `WidgetTheme.swift`; to switch bundle Lato TTFs, add them to UIAppFonts and change that function.

## Risks / not verified
- Never compiled. Likely trouble spots if CI fails: `Text + Text` chains (KalaRow, Caption, Counter), `@available` guards in ViewBuilders (DotsStrip, LockScreenView), the AppIntent (`@Parameter` + `init()`), the pbxproj hand edit. The checker proves graph/brace/key consistency, not types.
- iOS 18 tinted / accented rendering is not designed (colours become one tint; kala vs vikala differ by the word, as the spec says). The moon image is not marked for accented mode.
- A `reloadAllTimelines()` call per `put` (the bridge debounces and only sends changed JSON).
- The page must understand `&day=` on `/uposatha-calendar` (the bridge reads only `tab=`); `w=` is ignored by it. Tap on the "no place" note opens Home, not the place setting (no known route).
- Dots' tap area is the strip (full width x 32 pt), not a full third of the widget.

## What the lead / CI / owner must do
1. Apple Developer portal (owner): register App Group `group.gift.dhamma.uposatha`; App ID `gift.dhamma.uposatha` gets the App Groups capability; new App ID `gift.dhamma.uposatha.widget` with App Groups (same group). With `-allowProvisioningUpdates` and the ASC API key, automatic signing may create all of it by itself if the key's role allows (Admin); if the Archive step says "No profile for gift.dhamma.uposatha.widget" / "App Group not available", create them by hand and re-run.
2. Workflow `.github/workflows/build-app.yml`: **no change required.** Archive (`-scheme App -configuration Release -allowProvisioningUpdates ... CURRENT_PROJECT_VERSION=<run> DEVELOPMENT_TEAM=<secret>`) builds and signs the embedded appex too (the command-line overrides reach every target, so the versions stay identical); the export uses `signingStyle automatic`, which also resolves the second profile, so `ExportOptions.plist` needs no `provisioningProfiles` map. The simulator job (`CODE_SIGNING_ALLOWED=NO`, scheme App) builds the extension as a dependency; no new `-scheme`. If a manual-signing export is ever used, add `provisioningProfiles` for both bundle ids.
3. The CI-free check before pushing: `python3 -I uposatha/widget/tools/check_ios_widget.py`.
4. TestFlight device test: add the widget from the Home Screen gallery (small/medium/large) and the Lock Screen (iOS 16+); open the app once so `DgWidget.put` writes the data; tap dots (iOS 17), a month cell, the big area; check the app opens the right tab.
5. After changing `widget/design/strings.json`: `python3 uposatha/widget/tools/gen_ios_strings.py`.
