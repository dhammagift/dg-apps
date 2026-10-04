// Edge to edge (owner, dg-apps#41): the Uposatha app runs under the transparent system bars instead
// of the DgBars plugin painting strips round the page. What this checks, without a phone:
//
//   * the bundled page carries viewport-fit=cover (the app build only: the snapshot on disk is the
//     site's own and stays as it is);
//   * the DgBars plugin and its calls are gone, and only Capacitor's SystemBars is used;
//   * the bar ICONS follow the page's own theme (data-theme, the attribute the page really sets —
//     the old code watched data-bs-theme and so never saw a theme switch), for BOTH bars;
//   * the page's top bar is pushed below the status bar exactly when the insets actually reach the
//     page, and is left alone when they do not (an old WebView, where Capacitor pads it natively;
//     a page without viewport-fit=cover on iOS);
//   * the native files agree on both platforms: SystemBars' cover hint, no DgBars java, the window
//     background is the page background (light/dark), not the old navy strip; on iOS the root view
//     controller runs the WKWebView edge to edge and forwards the status bar query to the bridge,
//     so the page's own theme picks the icon colour there too.
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

check('the bundled files are not patched for cover (the bridge does it as the page is parsed)',
    /viewport-fit=cover/.test(read(path.join(WWW, 'index.html'))), false);
// The snapshot is the site's page, copied as it is: patching it here would be patched again by the
// site updater (it compares the snapshot tree against the site, site-manifest.json).
check('the build refuses a snapshot that is not the calendar page (run 466 bundled another app\'s shell)',
    /CALENDAR_MARKERS/.test(read(path.join(ROOT, 'build.js')))
    && /is not the calendar page/.test(read(path.join(ROOT, 'build.js'))), true);
check('the snapshot page itself is left as the site serves it',
    read(path.join(WWW, 'uposatha-calendar.html')).includes('content="width=device-width, initial-scale=1">'), true);
check('Android takes both orientations (owner: build with landscape and portrait)',
    /android:screenOrientation/.test(read(path.join(APP, 'AndroidManifest.xml'))), false);
check('iOS stays portrait only (the iPhone layout is portrait first, owner dg-apps#41)',
    /UIInterfaceOrientationLandscape/.test(read(path.join(ROOT, 'ios', 'App', 'App', 'Info.plist')).split('<key>UISupportedInterfaceOrientations~ipad</key>')[0]), false);
check('the page\'s theme reaches the window background (no white strip over a dark page)',
    /setTheme/.test(read(path.join(APP, 'java/gift/dhamma/uposatha/DgInsetsPlugin.java')))
    && /DgInsets.setTheme/.test(read(path.join(ROOT, 'src/uposatha-bridge.js'))), true);
check('DgBarsPlugin.java is gone',
    fs.existsSync(path.join(APP, 'java/gift/dhamma/uposatha/DgBarsPlugin.java')), false);

const java = ['MainActivity.java', 'DgShortcutsPlugin.java', 'DgSitePlugin.java', 'DgSoundPlugin.java', 'DgAlarmPlugin.java']
    .map((f) => read(path.join(APP, 'java/gift/dhamma/uposatha', f))).join('\n');
check('nothing registers or calls DgBars any more', /DgBars/.test(java.replace(/No DgBars any more[^\n]*/g, '')), false);
check('the built bridge makes no DgBars call',
    /Plugins\.DgBars|DgBars\./.test(read(path.join(WWW, 'uposatha-bridge.js'))), false);
check('... and the bundle carries no DgBars plugin at all',
    /DgBars/.test(fs.readdirSync(path.join(APP, 'java/gift/dhamma/uposatha')).join(' ')), false);
check('only Capacitor\'s own SystemBars is configured',
    Object.keys(JSON.parse(read(path.join(ROOT, 'capacitor.config.json'))).plugins), ['SystemBars', 'LocalNotifications']);
check('SystemBars passes the insets through to the page (cover from the first frame, css variables)',
    (({ initialViewportFitValueHint, insetsHandling }) => [initialViewportFitValueHint, insetsHandling])(
        JSON.parse(read(path.join(ROOT, 'capacitor.config.json'))).plugins.SystemBars), ['cover', 'css']);
const insetsJava = read(path.join(APP, 'java/gift/dhamma/uposatha/DgInsetsPlugin.java'));
check('Android: the bar icons and the window colour are set in one call (not SystemBars.setStyle, which repaints the window in the system colour)',
    /setAppearanceLightStatusBars/.test(insetsJava) && /setAppearanceLightNavigationBars/.test(insetsJava)
    && /getDecorView\(\)\.setBackgroundColor\(color\)/.test(insetsJava), true);
check('... and put back after a rotation or a change of the phone\'s theme (SystemBars repaints then)',
    /handleOnConfigurationChanged/.test(insetsJava) && /post\(this::apply\)/.test(insetsJava), true);
check('Android has one source of insets: no DgInsets.get any more',
    /public void get\(/.test(insetsJava), false);
check('the share sheet plugin is registered',
    /registerPlugin\(DgSharePlugin\.class\)/.test(read(path.join(APP, 'java/gift/dhamma/uposatha/MainActivity.java'))), true);
check('the window background is the page\'s light background, not the navy strip',
    /<color name="dg_navbar">#ffffff<\/color>/.test(read(path.join(APP, 'res/values/colors.xml'))), true);
check('... and the dark one in night mode',
    /<color name="dg_navbar">#111111<\/color>/.test(read(path.join(APP, 'res/values-night/colors.xml'))), true);
check('the first frame takes its icon colour from the theme, never a fixed choice',
    (read(path.join(APP, 'res/values/styles.xml')).match(/windowLightStatusBar">@bool\/dg_light_bar/g) || []).length, 3);

// The resources this change touches (and any others): aapt refuses an XML comment with a double
// hyphen in it ("The string \"--\" is not permitted within comments"), which is a build failure
// with a confusing message — cheap to catch here.
function commentProblems(dir) {
    const bad = [];
    for (const f of fs.readdirSync(dir)) {
        if (!f.endsWith('.xml')) continue;
        const text = read(path.join(dir, f));
        for (const m of text.matchAll(/<!--([\s\S]*?)-->/g)) {
            if (m[1].includes('--')) bad.push(`${dir.split('/').pop()}/${f}: ${m[1].trim().slice(0, 40)}…`);
        }
    }
    return bad;
}
check('no resource comment contains a double hyphen (aapt rejects it)',
    [...commentProblems(path.join(APP, 'res/values')), ...commentProblems(path.join(APP, 'res/values-night'))], []);

// ---- the iOS half ---------------------------------------------------------------------------------
//
// Android's half is the resources above; iOS's is the root view controller. The bridge is
// platform-shared, so its checks below cover both.
const BRIDGE = bridgeSource();
const dgApp = read(path.join(ROOT, 'ios', 'App', 'App', 'DgApp.swift'));
check('iOS: the root no longer confines the page to the safe area',
    /safeAreaLayoutGuide/.test(dgApp), false);
check('iOS: the page is pinned to the window\'s own edges',
    /view\.topAnchor/.test(dgApp) && /view\.bottomAnchor/.test(dgApp), true);
check('iOS: the status bar query reaches the bridge (the page picks its own icon colour)',
    /childViewControllerForStatusBarStyle/.test(dgApp), true);
check('iOS: behind the first paint is the page background (white / #111111), not a system colour',
    /dgPageBackground/.test(dgApp) && /0x11 \/ 255/.test(dgApp), true);
check('iOS answers the page\'s inset question (DgInsets.get)',
    /@objc\(DgInsetsPlugin\)/.test(dgApp), true);
check('the bridge pads the top bar on iOS too (no platform skip in applyTopInset)',
    /function applyTopInset\(\) \{\n\s*if \(IOS\) return;/.test(BRIDGE), false);
// iOS is served by DgSiteRouter, which answers "/" with /uposatha-calendar.html — the site's own
// snapshot, which build.js does NOT patch (it patches index.html). Without viewport-fit=cover on
// that copy WKWebView reports env(safe-area-inset-top) as 0 and the page's top bar ends up under
// the Dynamic Island (run 444's screenshots). The router patches it where every copy passes.
check('iOS: the served page gets viewport-fit=cover at serve time',
    /withViewportCover/.test(dgApp) && /viewport-fit=cover/.test(dgApp), true);

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

function capacitorStub(platform) {
    window.__calls = { styles: [], themes: [], shared: [], opened: [], vt: 0, dgbars: 0, report: null, insets: null, insetsAsked: 0 };
    // window.open is the WebView's; here it only records where a link was sent
    window.open = (u) => { window.__calls.opened.push(u); return null; };
    window.Capacitor = {
        getPlatform: () => platform || 'android', isNativePlatform: () => true,
        Plugins: {
            App: { addListener: () => ({ remove() {} }), exitApp() {} },
            DgShortcuts: { set: (o) => Promise.resolve({ count: o.items.length }) },
            DgSound: { pick: () => Promise.resolve({}), channel: () => Promise.resolve() },
            DgSite: { put: () => Promise.resolve(), list: () => Promise.resolve({ files: [] }), clear: () => Promise.resolve() },
            // the DEBUG proof plugin (iOS): the bridge reports the inset it applied
            DgSelfTest: { report: (o) => { window.__calls.report = o; return Promise.resolve(o); } },
            // iOS: the page asks for the web view's safe-area insets (no env() there)
            DgInsets: {
                get: () => { window.__calls.insetsAsked = (window.__calls.insetsAsked || 0) + 1; return Promise.resolve(window.__calls.insets || { top: 0, right: 0, bottom: 0, left: 0 }); },
                setTheme: (o) => { window.__calls.themes.push((o.dark ? 'dark ' : 'light ') + o.color); return Promise.resolve(); },
            },
            DgShare: { share: (o) => { window.__calls.shared.push(o); return Promise.resolve(); } },
            // addListener as well: the bridge wraps the plugin's own listeners, and Capacitor's real
            // plugin has it — the site's current page calls it as soon as it loads.
            LocalNotifications: { addListener: () => ({ remove() {} }), requestPermissions: () => Promise.resolve({ display: 'granted' }), createChannel: () => Promise.resolve(), getPending: () => Promise.resolve({ notifications: [] }), cancel: () => Promise.resolve(), schedule: () => Promise.resolve() },
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
// Stands in for the native side: the iOS plugin (DgInsets) answers with the web view's own insets
// and the bridge writes them into the CSS variables; on Android Capacitor's SystemBars injects the
// same variables by itself. Either way the page reads var(--safe-area-inset-top, env(...)).
function fakeInsets(px) {
    window.__calls.insets = { top: px, right: 0, bottom: 0, left: 0 };
    document.documentElement.style.setProperty('--safe-area-inset-top', px + 'px');   // what SystemBars injects on Android
    window.dispatchEvent(new Event('resize'));
}

// The app layer (.tbar, #dg-drawer, body.app) is put up by the page's own scripts after the
// snapshot loads: a check that reads it must wait for it, and if it never arrives it must say what
// the page really is instead of throwing inside getComputedStyle (that is how runs 464 and 465
// failed: a null element in CI, while the local run had it).
async function appReady(page) {
    await page.waitForSelector('.tbar', { timeout: 20000 }).catch(() => {});
    return page.evaluate(() => ({
        hasBar: !!document.querySelector('.tbar'),
        hasDrawer: !!document.getElementById('dg-drawer'),
        isApp: !!document.body && document.body.classList.contains('app'),
        title: document.title,
        href: location.href,
        bytes: document.documentElement ? document.documentElement.outerHTML.length : 0,
        scripts: Array.from(document.scripts).map((s) => s.src).filter(Boolean).slice(0, 4)
    }));
}

(async () => {
    await new Promise((r) => server.listen(PORT, '127.0.0.1', r));
    const browser = await launchChromium();
    try {
        // 1. No insets reach the page (an old WebView: Capacitor pads it): the bar keeps its own padding.
        {
            const ctx = await browser.newContext({ viewport: { width: 412, height: 915 }, isMobile: true, hasTouch: true });
            await ctx.addInitScript(capacitorStub);
            await ctx.addInitScript(BRIDGE);
            const page = await ctx.newPage();
            const errors = [];
            page.on('pageerror', (e) => errors.push(e.message));
            await page.addInitScript(() => { try { localStorage.setItem('uiScale', '100'); } catch (e) {} });
            await page.goto(`http://127.0.0.1:${PORT}/`, { waitUntil: 'load' });
            const app1 = await appReady(page);
            if (!app1.hasBar) console.log('       page is not the app layer:', JSON.stringify(app1));
            await page.waitForTimeout(2500);
            check('no insets: the top bar keeps its own padding',
                await page.evaluate(() => { const b = document.querySelector('.tbar'); return b ? getComputedStyle(b).paddingTop : 'no .tbar on this page'; }), '4px');
            // The drawer exists on the calendar page; if a build's page does not have it, say so
            // rather than throwing inside getComputedStyle (that is how run 464 failed: a null
            // element, not a wrong value).
            check('no insets: the drawer is not padded either',
                await page.evaluate(() => {
                    const d = document.getElementById('dg-drawer');
                    return d ? getComputedStyle(d).paddingTop : 'no drawer on this page';
                }), '0px');
            check('no insets: no cover padding is added at all',
                await page.evaluate(() => document.body.classList.contains('dg-safe-top-on')), false);
            check('Android: the light page sets dark icons and its own white window, in one call',
                await page.evaluate(() => window.__calls.themes), ['light #ffffff']);
            check('Android: SystemBars.setStyle is never called (it would repaint the window in the system colour)',
                await page.evaluate(() => window.__calls.styles), []);
            check('Android: the page is viewport-fit=cover once parsed (the insets reach it)',
                await page.evaluate(() => /viewport-fit=cover/.test(document.querySelector('meta[name=viewport]').content)), true);
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
            await page.addInitScript(() => { try { localStorage.setItem('uiScale', '100'); } catch (e) {} });
            await page.goto(`http://127.0.0.1:${PORT}/`, { waitUntil: 'load' });
            const app2 = await appReady(page);
            if (!app2.hasBar) console.log('       page is not the app layer:', JSON.stringify(app2));
            await page.waitForTimeout(2500);
            // The page's own interface scale (a stored 110% in a fresh profile) would divide the
            // inset by it: this scenario is about the plain case.
            await page.evaluate(() => { document.documentElement.style.removeProperty('--dg-zoom'); document.documentElement.style.zoom = ''; });
            await page.evaluate(fakeInsets, 30);
            await page.waitForTimeout(200);
            check('a 30px inset: the top bar steps down by it',
                await page.evaluate(() => { const b = document.querySelector('.tbar'); return b ? getComputedStyle(b).paddingTop : 'no .tbar on this page'; }), '34px');
            const rep = await page.evaluate(() => window.__calls.report);
            check('the page reports its measurements for the proof (what the screenshot cannot tell)',
                [rep && rep.topInset, rep && rep.barTop >= rep.topInset], [30, true]);
            check('the padding is the documented Capacitor pattern (its variable, then env(), then 0)',
                await page.evaluate(() => /body\.app \.tbar\{padding-top:calc\(4px \+ var\(--safe-area-inset-top, env\(safe-area-inset-top, 0px\)\) \/ var\(--dg-zoom, 1\)\)\}/.test(
                    (document.getElementById('dg-safe-top') || {}).textContent || '')), true);
            check('the chosen half of a segmented control is the accent green, like a switched-on toggle',
                await page.evaluate(() => {
                    const css = (document.getElementById('dg-safe-top') || {}).textContent || '';
                    const paint = /body\.app \.dg-segmented button\[aria-pressed="true"\][^{]*\{background:var\(--dg-accent\)/.test(css);
                    return paint;
                }), true);
            check('... and it really renders as the accent (not a grey)',
                await page.evaluate(() => {
                    const btn = document.querySelector('.dg-segmented button[aria-pressed="true"]');
                    if (!btn) return 'no pressed button on the page';
                    const acc = getComputedStyle(document.documentElement).getPropertyValue('--dg-accent').trim();
                    const probe = document.createElement('div');
                    probe.style.color = acc || '#149c7c';
                    document.body.appendChild(probe);
                    const want = getComputedStyle(probe).color;
                    probe.remove();
                    return getComputedStyle(btn).backgroundColor === want ? 'accent' : getComputedStyle(btn).backgroundColor + ' != ' + want;
                }), 'accent');
            check('the burger menu\'s drawer is padded too (it opened under the clock on Android)',
                /body\.app #dg-drawer\{padding-top:calc\(var\(--safe-area-inset-top/.test(
                    await page.evaluate(() => (document.getElementById('dg-safe-top') || {}).textContent || '')), true);
            check('the page reports the inset it really has ("effective"), read from the layout',
                await page.evaluate(() => window.__calls.report && window.__calls.report.topInset), 30);
            check('Android: SystemBars\' variable supplies it, DgInsets.get is not asked (one source)',
                await page.evaluate(() => [getComputedStyle(document.documentElement).getPropertyValue('--safe-area-inset-top').trim(), window.__calls.insetsAsked]), ['30px', 0]);
            // The theme the page itself switches (uposatha-calendar.js setTheme): data-theme and
            // data-bs-theme on <html>, body.dark — all in one go, as the page does.
            const setTheme = (eff) => {
                document.documentElement.setAttribute('data-theme', eff);
                document.documentElement.setAttribute('data-bs-theme', eff);
                document.body.classList.toggle('dark', eff === 'dark');
            };
            await page.evaluate(setTheme, 'dark');
            await page.waitForTimeout(200);
            const zoomPad = await page.evaluate(async () => {
                document.documentElement.style.setProperty('--dg-zoom', '1.5');
                document.documentElement.style.zoom = '1.5';
                window.dispatchEvent(new Event('resize'));
                await new Promise((r) => setTimeout(r, 50));
                const el = document.querySelector('.tbar');
                const bar = el ? getComputedStyle(el).paddingTop : 'no .tbar on this page';
                document.documentElement.style.zoom = '';
                document.documentElement.style.removeProperty('--dg-zoom');
                window.dispatchEvent(new Event('resize'));
                await new Promise((r) => setTimeout(r, 50));
                return bar;
            });
            // 10px of the bar's own padding (which the zoom scales to 15) plus the inset divided by
            // the zoom (30 / 1.5 = 20): 30 CSS px, which renders as 45 device-independent px — the
            // real 30px inset plus the bar's own 15. Without the division it would be 40 and grow
            // with every step of the font-size setting.
            check('at 150% interface zoom the inset is divided by it (the bar does not drift down)',
                zoomPad, '24px');

            check('switching to the page\'s dark theme sends the dark window and light icons',
                await page.evaluate(() => window.__calls.themes.slice(-1)), ['dark #111111']);
            await page.evaluate(setTheme, 'light');
            await page.waitForTimeout(200);
            check('... and back again', await page.evaluate(() => window.__calls.themes.slice(-1)), ['light #ffffff']);
            check('an unchanged theme is not sent again',
                await page.evaluate(() => window.__calls.themes.length) <= 4, true);
            check('nor does the page ask for DgBars strips', await page.evaluate(() => window.__calls.dgbars), 0);
            check('no script errors', errors, []);
            await ctx.close();
        }
        // 3. The app's own links, the share sheet, the toast and the theme circle (dg-apps#55, #56).
        {
            const ctx = await browser.newContext({ viewport: { width: 412, height: 915 }, isMobile: true, hasTouch: true, colorScheme: 'light' });
            await ctx.addInitScript(capacitorStub);
            await ctx.addInitScript(BRIDGE);
            const page = await ctx.newPage();
            const errors = [];
            page.on('pageerror', (e) => errors.push(e.message));
            await page.addInitScript(() => { try { localStorage.setItem('uiScale', '100'); localStorage.setItem('theme', 'light'); } catch (e) {} });
            await page.goto(`http://127.0.0.1:${PORT}/?lang=en`, { waitUntil: 'load' });
            await appReady(page);
            await page.waitForTimeout(2500);
            check('the menu open: the window takes the menu\'s dimming (the strip of a padded window on an old WebView)',
                await page.evaluate(async () => {
                    document.getElementById('b-menu').click();
                    await new Promise((r) => setTimeout(r, 400));
                    const dimmed = window.__calls.themes.slice(-1)[0];
                    document.querySelector('#dg-drawer .dg-drawer-close').click();
                    await new Promise((r) => setTimeout(r, 400));
                    return [dimmed !== 'light #ffffff' && /^light #[0-9a-f]{6}$/.test(dimmed), window.__calls.themes.slice(-1)[0]];
                }), [true, 'light #ffffff']);
            check('Help in the menu header opens the docs on dhamma.gift, not the app\'s own origin',
                await page.evaluate(() => { document.getElementById('d-help-top').click(); return window.__calls.opened.slice(-1)[0]; }),
                'https://dhamma.gift/docs/uposatha/');
            check('the Help link (an anchor) goes to dhamma.gift too',
                await page.evaluate(() => { document.getElementById('b-help').click(); return window.__calls.opened.slice(-1)[0]; }),
                'https://dhamma.gift/docs/uposatha/');
            check('Share opens the system sheet with the docs page (Android has no navigator.share of its own)',
                await page.evaluate(async () => { document.getElementById('b-share').click(); await new Promise((r) => setTimeout(r, 50)); return window.__calls.shared.slice(-1)[0]; }),
                { title: 'Uposatha', url: 'https://dhamma.gift/docs/uposatha' });
            check('... the menu\'s share as well, not the address the WebView happens to be at',
                await page.evaluate(async () => { const b = document.querySelector('#dg-drawer .dg-drawer-share'); if (!b) return 'no menu share'; b.click(); await new Promise((r) => setTimeout(r, 50)); return window.__calls.shared.slice(-1)[0].url; }),
                'https://dhamma.gift/docs/uposatha');
            check('"Link copied" is a toast above the tab bar, not a bare full-width bar',
                await page.evaluate(async () => {
                    window.showBubbleNotification('Link copied');
                    await new Promise((r) => setTimeout(r, 300));
                    const b = document.querySelector('.bubble-notification'), r = b.getBoundingClientRect();
                    const nav = document.querySelector('.appnav'), n = nav && !nav.hidden ? nav.getBoundingClientRect() : { top: innerHeight };
                    return { narrow: r.width < innerWidth - 30, round: parseFloat(getComputedStyle(b).borderRadius) > 10, aboveNav: r.bottom <= n.top + 1, shown: getComputedStyle(b).opacity === '1' };
                }), { narrow: true, round: true, aboveNav: true, shown: true });
            const vt = await page.evaluate(async () => {
                const was = document.documentElement.getAttribute('data-theme');
                if (typeof document.startViewTransition !== 'function') return 'no View Transitions in this browser';
                const real = document.startViewTransition.bind(document);
                document.startViewTransition = (cb) => { window.__calls.vt++; return real(cb); };
                const btn = document.getElementById('app-theme');
                const r = btn.getBoundingClientRect();
                btn.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, clientX: r.left + 5, clientY: r.top + 5 }));
                await new Promise((res) => setTimeout(res, 1400));
                return { was, now: document.documentElement.getAttribute('data-theme'), circles: window.__calls.vt, window: window.__calls.themes.slice(-1)[0] };
            });
            check('the theme button switches the theme through a circle from the tap, and the bars follow',
                vt, { was: 'light', now: 'dark', circles: 1, window: 'dark #111111' });
            check('... and back again, without a second theme change sneaking in',
                await page.evaluate(async () => {
                    const btn = document.getElementById('app-theme');
                    btn.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, clientX: 10, clientY: 10 }));
                    await new Promise((res) => setTimeout(res, 1400));
                    return [document.documentElement.getAttribute('data-theme'), window.__calls.vt];
                }), ['light', 2]);
            check('no script errors', errors, []);
            await ctx.close();
        }
        // 4. iOS: SystemBars sets the icons (no DgInsets.setTheme there), DgInsets.get supplies the inset.
        {
            const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, colorScheme: 'light' });
            await ctx.addInitScript(capacitorStub, 'ios');
            await ctx.addInitScript(BRIDGE);
            const page = await ctx.newPage();
            const errors = [];
            page.on('pageerror', (e) => errors.push(e.message));
            await page.addInitScript(() => { try { localStorage.setItem('uiScale', '100'); localStorage.setItem('theme', 'light'); } catch (e) {} });
            await page.goto(`http://127.0.0.1:${PORT}/`, { waitUntil: 'load' });
            await appReady(page);
            await page.waitForTimeout(2500);
            check('iOS: both bars get dark icons on the light page, through SystemBars',
                await page.evaluate(() => [window.__calls.styles, window.__calls.themes]), [['LIGHT/StatusBar', 'LIGHT/NavigationBar'], []]);
            check('iOS: the inset is asked for natively', await page.evaluate(() => window.__calls.insetsAsked > 0), true);
            check('iOS: the bridge does not patch the viewport (DgSiteRouter does at serve time)',
                await page.evaluate(() => /viewport-fit=cover/.test(document.querySelector('meta[name=viewport]').content)), false);
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
