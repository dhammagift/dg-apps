// The App Store screenshot tour: walks the dictionary page through the views the listing shows and tells the
// driver when each is on screen. Mirrors uposatha/test/ios-sim/tour.js — see there for why a tour rather than
// fixed timings, and why the driver (not the page) flips light/dark appearance between two of these stages.
//
// Loaded by the built page directly for this one purpose (build-app.yml's dict-ios-screenshots job appends the
// <script> tag to a build of www/ that is never shipped).
(function () {
  'use strict';

  var SETTLE_MS = 900;
  var SHOT_HOLD_MS = 4000;
  var WORD = 'dhamma';

  function plugin() { var P = window.Capacitor && window.Capacitor.Plugins; return P && P.DgSelfTest; }
  function wait(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }

  function waitFor(check, timeout) {
    var started = Date.now(), limit = timeout || 20000;
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

  function run() {
    return waitFor(function () { return $('#search-box') && $('.dictlist'); }, 30000)
      // 1. The start screen's own search box, with autocomplete suggestions (history is empty on a fresh
      // install, so the suggestions here are the word list, which needs 3+ characters — see autopali.js).
      .then(function () {
        var box = $('#search-box');
        if (box) { box.focus(); box.value = 'dham'; box.dispatchEvent(new Event('input', { bubbles: true })); }
        return stage('search', function () { return count('.ui-autocomplete .ui-menu-item') > 0; });
      })
      // 2. A real entry: several dictionaries at once (DPD and Sanskrit are expanded by default).
      .then(function () {
        var box = $('#search-box');
        if (box) { box.value = WORD; }
        var form = $('#search-form');
        if (form) form.requestSubmit ? form.requestSubmit() : form.submit();
        return stage('sources', function () {
          return document.body.dataset.screen === 'entry' && count('#external-dicts-container > div') >= 2 &&
            $('#ext-slot-dpd .ext-dict-toggle-icon') && $('#ext-slot-dpd .ext-dict-toggle-icon').textContent.indexOf('▼') >= 0;
        });
      })
      // 3. The declension (grammar) table of the first sense.
      .then(function () {
        var btn = [].slice.call(document.querySelectorAll('a.dpd-button')).filter(function (a) { return /declension/i.test(a.textContent || ''); })[0];
        if (btn) btn.click();
        return stage('declension', function () { return count('table.grammar tr') > 3; });
      })
      // 4. Canon definitions (the Tripitaka/Sutta-Vinaya dictionary, collapsed by default).
      .then(function () {
        var head = $('[data-dictcode="tripitaka"]');
        if (head) head.click();
        return stage('canon', function () {
          var slot = $('#ext-slot-tripitaka');
          return slot && slot.querySelector('.ext-dict-toggle-icon') && slot.querySelector('.ext-dict-toggle-icon').textContent.indexOf('▼') >= 0 && slot.children.length > 2;
        });
      })
      // 5. Recent words: back to the start screen, where the word just looked up is now in the history.
      .then(function () {
        var logo = $('#logo-link') || $('.wordmark');
        if (logo) logo.click();
        return stage('recent', function () {
          return document.body.dataset.screen === 'start' && (count('#history-pane li') > 0 || count('#chips > *') > 0);
        });
      })
      // 6. One more entry, in dark: a different, visually rich word for a good closing marketing shot.
      .then(function () {
        var box = $('#search-box');
        if (box) { box.value = 'nibbana'; }
        var form = $('#search-form');
        if (form) form.requestSubmit ? form.requestSubmit() : form.submit();
        return stage('sources-dark', function () {
          return document.body.dataset.screen === 'entry' && count('#external-dicts-container > div') >= 2;
        });
      })
      .then(function () { var P = plugin(); return P && P.stage ? Promise.resolve(P.stage({ name: 'done' })) : null; })
      .catch(function (e) { console.log('dg-tour: failed:', (e && e.message) || e); });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', run);
  else run();
})();
