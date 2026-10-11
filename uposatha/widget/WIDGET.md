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
  settings: { lang: "ru"|"en", bySuttas, detail, allMoons, showKala, placeSet, tzAuto, south, weekStart },
  today: { ymd, moon },                       // moon: phase 0..1 now (0 new, .5 full)
  uposathas: [ { start, day, end, lunarDay (8|14|15), phaseName (new|firstQuarter|full|lastQuarter), phase (0..1) } ],  // from the 1st of this month (at least 2 days back), ~11 weeks ahead
  days: [ { date, sunrise, noon, sunset, aruna, parts: [[name, "HH:MM", "HH:MM"] x6] } ],   // 31 days from yesterday
  moons: { from: "YYYY-MM-01", phase: [0..1, ...] } }   // the moon of every day at midday, from the 1st of this month through today + 75 days
```
- `day` is the Uposatha's OWN day: by the suttas the date AFTER `start.ymd` (it begins the evening before, `start` .. `end` is evening to evening); in the modern scheme `day == start.ymd`.
  The month grid: the evening-start date carries the solid mark, `day` a light tile (the same rule as the page's grid). Lists name the date it BEGINS on (`start.ymd`).
- `uposathas` holds past ones of the current month too (the calendar widget marks the whole month): the current / next one is ALWAYS found by time
  (the first whose `end.ms` is after now), never by index.
- `settings.weekStart`: 0 = the week starts on Sunday, 1 = Monday (the app's own setting; the widget's grid follows it).
- `settings.allMoons`: the app's "Moon of every day in the calendar" (off by default). The calendar widget follows it unless its own setting says otherwise;
  the phases come from `moons` (missing in data of an older page: today's moon carried on at the mean speed of the moon).
- `days` starts YESTERDAY (31 entries: a widget lives a month without the app being opened): the night part that is still running before dawn belongs to yesterday's day.
- The moon: a widget's big moon is the real phase now (`today.moon`, carried on by the clock); moons in list rows and under Uposatha days are the plain
  phase of that Uposatha day (new, 50 %, full; the 14th a crescent / gibbous). The lunar day shown with details is the page's rule: `floor(phase * 30) + 1`.
- The Uposatha runs from `start` (the evening before) to `end` (the evening after its day) by the app's own rule. The designer's text says "to dawn":
  the app is the source of truth, so `end` is what the page says.
- kala = `aruna.ms` .. `noon.ms` of a day; vikala = `noon.ms` .. next day's `aruna.ms`.
- South: every moon is rotated 180 degrees.

## The widgets (v2, 2026-10-10; mock-ups: https://test.dhamma.gift/assets/shots/uposatha-widget-v2/index.html)
Seven separate widgets instead of "three sizes x three layers". A small widget is ONE thing; the two big ones keep three slides (owner).
Every widget is one design that is SCALED to the cell the launcher gives (bigger cell = the same widget, bigger), never rearranged into another design.

| picker entry | cells | what | slides |
|---|---|---|---|
| Moon | 1x1 | the moon now, "30% ↑" (lit, growing / waning) | - |
| Moon + Uposatha | 2x1 | + the next Uposatha's day and the counter | - |
| Uposatha 2x2 | 2x2 | day · coming/now, counter, date + time, (details: the moon line), kala | - |
| Uposatha 4x1 | 4x1 | the same in one row | - |
| Uposatha 4x2 | 4x2 | big moon, the same lines, the moon line always, (details: what comes after) | Uposatha / Day & night / Calendar, opens on Uposatha |
| Day & night | 2x2 | the part of the day, kala / vikala, the bar dawn to dawn (wide: one row; tall: + the six parts) | - |
| Calendar | 4x4 (not below 4x3) | the month as in the app, the card of today, "Next" | Calendar / Uposatha / Day & night, opens on the calendar |

One wording table for all of them (`design/strings.json`, keys `w.*`): "15th day · coming|now", "1d 7h", "Sat 17 Oct" + "from 18:00" / "until 18:00",
"waxing crescent · 30%" (the moon NOW, eight names), "Kala until 12:41" / "Vikala until 05:50". No line is cut with an ellipsis: every line is measured with the
real font and the design is scaled so that it fits.
Each widget has its own settings (Android: the launcher's gear -> WidgetConfigActivity): theme (system / light / dark), transparency of the card, details and
the kala line ("as in the app" / on / off), slides on / off (big widgets), the calendar's "moon of every day" and "next" list.
