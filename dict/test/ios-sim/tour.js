// The App Store screenshot tour: walks the dictionary page through the views the listing shows and tells the
// driver when each is on screen. Mirrors uposatha/test/ios-sim/tour.js for the mechanism (a native call
// writes Documents/stage.txt, the driver screenshots on the change) — see there for why a tour rather than
// fixed timings.
//
// Unlike Uposatha, the dictionary's theme is NOT tied to the system's light/dark setting: it is a stored
// preference (localStorage.theme) applied once at load, flipped live by the in-page control (#theme-toggle ->
// body.classList.toggle('dark-mode'), static/home.js). So this tour flips it itself, mid-session, rather than
// asking the driver to change the simulator's appearance (which the page would never notice) — and each stage
// name says which theme it is, since the driver applies no theme bookkeeping of its own.
//
// Loaded by the built page directly for this one purpose (build-app.yml's dict-ios-screenshots job appends the
// <script> tag to a build of www/ that is never shipped).
(function () {
  'use strict';

  var SETTLE_MS = 900;
  // The native call now blocks until the driver acks the screenshot (DgSelfTestPlugin.swift), so this is
  // just a small buffer after that ack, not the sole thing standing between a slow CI screenshot and a
  // missed stage (that used to be a fixed 7s guess — and guessing wrong lost stages under load).
  var SHOT_HOLD_MS = 300;

  function plugin() { var P = window.Capacitor && window.Capacitor.Plugins; return P && P.DgSelfTest; }
  function wait(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }

  function waitFor(check, timeout) {
    // 45s default, not 20s: a freshly-launched simulator's first real interactions (autocomplete, first
    // navigation, first panel open) can be slow to settle — the SAME check that always passed fine by
    // stage 5 (declension-dark onward) intermittently timed out here on stage 2-4, on whichever device
    // happened to run first in the job, dropping those stages' screenshots entirely.
    var started = Date.now(), limit = timeout || 45000;
    return new Promise(function (resolve) {
      (function poll() {
        var ok = false;
        try { ok = !!check(); } catch (e) { ok = false; }
        if (ok) return resolve(true);
        if (Date.now() - started > limit) return resolve(false);
        setTimeout(poll, 200);
      })();
    });
  }

  function stage(name, ready) {
    return waitFor(ready).then(function () { return wait(SETTLE_MS); }).then(function () {
      var P = plugin();
      if (!P || typeof P.stage !== 'function') { console.log('dg-tour: no stage plugin, stopping'); return false; }
      return Promise.resolve(P.stage({ name: name })).then(function () { return wait(SHOT_HOLD_MS); }).then(function () { return true; });
    });
  }

  function count(sel) { return document.querySelectorAll(sel).length; }
  function $(sel) { return document.querySelector(sel); }
  function search(word) {
    var box = $('#search-box');
    if (box) box.value = word;
    var form = $('#search-form');
    if (form) { if (form.requestSubmit) form.requestSubmit(); else form.submit(); }
  }

  function run() {
    return waitFor(function () { return $('#search-box') && $('.dictlist'); }, 30000)
      // 1. The start screen itself: what a reader sees before typing anything. Blur first: the search box
      // auto-focuses on load, and a screenshot with the keyboard up hides half the hero copy behind it.
      .then(function () { var ae = document.activeElement; if (ae && ae.blur) ae.blur(); return stage('home', function () { return document.body.dataset.screen === 'start' && count('.dictlist li') > 0; }); })
      // 2. Autocomplete suggestions.
      .then(function () {
        var box = $('#search-box');
        if (box) { box.focus(); box.value = 'dham'; box.dispatchEvent(new Event('input', { bubbles: true })); }
        return stage('search', function () { return count('.ui-autocomplete .ui-menu-item') > 0; });
      })
      // 3. A real entry: several dictionaries at once (DPD and Sanskrit are expanded by default).
      .then(function () {
        search('dhamma');
        return stage('sources', function () { return document.body.dataset.screen === 'entry' && count('#external-dicts-container > div[id^="ext-slot-"]') >= 2; });
      })
      // 4. The app's own settings panel (font size, theme, sandhi mark, voice, offline dictionary, ...).
      .then(function () {
        if (typeof window.dgToggleMenu === 'function') window.dgToggleMenu();
        return stage('settings', function () { var m = $('#p-menu'); return m && m.dataset.open === 'true'; });
      })
      // Close it, then switch to dark — live, no reload (the reason this app needed its own mechanism).
      .then(function () {
        if (typeof window.closePanels === 'function') window.closePanels();
        var tt = document.getElementById('theme-toggle');
        if (tt) { tt.checked = true; tt.dispatchEvent(new Event('change', { bubbles: true })); }
        return waitFor(function () { return !$('.panel[data-open="true"]') && document.body.classList.contains('dark-mode'); }, 8000);
      })
      // 5. The declension (grammar) table, in dark.
      .then(function () {
        var btn = [].slice.call(document.querySelectorAll('a.dpd-button')).filter(function (a) { return /declension/i.test(a.textContent || ''); })[0];
        if (btn) btn.click();
        return stage('declension-dark', function () { return count('table.grammar tr') > 3; });
      })
      // 6. Canon definitions (Tripitaka/Sutta-Vinaya, collapsed by default), in dark.
      .then(function () {
        var head = $('[data-dictcode="tripitaka"]');
        if (head) head.click();
        return stage('canon-dark', function () {
          var slot = $('#ext-slot-tripitaka'), icon = slot && slot.querySelector('.ext-dict-toggle-icon');
          var open = !!icon && icon.textContent.indexOf('▼') >= 0 && slot.children.length > 2;
          // Unlike the declension click (which the page scrolls to on its own), expanding this slot leaves
          // the scroll position wherever declension-dark left it — the previous run's canon-dark screenshot
          // was pixel-identical to declension-dark because of exactly that, nothing had actually scrolled.
          if (open && head && head.scrollIntoView) head.scrollIntoView({ block: 'start' });
          return open;
        });
      })
      // 7. A different word, still dark: the variety the listing wants (not the same entry six times over).
      .then(function () {
        search('nibbana');
        return stage('word2-dark', function () { return document.body.dataset.screen === 'entry' && count('#external-dicts-container > div[id^="ext-slot-"]') >= 2; });
      })
      .then(function () { var P = plugin(); return P && P.stage ? Promise.resolve(P.stage({ name: 'done' })) : null; })
      .catch(function (e) { console.log('dg-tour: failed:', (e && e.message) || e); });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', run);
  else run();
})();
