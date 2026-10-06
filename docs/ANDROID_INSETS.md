# Dhamma.Gift app: system bars, insets, layers

One scheme, so a fix in one place does not break another. Everything below is checked by `tools/emu-screens.sh` (emulator screens, light and dark).

## Where the numbers come from
| What | Source | Used as |
|---|---|---|
| Status / navigation bar height, cutout | Android window insets -> `env(safe-area-inset-*)` (viewport-fit=cover) **and** Capacitor SystemBars' `--safe-area-inset-*` on `<html>` (a WebView whose env() stays 0) | `max(env(..), var(--safe-area-inset-..))` everywhere |
| In the home page (`html.dg-app`) | home.css: `--dg-sat/sab/sal/sar` = the max() above / `--dg-zoom` (interface scale) | page paddings, drawer, quick window, sheets |
| In a bundled site page (Memo, sign-in, tools) | build-assets.js `coverViewportInSubpages()`: `viewport-fit=cover` + `html{padding: max(env, var)}` | the page keeps clear of the bars |
| Window colour before the first paint | `values/colors.xml` `dg_navbar` (white), `values-night` (dark) | only the launch frame |
| Bar icons (light/dark) | native-bridge.js `syncBarIcons`: home view -> light; else by theme, else by the colour the page paints at its top edge | `SystemBars.setStyle` |

## The strip behind the status bar (never covered)
- Home page and its views: `html.dg-app body::before` (home.css): `height: var(--dg-sat)`, navy (`--dg-navy`) on the home view, `--dg-surface` elsewhere, **z-index 2147483000: above every layer** (header 850, scrims 1080/1083, drawer 1085, quick window 10000, toasts).
- Bundled site pages: `#dg-edge-strip` (native-bridge.js), same height, colour = what the page paints at its top edge, z-index max.
- Rule: nothing may be drawn over the strip; panels start below it (drawer: `padding-top: var(--dg-sat)`; quick window: height minus `--dg-sat` and `--dg-sab`, centre shifted).

## Layers over the page (z-index)
850 pinned header - 900 busy indicator - 1080 sheet scrim - 1083 sheets - 1084 drawer scrim - 1085 drawer - 9999/10000 quick window (4NT) - 10040/10050 sheets above the quick window - **2147483000 status strip**.
Bottom: sheets and floating buttons add `--dg-sab` (translate), the gesture bar icons follow the theme.

## When adding a new full-screen or top-anchored layer
1. Never `top:0` without `padding-top: var(--dg-sat)` (or `top: var(--dg-sat)`); bottom-anchored: add `--dg-sab`.
2. Keep its z-index below 2147483000.
3. Add a shot of it to `tools/emu-screens.sh` (light and dark) before shipping.
