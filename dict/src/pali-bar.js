// The Pāli letters above the keyboard (Dictionary app). While a text field has the focus, a row sits on top of the keyboard:
// Paste, and the letters a phone keyboard hides - ā ī ū ṁ ṅ ñ ṭ ḍ ṇ ḷ (all of Pāli) - one tap each; "…" opens a second row with
// what Sanskrit and the other niggahīta need (ṃ ś ṣ ṛ ṝ ḹ ḥ). Paste reads the clipboard only when it is tapped, never on its own.
// Switched off in the menu ("Pāli letters above the keyboard"), flag dgPaliBar = 'off'. Default: on.
//
// Where the keyboard is: Android tells the page its height (MainActivity's insets callback calls window.__dgIme(cssPx)); if the
// WebView itself was shrunk by it (innerHeight dropped by about that much) the row simply sits at the bottom, otherwise it is
// lifted by the keyboard's height. A page that was resized by a browser's visualViewport is handled the same way.
(function paliBar() {
  var FLAG = 'dgPaliBar';
  var MAIN = ['ā', 'ī', 'ū', 'ṁ', 'ṅ', 'ñ', 'ṭ', 'ḍ', 'ṇ', 'ḷ'];
  var MORE = ['ṃ', 'ś', 'ṣ', 'ṛ', 'ṝ', 'ḹ', 'ḥ'];
  var LONG_L = /[ḷḹ]/;   // a sans-serif l with a dot under it reads as "!": these two are set in a serif face

  function enabled() { try { return localStorage.getItem(FLAG) !== 'off'; } catch (e) { return true; } }
  function isRu() { return document.documentElement.lang === 'ru'; }
  function zoom() { return parseFloat(document.documentElement.style.zoom) || 1; }
  function typable(el) {
    if (!el || el.disabled || el.readOnly) return false;
    if (el.tagName === 'TEXTAREA') return true;
    return el.tagName === 'INPUT' && /^(text|search|)$/i.test(el.getAttribute('type') || '');
  }

  var bar, field, more, imeCss = 0, baseH = 0;   // (imeSeen / native: below)

  function css() {
    if (document.getElementById('dg-pali-css')) return;
    var st = document.createElement('style');
    st.id = 'dg-pali-css';
    st.textContent = ''
      + '#dg-pali{position:fixed;left:0;right:0;z-index:2147482500;background:var(--dg-surface-hover,#eef1f4);border-top:1px solid var(--dg-border,#d3d9df);'
      + 'padding:6px 6px calc(6px + 0px);font:500 19px/1 Lato,system-ui,sans-serif;-webkit-user-select:none;user-select:none;touch-action:manipulation;'
      + 'transform:translateY(24px);opacity:0;pointer-events:none;transition:transform .22s cubic-bezier(.2,.8,.2,1),opacity .18s ease-out}'
      + '#dg-pali.on{transform:none;opacity:1;pointer-events:auto}'
      + '#dg-pali .r{display:flex;gap:4px}#dg-pali .r+.r{margin-top:5px}'
      + '#dg-pali button{flex:1 1 0;min-width:0;height:40px;padding:0;border:0;border-radius:9px;background:var(--dg-surface,#fff);color:var(--dg-text,#1b2430);'
      + 'font:inherit;box-shadow:0 1px 0 var(--dg-border,#c7cdd4);-webkit-tap-highlight-color:transparent}'
      + '#dg-pali button:active{background:var(--dg-accent-bg,#d9efe8)}'
      + '#dg-pali .paste{flex:0 0 44px;color:var(--dg-accent,#139b7b);display:flex;align-items:center;justify-content:center}'
      + '#dg-pali .ser{font-family:Georgia,"Times New Roman",serif;font-size:21px}'
      + '#dg-pali .more{flex:0 0 40px;font-size:17px}';
    document.head.appendChild(st);
  }

  function btn(label, cls, aria) {
    var b = document.createElement('button');
    b.type = 'button';
    b.textContent = label;
    if (cls) b.className = cls;
    if (aria) b.setAttribute('aria-label', aria);
    // The field keeps the focus (and the keyboard stays) while a key of the row is pressed.
    b.addEventListener('pointerdown', function (e) { e.preventDefault(); });
    b.addEventListener('mousedown', function (e) { e.preventDefault(); });
    return b;
  }

  function insert(text) {
    if (!field) return;
    var s = field.selectionStart, e = field.selectionEnd;
    if (s == null) { field.value += text; } else { field.setRangeText(text, s, e, 'end'); }
    field.dispatchEvent(new Event('input', { bubbles: true }));
  }

  function build() {
    css();
    bar = document.createElement('div');
    bar.id = 'dg-pali';
    var r1 = document.createElement('div');
    r1.className = 'r';
    var paste = btn('', 'paste', isRu() ? 'Вставить' : 'Paste');
    // Font Awesome 7 Free "paste" (solid, CC BY 4.0), the same set the site uses.
    paste.innerHTML = '<svg viewBox="0 0 512 512" width="20" height="20" aria-hidden="true"><path fill="currentColor" d="M64 48l224 0c8.8 0 16 7.2 16 16l0 48 48 0 0-48c0-35.3-28.7-64-64-64L64 0C28.7 0 0 28.7 0 64L0 384c0 35.3 28.7 64 64 64l112 0 0-48-112 0c-8.8 0-16-7.2-16-16L48 64c0-8.8 7.2-16 16-16zm176 72c0-13.3-10.7-24-24-24L104 96c-13.3 0-24 10.7-24 24s10.7 24 24 24l105.6 0c8.8-8.6 19-15.8 30.2-21.1 .1-.9 .2-1.9 .2-2.9zM448 464l-160 0c-8.8 0-16-7.2-16-16l0-224c0-8.8 7.2-16 16-16l101.5 0c4.2 0 8.3 1.7 11.3 4.7l58.5 58.5c3 3 4.7 7.1 4.7 11.3L464 448c0 8.8-7.2 16-16 16zM224 224l0 224c0 35.3 28.7 64 64 64l160 0c35.3 0 64-28.7 64-64l0-165.5c0-17-6.7-33.3-18.7-45.3l-58.5-58.5c-12-12-28.3-18.7-45.3-18.7L288 160c-35.3 0-64 28.7-64 64z"/></svg>';
    paste.addEventListener('click', function () {
      // Only now, on this tap: the clipboard is not read any other time. The WebView has no navigator.clipboard.readText, so the app's
      // own plugin reads it (DgClipboard; Android itself says "pasted from clipboard"), the browser API is the fallback.
      var native = window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.DgClipboard;
      var cb = navigator.clipboard;
      var read = native && typeof native.read === 'function' ? native.read().then(function (r) { return r && r.text; })
        : cb && typeof cb.readText === 'function' ? cb.readText() : Promise.resolve('');
      read.then(function (t) { if (t) insert(String(t).replace(/\s+/g, ' ').trim()); }, function () { /* refused: nothing to paste */ });
    });
    r1.appendChild(paste);
    MAIN.forEach(function (ch) { var b = btn(ch, LONG_L.test(ch) ? 'ser' : ''); b.addEventListener('click', function () { insert(ch); }); r1.appendChild(b); });
    var mb = btn('…', 'more', isRu() ? 'Ещё буквы' : 'More letters');
    r1.appendChild(mb);
    more = document.createElement('div');
    more.className = 'r';
    more.style.display = 'none';
    MORE.forEach(function (ch) { var b = btn(ch, LONG_L.test(ch) ? 'ser' : ''); b.addEventListener('click', function () { insert(ch); }); more.appendChild(b); });
    mb.addEventListener('click', function () { more.style.display = more.style.display === 'none' ? 'flex' : 'none'; place(); });
    bar.appendChild(r1);
    bar.appendChild(more);
    document.body.appendChild(bar);
  }

  // The keyboard's height in the page's own (zoomed) css px, and whether the WebView was already shrunk by it.
  function lift() {
    var z = zoom();
    var vv = window.visualViewport;
    var fromVv = vv ? Math.max(0, window.innerHeight - vv.height - vv.offsetTop) : 0;   // a browser: the keyboard overlays, the visual viewport shrinks
    if (fromVv > 80) return fromVv / z;
    if (!imeCss) return 0;
    var resized = baseH && (baseH - window.innerHeight) > imeCss * 0.5;                 // the WebView itself got shorter by the keyboard
    return resized ? 0 : imeCss / z;
  }

  function place() {
    if (!bar) return;
    bar.style.bottom = lift() + 'px';
  }

  // In the app the row waits for the keyboard's own report: shown before it, the row would sit at the bottom of the screen for a moment and
  // then jump up. Once any report has come (or in the app from the start) the row is there only while the keyboard is.
  var native = !!(window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform());
  var imeSeen = false;
  function wanted() {
    if (!enabled() || !field) return false;
    return (native || imeSeen) ? imeCss > 0 : true;
  }
  // Slides up from below (and back down) with the keyboard, never drawn in a wrong place: it is built invisible and only .on shows it.
  function render() {
    var on = wanted();
    if (on && !bar) build();
    if (!bar) return;
    place();
    bar.classList.toggle('on', on);
  }

  function show(el) {
    if (!enabled() || !typable(el)) return;
    field = el;
    if (!baseH || window.innerHeight > baseH) baseH = window.innerHeight;
    render();
  }
  function hide() {
    field = null;
    render();
  }

  window.__dgIme = function (h) {
    imeCss = h || 0;
    if (!imeCss) baseH = window.innerHeight;
    imeSeen = true;
    // The keyboard came up over a field that already has the focus (no focusin then), or went down while it keeps it.
    if (imeCss && !field && document.activeElement && typable(document.activeElement)) field = document.activeElement;
    render();
  };

  // Capture phase: a page's own handler may stop the event before it bubbles up here.
  document.addEventListener('focusin', function (e) { show(e.target); }, true);
  document.addEventListener('focusout', function () {
    // The next field may take the focus a tick later; the row stays then.
    setTimeout(function () { if (!typable(document.activeElement)) hide(); }, 120);
  }, true);
  window.addEventListener('resize', place);
  if (window.visualViewport) window.visualViewport.addEventListener('resize', place);
  // The page may focus its field on its own (the dictionary does, on load): no focusin comes after that.
  function already() { if (document.activeElement && typable(document.activeElement)) show(document.activeElement); }
  if (document.body) already(); else document.addEventListener('DOMContentLoaded', already);
  // The menu switch.
  window.addEventListener('dg:pali-bar', function () { render(); });
})();
