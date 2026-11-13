// Shared by the bundled-page apps (Dhamma.Gift, Uposatha, Dict): the parts of their bridges that keep a page that is
// BUNDLED in the APK working and current. Pasted into each bridge by its build.js at the marker
// "// @site-updater"; the bridge defines SITE_CONFIG first and calls updateSite() when the page has loaded.
//
//   SITE_CONFIG = { site: 'https://dict.dhamma.gift', urlFor: function (path) { return path; }, updatable: optional (path) => bool,
//                   gate: optional (manifest) => Promise<bool> (false: this check applies nothing), silent: optional bool (no "new version" bar),
//                   manual: optional bool (nothing is fetched unless a person asks: the version row's button; no checks at start or on return to the app),
//                   checkEvery: optional ms (a check by itself once this much time has passed, manual or not) }
//
// Uses the bridge's Cap (window.Capacitor) and store() (localStorage read).
  // ---- keeping the bundled page up to date --------------------------------------------------
  //
  // The APK holds the page as it was when it was built. When the phone is online, and at most every 6 hours, the site's
  // SIGNED list of its files (SITE + /app-site-manifest.json: dg-node scripts/site-manifest.js signs it on the server)
  // is read. Nothing is taken unless the signature is good, the list is for this site, and the site's build is NEWER than
  // the bundle's (the bundle's site-manifest.json carries its commit time): an app built from code ahead of the site must
  // never trade its files for the site's older ones. Then only the files whose SHA-256 in the list differs from what the
  // app has are downloaded, and each must hash to exactly the listed value. All of them go to DgSite or none does; with
  // Dhamma.Gift's DgSite they are kept apart until the next start of the app, so a running page never mixes old and new
  // files. A file the new page brings that the bundle has never had (named in a new html / css) is fetched too, if the list
  // has it. Nothing is ever deleted: a file the site no longer has stays, harmlessly.
  // SITE_CONFIG (defined by the bridge that pastes this in): { site: where the page comes from, urlFor(path): a
  // bundled file's address on the site (a page is not served under its .html name) }
  var SITE = SITE_CONFIG.site;
  var SITE_CHECK_EVERY = 6 * 3600 * 1000;   // a successful check is not repeated sooner; a failed one does not count (see updateSite)
  // The public half of the key the site's list is signed with (ECDSA P-256, SPKI; the private half is on the server only:
  // /root/.secrets/site-manifest-signing.pem). A new key needs a new app build. window.__dgSiteKey is a test hook only (the
  // browser tests sign with a throwaway key): read once, so it counts only when set before the bridge runs, and only on the
  // tests' 127.0.0.1 servers (an app's own origin is never 127.0.0.1, so there the hook is ignored).
  var SITE_PUBLIC_KEY = (window.location.hostname === '127.0.0.1' && window.__dgSiteKey) || 'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEHXt2cUx8f9Uw4xcYCvmqMMhZnQw/ei9pVMlIBhxMdPeOlKJrcwU+dTNcIsSdYkDQZpk4KOddNbrJe68Hi5ryUg==';
  var RUN_KEY = 'dgSiteRun';   // sessionStorage: set by the first page of a run of the app (it lives as long as the WebView)

  function bytesToBase64(bytes) {
    var out = '';
    for (var i = 0; i < bytes.length; i += 0x8000) out += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    return btoa(out);
  }

  function hex(buf) {
    return Array.prototype.map.call(new Uint8Array(buf), function (b) { return ('0' + b.toString(16)).slice(-2); }).join('');
  }

  // Local files a text file mentions: absolute paths under the site's own roots, and, in html, relative src / href
  // (resolved against the file's own directory).
  function referencedPaths(text, from) {
    var found = [], m;
    var abs = /["'(=]\s*(\/(?:assets|nodejs|offline|reader|settings|spa|static)\/[A-Za-z0-9_\-./]+\.[A-Za-z0-9]+)/g;
    while ((m = abs.exec(text))) found.push(m[1]);
    if (/\.html$/.test(from)) {
      var rel = /(?:src|href)="([A-Za-z0-9_\-./]+\.[A-Za-z0-9]+)(?:\?[^"]*)?"/g;
      var dir = from.replace(/[^/]*$/, '');
      while ((m = rel.exec(text))) {
        if (/^(?:https?:|\/\/|#)/.test(m[1])) continue;
        found.push(m[1].charAt(0) === '/' ? m[1] : dir + m[1]);
      }
    }
    return found;
  }

  // The bar that tells the reader the page has new files (the files are already saved: the next start uses them anyway,
  // the button only reloads the page now). Shown once per update; "x" hides it until the next start.
  // The offline library's consent sheet (dg-node offline-status.js, #dgConsent) sits at the bottom too: on a first start the bar
  // lay over its Download button, and a tap there was a tap on Update - the page reloaded and the download never began (Test Lab
  // 2026-10-30, DG 566). The bar waits until the sheet is answered.
  function afterConsent(fn) {
    if (!document.getElementById('dgConsent')) { fn(); return; }
    var mo = new MutationObserver(function () {
      if (document.getElementById('dgConsent')) return;
      mo.disconnect();
      fn();
    });
    mo.observe(document.body, { childList: true, subtree: true });
  }
  // White (or dark) card in the page's theme, also when the theme is switched while it is up (dark = a solid dark body background).
  function paintLikePage(el) {
    function paint() {
      var bg = (getComputedStyle(document.body).backgroundColor.match(/[\d.]+/g) || [255, 255, 255]).map(Number);
      var dark = (0.299 * bg[0] + 0.587 * bg[1] + 0.114 * bg[2]) < 128 && (bg[3] === undefined || bg[3] > 0.5);
      el.style.borderColor = dark ? '#34414f' : '#d9e1e8';
      el.style.background = dark ? '#1d2630' : '#fff';
      el.style.color = dark ? '#e8eef4' : '#1b2430';
      el.style.boxShadow = '0 8px 28px ' + (dark ? 'rgba(0,0,0,.55)' : 'rgba(15,30,50,.22)');
    }
    paint();
    new MutationObserver(paint).observe(document.body, { attributes: true, attributeFilter: ['class'] });
  }
  function showUpdateBar() {
    if (document.getElementById('dg-upd')) return;
    function barText() {
      var ru = typeof isRu === 'function' ? isRu() : /^ru/i.test(document.documentElement.lang || '');
      return ru ? { head: 'Доступна новая версия', sub: 'Страница обновится за секунду', go: 'Обновить', busy: 'Обновляю…', later: 'Позже' }
                : { head: 'New version available', sub: 'The page reloads in a second', go: 'Update', busy: 'Updating…', later: 'Later' };
    }
    var t = barText();
    var busy = false;
    var bar = document.createElement('div');
    bar.id = 'dg-upd';
    bar.setAttribute('role', 'status');
    bar.style.cssText = 'position:fixed;left:12px;right:12px;max-width:440px;margin:0 auto;bottom:calc(14px + max(env(safe-area-inset-bottom,0px),var(--safe-area-inset-bottom,0px)));z-index:2147482000;'
      + 'display:flex;align-items:center;gap:12px;padding:12px 12px 12px 16px;border-radius:16px;border:1px solid;font:500 15px/1.25 system-ui,sans-serif';
    paintLikePage(bar);
    var text = document.createElement('div');
    text.style.cssText = 'flex:1;min-width:0';
    text.innerHTML = '<div></div><div style="font-weight:400;font-size:12.5px;opacity:.7;margin-top:2px"></div>';
    text.firstChild.textContent = t.head;
    text.lastChild.textContent = t.sub;
    var go = document.createElement('button');
    go.type = 'button';
    go.textContent = t.go;
    go.style.cssText = 'font:600 14px system-ui,sans-serif;border:0;border-radius:11px;padding:10px 16px;background:#139b7b;color:#fff';
    go.addEventListener('click', function () {
      busy = true;
      text.firstChild.textContent = t.busy;
      text.lastChild.textContent = '';
      go.remove(); x.remove();
      try { localStorage.setItem('dgSiteApplied', '1'); } catch (e) { /* no storage: no confirmation after the reload */ }
      // The kept-apart files take over now (Dhamma.Gift's DgSite.apply), and the reload counts as a start for the boot guard.
      nativeSite('apply').catch(function () { /* older DgSite: the files are live already */ }).then(function () {
        try { sessionStorage.removeItem(RUN_KEY); } catch (e) { /* no storage */ }
        setTimeout(function () { location.reload(); }, 250);
      });
    });
    var x = document.createElement('button');
    x.type = 'button';
    x.setAttribute('aria-label', t.later);
    x.textContent = '✕';
    x.style.cssText = 'border:0;background:none;color:inherit;opacity:.55;padding:8px;font-size:18px;line-height:1';
    x.addEventListener('click', function () { bar.remove(); });
    bar.appendChild(text); bar.appendChild(go); bar.appendChild(x);
    document.body.appendChild(bar);
    // The strings are a hand-kept ru/en table (not i18n {{tokens}}), so re-apply them when the page language is switched
    // while the bar is up — otherwise the bar keeps whatever language was active when it was first shown (mixed UI).
    function relabel() {
      if (!document.body.contains(bar)) { document.removeEventListener('dhamma:languagechange', relabel); return; }
      t = barText();
      if (busy) { text.firstChild.textContent = t.busy; }
      else { text.firstChild.textContent = t.head; text.lastChild.textContent = t.sub; go.textContent = t.go; }
      x.setAttribute('aria-label', t.later);
    }
    document.addEventListener('dhamma:languagechange', relabel);
  }

  // ---- what the person is told ---------------------------------------------------------------
  function siteRu() { return typeof isRu === 'function' ? isRu() : /^ru/i.test(document.documentElement.lang || ''); }
  var ST = {
    ru: { busy: 'Проверяю…', current: 'Актуально', new: 'Обновление получено - нажмите «Обновить» внизу, приложение перезапустится', needsApp: 'На сайте есть обновление, но для него нужна новая версия приложения', offline: 'Нет соединения', failed: 'Не удалось проверить, попробуйте позже',
          done: 'Обновление установлено', restart: 'Перезапустить', broke: 'Обновление не заработало', brokeSub: 'Включена встроенная версия. Если что-то не работает, переустановите приложение из магазина' },
    en: { busy: 'Checking…', current: 'Up to date', new: 'Update received - tap Update below, the app restarts', needsApp: 'The site has an update that needs a newer app version', offline: 'No connection', failed: 'Could not check, try again later',
          done: 'Update installed', restart: 'Restart', broke: 'The update did not work', brokeSub: 'The built-in version is back. If something is broken, reinstall the app from the store' }
  };
  function st() { return ST[siteRu() ? 'ru' : 'en']; }
  // Checks now (the version row's button) and says the result through say(text); resolves when done.
  window.__dgSiteCheckSay = function (say) {
    say(st().busy);
    return updateSite(true).then(function (r) { say(st()[r.state] || st().failed); }, function () { say(st().failed); });
  };
  // A short message over the page: "applied" after the reload an update asked for, "did not work" after the safety net fired.
  // "Applied" carries a Restart button: swiping the app away only sends it to the background, so "close and reopen" could not
  // be done (owner 2026-11-02). DgSite.restart starts the app afresh (Android) or reloads the page from scratch (iOS).
  function showNotice(head, sub, bad) {
    if (!document.body) return;
    var n = document.createElement('div');
    n.setAttribute('role', 'status');
    n.style.cssText = 'position:fixed;left:12px;right:12px;max-width:440px;margin:0 auto;bottom:calc(14px + max(env(safe-area-inset-bottom,0px),var(--safe-area-inset-bottom,0px)));z-index:2147482000;'
      + 'display:flex;align-items:center;gap:12px;padding:12px 12px 12px 16px;border-radius:16px;border:1px solid;font:500 15px/1.25 system-ui,sans-serif';
    if (bad) n.style.cssText += ';border-color:#f2b33d;box-shadow:0 8px 28px rgba(15,30,50,.3);color:#2b1d00;background:#f2b33d';   // warning amber, not danger red
    else paintLikePage(n);   // like the "New version" bar
    n.innerHTML = '<div style="flex:1;min-width:0"><div></div><div style="font-weight:400;font-size:12.5px;opacity:.9;margin-top:2px"></div></div>';
    n.firstChild.firstChild.innerHTML = bad ? '⚠ ' : '<span style="color:#139b7b">✓</span> ';
    n.firstChild.firstChild.appendChild(document.createTextNode(head));
    if (sub) n.firstChild.lastChild.textContent = sub; else n.firstChild.lastChild.remove();
    if (!bad) {
      var go = document.createElement('button');
      go.type = 'button';
      go.textContent = st().restart;
      go.style.cssText = 'font:600 14px system-ui,sans-serif;border:0;border-radius:11px;padding:10px 16px;background:#139b7b;color:#fff';
      go.addEventListener('click', function (e) {
        e.stopPropagation();
        nativeSite('restart').catch(function () { location.reload(); });
      });
      n.appendChild(go);
      var x = document.createElement('button');   // Restart is optional: a visible way out, as on the "New version" bar
      x.type = 'button';
      x.setAttribute('aria-label', siteRu() ? 'Закрыть' : 'Close');
      x.textContent = '✕';
      x.style.cssText = 'border:0;background:none;color:inherit;opacity:.55;padding:8px;font-size:18px;line-height:1';
      n.appendChild(x);
    }
    n.addEventListener('click', function () { n.remove(); });
    document.body.appendChild(n);
    setTimeout(function () { n.remove(); }, bad ? 15000 : 10000);   // time to reach Restart
  }
  function showPendingNotice() {
    var applied = store('dgSiteApplied') === '1', broke = store('dgSiteBroke') === '1';
    if (!applied && !broke) return;
    try { localStorage.removeItem('dgSiteApplied'); localStorage.removeItem('dgSiteBroke'); } catch (e) { /* ignore */ }
    if (broke) showNotice(st().broke, st().brokeSub, true); else showNotice(st().done, '', false);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', showPendingNotice); else setTimeout(showPendingNotice, 500);

  // A DgSite method that only Dhamma.Gift's plugin has (commit / discard / apply: a round kept apart until the next start).
  // Capacitor answers an unknown method with code UNIMPLEMENTED; Dict's and Uposatha's plugins write the live files at once.
  function nativeSite(name) {
    var DS = Cap.Plugins && Cap.Plugins.DgSite;
    if (!DS || typeof DS[name] !== 'function') return Promise.reject({ code: 'UNIMPLEMENTED' });
    return Promise.resolve().then(function () { return DS[name](); });
  }
  function unimplemented(e) { return !!e && e.code === 'UNIMPLEMENTED'; }
  function forgetDownloads() {
    try { ['dgSiteHashes', 'dgSiteCheckedAt', 'dgSiteFresh', 'dgSiteBoots'].forEach(function (k) { localStorage.removeItem(k); }); } catch (e) { /* ignore */ }
  }

  // New files that stop the page from starting must not trap the app: three STARTS of the app in a row in which no page ran
  // for a few seconds put the bundle's own copy back (everything downloaded is dropped). Starts, not page loads: a reload, a
  // History row, a deep link or the dictionary's step to /ru/ load a page again within the same run (sessionStorage).
  // dgSiteFresh: 'pending' = stored during a run, serving from the next one; '1' = serving, not yet seen to work; '0' = fine.
  function newRun() {
    try {
      if (sessionStorage.getItem(RUN_KEY)) return false;
      sessionStorage.setItem(RUN_KEY, '1');
    } catch (e) { /* no storage: every load counts */ }
    return true;
  }
  (function bootGuard() {
    var DS = Cap.Plugins && Cap.Plugins.DgSite;
    var fresh = store('dgSiteFresh');
    if (newRun() && (fresh === '1' || fresh === 'pending')) {
      var n = fresh === 'pending' ? 1 : (parseInt(store('dgSiteBoots'), 10) || 0) + 1;
      try { localStorage.setItem('dgSiteFresh', '1'); localStorage.setItem('dgSiteBoots', String(n)); } catch (e) { /* no storage: no guard */ }
      if (n >= 3 && DS && typeof DS.clear === 'function') {
        DS.clear().then(function () {
          forgetDownloads();
          try { localStorage.setItem('dgSiteBroke', '1'); } catch (e) { /* ignore */ }
          console.log('[dg-site] the downloaded files did not start the page: back to the bundled copy');
        }, function () { /* try again at the next start */ });
        return;
      }
    }
    if (store('dgSiteFresh') !== '1') return;
    // This page ran and came up (SITE_CONFIG.ready: Dhamma.Gift's router is there), or the person left it after it came up: the
    // files it started with are good. Not up 15 s after load with files not yet proven (a taken page whose script throws - ultra's
    // review 2026-11-12): the bundle's own copy goes back at once and the page loads again, not three starts later.
    var done = false, ready = SITE_CONFIG.ready || function () { return true; };
    function settled() {
      if (done || store('dgSiteFresh') !== '1' || !ready()) return;
      done = true;
      try { localStorage.setItem('dgSiteBoots', '0'); localStorage.setItem('dgSiteFresh', '0'); } catch (e) { /* no storage */ }
    }
    function watch(waited) {
      setTimeout(function () {
        if (done) return;
        if (ready()) { settled(); return; }
        if (waited < 15000) { watch(waited + 1000); return; }
        if (!DS || typeof DS.clear !== 'function') return;
        DS.clear().then(function () {
          forgetDownloads();
          try { localStorage.setItem('dgSiteBroke', '1'); } catch (e) { /* ignore */ }
          console.log('[dg-site] the page did not come up with the downloaded files: back to the bundled copy');
          if (window.location && window.location.reload) window.location.reload();
        }, function () { /* the start count above still applies */ });
      }, waited === 0 ? 4000 : 1000);
    }
    if (document.readyState === 'complete') watch(0); else window.addEventListener('load', function () { watch(0); }, { once: true });
    document.addEventListener('visibilitychange', function () { if (document.visibilityState === 'hidden') settled(); });
  })();

  // A new version of the app brings a new bundle: what an older version downloaded (it sits in front of the bundled files, and its
  // hashes are compared with the site instead of the bundle's) is dropped, so the bundle is the starting point again.
  (function versionGuard() {
    var DS = Cap.Plugins && Cap.Plugins.DgSite, v = window.__DG_APP_VERSION__;
    if (!v || !DS || typeof DS.clear !== 'function' || store('dgAppVersion') === v) return;
    DS.clear().then(function () {
      forgetDownloads();
      try { localStorage.setItem('dgAppVersion', v); } catch (e) { /* no storage */ }
    }, function () { /* try again at the next start */ });
  })();

  function b64bytes(s) {
    var bin = atob(s), out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  function definite(message) { var e = new Error(message); e.definite = true; return e; }
  // The site's list of its files: { origin, commit, commitTime, contains: [12-char ids of its last commits], hashes: { site
  // path or full URL: sha256 } }, served as
  // { signed: "<the list as JSON text>", sig: "<base64 ECDSA P-256 / SHA-256 signature of that text, r||s>" }. Rejects
  // with e.definite when the site answered and the answer is no (no list, not signed, a bad signature, another site's).
  function signedSiteManifest() {
    return fetch(SITE + '/app-site-manifest.json', { cache: 'no-cache' }).then(function (r) {
      if (!r.ok) throw definite('the site has no signed file list (HTTP ' + r.status + ')');
      return r.json();
    }).then(function (env) {
      if (!env || typeof env.signed !== 'string' || typeof env.sig !== 'string') throw definite('the site\'s file list is not signed');
      return crypto.subtle.importKey('spki', b64bytes(SITE_PUBLIC_KEY), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']).then(function (key) {
        return crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, key, b64bytes(env.sig), new TextEncoder().encode(env.signed));
      }).then(function (good) {
        if (!good) throw definite('the site\'s file list has a bad signature');
        var m = JSON.parse(env.signed);
        if (!m || m.origin !== SITE || !m.hashes || !m.commitTime) throw definite('the signed file list is not for ' + SITE);
        return m;
      });
    });
  }
  // Is the site's build newer than the bundle? Built from a known commit (Dhamma.Gift): the site must have moved on FROM it (its
  // list carries the last commits of its history, `contains`), not merely be later - a later fix made on an older line of the
  // code would still lack the bundle's own changes. Otherwise: the site's commit is later than the moment the bundle was built.
  function siteIsNewer(bundle, site) {
    if (bundle.commit) return site.commit !== bundle.commit && (site.contains || []).indexOf(bundle.commit.slice(0, 12)) >= 0;
    var built = Math.floor((Date.parse(bundle.built || '') || 0) / 1000);
    return !!built && site.commitTime > built;
  }

  var checking = null;   // the round under way: a person's check joins it (it answered 'busy' at once - the icon stopped, "Checking…" stayed)
  var staged = false;   // a round is kept apart for the next start (Dhamma.Gift): no second round in this run
  function stamp() { try { localStorage.setItem('dgSiteCheckedAt', String(Date.now())); } catch (e) { /* checked again next time */ } }
  // force: a person asked (the version row in the menu) - no waiting for SITE_CHECK_EVERY. Resolves {state: 'offline' | 'busy' | 'failed' | 'new' | 'current'}.
  function updateSite(force) {
    var DS = Cap.Plugins && Cap.Plugins.DgSite;
    var res = { state: 'current' };
    if (!DS || !window.crypto || !crypto.subtle) return Promise.resolve({ state: 'failed' });
    // no network unless a person asks - or, with checkEvery, once that much time has passed since the last good check
    // (owner 2026-11-12, Uposatha: nobody knows to press "check", let alone when)
    var every = SITE_CONFIG.checkEvery || SITE_CHECK_EVERY, last = parseInt(store('dgSiteCheckedAt'), 10) || 0;
    if (SITE_CONFIG.manual && !force && SITE_CONFIG.checkEvery && !last) { stamp(); return Promise.resolve(res); }   // the month counts from the first start
    if (SITE_CONFIG.manual && !force && !(SITE_CONFIG.checkEvery && Date.now() - last >= every)) return Promise.resolve(res);
    if (checking) return checking;
    if (staged) return Promise.resolve({ state: 'new' });
    if (navigator.onLine === false) return Promise.resolve({ state: 'offline' });
    // A first start has no time stamp and always checks; after that, not sooner than SITE_CHECK_EVERY.
    if (!force && Date.now() - last < every) return Promise.resolve(res);
    var hashes = {};
    try { hashes = JSON.parse(store('dgSiteHashes')) || {}; } catch (e) { hashes = {}; }
    var chain = Promise.all([
      fetch('/site-manifest.json', { cache: 'no-store' }).then(function (r) { return r.json(); }),
      signedSiteManifest(),
    ]).then(function (both) {
      var bundle = both[0], site = both[1];
      if (!siteIsNewer(bundle, site)) {
        console.log('[dg-site] the site (' + String(site.commit || '').slice(0, 8) + ') is not newer than the bundle: nothing to take');
        stamp();
        return null;
      }
      // The app may refuse an update that its own pages cannot take (Dhamma.Gift: the site's page has elements the bundled page lacks).
      // A refusal is said as such, not as «Актуально»: the site is newer and the app did not take it (owner 2026-11-13: «Актуально.
      // Оно не актуально» - every update had been refused for an id only the server's page had).
      if (SITE_CONFIG.gate) return Promise.resolve(SITE_CONFIG.gate(bundle)).then(function (open) { if (open) return run(bundle, site); res.state = 'needsApp'; return null; });
      return run(bundle, site);
    });
    function run(bundle, site) {
      var ok = SITE_CONFIG.updatable || function () { return true; };
      var queue = bundle.files.filter(ok), seen = {}, changes = [], written = [], shown = 0, fetched = 0, failed = 0;
      bundle.files.forEach(function (f) { seen[f] = 1; });
      function urlOf(path) { var from = SITE_CONFIG.urlFor(path); return /^https?:\/\//.test(from) ? from : SITE + from; }
      // The list names the site's own files by path and anything elsewhere (Dict's icons from dhamma.gift) by full URL.
      function listed(url) { return site.hashes[url.indexOf(SITE + '/') === 0 ? url.slice(SITE.length) : url]; }
      function next() {
        var path = queue.shift();
        if (!path) return Promise.resolve();
        var url = urlOf(path), want = listed(url), had = hashes[path] || (bundle.hashes || {})[path];
        // Not in the list: the site no longer has it (or does not vouch for it), the app keeps its copy. Same hash: nothing to fetch.
        if (!want || want === had) return next();
        fetched++;
        return fetch(url, { cache: 'no-cache' }).then(function (r) {
          if (!r.ok) throw new Error('HTTP ' + r.status + ' for ' + url);
          return r.arrayBuffer();
        }).then(function (buf) {
          return crypto.subtle.digest('SHA-256', buf).then(function (digest) {
            // Exactly the bytes the signed list names, or nothing at all (a cache in between, a file changed after signing).
            if (hex(digest) !== want) throw new Error(path + ' does not match the signed list');
            // A page and its stylesheets name the files they need; a script's strings name half the site's assets
            // (a first version followed those and pulled 30 MB), and what a script fetches on demand is in the bundle already.
            if (/\.(html|css)$/.test(path)) {
              referencedPaths(new TextDecoder().decode(buf), path).forEach(function (p) { if (!seen[p] && ok(p)) { seen[p] = 1; queue.push(p); } });
            }
            changes.push({ path: path, data: bytesToBase64(new Uint8Array(buf)), sha: want, known: !!had });
          });
        }).then(next, function (e) { failed++; console.log('[dg-site] ' + ((e && e.message) || e) + ': nothing applied'); });
      }
      // Everything is fetched before anything is stored, the pages go last, and the first write that fails stops the round.
      function store1() {
        var c = changes.shift();
        if (!c) return Promise.resolve();
        return DS.put({ path: c.path, data: c.data }).then(function () { written.push(c); return store1(); });
      }
      // A round that could not be stored completely is taken back: Dhamma.Gift's DgSite drops the kept-apart round; the
      // others wrote the live files, so everything downloaded goes and the bundle is the starting point again.
      function rollback(e) {
        failed++;
        console.log('[dg-site] could not store the update (' + ((e && e.message) || e) + '): rolled back');
        return nativeSite('discard').catch(function (e2) {
          if (!unimplemented(e2)) throw e2;
          return DS.clear().then(forgetDownloads);
        }).catch(function () { /* an incomplete round is never served: the next start drops it */ });
      }
      // The pages (SITE_CONFIG.pages: [{path, source, make}]): the site's page source, exactly as the signed list names it, made into
      // the app's page by make() (page-transforms.js, the same edits the build makes). An edit that cannot be made keeps the app's page.
      // Pages come in groups (pg.group, default 'main'): each group is one piece, and one group that cannot be made keeps only itself.
      function pages() {
        var groups = {}, order = [];
        (SITE_CONFIG.pages || []).forEach(function (pg) { var g = pg.group || 'main'; if (!groups[g]) { groups[g] = []; order.push(g); } groups[g].push(pg); });
        return order.reduce(function (p, g) { return p.then(function () { return group(groups[g].slice()); }); }, Promise.resolve());
      }
      function group(list) {
        var made = [], broken = false, due = false;
        // Taken together or not at all: the page and the bundles it calls are one piece (any of them changed = all are made again)
        list.forEach(function (pg) {
          (pg.sources || [pg.source]).forEach(function (src) { var w = listed(urlOf(src)); if (!w) broken = true; });
        });
        if (broken) return Promise.resolve();   // the site does not vouch for a source: the app's own copies stay
        function keyOf(pg) { return (pg.sources || [pg.source]).map(function (src) { return listed(urlOf(src)); }).join(','); }
        list.forEach(function (pg) { if (keyOf(pg) !== hashes['page:' + pg.path]) due = true; });
        if (!due) return Promise.resolve();
        function one() {
          var pg = list.shift();
          if (!pg) return Promise.resolve();
          var srcs = pg.sources || [pg.source];
          return Promise.all(srcs.map(function (src) {
            var url = urlOf(src), want = listed(url);
            fetched++;
            return fetch(url, { cache: 'no-cache' }).then(function (r) {
              if (!r.ok) throw new Error('HTTP ' + r.status + ' for ' + url);
              return r.arrayBuffer();
            }).then(function (buf) {
              return crypto.subtle.digest('SHA-256', buf).then(function (digest) {
                if (hex(digest) !== want) throw new Error(src + ' does not match the signed list');
                return new TextDecoder().decode(buf);
              });
            });
          })).then(function (texts) {
            var out = pg.make(pg.sources ? texts : texts[0]);
            made.push({ path: pg.path, data: bytesToBase64(new TextEncoder().encode(out)), sha: keyOf(pg), key: 'page:' + pg.path, known: true });
            return one();
          });
        }
        return one().then(function () { Array.prototype.push.apply(changes, made); },
          function (e) { console.log('[dg-site] the page and its bundles are kept as they are: ' + ((e && e.message) || e)); });
      }
      return next().then(pages).then(function () {
        // All or nothing: a half-fetched update would leave a page next to the old files it was written against, and a
        // check that could not finish is not a check (it used to be stamped as done, and nothing was tried again for 12 hours).
        if (failed || !changes.length) return null;
        changes.sort(function (a, b) { return (/\.html$/.test(a.path) ? 1 : 0) - (/\.html$/.test(b.path) ? 1 : 0); });
        return store1().then(function () {
          return nativeSite('commit').then(function () { staged = true; }, function (e) { if (!unimplemented(e)) throw e; });
        }).then(function () {
          written.forEach(function (c) { hashes[c.key || c.path] = c.sha; if (c.known) shown++; });
          try {
            localStorage.setItem('dgSiteHashes', JSON.stringify(hashes));
            localStorage.setItem('dgSiteFresh', 'pending');
            localStorage.setItem('dgSiteBoots', '0');
          } catch (e) { /* no storage: it is checked again next time */ }
        }, rollback);
      }).then(function () {
        if (!failed) stamp();
        console.log('[dg-site] the site is at ' + String(site.commit || '').slice(0, 8) + ': ' + fetched + ' files fetched, ' + (failed ? 'nothing applied' : written.length + ' stored'));
        if (failed) res.state = 'failed'; else if (shown) res.state = 'new';
        // A file the bundle never had (the page names it, the snapshot did not carry it: the manifest, the icons) is saved quietly; the
        // bar is for files that CHANGED since the bundle - a first check used to announce an update on every fresh install.
        if (shown && !failed && !SITE_CONFIG.silent) afterConsent(showUpdateBar);
      });
    }
    return (checking = chain.catch(function (e) {
      res.state = 'failed';
      if (e && e.definite) stamp();   // the site answered no: asking again on every return to the app changes nothing
      console.log('[dg-site] update failed:', (e && e.message) || e);
    }).then(function () { checking = null; return res; }));
  }
  window.__dgCheckSiteUpdate = function () { return updateSite(true); };

  // Back in the app after a while: the same check, which the time stamp keeps to once in six hours.
  if (!SITE_CONFIG.manual) document.addEventListener('visibilitychange', function () { if (document.visibilityState === 'visible') updateSite(); });

