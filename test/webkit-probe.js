// WebKit probe (.github/workflows/webkit-probe.yml): opens a live page as an iPhone in Playwright's WebKit,
// opens the settings sheet the way the app does, and reports how wide things really are — the page, the
// sheet's iframe, and the document inside it — plus screenshots. Numbers, not a pass/fail: it is for
// seeing what WebKit does with the page zoom (html.style.zoom) and the settings iframe's own zoom.
const { webkit, devices } = require('playwright');
const fs = require('fs');

const URL = process.env.PROBE_URL || 'https://test.dhamma.gift/';
const DEVICE = process.env.PROBE_DEVICE || 'iPhone 15 Pro';
const OUT = 'out';

(async () => {
    fs.mkdirSync(OUT, { recursive: true });
    const browser = await webkit.launch();
    const ctx = await browser.newContext({ ...devices[DEVICE] });
    const page = await ctx.newPage();
    const report = { url: URL, device: DEVICE };
    await page.goto(URL, { waitUntil: 'networkidle' });
    await page.waitForTimeout(1500);
    report.page = await page.evaluate(() => ({
        innerWidth, rootZoom: document.documentElement.style.zoom || '(none)',
        scrollWidth: document.documentElement.scrollWidth, clientWidth: document.documentElement.clientWidth,
        dgApp: document.documentElement.classList.contains('dg-app'),
    }));
    await page.screenshot({ path: OUT + '/1-page.png' });

    await page.evaluate(() => { if (window.DgHome && window.DgHome.openSettingsSheet) window.DgHome.openSettingsSheet(); });
    await page.waitForFunction(() => window.DgHome && window.DgHome.isSettingsSheetOpen && window.DgHome.isSettingsSheetOpen(), null, { timeout: 15000 }).catch(() => {});
    await page.waitForTimeout(2500);
    report.sheet = await page.evaluate(() => {
        const f = [...document.querySelectorAll('iframe')].find(x => /\/settings\//.test(x.src || ''));
        if (!f) return { iframe: false };
        const r = f.getBoundingClientRect();
        let inner = null;
        try {
            const d = f.contentDocument, w = f.contentWindow;
            inner = {
                innerWidth: w.innerWidth, rootZoom: d.documentElement.style.zoom || '(none)',
                dgZoomVar: getComputedStyle(d.documentElement).getPropertyValue('--dg-zoom'),
                scrollWidth: d.documentElement.scrollWidth, clientWidth: d.documentElement.clientWidth,
                bodyScrollWidth: d.body.scrollWidth,
                widest: [...d.querySelectorAll('body *')].map(e => ({ e, w: e.getBoundingClientRect().right }))
                    .sort((a, b) => b.w - a.w).slice(0, 5)
                    .map(x => (x.e.id ? '#' + x.e.id : x.e.tagName.toLowerCase() + '.' + [...x.e.classList].join('.')) + ' right=' + Math.round(x.w)),
            };
        } catch (e) { inner = { error: String(e) }; }
        return { iframe: true, src: f.src, rect: { x: r.x, width: r.width, right: r.right }, inner };
    });
    await page.screenshot({ path: OUT + '/2-settings-sheet.png' });
    // Try zoom values inside the sheet: which one leaves nothing wider than the frame?
    report.trials = [];
    for (const z of ['0.909091', '1', '1.1']) {
        const t = await page.evaluate((z) => {
            const f = [...document.querySelectorAll('iframe')].find(x => /\/settings\//.test(x.src || ''));
            if (!f) return null;
            const d = f.contentDocument, w = f.contentWindow;
            d.documentElement.style.zoom = z;
            d.documentElement.style.setProperty('--dg-zoom', z);
            void d.body.offsetWidth;
            const frameW = f.getBoundingClientRect().width;
            return { zoom: z, frameInnerWidth: w.innerWidth, frameRectWidth: frameW,
                     bodyScrollWidth: d.body.scrollWidth, docScrollWidth: d.documentElement.scrollWidth,
                     overflowX: d.documentElement.scrollWidth > d.documentElement.clientWidth + 1 };
        }, z);
        await page.waitForTimeout(400);
        await page.screenshot({ path: OUT + '/3-zoom-' + z + '.png' });
        report.trials.push(t);
    }
    fs.writeFileSync(OUT + '/report.json', JSON.stringify(report, null, 2));
    console.log(JSON.stringify(report, null, 2));
    await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
