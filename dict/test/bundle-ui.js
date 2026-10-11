// Browser check that the dictionary app opens with NO network: the bundled page (www/, a snapshot of the site's
// page in both languages) served the way the app serves it (a directory's index.html, else the file), with the
// real bridge and every request to anywhere else refused. And that the updater hands DgSite exactly the file
// the site changed. What the app's native proxy does for a word's page (Java, DgSitePlugin) cannot run here.
//
//   (cd dict && node tools/bundle-from-repo.js <ddg-ui dir> <dg-node dir> && node build.js) first, then:  node dict/test/bundle-ui.js
const fs = require('fs');
const path = require('path');
const { chromium } = require('/usr/lib/node_modules/@playwright/cli/node_modules/playwright');

const WWW = path.join(__dirname, '..', 'www');
const SHOTS = process.env.DG_SHOTS || '/var/www/html/dict-app';
const PORT = 8108;
const { bridgeSource } = require(path.join(__dirname, '..', 'build.js'));
const { siteSigner, sha256 } = require(path.join(__dirname, '..', '..', 'test', 'signed-site-list.js'));

const results = [];
function check(name, actual, expected) {
    const pass = JSON.stringify(actual) === JSON.stringify(expected);
    results.push(pass);
    console.log(`${pass ? 'ok  ' : 'FAIL'} ${name}${pass ? '' : `\n       expected ${JSON.stringify(expected)}\n       actual   ${JSON.stringify(actual)}`}`);
}

const { serveWww, TYPES } = require('./serve-www.js');
const server = serveWww(WWW);

function capacitorStub() {
    window.__calls = { puts: [], shortcuts: [] };
    window.Capacitor = {
        getPlatform: () => 'android', isNativePlatform: () => true,
        Plugins: {
            App: { addListener: () => ({ remove() {} }), exitApp() {} },
            DgShortcuts: { set: (o) => { window.__calls.shortcuts.push(o.items); return Promise.resolve({ count: o.items.length }); } },
            DgSite: { put: (o) => { window.__calls.puts.push({ path: o.path, data: o.data }); return Promise.resolve(); }, list: () => Promise.resolve({ files: [] }), clear: () => Promise.resolve() },
        },
    };
}

(async () => {
    await new Promise((r) => server.listen(PORT, '127.0.0.1', r));
    const browser = await chromium.launch({ args: ['--no-sandbox'] });
    const BRIDGE = bridgeSource();
    const SIGNER = siteSigner();   // the updater takes only a list signed with the key it trusts: this one, through its test hook
    const manifest = JSON.parse(fs.readFileSync(path.join(WWW, 'site-manifest.json'), 'utf8'));
    const changed = manifest.files.find((f) => /\/static\/dg\.css$/.test(f) && !f.startsWith('/ru/')) || manifest.files.find((f) => f.endsWith('.css'));
    try {
        for (const [theme, lang, url] of [['light', 'en', '/'], ['dark', 'ru', '/ru/']]) {
            const ctx = await browser.newContext({ viewport: { width: 412, height: 915 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, colorScheme: theme, locale: lang === 'ru' ? 'ru-RU' : 'en-US' });
            await ctx.addInitScript(capacitorStub);
            await ctx.addInitScript(SIGNER.initScript);
            await ctx.addInitScript(BRIDGE);
            const page = await ctx.newPage();
            const bad = [], errors = [];
            const changedBody = fs.readFileSync(path.join(WWW, changed), 'utf8') + '\n/* changed on the site */\n';
            await page.route(/^https?:\/\/(?!127\.0\.0\.1)/, (route) => {
                const u = new URL(route.request().url());
                if (u.origin === 'https://dict.dhamma.gift' || u.origin === 'https://dhamma.gift') {   // find on the page's files come from dhamma.gift (urlFor in the bridge)
                    let p = u.pathname;
                    if (p.endsWith('/')) p += 'index.html';
                    // The site's signed list: the bundle's own hashes, but the changed file's is the site's new one.
                    if (p === '/app-site-manifest.json') return route.fulfill({ status: 200, contentType: 'application/json', body: SIGNER.envelope(u.origin, Object.assign({}, manifest.hashes, { [changed]: sha256(changedBody) })) });
                    if (p === changed) return route.fulfill({ status: 200, contentType: 'text/css', body: changedBody });
                    const f = path.join(WWW, p);
                    if (manifest.files.includes(p) && fs.existsSync(f)) return route.fulfill({ status: 200, contentType: TYPES[path.extname(f).slice(1)] || 'application/octet-stream', body: fs.readFileSync(f) });
                    return route.fulfill({ status: 404, body: '' });
                }
                return route.abort('internetdisconnected');
            });
            page.on('response', (r) => { if (r.url().startsWith(`http://127.0.0.1:${PORT}`) && r.status() >= 400) bad.push(r.status() + ' ' + r.url()); });
            page.on('pageerror', (e) => errors.push(e.message));
            await page.goto(`http://127.0.0.1:${PORT}${url}`, { waitUntil: 'load' });
            await page.waitForTimeout(3500);
            check(`${lang}/${theme}: the search box is there`, await page.evaluate(() => !!document.querySelector('input[type=search], input[type=text], #search')), true);
            check(`${lang}/${theme}: the page's language`, await page.evaluate(() => document.documentElement.lang), lang);
            check(`${lang}/${theme}: no script errors offline`, errors, []);
            check(`${lang}/${theme}: nothing of the app's own is missing (no 4xx)`, bad, []);
            await page.screenshot({ path: path.join(SHOTS, `launch-dict-offline-${lang}-${theme}.png`) });
            await page.waitForTimeout(6500);
            const puts = await page.evaluate(() => window.__calls.puts.map((p) => [p.path, atob(p.data).endsWith('/* changed on the site */\n')]));
            check(`${lang}/${theme}: the updater hands over exactly the file the site changed`, puts, [[changed, true]]);
            await ctx.close();
        }
    } finally {
        await browser.close();
        server.close();
    }
    console.log(`\n${results.filter(Boolean).length}/${results.length} checks passed`);
    process.exit(results.every(Boolean) ? 0 : 1);
})();
