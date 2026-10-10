# Uposatha widget: what the app side does

Design (from the designer, 2026-10-09): `design/README.md` (the spec), `design/strings.json` (all texts ru/en), `design/dg-moon.js`
(the designer's moon; `design/dg-moon-site.js` is the site's copy that uses the NASA photo). Mock-ups: https://test.dhamma.gift/assets/shots/widget-design/widget.html
The moon photo for native: `moon-nasa-420.png` (NASA SVS CGI Moon Kit, LROC colour map, near side, orthographic, public domain; the disk fills the square).

## Data flow
1. The page (`uposatha-calendar.js`) builds the data: `window.__upoWidgetData()` (a plain object, shape below) and fires `document` event `upo:painted` after each paint.
2. The bridge (`src/uposatha-bridge.js`) listens, debounces, and calls the native plugin `DgWidget.put({ json: "<the object as a string>" })`.
3. Native stores the string (Android: SharedPreferences `dg_widget` key `data`; iOS: App Group `group.gift.dhamma.uposatha` UserDefaults key `data`),
   then redraws every widget (Android: `AppWidgetManager`; iOS: `WidgetCenter.shared.reloadAllTimelines()`).
4. The widget never calculates the moon, the sun or the Uposatha; it lays out this data and counts time forward from it.
   Every moment is `{ ms (epoch), ymd ("YYYY-MM-DD" in the place's time zone `tz`), hm ("HH:MM" in `tz`) }`; show `hm` as is.

## Shape (see `fixture-ru.json`, a real output)
```
{ generatedAt, tz,
  settings: { lang: "ru"|"en", bySuttas, detail, showKala, placeSet, south },
  today: { ymd, moon },                       // moon: phase 0..1 now (0 new, .5 full)
  uposathas: [ { start, day, end, lunarDay (8|14|15), phaseName (new|firstQuarter|full|lastQuarter), phase (0..1) } ],  // from 2 days ago, ~11 weeks
  days: [ { date, sunrise, noon, sunset, aruna, parts: [[name, "HH:MM", "HH:MM"] x6] } ] }   // 14 days from today
```
- `day` is the Uposatha's OWN day: by the suttas the date AFTER `start.ymd` (it begins the evening before, `start` .. `end` is evening to evening); in the modern scheme `day == start.ymd`.
  The month grid: the evening-start date solid, `day` a light band joined to it (the same rule as the page's grid). Lists name the date it BEGINS on (`start.ymd`).
- `settings.weekStart`: 0 = the week starts on Sunday, 1 = Monday (the app's own setting; the widget's grid follows it).
- `days` starts YESTERDAY (14 entries): the night part that is still running before dawn belongs to yesterday's day.
- The moon: layer 1's big moon is the real phase now (`today.moon`, carried on by the clock); moons in list rows are the plain phase of that Uposatha day (new, 50 %, full; the 14th a crescent / gibbous).
- The Uposatha runs from `start` (the evening before) to `end` (the evening after its day) by the app's own rule. The designer's text says "to dawn":
  the app is the source of truth, so `end` is what the page says.
- kala = `aruna.ms` .. `noon.ms` of a day; vikala = `noon.ms` .. next day's `aruna.ms`.
- The moon of a row/day: `phase` (the layer 1 uses the next/current Uposatha's `phase`, the month layer the dots). South: rotate 180 degrees.
