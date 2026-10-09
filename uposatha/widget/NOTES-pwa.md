# Uposatha widgets for the PWA (Windows 11 Widgets Board)

Built 2026-10-09 in the TEST checkout `/var/www/dg-node-test` (served at https://test.dhamma.gift). Nothing committed, pushed or restarted.
The look is the web version of the same data (Adaptive Cards, system fonts, emoji moon), not the native design.

## What the doc says (Microsoft Edge, "Display a PWA widget in the Windows Widgets Board", updated 2026-09)
- Windows 11 only. Widgets are declared in the PWA manifest (`widgets`), drawn from **Adaptive Card templates** (sample uses 1.5, the Widgets Board supports 1.5/1.6; we use **1.5**),
  filled by the PWA's **service worker** with `self.widgets.updateByTag(tag, {template, data})` (both strings). The board does not draw anything by itself.
- Required manifest fields: `name`, `description`, `tag`, `ms_ac_template`, `screenshots`; the doc also calls `template` required (informational only). `update` (seconds) is
  only a hint: the worker must do the updating. Screenshot for the picker: medium widget, 300x304, transparent rounded corners (ours: 300x304).
- Only `Action.Execute` is run (its `verb` arrives as `event.action` in `widgetclick`). Recommended touch targets: small 1, medium 3, large 4. No scrolling, no pivots.
- One template serves all three sizes with `$when: "${$host.widgetSize == 'small'}"` (host properties: widgetSize, hostTheme, ...).
- To test locally the doc asks for **WinAppSDK 1.2** and **Windows Developer Mode on**. To ship, the PWA is packed with PWABuilder into a Microsoft Store app (needs a public https URL).
  The doc's own demo (PWAmp) is simply installed from Edge, then Win+W, "Add widgets"; so a Store package is **not** needed to try it. The doc does not say anything more
  precise (no Edge flag is mentioned). I could not run Windows or Edge here: **nothing of the board side is tested**.

## What was built
| Layer | Widget tag | Template | Sizes |
|---|---|---|---|
| Uposatha + kala (main) | `uposatha-main` | `/assets/widgets/uposatha-main.json` | small / medium / large (large adds the mode, "no place" note and the next three) |
| Day & night | `uposatha-day` | `/assets/widgets/uposatha-day.json` | small: part + kala; medium: + the scale of the day (6 coloured parts, current one amber); large: + list of the six parts with times |
| Month | `uposatha-month` | `/assets/widgets/uposatha-month.json` | small: next Uposatha; medium: next three + grid; large: grid + legend + next three |

- Month grid = ColumnSets of TextBlocks (colour/weight only: Uposatha evening blue-bold, its day green-bold, today red, past days subtle). A styled Column was tried and dropped: it carries the host's own padding and clips two-digit numbers.
- Languages: the template can not be localized, so ru/en come through the data: the worker fills the strings from `design/strings.json` (copied to `/assets/widgets/uposatha-strings.json`) by the language the page saved.
- Whole card = one `Action.Execute` (`open-main` / `open-day` / `open-month`) -> worker opens `/uposatha-calendar?app=1&source=widget&tab=home|parts|cal` (an open Uposatha window is navigated and focused instead).
  The page now reads `?tab=` itself (one line in `uposatha-calendar.js`; before only the native bridge did).
- Data flow: page -> IndexedDB `dg-uposatha` / store `kv` / key `widget` (place, tz, lang, bySuttas, lite, showKala, south, noon, twi), written after a paint when something changed, then
  `postMessage({type:'upo-widgets-refresh'})` to the worker -> worker `build()` + `card()` -> `updateByTag`. The page has to be opened once (and again after a change of settings; the message redraws at once).
- Worker (existing site worker `/sw.js` = `public/service-worker.js`, scope `/`, already registered by the Uposatha page and already controls the manifest scope `/uposatha-calendar`; no new registration, no server route):
  `importScripts` of astronomy + `uposatha-core.js` + `uposatha-widget-data.js` (in try/catch: a failed import does not kill the worker);
  listeners `widgetinstall` (registers periodic sync `tag`, `minInterval = update*1000` ms, then draws), `widgetuninstall` (last instance: unregister), `widgetresume`, `widgetclick`, `periodicsync`
  (tags starting with `uposatha-`), `message`, `activate` (redraws widgets installed before a new worker). Template/strings are fetched network-first and kept in the shell cache (also in the precache list).
- The data URL (`/assets/widgets/uposatha-data.json`) is a static placeholder ("open Uposatha to load the data"); when the worker controls a page, the same URL answers with the live data (handy to look at what the worker computes).
- Shared builder: `public/overrides/js/uposatha-widget-data.js` (UMD: page, worker, Node). `build(env)` is the page's former `__upoWidgetData` body, unchanged in output
  (`window.__upoWidgetData()` still exists, same shape, same 30-minute cache; verified on the live test page against the output captured before the change: identical).
  `card(raw, strings, now)` makes the strings for the cards.

## Files (dg-node-test)
New: `public/overrides/js/uposatha-widget-data.js`; `public/overrides/widgets/{uposatha-main,uposatha-day,uposatha-month,uposatha-data,uposatha-strings}.json`;
`public/overrides/img/uposatha-widget-{main,day,month}.png` (300x304, rendered from the real cards with the Adaptive Cards JS renderer); `test/uposatha-widget.js`;
`test/fixtures/uposatha-widget-{fixture-ru,golden-utc-ru,golden-almaty-en}.json` (fixture = copy of `widget/fixture-ru.json`; golden = output of the page captured before the refactor, Date frozen at 1791560000000).
Changed: `public/uposatha-calendar.webmanifest` (+`widgets`), `public/service-worker.js`, `public/overrides/js/uposatha-calendar.js` (builder call, IndexedDB mirror, `?tab=`),
`public/uposatha-calendar.html` (+1 script tag), `package.json` (+`test-uposatha-widget`).
Changed in dg-apps: `uposatha/tools/page-files.json` (+`/assets/js/uposatha-widget-data.js`: the native bundle needs the new script or `__upoWidgetData` returns null there).
Backups: `~/claudeBak/*.pre-pwa-widget` (webmanifest, service-worker.js, uposatha-calendar.js, uposatha-calendar.html, package.json, page-files.json). `settings.js` / `voice.js` untouched.

## Tests (run: `node test/uposatha-widget.js`, all green)
Shape equals `fixture-ru.json`; output equals the page's golden output (UTC/ru/no place and Almaty/en/non-sutta/mid-noon); `card()` ru/en x 5 moments; all `${...}` bindings of the three templates exist in `card()` output and in the placeholder; AC 1.5, a block per size, only
`Action.Execute` with verbs the worker handles; manifest files exist (PNG sizes match); the worker code is loaded as a worker would (importScripts, no module system) and driven with fake `widgets`/`indexedDB`/`fetch`.
Also checked: `https://test.dhamma.gift/uposatha-calendar.webmanifest` lists the 3 widgets and every URL in them (templates, data, screenshots, icons, strings, scripts, `/sw.js`) answers 200;
in Chromium the page wrote the IndexedDB record, the worker took control, imported the scripts and answered the data URL with live data, `?tab=cal` opened the calendar tab; `test/uposatha-core.js` still passes.

## How the owner tests (Edge on Windows 11)
1. Once per machine (from the doc): install WinAppSDK 1.2 and turn on Settings > System > For developers > Developer Mode.
2. Edge: open https://test.dhamma.gift/uposatha-calendar, set the place/language you want, menu > Apps > Install this site as an app (or the install icon in the address bar). Keep the page open a few seconds (worker + settings mirror).
3. Win+W, "+" (Add widgets) in the board: find "Uposatha + kala", "Day & night", "Month" (the picker shows the 300x304 screenshots). Add one; it should fill within seconds. Right-click/"..." menu: switch small/medium/large.
4. Click the card: the app opens on Home / Parts / Calendar. Change the language or place in the app: the widget redraws (message). Close and reopen the board: `widgetresume` redraws.
5. Debug: edge://serviceworker-internals (or DevTools > Application > Service workers of the installed app) for `[sw]` warnings; DevTools > Application > Periodic background sync (event name `uposatha-main`) fires a sync by hand.
If the widgets do not show in the picker: check that the installed app really took the new manifest (uninstall and reinstall it; manifest is cached up to 1 h) and that Developer Mode is on.

## Known limits / decisions
- Not run on Windows: board look, sizes (the doc gives no pixel size per widget size; layouts are made to degrade, small is tight), clipping, picker behaviour, periodic-sync frequency are unverified.
- No live ticking: Adaptive Cards have no timers. "1 d 7 h" and "kala, N min left" are as of the last redraw (install, resume, settings change, activate, periodic sync). Periodic sync is browser-controlled (`update` 3600 s is only a request; Chromium may give hours),
  so the kala -> vikala switch at midday shows at the next redraw (opening the board redraws). The text says the absolute times (until 12:41) next to the counters.
- Moon is the emoji of the nearest of 8 phases (south flips), not the NASA photo (would need 8+ images; not done). On the board the emoji font is Segoe UI Emoji.
- The Uposatha ends at sunset by the app's rule; the designer's string "dawn" (`detail.endNow`) is replaced by "until <day>, <time>" (`lite.until`) so the card does not say something the data does not.
- Weeks start on Monday (the page's own start-of-week setting is not mirrored). Uposathas earlier than 2 days ago are not in the data, so past ones of the current month are not marked.
- The part of the night before the first day's sunrise uses yesterday's sunset = today's minus 24 h (minutes off at most).
- Touch targets: one per widget (the whole card). No per-day links, no layer dots: each layer is its own widget (the Widgets Board has its own size menu). Only `Action.Execute` exists in widgets.
- `multiple: false` (one instance per widget) is the conservative choice. `minInterval` is passed in ms (`update*1000`; the doc's snippet passes seconds as is, which looks like a slip).
- Decision: the shared `/sw.js` is used, not a dedicated worker. Cost: astronomy (116 KB) + core + builder are imported on every start of the site worker for everybody (not only Uposatha users). A dedicated worker needs an exact route
  in `dg-fastify.js` (single-segment paths go to the search catch-all) and a restart: not done. If this cost matters, switch to `/uposatha-sw.js` with scope `/uposatha-calendar`.
- Native apps: no change of shape; `page-files.json` must keep listing the new script.
- Found, not fixed (not mine): `uposatha-calendar.js` reads `TWI` in `state.twi` before `var TWI` is assigned (in HEAD too), so a stored `dgUposathaTwi` makes the whole page throw `TypeError: Cannot use 'in' operator`. Moving `var TWI = {...}` above `var state` fixes it.
