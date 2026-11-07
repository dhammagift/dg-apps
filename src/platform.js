// Native platform implementation for the offline layer (dg-node's public/offline/app.js reads
// window.dgPlatform; see its header and docs/OFFLINE_PWA_PLAN.md "platform.js"). This file is
// bundled into www/ and must be the FIRST script on the page (build-page.js injects it at the
// dg:app-scripts marker) so the site's browser platform.js — which loads right after with a
// `if (window.dgPlatform) return` guard — becomes a no-op.
//
// The app's own origin is https://localhost on Android and capacitor://localhost on iOS — Capacitor's
// defaults, and NOT configurable to https on iOS (it refuses a scheme WKWebView itself handles).
// Nothing here hardcodes either one: this file and native-bridge.js compare against location.origin.
// The difference matters for one thing only — the offline layer needs a secure context, which both
// are (WebKit treats a scheme registered by the embedding app as trustworthy).
//
// Differences from the browser implementation, all of them app constraints:
//   - distBase: the app's own origin has no server behind it, so the database and its manifest are
//     fetched from the real site.
//   - onlineBase: every "needs the internet" data request (a language outside the ru+en slice,
//     script conversion, /api/transliterate, and any data request before the library is open)
//     is forwarded to the real site instead of the dead-end local origin.
//   - mapStatic: TOC and the Patimokkha fragments are bundled as static files (build-toc-
//     snapshot.js / build-assets.js), so their API URLs are rewritten to those files — no
//     server exists here to compute them.
//   - askConsent: always asks, Wi-Fi included — App Store guideline 4.2.3(ii) requires disclosing
//     the size and prompting before a first-launch download regardless of connection, and a
//     reader on Wi-Fi is not automatically one who wants a ~600MB library. The site's own consent
//     sheet handles it when present; a native dialog (@capacitor/dialog) is the fallback, naming
//     the real byte size from the published manifest either way.
//   - Auto-download on first open: the app must work offline by definition, so the first launch
//     starts the download by itself (the site is opt-in — its app.js only downloads on an
//     explicit intent key, which this file sets). A decline is remembered, so a reader on
//     mobile data who said no is never asked again on every launch; Settings → Offline
//     library → Download still works.
(function () {
    'use strict';

    // Test APKs are built with DG_ONLINE_ORIGIN=https://test.dhamma.gift (build-assets.js prepends it).
    var ONLINE_ORIGIN = window.DG_ONLINE_ORIGIN || 'https://dhamma.gift';
    var STATE_KEY = 'dg.offline.state';
    var WANT_DATA_KEY = 'dg.offline.wantData';
    var DECLINED_KEY = 'dg.app.downloadDeclined';

    // search/index.html's quote popup / "open in new tab" check this to take their app branch (a
    // phone has no server behind a second copy of the page); nothing set it since app.js moved to dg-node.
    window.dgOfflineReady = true;
    // Where the published archive and its manifest live on the real site. Always the NETWORK base,
    // even after the archive has been fetched onto the device: the manifest is a few hundred bytes,
    // and pointing it at the local file handler would turn a 404 into "the library is not
    // published" during the update check.
    var REMOTE_BASE = ONLINE_ORIGIN + '/mobile-data';
    var ARCHIVE = 'dg.db.gz';

    // iOS: the library is a plain dg.db in the App Group container, downloaded and unpacked by
    // DgDownloadPlugin.swift on the system's background URLSession (a WebView's JavaScript is
    // suspended the moment the app leaves the foreground) and read in place by the worker through
    // the native /dg-sql endpoint (DgSharedLibrary.swift) — no import into OPFS, and the share
    // extension reads the same file. The offline layer asks for this after consent and before its
    // own transfer (dg-node's offline/app.js, prepareArchive), so the consent sheet, the progress
    // card and the update path are untouched. `update` re-downloads; otherwise a file already on
    // disk is the answer.
    //
    // A browser has no Capacitor at all and keeps the code path it has always had; Android has its own, below.
    function prepareArchive(opts) {
        var Plugins = window.Capacitor && window.Capacitor.Plugins;
        var D = Plugins && Plugins.DgDownload;
        if (!D || typeof D.start !== 'function' || typeof D.existing !== 'function') return Promise.resolve(false);
        var fresh = !!(opts && opts.update);
        if (window.Capacitor.getPlatform && window.Capacitor.getPlatform() === 'android') return prepareAndroid(D, fresh);
        return Promise.resolve(fresh ? null : D.existing()).then(function (onDisk) {
            if (onDisk && onDisk.path) return true;
            // The manifest's sha256 (of the unpacked database): the plugin checks it before the file replaces the library,
            // as Android's service does.
            return readManifest().then(function (m) {
                return D.start({ url: REMOTE_BASE + '/' + ARCHIVE, sha256: (m && m.sha256) || '' });
            }).then(function (file) { return !!(file && file.path); });
        }).catch(function () { return false; });   // refused, offline, plugin unhappy: the worker's own path
    }

    // The card's x (dg-node app.js, dgCancelOfflineDownload): the native transfer stops and drops its partial file, and the
    // waiting start() is refused - app.js then imports nothing.
    function cancelArchive() {
        var D = window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.DgDownload;
        if (!D || typeof D.cancel !== 'function') return Promise.resolve(false);
        return Promise.resolve(D.cancel()).then(function () { return true; }, function () { return false; });
    }

    // Android: DgDownloadPlugin.java downloads the archive and the manifest in a foreground service into the app's files
    // directory (resuming after a break; a WebView's JavaScript is frozen in the background and the download stopped with
    // it, issue #62). The page then reads both through Capacitor's file URL as if that directory were the site: the worker
    // imports the archive as before, only much sooner. The native progress becomes the page's own progress events, and the
    // native notification replaces the mirrored one while the transfer runs (native-bridge.js looks at dgNativeDownload).
    var androidProgressWired = false;
    function wireAndroidProgress(D) {
        if (!androidProgressWired && typeof D.addListener === 'function') {
            androidProgressWired = true;
            // The plugin's "progress" events reach the page through native-bridge.js (bridgeNativeDownloadProgress): a
            // second listener here made every event two, and the card redrew twice as often.
            // The archive is only needed until the worker has imported it: the finished download frees ~200 MB.
            window.addEventListener('dg:dl-progress', function (e) {
                if (e.detail && e.detail.done && typeof D.clear === 'function') { try { D.clear(); } catch (x) { /* nothing to clear */ } }
            });
        }
    }
    function prepareAndroid(D, fresh) {
        wireAndroidProgress(D);
        window.dgNativeDownload = true;
        // The first notification, and with it Android 13+'s permission prompt (the native service posts the later ones).
        try { var P = window.Capacitor.Plugins.DgProgress; if (P && P.update) P.update({ title: 'Dhamma.gift', text: 'Downloading the offline library', percent: -1 }); } catch (x) { /* no notification */ }
        return Promise.resolve(D.start({ base: REMOTE_BASE, fresh: fresh })).then(function (r) {
            if (!r || !r.path) return false;
            window.dgPlatform.distBase = window.Capacitor.convertFileSrc(r.path);
            return true;
        }).catch(function () { return false; }).then(function (ok) { window.dgNativeDownload = false; return ok; });
    }

    // Packs (dg-node app.js prepareArchive): the files the worker lacks, {path, bytes, sha256} relative to `base`, fetched by
    // the same foreground service into the library directory; the answer is that directory's file URL, which the worker
    // imports them from. iOS (DG_NATIVE_PACKS): DgDownloadPlugin.swift fetches them on its background URLSession and unpacks
    // each beside the old dg.db, where the worker opens them natively (no import); the answer only says they are there.
    function preparePacks(opts) {
        var D = window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.DgDownload;
        var android = window.Capacitor && window.Capacitor.getPlatform && window.Capacitor.getPlatform() === 'android';
        if (D && typeof D.start === 'function' && !android && window.DG_NATIVE_PACKS) {
            return Promise.resolve(D.start({ base: opts.base, files: JSON.stringify(opts.files || []) })).then(function (r) {
                return r && r.path ? 'native:' + r.path : null;
            }).catch(function (e) {
                // the downloader's own words (HTTP, checksum, "no data arrived"), for the device log and the self-test
                window.dgLastPacksError = String((e && (e.message || e.errorMessage)) || e);
                console.log('[dg-offline] native packs download failed: ' + window.dgLastPacksError);
                return null;
            });
        }
        // false = not this platform's job (a browser): the page's worker downloads; null below = the transfer failed
        if (!D || typeof D.start !== 'function' || !android) return Promise.resolve(false);
        wireAndroidProgress(D);
        window.dgNativeDownload = true;
        try { var P = window.Capacitor.Plugins.DgProgress; if (P && P.update) P.update({ title: 'Dhamma.gift', text: 'Downloading the offline library', percent: -1 }); } catch (x) { /* no notification permission */ }
        return Promise.resolve(D.start({ base: opts.base, files: JSON.stringify(opts.files || []) })).then(function (r) {
            return r && r.path ? window.Capacitor.convertFileSrc(r.path) : null;
        }).catch(function () { return null; }).then(function (b) { window.dgNativeDownload = false; return b; });
    }

    window.dgPlatform = {
        name: 'native',
        distBase: window.DG_DIST_BASE || REMOTE_BASE,
        onlineBase: ONLINE_ORIGIN,
        prepareArchive: prepareArchive,
        preparePacks: preparePacks,
        cancelArchive: cancelArchive,
        // Set by the iOS shell (DgSharedLibrary.userScript): SQL runs natively at this path on the
        // page's own origin, and db-worker.js takes its native branch (with DG_NATIVE_PACKS, on packs). Undefined on Android.
        nativeSql: window.DG_NATIVE_SQL || null,

        mapStatic: function (p) {
            if (p === '/api/toc') return '/api-snapshots/toc.json';
            if (p.indexOf('/api/toc/book/') === 0) {
                return '/api-snapshots/toc-book-' + decodeURIComponent(p.slice('/api/toc/book/'.length)) + '.json';
            }
            // Bundled as reader/{bu,bi}-pm-fragment.html (build-assets.js ASSETS); the worker
            // has no such route and the local origin has no server.
            if (p.indexOf('/api/patimokkha-fragment/') === 0) {
                var side = p.slice('/api/patimokkha-fragment/'.length);
                if (side === 'bu' || side === 'bi') return '/reader/' + side + '-pm-fragment.html';
            }
            return null;
        },

        askConsent: function askConsent() {
            var Network = window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.Network;
            if (!Network) return Promise.resolve(true);
            return Promise.all([Network.getStatus(), packsOn() ? readPacksPlan() : readManifest()]).then(function (out) {
                var status = out[0];
                var m = out[1] || {};
                // Offline: ask once the network is back, with the real sizes - answering "yes" here marked the transfer as
                // agreed, and the next launch online downloaded ~150 MB with no question at all (f3-ultra's review
                // 2026-11-01; App Store 4.2.3 wants the question).
                if (status.connected === false) {
                    return new Promise(function (resolve) {
                        var handle = Network.addListener('networkStatusChange', function (st) {
                            if (!st || !st.connected) return;
                            Promise.resolve(handle).then(function (h) { if (h && h.remove) h.remove(); });
                            resolve(askConsent());
                        });
                    });
                }
                // The site's own consent sheet (dg-node offline-status.js, 'dg:need-consent'): themed,
                // both figures — the archive that downloads and the database on the device. The native
                // AlertDialog showed only the on-device size ("584 MB"), which read as the download.
                return new Promise(function (resolve) {
                    var answered = false;
                    window.dispatchEvent(new CustomEvent('dg:need-consent', { detail: {
                        bytes: m.bytes, bytesGz: m.bytes_gz, langs: m.langs, packs: m.packs, selected: m.selected,
                        resolve: function (p) { answered = true; resolve(p); },
                    } }));
                    if (!answered) resolve(nativeConsent(m));
                });
            }).catch(function () { return true; });
        },
    };

    // Fallback for a page without offline-status.js.
    function nativeConsent(m) {
        var Dialog = window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.Dialog;
        if (!Dialog) return true;
        var ru = (localStorage.getItem('dhammaLanguage') || localStorage.getItem('siteLanguage') || 'en') === 'ru';
        var mb = function (b) { return Math.round(b / 1048576) + (ru ? ' МБ' : ' MB'); };
        var size = m.bytes_gz && m.bytes
            ? (ru ? ' (скачать ' + mb(m.bytes_gz) + ', на устройстве ' + mb(m.bytes) + ')' : ' (' + mb(m.bytes_gz) + ' download, ' + mb(m.bytes) + ' on device)')
            : '';
        return Dialog.confirm({
            title: ru ? 'Офлайн-библиотека' : 'Offline library',
            message: ru ? 'Скачать офлайн-библиотеку' + size + '?'
                        : 'Download the offline library' + size + '?',
            okButtonTitle: ru ? 'Скачать' : 'Download',
            cancelButtonTitle: ru ? 'Не сейчас' : 'Not now',
        }).then(function (v) { return !!v.value; });
    }

    // A build that takes the library in packs (a test build: DG_PACKS_BASE, dg-node app.js PACKS_ON) shows what that download
    // is: the packs picked in Settings, or the first ones - the Mahāsaṅgīti and the interface language's translation (app.js
    // firstPacks). It showed the single library's 245 MB, all languages (f3-ultra, run 661's first-launch.png).
    function packsOn() { return !!window.DG_PACKS_BASE && (!window.DG_NATIVE_SQL || !!window.DG_NATIVE_PACKS) && window.DG_OFFLINE_PACKS !== false; }
    function readPacksPlan() {
        return fetch(String(window.DG_PACKS_BASE).replace(/\/$/, '') + '/packs-manifest.json')
            .then(function (r) { return r.ok ? r.json() : null; })
            .then(function (m) {
                if (!m || !Array.isArray(m.packs)) return readManifest();
                // the sheet (dg-node offline-status.js) lists them, ticks these, and "Add ›" unfolds the rest (owner 2026-11-01)
                var picked = null;
                try { picked = JSON.parse(localStorage.getItem('dg.offline.packs') || 'null'); } catch (e) { /* none */ }
                var ui = 'en';
                try { ui = (localStorage.getItem('dhammaLanguage') || localStorage.getItem('siteLanguage') || 'en') === 'ru' ? 'ru' : 'en'; } catch (e) { /* none */ }
                var want = Array.isArray(picked) ? picked : ['tr-' + ui];
                var packs = m.packs.filter(function (p) { return p.main || p.required || want.indexOf(p.id) !== -1; });
                var langs = [];
                packs.forEach(function (p) { if (p.kind === 'translation') (p.langs || [p.lang]).forEach(function (l) { if (l && langs.indexOf(l) === -1) langs.push(l); }); });
                return {
                    packs: m.packs,
                    selected: packs.map(function (p) { return p.id; }),
                    bytes: packs.reduce(function (a, p) { return a + (p.bytes || 0); }, 0),
                    bytes_gz: packs.reduce(function (a, p) { return a + (p.bytes_gz || 0); }, 0),
                    langs: langs.join(','),
                };
            })
            .catch(function () { return readManifest(); });
    }

    // The published manifest carries the real sizes: bytes_gz is what crosses the connection, bytes is
    // the database it unpacks into. A few hundred bytes.
    function readManifest() {
        var base = REMOTE_BASE;
        return fetch(base.replace(/\/$/, '') + '/db-manifest.json')
            .then(function (r) { return r.ok ? r.json() : null; })
            .catch(function () { return null; });
    }

    // The auto-download intent. Set only when nothing is stored yet (the intent is harmless when a
    // library exists — app.js only acts on it when the probe finds none) and when a previous
    // decline is still standing. The decline flag is cleared by the download itself: once
    // dg.offline.state reports present, the flag is history.
    // Not in the iOS share sheet: that process cannot download (no plugin), it only reads what the
    // app downloaded, and the extension seeds the layer's own "a library exists" flag when it does.
    try {
        var state = JSON.parse(localStorage.getItem(STATE_KEY) || 'null');
        var declined = localStorage.getItem(DECLINED_KEY) === '1';
        if (state && state.present) {
            if (declined) localStorage.removeItem(DECLINED_KEY);
        } else if (!declined && !window.DG_SHARE_SHEET) {
            localStorage.setItem(WANT_DATA_KEY, '1');
        }
    } catch (e) { /* private mode / quota — the reader downloads from Settings as on the site */ }

    // Mark a declined auto-download. askConsent cannot distinguish "wifi, silent yes" from a real
    // decline, and the 'offline-data-download-declined' rejection lands in app.js's
    // dgOfflineLibrary promise, not here — so app.js dispatches this event on that exact
    // rejection (small site-side hook) and the flag is remembered.
    // A library the reader deleted in Settings must not come straight back: without this the next
    // launch saw "nothing stored, never declined" and started the 216 MB download on its own. The
    // same flag as a decline; it clears once a library is present again (Settings → Download).
    window.addEventListener('message', function (event) {
        if (event.origin !== location.origin || !event.data || !event.data.dgOfflineDeleteRequest) return;
        try { localStorage.setItem(DECLINED_KEY, '1'); localStorage.removeItem(WANT_DATA_KEY); } catch (e) { /* private mode */ }
    });
    window.addEventListener('dg:download-declined', function () {
        try { localStorage.setItem(DECLINED_KEY, '1'); } catch (e) { /* ignore */ }
    });
})();
// The speechSynthesis stand-in lives in src/tts.js now: every page with the voice player needs it.
