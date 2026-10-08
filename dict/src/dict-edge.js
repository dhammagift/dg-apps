// Edge to edge for the Dictionary app (Android; same scheme as Dhamma.Gift, docs/ANDROID_INSETS.md).
//
// The page draws under transparent system bars (viewport-fit=cover). Nothing native paints a strip any more, and there is
// nothing at the bottom: the page runs to the screen's edge under the gesture bar. What is left for the page to do:
//   - keep clear of the status bar: a strip of its own colour on top (#dg-edge-strip, above every layer), the page starts
//     below it, and what is stuck to the top (the header, the history drop-down) is moved down by the same height;
//   - keep what sits at the bottom clear of the gesture bar (the settings sheet, the toast, the end of the page);
//   - tell the system bars' icons which colour to be, by the theme (SystemBars.setStyle).
// The heights: env(safe-area-inset-*) and Capacitor SystemBars' --safe-area-inset-* (a WebView whose env() stays 0), whichever is
// larger, divided by the page's own interface scale (--dg-zoom: the "Font size" setting zooms <html>, and a px written inside it
// would be multiplied by that again).
// Tested without a phone by test/probe-edge.js (the live page, a simulated 24 / 48 px inset, this very file).
(function dictEdge() {
  var CSS = ''
    + ':root{'
    + '--dg-sat:calc(max(env(safe-area-inset-top,0px),var(--safe-area-inset-top,0px)) / var(--dg-zoom,1));'
    + '--dg-sab:calc(max(env(safe-area-inset-bottom,0px),var(--safe-area-inset-bottom,0px)) / var(--dg-zoom,1));'
    + '--dg-sal:calc(max(env(safe-area-inset-left,0px),var(--safe-area-inset-left,0px)) / var(--dg-zoom,1));'
    + '--dg-sar:calc(max(env(safe-area-inset-right,0px),var(--safe-area-inset-right,0px)) / var(--dg-zoom,1))}'
    + 'body{padding-top:var(--dg-sat);padding-left:var(--dg-sal);padding-right:var(--dg-sar)}'
    + '.tbar{top:var(--dg-sat)}'
    + '.panel .pb,.helpdlg .pb{padding-bottom:calc(26px + var(--dg-sab))}'
    + '.panel.hist-p{top:calc(56px + var(--dg-sat))}'
    + '.pagefoot{padding-bottom:calc(34px + var(--dg-sab))}'
    + '.bubble-notification{margin-bottom:var(--dg-sab)}'
    + '#dg-edge-strip{position:fixed;top:0;left:0;right:0;height:var(--dg-sat);background:var(--dg-page,#fff);z-index:2147483647;pointer-events:none}';

  function cover() {
    var m = document.querySelector('meta[name="viewport"]');
    if (!m) {
      m = document.createElement('meta');
      m.name = 'viewport';
      m.content = 'width=device-width, initial-scale=1, viewport-fit=cover';
      document.head.appendChild(m);
    } else if (!/viewport-fit\s*=\s*cover/.test(m.content)) {
      m.content = m.content.replace(/,?\s*viewport-fit\s*=\s*\w+/, '') + ', viewport-fit=cover';
    }
  }

  function dressPage() {
    cover();
    if (!document.getElementById('dg-edge-css')) {
      var st = document.createElement('style');
      st.id = 'dg-edge-css';
      st.textContent = CSS;
      document.head.appendChild(st);
    }
    if (!document.getElementById('dg-edge-strip')) {
      var strip = document.createElement('div');
      strip.id = 'dg-edge-strip';
      document.body.appendChild(strip);
    }
  }

  // The icons of the status and gesture bars: light on the dark theme, dark on the light one (Capacitor's names: DARK = light icons).
  var Cap = window.Capacitor;
  var Bars = Cap && Cap.Plugins && Cap.Plugins.SystemBars;
  var last = '';
  function icons(force) {
    if (!Bars || typeof Bars.setStyle !== 'function' || !document.body) return;
    var dark = document.body.classList.contains('dark-mode');
    var style = dark ? 'DARK' : 'LIGHT';
    if (!force && style === last) return;
    last = style;
    Bars.setStyle({ style: style, bar: 'StatusBar' }).catch(function () { last = ''; });
    Bars.setStyle({ style: style, bar: 'NavigationBar' }).catch(function () { last = ''; });
  }

  function start() {
    dressPage();
    icons(true);
    new MutationObserver(function () { icons(false); }).observe(document.body, { attributes: true, attributeFilter: ['class'] });
    // A system dialog (or the app's return from the background) may have reset the bars.
    document.addEventListener('visibilitychange', function () { if (document.visibilityState === 'visible') icons(true); });
  }
  if (document.body) start(); else document.addEventListener('DOMContentLoaded', start);
})();
