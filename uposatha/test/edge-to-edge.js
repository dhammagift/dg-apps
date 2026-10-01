// Edge to edge (owner, dg-apps#41): the Uposatha app runs under the transparent system bars instead
// of the DgBars plugin painting strips round the page. What this checks, without a phone:
//
//   * the bundled page carries viewport-fit=cover (the app build only: the snapshot on disk is the
//     site's own and stays as it is);
//   * the DgBars plugin and its calls are gone, and only Capacitor's SystemBars is used;
//   * the bar ICONS follow the page's own theme (data-theme, the attribute the page really sets —
//     the old code watched data-bs-theme and so never saw a theme switch), for BOTH bars;
//   * the page's top bar is pushed below the status bar exactly when the insets actually reach the
//     page, and is left alone when they do not (an old WebView, where Capacitor pads it natively);
//   * the native files agree: SystemBars' cover hint, no DgBars java, the window background is the
//     page background (light/dark), not the old navy strip.
//
//   (cd uposatha && node build.js) then:  node uposatha/test/edge-to-edge.js
const fs = require('fs');
const path = require('path');
const http = require('http');
// The app's own playwright (uposatha/node_modules, where the build job's `npx playwright install`
// puts the matching browser), or the global CLI of a dev box — whichever can really launch, so the
// test runs the same way in CI and by hand.
function playwrightCandidates() {
    const list = [process.env.DG_PLAYWRIGHT].filter(Boolean);
    try { list.push(require.resolve('playwright', { paths: [process.cwd(), __dirname] })); } catch (e) { /* not installed */ }
    list.push('/usr/lib/node_modules/@playwright/cli/node_modules/playwright');
    return list;
}
async function launchChromium() {
    const tried = [];
    for (const mod of playwrightCandidates()) {
        try {
            return await require(mod).chromium.launch({ args: ['--no-sandbox'] });
        } catch (e) {
            tried.push(`${mod}: ${String(e.message).split('\n')[0]}`);
        }
    }
    throw new Error('no usable playwright:\n  ' + tried.join('\n  '));
}

const ROOT = path.join(__dirname, '..');
const APP = path.join(ROOT, 'android', 'app', 'src', 'main');
const WWW = path.join(ROOT, 'www');
const PORT = 8108;
const { bridgeSource } = require(path.join(ROOT, 'build.js'));

const results = [];
function check(name, actual, expected) {
    const pass = JSON.stringify(actual) === JSON.stringify(expected);
    results.push(pass);
    console.log(`${pass ? 'ok  ' : 'FAIL'} ${name}${pass ? '' : `\n       expected ${JSON.stringify(expected)}\n       actual   ${JSON.stringify(actual)}`}`);
}
const read = (p) => fs.readFileSync(p, 'utf8');

// ---- the files -----------------------------------------------------------------------------------

check('the bundled page asks for the cover viewport',
    /<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">/.test(read(path.join(WWW, 'index.html'))), true);
// The snapshot is the site's page, copied as it is: patching it here would be patched again by the
// site updater (it compares the snapshot tree against the site, site-manifest.json).
check('the snapshot page itself is left as the site serves it',
    read(path.join(WWW, 'uposatha-calendar.html')).includes('content="width=device-width, initial-scale=1">'), true);
check('DgBarsPlugin.java is gone',
    fs.existsSync(path.join(APP, 'java/gift/dhamma/uposatha/DgBarsPlugin.java')), false);

const java = ['MainActivity.java', 'DgShortcutsPlugin.java', 'DgSitePlugin.java', 'DgSoundPlugin.java', 'DgAlarmPlugin.java']
    .map((f) => read(path.join(APP, 'java/gift/dhamma/uposatha', f))).join('\n');
check('nothing registers or calls DgBars any more', /DgBars/.test(java.replace(/No DgBars any more[^\n]*/g, '')), false);
check('the built bridge only mentions DgBars in a comment (no plugin call)',
    (read(path.join(WWW, 'uposatha-bridge.js')).match(/DgBars/g) || []).length, 1);
check('... and the bundle carries no DgBars plugin at all',
    /DgBars/.test(fs.readdirSync(path.join(APP, 'java/gift/dhamma/uposatha')).join(' ')), false);
check('only Capacitor\'s own SystemBars is configured',
    Object.keys(JSON.parse(read(path.join(ROOT, 'capacitor.config.json'))).plugins), ['SystemBars', 'LocalNotifications']);
check('SystemBars is told the viewport will be cover (no first-paint shift)',
    JSON.parse(read(path.join(ROOT, 'capacitor.config.json'))).plugins.SystemBars.initialViewportFitValueHint, 'cover');
check('the window background is the page\'s light background, not the navy strip',
    /<color name="dg_navbar">#ffffff<\/color>/.test(read(path.join(APP, 'res/values/colors.xml'))), true);
check('... and the dark one in night mode',
    /<color name="dg_navbar">#111111<\/color>/.test(read(path.join(APP, 'res/values-night/colors.xml'))), true);
check('the first frame takes its icon colour from the theme, never a fixed choice',
    (read(path.join(APP, 'res/values/styles.xml')).match(/windowLightStatusBar">@bool\/dg_light_bar/g) || []).length, 3);

// ---- the page, with the real bridge and a recorder for the plugins -------------------------------

const TYPES = { html: 'text/html', js: 'application/javascript', css: 'text/css', json: 'application/json', svg: 'image/svg+xml', woff2: 'font/woff2', png: 'image/png', wasm: 'application/wasm' };
const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://x');
    let file = path.join(WWW, decodeURIComponent(url.pathname));
    if (!file.startsWith(WWW) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(WWW, 'index.html');
    const ext = path.extname(file).slice(1);
    res.writeHead(200, { 'content-type': TYPES[ext] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
});

function capacitorStub() {
    window.__calls = { styles: [], dgbars: 0 };
    window.Capacitor = {
        getPlatform: () => 'android', isNativePlatform: () => true,
        Plugins: {
            App: { addListener: () => ({ remove() {} }), exitApp() {} },
            DgShortcuts: { set: (o) => Promise.resolve({ count: o.items.length }) },
            DgSound: { pick: () => Promise.resolve({}), channel: () => Promise.resolve() },
            DgSite: { put: () => Promise.resolve(), list: () => Promise.resolve({ files: [] }), clear: () => Promise.resolve() },
            LocalNotifications: { requestPermissions: () => Promise.resolve({ display: 'granted' }), createChannel: () => Promise.resolve(), getPending: () => Promise.resolve({ notifications: [] }), cancel: () => Promise.resolve(), schedule: () => Promise.resolve() },
            SystemBars: {
                setStyle: (o) => { window.__calls.styles.push(o.style + '/' + o.bar); return Promise.resolve(); },
                // The native DgBars is gone; a call to it would show up here as a page error instead.
                DgBars: { set: () => { window.__calls.dgbars++; return Promise.resolve(); } },
            },
        },
    };
}

// Stands in for the native side of SystemBars: the custom property it writes into the page (the
// SystemBars plugin does this on every inset change, for old and new WebViews alike), which is what
// the bridge's inset probe falls back on where env() itself is broken.
function fakeInsets(px) {
    document.documentElement.style.setProperty('--safe-area-inset-top', px + 'px');
    window.dispatchEvent(new Event('resize'));
}

(async () => {
    await new Promise((r) => server.listen(PORT, '127.0.0.1', r));
    const browser = await launchChromium();
    const BRIDGE = bridgeSource();
    try {
        // 1. No insets reach the page (an old WebView: Capacitor pads it): the bar keeps its own padding.
        {
            const ctx = await browser.newContext({ viewport: { width: 412, height: 915 }, isMobile: true, hasTouch: true });
            await ctx.addInitScript(capacitorStub);
            await ctx.addInitScript(BRIDGE);
            const page = await ctx.newPage();
            const errors = [];
            page.on('pageerror', (e) => errors.push(e.message));
            await page.goto(`http://127.0.0.1:${PORT}/`, { waitUntil: 'load' });
            await page.waitForTimeout(2500);
            check('no insets: the top bar keeps its own padding',
                await page.evaluate(() => getComputedStyle(document.querySelector('.tbar')).paddingTop), '10px');
            check('no insets: no cover padding is added at all',
                await page.evaluate(() => document.body.classList.contains('dg-safe-top-on')), false);
            check('the light page gets dark icons, on both bars',
                await page.evaluate(() => window.__calls.styles), ['LIGHT/StatusBar', 'LIGHT/NavigationBar']);
            check('the page never asks for its own DgBars strips',
                await page.evaluate(() => window.__calls.dgbars), 0);
            check('no script errors', errors, []);
            await ctx.close();
        }
        // 2. The insets do reach the page (WebView 140+, viewport-fit=cover): the bar steps down by
        //    exactly the inset, the icons follow the page's theme, and a theme switch is not missed.
        {
            const ctx = await browser.newContext({ viewport: { width: 412, height: 915 }, isMobile: true, hasTouch: true, colorScheme: 'light' });
            await ctx.addInitScript(capacitorStub);
            await ctx.addInitScript(BRIDGE);
            const page = await ctx.newPage();
            const errors = [];
            page.on('pageerror', (e) => errors.push(e.message));
            await page.goto(`http://127.0.0.1:${PORT}/`, { waitUntil: 'load' });
            await page.waitForTimeout(2500);
            await page.evaluate(fakeInsets, 30);
            await page.waitForTimeout(200);
            check('a 30px inset: the top bar steps down by it',
                await page.evaluate(() => getComputedStyle(document.querySelector('.tbar')).paddingTop), '40px');
            check('the inset is written where the platform really pays it (no double padding without one)',
                await page.evaluate(() => (document.getElementById('dg-safe-top') || {}).textContent || ''), 'body.app .tbar{padding-top:calc(10px + 30px)}');
            // The theme the page itself switches (uposatha-calendar.js setTheme): data-theme on <html>.
            await page.evaluate(() => document.documentElement.setAttribute('data-theme', 'dark'));
            await page.waitForTimeout(200);
            check('switching to the page\'s dark theme flips both bars',
                await page.evaluate(() => window.__calls.styles.slice(-2)), ['DARK/StatusBar', 'DARK/NavigationBar']);
            await page.evaluate(() => document.documentElement.setAttribute('data-theme', 'light'));
            await page.waitForTimeout(200);
            check('... and back again', await page.evaluate(() => window.__calls.styles.slice(-2)), ['LIGHT/StatusBar', 'LIGHT/NavigationBar']);
            check('an unchanged style is not sent again',
                await page.evaluate(() => window.__calls.styles.length) <= 6, true);
            check('nor does the page ask for DgBars strips', await page.evaluate(() => window.__calls.dgbars), 0);
            check('no script errors', errors, []);
            await ctx.close();
        }
    } finally {
        await browser.close();
        server.close();
    }
    console.log(`\n${results.filter(Boolean).length}/${results.length} checks passed`);
    process.exit(results.every(Boolean) ? 0 : 1);
})();
