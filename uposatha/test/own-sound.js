// The person's own sound is offered in all four lists of sounds (Uposatha, end of food, start of food, parts of the night and
// day), is picked from any of them, and is the same sound everywhere. The real bridge and page (www/), Capacitor stubbed.
//
//   (cd uposatha && node tools/bundle-from-repo.js <dg-node dir> && node build.js) first, then:  node uposatha/test/own-sound.js
const fs = require('fs');
const path = require('path');
const http = require('http');
const { chromium } = require('/usr/lib/node_modules/@playwright/cli/node_modules/playwright');
const WWW = path.join(__dirname, '..', 'www');
const PORT = 8109;
const { bridgeSource } = require(path.join(__dirname, '..', 'build.js'));
const results = [];
function check(name, actual, expected) {
    const pass = JSON.stringify(actual) === JSON.stringify(expected);
    results.push(pass);
    console.log(`${pass ? 'ok  ' : 'FAIL'} ${name}${pass ? '' : `\n       expected ${JSON.stringify(expected)}\n       actual   ${JSON.stringify(actual)}`}`);
}
const TYPES = { html: 'text/html', js: 'application/javascript', css: 'text/css', json: 'application/json', svg: 'image/svg+xml', woff2: 'font/woff2', png: 'image/png' };
const server = http.createServer((req, res) => {
    let file = path.join(WWW, decodeURIComponent(new URL(req.url, 'http://x').pathname));
    if (!file.startsWith(WWW) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(WWW, 'index.html');
    res.writeHead(200, { 'content-type': TYPES[path.extname(file).slice(1)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
});
function capacitorStub() {
    window.__picks = 0; window.__sched = [];
    window.Capacitor = {
        getPlatform: () => 'android', isNativePlatform: () => true,
        Plugins: {
            App: { addListener: () => ({ remove() {} }), exitApp() {} },
            DgShortcuts: { set: (o) => Promise.resolve({ count: o.items.length }) },
            DgInsets: { get: () => Promise.resolve({ top: 0, right: 0, bottom: 0, left: 0 }), setTheme: () => Promise.resolve() },
            DgSound: { pick: () => { window.__picks++; return Promise.resolve({ channelId: 'uposatha-own-' + window.__picks, name: 'Bell ' + window.__picks }); }, channel: () => Promise.resolve(), dndAccess: () => Promise.resolve({ granted: false }) },
            DgSite: { put: () => Promise.resolve(), list: () => Promise.resolve({ files: [] }), clear: () => Promise.resolve() },
            SystemBars: { setStyle: () => Promise.resolve() },
            LocalNotifications: { addListener: () => ({ remove() {} }), requestPermissions: () => Promise.resolve({ display: 'granted' }), createChannel: () => Promise.resolve(), getPending: () => Promise.resolve({ notifications: [] }), cancel: () => Promise.resolve(), schedule: (o) => { window.__sched.push(o.notifications.map((n) => n.channelId)); (window.__sched2 = window.__sched2 || []).push(...o.notifications.map((n) => ({ title: n.title, body: n.body, channelId: n.channelId, at: +new Date(n.schedule.at) }))); return Promise.resolve({ notifications: [] }); } },
        },
    };
}
const SELECTS = ['rem-sound', 'mrem-sound', 'mbeg-sound', 'psnd'];
const pick = (page, id, v) => page.evaluate(([i, val]) => { const s = document.getElementById(i); s.value = val; s.dispatchEvent(new Event('change')); }, [id, v]);
const ls = (page, k) => page.evaluate((key) => JSON.parse(localStorage.getItem(key) || 'null'), k);

(async () => {
    await new Promise((r) => server.listen(PORT, '127.0.0.1', r));
    const browser = await chromium.launch({ args: ['--no-sandbox'] });
    try {
        const ctx = await browser.newContext({ viewport: { width: 412, height: 915 }, isMobile: true, hasTouch: true });
        await ctx.addInitScript(capacitorStub);
        await ctx.addInitScript(bridgeSource());
        const page = await ctx.newPage();
        const errors = [];
        page.on('pageerror', (e) => errors.push(e.message));
        await page.goto(`http://127.0.0.1:${PORT}/`, { waitUntil: 'load' });
        await page.waitForSelector('#mbeg-sound', { state: 'attached', timeout: 20000 });
        await page.waitForTimeout(1500);
        const values = (id) => page.evaluate((i) => [...document.querySelectorAll('#' + i + ' option')].map((o) => o.value), id);
        for (const id of SELECTS) check(`${id}: "own" is offered, and nothing to replace yet`, (await values(id)).filter((v) => /^own/.test(v)), ['own']);

        await pick(page, 'mbeg-sound', 'own');   // no own sound yet: the picker opens, from this list
        await page.waitForTimeout(300);
        check('picked from the start-of-food list: one pick, the choice is own', [await page.evaluate(() => window.__picks), (await ls(page, 'dgUposathaMeal')).begSnd, (await ls(page, 'dgUposathaRemind')).ownChannel], [1, 'own', 'uposatha-own-1']);
        for (const id of SELECTS) check(`${id}: now offers the sound and "change"`, (await values(id)).filter((v) => /^own/.test(v)), ['own', 'own-pick']);
        check('... under its name', await page.evaluate(() => document.querySelector('#psnd option[value="own"]').textContent.includes('Bell 1')), true);

        await pick(page, 'psnd', 'own');         // there is one: chosen without the picker
        await pick(page, 'mrem-sound', 'own');
        await page.waitForTimeout(300);
        check('chosen in the other lists: no new pick, the same sound', [await page.evaluate(() => window.__picks), (await ls(page, 'dgUposathaParts')).snd, (await ls(page, 'dgUposathaMeal')).snd], [1, 'own', 'own']);

        await pick(page, 'mrem-sound', 'own-pick'); // replace it from any list: it is replaced for all
        await page.waitForTimeout(300);
        check('changed from another list: one more pick, one channel for all', [await page.evaluate(() => window.__picks), (await ls(page, 'dgUposathaRemind')).ownChannel], [2, 'uposatha-own-2']);

        // Scheduling: a reminder whose sound is own goes on the own channel, whichever list chose it.
        await page.evaluate(() => { const m = JSON.parse(localStorage.getItem('dgUposathaMeal')); m.rem = true; m.beg = true; localStorage.setItem('dgUposathaMeal', JSON.stringify(m)); });
        await page.reload({ waitUntil: 'load' });
        await page.waitForTimeout(3000);
        check('scheduled reminders use the shared own channel', await page.evaluate(() => window.__sched.flat().filter((c) => /uposatha-own/.test(c)).every((c) => c === 'uposatha-own-2') && window.__sched.flat().some((c) => c === 'uposatha-own-2')), true);
        check('no script errors', errors, []);
        await ctx.close();

        // The catch-up: a reminder whose time has passed is shown at once, quietly, and says it was missed. The clock is fixed one
        // day after the 8th-day reminder was due ("1 day ahead" of an Uposatha that begins on the evening of 3 Oct 2026).
        const ctx2 = await browser.newContext({ viewport: { width: 412, height: 915 }, isMobile: true, hasTouch: true, locale: 'en-US', timezoneId: 'Asia/Almaty' });
        await ctx2.addInitScript(capacitorStub);
        await ctx2.addInitScript(bridgeSource());
        await ctx2.addInitScript(() => { try { localStorage.setItem('dgUposathaRemind', JSON.stringify({ on: true, lead: 24, d8: true, d14: true, d15: false, sound: 'gong', ownChannel: '', ownName: '' })); } catch (e) { /* none */ } });
        const page2 = await ctx2.newPage();
        await page2.clock.setFixedTime(new Date('2026-10-03T07:00:00Z'));   // 12:00 in Almaty, before the evening it begins
        await page2.goto(`http://127.0.0.1:${PORT}/`, { waitUntil: 'load' });
        await page2.waitForTimeout(3500);
        const sched = await page2.evaluate(() => window.__sched2 || []);
        const late = sched.filter((n) => n.title === 'Missed reminder');
        check('a missed reminder is announced as missed, on the silent channel', [late.length > 0, late.every((n) => n.channelId === 'uposatha-none-v1')], [true, true]);
        console.log('       e.g.', JSON.stringify(late.slice(0, 1).map((n) => [n.title, n.body])));
        check('a reminder still ahead keeps its own title and sound', sched.filter((n) => n.title !== 'Missed reminder').every((n) => n.channelId !== 'uposatha-none-v1'), true);
        await ctx2.close();
    } finally {
        await browser.close();
        server.close();
    }
    console.log(`\n${results.filter(Boolean).length}/${results.length} checks passed`);
    process.exit(results.every(Boolean) ? 0 : 1);
})();
