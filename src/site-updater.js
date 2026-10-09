// Shared by the bundled-page apps (Uposatha, Dict): the parts of their bridges that keep a page that is
// BUNDLED in the APK working and current. Pasted into each bridge by its build.js at the marker
// "// @site-updater"; the bridge defines SITE_CONFIG first and calls updateSite() when the page has loaded.
//
//   SITE_CONFIG = { site: 'https://dict.dhamma.gift', urlFor: function (path) { return path; }, updatable: optional (path) => bool,
//                   gate: optional (manifest) => Promise<bool> (false: this check applies nothing), silent: optional bool (no "new version" bar) }
//
// Uses the bridge's Cap (window.Capacitor) and store() (localStorage read).
  // ---- keeping the bundled page up to date --------------------------------------------------
  //
  // The APK holds the page as it was when it was built. When the phone is online, and at most every 6
  // hours, every file of the bundle is fetched from the site; the ones whose SHA-256 differs from what the
  // app has (the manifest of the bundle, then whatever was downloaded before) go to DgSite, which serves
  // them from the next request on — for the page itself, the next launch. A file the new page brings that
  // the bundle has never had (found in the new html / css / js) is fetched too. Nothing is ever deleted: a
  // file the site no longer has stays, harmlessly.
  // SITE_CONFIG (defined by the bridge that pastes this in): { site: where the page comes from, urlFor(path): a
  // bundled file's address on the site (a page is not served under its .html name) }
  var SITE = SITE_CONFIG.site;
  var SITE_CHECK_EVERY = 6 * 3600 * 1000;   // a successful check is not repeated sooner; a failed one does not count (see updateSite)

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
  function showUpdateBar() {
    if (document.getElementById('dg-upd')) return;
    var ru = typeof isRu === 'function' ? isRu() : /^ru/i.test(document.documentElement.lang || '');
    var t = ru ? { head: 'Доступна новая версия', sub: 'Страница обновится за секунду', go: 'Обновить', busy: 'Обновляю…', later: 'Позже' }
               : { head: 'New version available', sub: 'The page reloads in a second', go: 'Update', busy: 'Updating…', later: 'Later' };
    var bar = document.createElement('div');
    bar.id = 'dg-upd';
    bar.setAttribute('role', 'status');
    bar.style.cssText = 'position:fixed;left:12px;right:12px;bottom:calc(14px + max(env(safe-area-inset-bottom,0px),var(--safe-area-inset-bottom,0px)));z-index:2147482000;'
      + 'display:flex;align-items:center;gap:12px;padding:12px 12px 12px 16px;border-radius:16px;border:1px solid;font:500 15px/1.25 system-ui,sans-serif';
    // Colours follow the page's theme, also when it is switched while the bar is up (dark = a solid dark body background).
    function paint() {
      var bg = (getComputedStyle(document.body).backgroundColor.match(/[\d.]+/g) || [255, 255, 255]).map(Number);
      var dark = (0.299 * bg[0] + 0.587 * bg[1] + 0.114 * bg[2]) < 128 && (bg[3] === undefined || bg[3] > 0.5);
      bar.style.borderColor = dark ? '#34414f' : '#d9e1e8';
      bar.style.background = dark ? '#1d2630' : '#fff';
      bar.style.color = dark ? '#e8eef4' : '#1b2430';
      bar.style.boxShadow = '0 8px 28px ' + (dark ? 'rgba(0,0,0,.55)' : 'rgba(15,30,50,.22)');
    }
    paint();
    new MutationObserver(paint).observe(document.body, { attributes: true, attributeFilter: ['class'] });
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
      text.firstChild.textContent = t.busy;
      text.lastChild.textContent = '';
      go.remove(); x.remove();
      try { localStorage.setItem('dgSiteApplied', '1'); } catch (e) { /* no storage: no confirmation after the reload */ }
      setTimeout(function () { location.reload(); }, 250);
    });
    var x = document.createElement('button');
    x.type = 'button';
    x.setAttribute('aria-label', t.later);
    x.textContent = '✕';
    x.style.cssText = 'border:0;background:none;color:inherit;opacity:.55;padding:8px;font-size:18px;line-height:1';
    x.addEventListener('click', function () { bar.remove(); });
    bar.appendChild(text); bar.appendChild(go); bar.appendChild(x);
    document.body.appendChild(bar);
  }

  // ---- what the person is told ---------------------------------------------------------------
  function siteRu() { return typeof isRu === 'function' ? isRu() : /^ru/i.test(document.documentElement.lang || ''); }
  var ST = {
    ru: { busy: 'Проверяю…', current: 'Всё актуально', new: 'Есть обновление - нажмите «Обновить» внизу', offline: 'Нет соединения', failed: 'Не удалось проверить, попробуйте позже',
          done: 'Обновление применено', doneSub: 'Теперь у вас свежая версия', broke: 'Обновление не заработало', brokeSub: 'Включена встроенная версия. Если что-то не работает, переустановите приложение из магазина' },
    en: { busy: 'Checking…', current: 'Everything is up to date', new: 'Update found - use the Update button below', offline: 'No connection', failed: 'Could not check, try again later',
          done: 'Update applied', doneSub: 'You now have the latest version', broke: 'The update did not work', brokeSub: 'The built-in version is back. If something is broken, reinstall the app from the store' }
  };
  function st() { return ST[siteRu() ? 'ru' : 'en']; }
  // Checks now (the version row's button) and says the result through say(text); resolves when done.
  window.__dgSiteCheckSay = function (say) {
    say(st().busy);
    return updateSite(true).then(function (r) { say(st()[r.state] || st().failed); }, function () { say(st().failed); });
  };
  // A short message over the page: "applied" after the reload an update asked for, "did not work" after the safety net fired.
  function showNotice(head, sub, bad) {
    if (!document.body) return;
    var n = document.createElement('div');
    n.setAttribute('role', 'status');
    n.style.cssText = 'position:fixed;left:12px;right:12px;bottom:calc(14px + max(env(safe-area-inset-bottom,0px),var(--safe-area-inset-bottom,0px)));z-index:2147482000;'
      + 'padding:12px 16px;border-radius:16px;font:500 15px/1.25 system-ui,sans-serif;color:#fff;box-shadow:0 8px 28px rgba(15,30,50,.3);background:' + (bad ? '#b4472f' : '#139b7b');
    n.innerHTML = '<div></div><div style="font-weight:400;font-size:12.5px;opacity:.9;margin-top:2px"></div>';
    n.firstChild.textContent = (bad ? '⚠ ' : '✓ ') + head;
    n.lastChild.textContent = sub;
    n.addEventListener('click', function () { n.remove(); });
    document.body.appendChild(n);
    setTimeout(function () { n.remove(); }, bad ? 15000 : 4500);
  }
  function showPendingNotice() {
    var applied = store('dgSiteApplied') === '1', broke = store('dgSiteBroke') === '1';
    if (!applied && !broke) return;
    try { localStorage.removeItem('dgSiteApplied'); localStorage.removeItem('dgSiteBroke'); } catch (e) { /* ignore */ }
    if (broke) showNotice(st().broke, st().brokeSub, true); else showNotice(st().done, st().doneSub, false);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', showPendingNotice); else setTimeout(showPendingNotice, 500);

  // New files that stop the page from starting must not trap the app: three starts in a row that never reached
  // "the page has settled" put the bundle's own copy back (everything downloaded is dropped).
  (function bootGuard() {
    var DS = Cap.Plugins && Cap.Plugins.DgSite;
    if (store('dgSiteFresh') !== '1') return;
    var n = (parseInt(store('dgSiteBoots'), 10) || 0) + 1;
    try { localStorage.setItem('dgSiteBoots', String(n)); } catch (e) { /* no storage: no guard */ }
    if (n >= 3 && DS && typeof DS.clear === 'function') {
      DS.clear().then(function () {
        try { ['dgSiteHashes', 'dgSiteCheckedAt', 'dgSiteFresh', 'dgSiteBoots'].forEach(function (k) { localStorage.removeItem(k); }); localStorage.setItem('dgSiteBroke', '1'); } catch (e) { /* ignore */ }
        console.log('[dg-site] the downloaded files did not start the page: back to the bundled copy');
      }, function () { /* try again at the next start */ });
    }
  })();

  // A new version of the app brings a new bundle: what an older version downloaded (it sits in front of the bundled files, and its
  // hashes are compared with the site instead of the bundle's) is dropped, so the bundle is the starting point again.
  (function versionGuard() {
    var DS = Cap.Plugins && Cap.Plugins.DgSite, v = window.__DG_APP_VERSION__;
    if (!v || !DS || typeof DS.clear !== 'function' || store('dgAppVersion') === v) return;
    DS.clear().then(function () {
      try {
        ['dgSiteHashes', 'dgSiteCheckedAt', 'dgSiteFresh', 'dgSiteBoots'].forEach(function (k) { localStorage.removeItem(k); });
        localStorage.setItem('dgAppVersion', v);
      } catch (e) { /* no storage */ }
    }, function () { /* try again at the next start */ });
  })();

  var checking = false;
  // force: a person asked (the version row in the menu) - no waiting for SITE_CHECK_EVERY. Resolves {state: 'offline' | 'busy' | 'failed' | 'new' | 'current'}.
  function updateSite(force) {
    var DS = Cap.Plugins && Cap.Plugins.DgSite;
    var res = { state: 'current' };
    // Called once the page has settled: the files it started with are good.
    try { localStorage.setItem('dgSiteBoots', '0'); localStorage.setItem('dgSiteFresh', '0'); } catch (e) { /* no storage */ }
    if (!DS || !window.crypto || !crypto.subtle) return Promise.resolve({ state: 'failed' });
    if (checking) return Promise.resolve({ state: 'busy' });
    if (navigator.onLine === false) return Promise.resolve({ state: 'offline' });
    // A first start has no time stamp and always checks; after that, not sooner than SITE_CHECK_EVERY.
    if (!force && Date.now() - (parseInt(store('dgSiteCheckedAt'), 10) || 0) < SITE_CHECK_EVERY) return Promise.resolve(res);
    checking = true;
    var hashes = {};
    try { hashes = JSON.parse(store('dgSiteHashes')) || {}; } catch (e) { hashes = {}; }
    var chain = fetch('/site-manifest.json', { cache: 'no-store' }).then(function (r) { return r.json(); }).then(function (manifest) {
      // The app may refuse an update that its own pages cannot take (Dhamma.Gift: the site's page has elements the bundled page lacks).
      if (SITE_CONFIG.gate) return Promise.resolve(SITE_CONFIG.gate(manifest)).then(function (open) { return open ? run(manifest) : null; });
      return run(manifest);
    });
    function run(manifest) {
      var ok = SITE_CONFIG.updatable || function () { return true; };
      var queue = manifest.files.filter(ok), seen = {}, changes = [], changed = 0, shown = 0, fetched = 0, failed = 0;
      manifest.files.forEach(function (f) { seen[f] = 1; });
      function next() {
        var path = queue.shift();
        if (!path || fetched > 400) return Promise.resolve();
        fetched++;
        // 'no-cache', not 'no-store': the WebView keeps what it fetched and asks the site with the file's ETag, so a file
        // that has not changed comes back as a 304 with no body — a check costs a few KB, not the whole page again.
        var from = SITE_CONFIG.urlFor(path);
        return fetch(/^https?:\/\//.test(from) ? from : SITE + from, { cache: 'no-cache' }).then(function (res) {
          if (!res.ok) { if (res.status !== 404) failed++; return null; }   // 404: the site no longer has it, and that is fine
          return res.arrayBuffer();
        }).then(function (buf) {
          if (!buf || !buf.byteLength) return null;
          return crypto.subtle.digest('SHA-256', buf).then(function (digest) {
            var sha = hex(digest), had = hashes[path] || (manifest.hashes || {})[path];
            // A page and its stylesheets name the files they need; a script's strings name half the site's assets
            // (a first version followed those and pulled 30 MB), and what a script fetches on demand is in the bundle
            // already (the snapshot's browser ran it).
            if (/\.(html|css)$/.test(path)) {
              referencedPaths(new TextDecoder().decode(buf), path).forEach(function (p) { if (!seen[p] && ok(p)) { seen[p] = 1; queue.push(p); } });
            }
            if (sha === had) return null;
            changes.push({ path: path, data: bytesToBase64(new Uint8Array(buf)), sha: sha, known: !!had });
            return null;
          });
        }).catch(function () { failed++; }).then(next);   // a file that would not come: the check is not complete (below)
      }
      // Everything is fetched before anything is stored, and the pages go last: a page that arrives before the
      // files it names would run against the old ones.
      function store1() {
        var c = changes.shift();
        if (!c) return Promise.resolve();
        return DS.put({ path: c.path, data: c.data }).then(function () { hashes[c.path] = c.sha; changed++; if (c.known) shown++; }, function () { failed++; }).then(store1);
      }
      return next().then(function () {
        // All or nothing: a half-fetched update would leave a page next to the old files it was written against, and a
        // check that could not finish is not a check (it used to be stamped as done, and nothing was tried again for 12 hours).
        if (failed) { changes = []; return null; }
        changes.sort(function (a, b) { return (/\.html$/.test(a.path) ? 1 : 0) - (/\.html$/.test(b.path) ? 1 : 0); });
        return store1();
      }).then(function () {
        try {
          localStorage.setItem('dgSiteHashes', JSON.stringify(hashes));
          if (!failed) localStorage.setItem('dgSiteCheckedAt', String(Date.now()));
          if (changed) { localStorage.setItem('dgSiteFresh', '1'); localStorage.setItem('dgSiteBoots', '0'); }
        } catch (e) { /* no storage: it is checked again next time */ }
        console.log('[dg-site] checked ' + fetched + ' files, ' + changed + ' updated' + (failed ? ', ' + failed + ' failed: nothing applied' : ''));
        if (failed) res.state = 'failed'; else if (shown) res.state = 'new';
        // A file the bundle never had (the page names it, the snapshot did not carry it: the manifest, the icons) is saved quietly; the
        // bar is for files that CHANGED since the bundle - a first check used to announce an update on every fresh install.
        if (shown && !failed && !SITE_CONFIG.silent) showUpdateBar();
      });
    }
    return chain.catch(function (e) { res.state = 'failed'; console.log('[dg-site] update failed:', (e && e.message) || e); }).then(function () { checking = false; return res; });
  }
  window.__dgCheckSiteUpdate = function () { return updateSite(true); };

  // Back in the app after a while: the same check, which the time stamp keeps to once in six hours.
  document.addEventListener('visibilitychange', function () { if (document.visibilityState === 'visible') updateSite(); });

