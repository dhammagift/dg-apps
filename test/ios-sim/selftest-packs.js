// The packs self-test for a real iPhone (Firebase Test Lab, test/ios-sim/testlab): the offline library in packs, downloaded
// for real from the site the build talks to (window.DG_PACKS_BASE) by the native downloader (DgDownloadPlugin.swift) and
// opened natively (DgSharedLibrary.swift, db-worker.js openNativePacks); then questions that only the local library can
// answer - prepare-www.js --packs points every "needs the internet" origin at a dead port, the packs base excepted.
// Injected only by prepare-www.js --packs into a build output tree; a shipped bundle never contains it.
//
// The verdict goes on the screen as one line "DG-SELFTEST-DONE PASS|FAIL {json}" (the UI test reads it there: it cannot
// read the app's files) and, in a debug build, to Documents/selftest.json through DgSelfTest.
(function () {
    'use strict';
    var DONE_KEY = 'dg.selftest.packs.done';
    var DEADLINE_MS = 30 * 60 * 1000;   // ~160 MB over a test farm's network, then the unpacking
    // In the language of the translation that was downloaded: the consent sheet's own choice decides it (English on an English
    // device, the simulator run of 2026-11-07); a question in another language rightly goes to the server, a dead port here.
    function cases(lang) {
        var word = lang === 'ru' ? '%D1%87%D0%B5%D1%80%D0%B5%D0%BF%D0%B0%D1%85%D0%B0' : 'tortoise';
        return [
            { name: 'search-kacchapa', url: '/search?q=kacchapa&langs=' + lang, expect: 'sn35.240' },
            { name: 'search-translation', url: '/search?q=' + word + '&langs=' + lang, expect: '"metadata"' },
            { name: 'text-sn35.240-' + lang, url: '/api/text/sn35.240?mode=single&lang=' + lang, expect: '"' + lang + '_' },
            { name: 'text-dn22-' + lang, url: '/api/text/dn22?mode=single&lang=' + lang, expect: 'Mahāsatipaṭṭhānasutta' },
            { name: 'nav-sn56.11', url: '/api/nav/sn56.11', expect: 'sn56' },
        ];
    }
    var CASES = cases('ru');
    var started = Date.now(), report = { kind: 'packs', startedAt: new Date().toISOString(), steps: [], cases: [] };
    function step(s) { report.steps.push(Math.round((Date.now() - started) / 1000) + 's ' + s); console.log('[dg-selftest] ' + s); show('running: ' + s); }
    function show(text) {
        var el = document.getElementById('dg-selftest-result');
        if (!el) {
            el = document.createElement('pre');
            el.id = 'dg-selftest-result';
            el.setAttribute('aria-label', text);
            el.style.cssText = 'position:fixed;left:0;right:0;bottom:0;z-index:2147483647;margin:0;padding:8px;font:12px/1.3 monospace;white-space:pre-wrap;background:#ffd;color:#000;max-height:40vh;overflow:auto';
            document.body.appendChild(el);
        }
        el.textContent = text;
        el.setAttribute('aria-label', text);
    }
    function finish(ok) {
        report.ok = ok;
        report.progress = progress;
        report.nativeError = window.dgLastPacksError || null;
        report.seconds = Math.round((Date.now() - started) / 1000);
        try { report.diag = window.dgOfflineDiagnostics && window.dgOfflineDiagnostics(); } catch (e) { report.diag = String(e); }
        try { report.state = JSON.parse(localStorage.getItem('dg.offline.state') || 'null'); } catch (e) { report.state = null; }
        var json = JSON.stringify(report);
        try { localStorage.setItem(DONE_KEY, '1'); } catch (e) { /* no storage */ }
        show('DG-SELFTEST-DONE ' + (ok ? 'PASS' : 'FAIL') + ' ' + json);
        var P = window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.DgSelfTest;
        if (P && P.write) P.write({ json: json }).catch(function () { /* the screen has it */ });
    }
    function wait(cond, ms) {
        return new Promise(function (resolve) {
            var end = Date.now() + ms;
            (function poll() { var v = false; try { v = cond(); } catch (e) { v = false; } if (v || Date.now() > end) resolve(!!v); else setTimeout(poll, 1000); })();
        });
    }
    // the native downloader's progress, first and last, and its error if it gives one
    var progress = { events: 0, first: null, last: null };
    window.addEventListener('dg:dl-progress', function (e) {
        var d = e.detail || {};
        progress.events++;
        var at = Math.round((Date.now() - started) / 1000) + 's ' + d.phase + ' ' + d.loaded + '/' + d.total;
        if (!progress.first) progress.first = at;
        progress.last = at;
    });
    function run() {
        step('page up; packs base ' + window.DG_PACKS_BASE + ', native packs ' + !!window.DG_NATIVE_PACKS);
        try { localStorage.setItem('dg.offline.packs', JSON.stringify(['tr-ru'])); } catch (e) { /* none */ }
        return wait(function () { return typeof window.dgStartOfflineDownload === 'function'; }, 60000).then(function (ok) {
            if (!ok) throw new Error('the offline layer never started');
            step('download: root-ms + tr-ru');
            window.dgStartOfflineDownload('open', true);
            // The first start's consent sheet waits for its Download (Test Lab iPhone 16 Pro, 2026-11-07: it stood there for
            // 30 minutes) - pressed as a reader presses it
            var presses = 0;
            var press = setInterval(function () {
                var sheet = document.getElementById('dgConsent');
                var b = sheet && [].slice.call(sheet.querySelectorAll('button')).filter(function (x) { return /^(Download|Скачать)$/.test(x.textContent.trim()); })[0];
                if (b) { b.click(); presses++; step('pressed Download in the consent sheet'); }
                if (presses > 2 || Date.now() - started > 120000) clearInterval(press);
            }, 1500);
            return wait(function () { return window.dgOfflineDiagnostics && window.dgOfflineDiagnostics().mode === 'local'; }, DEADLINE_MS);
        }).then(function (local) {
            if (!local) throw new Error('the library never became local');
            var packs = (JSON.parse(localStorage.getItem('dg.offline.state') || '{}')).packs || [];
            step('library local: ' + JSON.stringify(packs));
            CASES = cases(packs.indexOf('tr-ru') !== -1 ? 'ru' : 'en');
            return CASES.reduce(function (p, c) {
                return p.then(function () {
                    var t0 = Date.now();
                    return fetch(c.url).then(function (r) { return r.text().then(function (b) { return { status: r.status, body: b }; }); })
                        .catch(function (e) { return { status: 0, body: String(e) }; })
                        .then(function (r) {
                            var ok = r.status === 200 && (!c.expect || r.body.indexOf(c.expect) !== -1);
                            report.cases.push({ name: c.name, ok: ok, status: r.status, ms: Date.now() - t0, bytes: r.body.length, head: ok ? '' : r.body.slice(0, 200) });
                            step(c.name + ' ' + (ok ? 'ok' : 'FAILED'));
                        });
                });
            }, Promise.resolve());
        }).then(function () {
            finish(report.cases.length === CASES.length && report.cases.every(function (c) { return c.ok; }));
        }).catch(function (e) {
            report.error = String(e && e.message || e);
            finish(false);
        });
    }
    var done = false;
    try { done = localStorage.getItem(DONE_KEY) === '1'; } catch (e) { /* none */ }
    if (done) { show('DG-SELFTEST-DONE (an earlier run of this install)'); return; }
    if (document.readyState === 'complete') setTimeout(run, 3000);
    else window.addEventListener('load', function () { setTimeout(run, 3000); });
})();
