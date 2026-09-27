// The App Store screenshot tour: walks the calendar page through the views the listing shows and tells the driver
// when each is on screen. The same device as the reader app's test/ios-sim/tour.js — see there for why a tour
// rather than fixed timings (a screenshot taken at the wrong moment is worse than none: it looks like a bug).
//
// The tour does not know about light/dark itself — the driver (drive.sh) flips the simulator's OS appearance
// between two of these stages, which WebKit's prefers-color-scheme picks up live, no relaunch needed (the reader
// app's own drive.sh does the same between its light and dark screenshots).
//
// Loaded by the built page directly for this one purpose (build-app.yml's uposatha-ios-screenshots job appends
// the <script> tag to a build of www/ that is never shipped).
(function () {
  'use strict';

  var SETTLE_MS = 900;
  var SHOT_HOLD_MS = 4000;   // the driver screenshots the simulator from outside; the view must still be there when it does

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

  function tab(name) { var b = document.querySelector('#appnav [data-tab="' + name + '"]'); if (b) b.click(); }
  function filled(sel) { var el = document.querySelector(sel); return el && el.children.length > 0; }

  // Order matters: the driver switches the simulator to dark appearance right after "keys" and photographs
  // the rest in dark, so the light/dark split in the listing is this line, not a page decision.
  function run() {
    return waitFor(function () { return filled('#s-summary') && window.UposathaCore; }, 30000)
      .then(function () { return stage('home', function () { return filled('#meal'); }); })
      .then(function () { tab('cal'); return stage('cal', function () { return filled('#grid'); }); })
      .then(function () { tab('list'); return stage('list', function () { return filled('#list'); }); })
      .then(function () { tab('keys'); return stage('keys', function () { return filled('#keylist'); }); })
      .then(function () { tab('parts'); return stage('parts', function () { return filled('#pgrid'); }); })
      .then(function () {
        var gear = document.getElementById('app-gear');
        if (gear) gear.click();
        return stage('reminders', function () { return document.body.classList.contains('dg-drawer-open') && document.getElementById('sw-rem'); });
      })
      .then(function () {
        var close = document.querySelector('#dg-drawer .dg-drawer-close');
        if (close) close.click();
        tab('home');
        return stage('home2', function () { return !document.body.classList.contains('dg-drawer-open') && filled('#meal'); });
      })
      .then(function () { tab('cal'); return stage('cal2', function () { return filled('#grid'); }); })
      .then(function () { var P = plugin(); return P && P.stage ? Promise.resolve(P.stage({ name: 'done' })) : null; })
      .catch(function (e) { console.log('dg-tour: failed:', (e && e.message) || e); });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', run);
  else run();
})();
