// Browser check that the Uposatha app opens with NO network: the bundled page (www/, a snapshot of the site's
// calendar page) served the way Capacitor serves the APK's assets, with the real bridge and every request
// to anywhere else refused. And that the updater fetches what the site has changed — one file — and hands
// only that to DgSite.
//
//   (cd uposatha && node tools/bundle-from-repo.js <dg-node dir> && node build.js) first, then:  node uposatha/test/bundle-ui.js
const fs = require('fs');
const path = require('path');
const http = require('http');
const { chromium } = require('/usr/lib/node_modules/@playwright/cli/node_modules/playwright');

const WWW = path.join(__dirname, '..', 'www');
const SHOTS = process.env.DG_SHOTS || '/var/www/html/dict-app';
const PORT = 8107;
const { bridgeSource } = require(path.join(__dirname, '..', 'build.js'));
const { siteSigner, sha256 } = require(path.join(__dirname, '..', '..', 'test', 'signed-site-list.js'));

const results = [];
function check(name, actual, expected) {
    const pass = JSON.stringify(actual) === JSON.stringify(expected);
    results.push(pass);
    console.log(`${pass ? 'ok  ' : 'FAIL'} ${name}${pass ? '' : `\n       expected ${JSON.stringify(expected)}\n       actual   ${JSON.stringify(actual)}`}`);
}

// Capacitor's asset server: a file if there is one, else the app's index.html (its SPA fallback).
const TYPES = { html: 'text/html', js: 'application/javascript', css: 'text/css', json: 'application/json', svg: 'image/svg+xml', woff2: 'font/woff2', png: 'image/png', wasm: 'application/wasm' };
// A FILE (a path with an extension) that is not in the bundle is not served here. In the app such a request goes to dhamma.gift
// (DgSitePlugin.proxy): the page waits for the network at every launch, and offline the file is not there at all. Answering it with
// index.html and 200, as this server did, hid seven missing fonts (2026-10: a blank screen after the splash on a phone).
const absent = [];
const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://x');
    let file = path.join(WWW, decodeURIComponent(url.pathname));
    const there = file.startsWith(WWW) && fs.existsSync(file) && !fs.statSync(file).isDirectory();
    if (!there && /\.[a-z0-9]{2,5}$/i.test(url.pathname)) { absent.push(url.pathname); res.writeHead(404); res.end(); return; }
    if (!there) file = path.join(WWW, 'index.html');
    const ext = path.extname(file).slice(1);
    res.writeHead(200, { 'content-type': TYPES[ext] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
});

function capacitorStub() {
    window.__calls = { puts: [], shortcuts: [] };
    window.Capacitor = {
        getPlatform: () => 'android', isNativePlatform: () => true,
        Plugins: {
            App: { addListener: () => ({ remove() {} }), exitApp() {} },
            DgShortcuts: { set: (o) => { window.__calls.shortcuts.push(o.items); return Promise.resolve({ count: o.items.length }); } },
            DgSound: { pick: () => Promise.resolve({}), channel: () => Promise.resolve() },
            DgSite: { put: (o) => { window.__calls.puts.push({ path: o.path, data: o.data }); return Promise.resolve(); }, list: () => Promise.resolve({ files: [] }), clear: () => Promise.resolve() },
            LocalNotifications: { addListener: () => ({ remove() {} }), requestPermissions: () => Promise.resolve({ display: 'granted' }), createChannel: () => Promise.resolve(), getPending: () => Promise.resolve({ notifications: [] }), cancel: () => Promise.resolve(), schedule: () => Promise.resolve() },
        },
    };
}

(async () => {
    await new Promise((r) => server.listen(PORT, '127.0.0.1', r));
    const browser = await chromium.launch({ args: ['--no-sandbox'] });
    const BRIDGE = bridgeSource();
    const SIGNER = siteSigner();   // the updater takes only a list signed with the key it trusts: this one, through its test hook
    const manifest = JSON.parse(fs.readFileSync(path.join(WWW, 'site-manifest.json'), 'utf8'));
    try {
        for (const [theme, lang] of [['light', 'ru'], ['dark', 'en']]) {
            const ctx = await browser.newContext({ viewport: { width: 412, height: 915 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, colorScheme: theme, locale: lang === 'ru' ? 'ru-RU' : 'en-US' });
            await ctx.addInitScript(capacitorStub);
            await ctx.addInitScript(SIGNER.initScript);
            await ctx.addInitScript(BRIDGE);
            const page = await ctx.newPage();
            const refused = [], bad = [], errors = [];
            absent.length = 0;
            // Offline: nothing outside the app's own origin is reachable, except the "site" we stand in for below.
            const changed = '/assets/js/uposatha-quotes.json';   // a text: only the json follows the site, the code is the build's
            const changedBody = fs.readFileSync(path.join(WWW, changed), 'utf8') + '\n\n';
            await page.route(/^https?:\/\/(?!127\.0\.0\.1)/, (route) => {
                const u = new URL(route.request().url());
                if (u.origin === 'https://dhamma.gift') {
                    const p = u.pathname === '/uposatha-calendar' ? '/uposatha-calendar.html' : u.pathname;
                    // The site's signed list: the bundle's own hashes, but the changed file's is the site's new one.
                    if (p === '/app-site-manifest.json') return route.fulfill({ status: 200, contentType: 'application/json', body: SIGNER.envelope(u.origin, Object.assign({}, manifest.hashes, { [changed]: sha256(changedBody) })) });
                    if (p === changed) return route.fulfill({ status: 200, contentType: 'application/json', body: changedBody });
                    const f = path.join(WWW, p);
                    if (manifest.files.includes(p) && fs.existsSync(f)) return route.fulfill({ status: 200, contentType: TYPES[path.extname(f).slice(1)] || 'application/octet-stream', body: fs.readFileSync(f) });
                    return route.fulfill({ status: 404, body: '' });
                }
                refused.push(u.href);
                return route.abort('internetdisconnected');
            });
            page.on('response', (r) => { if (r.url().startsWith(`http://127.0.0.1:${PORT}`) && r.status() >= 400) bad.push(r.status() + ' ' + r.url()); });
            page.on('pageerror', (e) => errors.push(e.message));
            await page.goto(`http://127.0.0.1:${PORT}/`, { waitUntil: 'load' });
            await page.waitForTimeout(600);
            check(`${lang}/${theme}: no splash of the page at 0.6 s`, await page.evaluate(() => !document.getElementById('up-splash')), true);
            await page.waitForTimeout(2400);
            check(`${lang}/${theme}: the app layer is up (tabs at the bottom)`, await page.evaluate(() => [document.body.classList.contains('app'), !document.getElementById('appnav').hidden]), [true, true]);
            check(`${lang}/${theme}: the calendar has days`, await page.evaluate(() => { document.querySelector('#appnav [data-tab="list"]').click(); return document.body.innerText.length > 500; }), true);
            check(`${lang}/${theme}: the page draws no splash of its own (Android's is native)`, await page.evaluate(() => !document.getElementById('up-splash')), true);
            check(`${lang}/${theme}: no script errors offline`, errors, []);
            check(`${lang}/${theme}: nothing of the app's own is missing (no 4xx)`, bad, []);
            check(`${lang}/${theme}: every file the page asks for is in the bundle`, [...new Set(absent)], []);
            if (theme === 'light') {
                console.log('       requests refused (the site chrome asking for the network):', JSON.stringify([...new Set(refused)].slice(0, 6)));
            }
            await page.screenshot({ path: path.join(SHOTS, `launch-upo-offline-${lang}-${theme}.png`) });
            // The updater runs only when a person asks (the version row's button): nothing by itself 6 s after load, then one tap
            // takes the one changed file from the site, and only that one.
            await page.waitForTimeout(7000);
            const before = await page.evaluate(() => window.__calls.puts.filter((p) => p.path !== '/dg-edgetoedge.json').length);
            check(`${lang}/${theme}: nothing is fetched by itself`, before, 0);
            check(`${lang}/${theme}: the version row has its check button`, await page.evaluate(() => !!document.querySelector('.up-ver .up-check')), true);
            await page.evaluate(() => document.querySelector('.up-ver .up-check').click());
            await page.waitForTimeout(6000);
            const puts = await page.evaluate(() => window.__calls.puts.filter((p) => p.path !== '/dg-edgetoedge.json').map((p) => [p.path, atob(p.data).endsWith('\n\n')]));
            check(`${lang}/${theme}: the button hands over exactly the file the site changed`, puts, [[changed, true]]);
            check(`${lang}/${theme}: the row says what happened`, await page.evaluate(() => (document.querySelector('.up-check-note') || {}).textContent.length > 3), true);
            await ctx.close();
        }
    } finally {
        await browser.close();
        server.close();
    }
    console.log(`\n${results.filter(Boolean).length}/${results.length} checks passed`);
    process.exit(results.every(Boolean) ? 0 : 1);
})();
