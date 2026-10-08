// Edge-to-edge check for the Dictionary app without a phone: the live page, a simulated inset (Capacitor SystemBars' vars), and
// the real src/dict-edge.js. It lists anything visible that starts above the status strip, checks that the sticky header keeps
// clear of it while scrolling, that the strip has the page's colour, and that the bottom sheet / toast / page end clear the gesture
// bar. Light and dark, English and Russian, 0 / 24 / 48 px.
//
//   node dict/test/probe-edge.js [site=https://dict.dhamma.gift] [outdir=/tmp/dict-edge]
const fs = require('fs');
const path = require('path');
const { chromium, devices } = require(process.env.PLAYWRIGHT_CORE || 'playwright-core');

const SITE = process.argv[2] || 'https://dict.dhamma.gift';
const OUT = process.argv[3] || '/tmp/dict-edge';
const EDGE = fs.readFileSync(path.join(__dirname, '..', 'src', 'dict-edge.js'), 'utf8');
fs.mkdirSync(OUT, { recursive: true });

let failed = 0;
function check(label, ok, detail) {
  if (!ok) failed++;
  console.log((ok ? 'ok   ' : 'FAIL ') + label + (ok ? '' : '  ' + detail));
}

(async () => {
  const browser = await chromium.launch();
  for (const inset of [0, 24, 48]) {
    for (const dark of [false, true]) {
      for (const lang of ['en', 'ru']) {
        const tag = `${lang}/${dark ? 'dark' : 'light'}/${inset}px`;
        const ctx = await browser.newContext({ ...devices['Pixel 7'], colorScheme: dark ? 'dark' : 'light' });
        const page = await ctx.newPage();
        await page.goto(SITE + '/' + (lang === 'ru' ? 'ru/' : '') + 'kacchapa', { waitUntil: 'load' });
        await page.waitForTimeout(3500);
        if (dark) await page.evaluate(() => document.body.classList.add('dark-mode'));
        await page.addStyleTag({ content: `:root{--safe-area-inset-top:${inset}px;--safe-area-inset-bottom:${inset}px}` });
        await page.evaluate(EDGE);
        await page.waitForTimeout(500);

        const top = await page.evaluate(() => {
          const sat = document.getElementById('dg-edge-strip').getBoundingClientRect().height;
          const bad = [];
          document.querySelectorAll('body *').forEach((e) => {
            if (e.id === 'dg-edge-strip' || e.closest('#dg-edge-strip') || e.children.length) return;
            const cs = getComputedStyle(e);
            if (cs.visibility === 'hidden' || cs.display === 'none' || +cs.opacity === 0) return;
            const r = e.getBoundingClientRect();
            if (r.width < 1 || r.height < 2) return;   // 1px spacers are not content
            if (r.top < sat - 0.5 && r.bottom > 0.5) bad.push((e.tagName + '#' + e.id + '.' + (typeof e.className === 'string' ? e.className : '')).slice(0, 50) + ' top=' + Math.round(r.top));
          });
          const tbar = document.querySelector('.tbar');
          const strip = document.getElementById('dg-edge-strip');
          return {
            sat, bad: bad.slice(0, 5),
            tbarTop: tbar ? Math.round(tbar.getBoundingClientRect().top) : null,
            stripBg: getComputedStyle(strip).backgroundColor, tbarBg: tbar ? getComputedStyle(tbar).backgroundColor : null,
            cover: /viewport-fit=cover/.test(document.querySelector('meta[name=viewport]').content),
          };
        });
        check(`${tag}: viewport-fit=cover`, top.cover, '');
        check(`${tag}: strip is ${inset}px`, Math.round(top.sat) === inset, 'got ' + top.sat);
        check(`${tag}: nothing visible starts above the strip`, top.bad.length === 0, top.bad.join(' | '));
        check(`${tag}: header below the strip`, top.tbarTop >= inset - 1, 'tbar top ' + top.tbarTop);
        check(`${tag}: strip has the page colour`, top.stripBg === top.tbarBg, top.stripBg + ' vs ' + top.tbarBg);

        // scrolled: the sticky header keeps clear of the strip
        await page.evaluate(() => window.scrollTo(0, 700));
        await page.waitForTimeout(500);
        const stuck = await page.evaluate(() => { const t = document.querySelector('.tbar'); const r = t.getBoundingClientRect(); return { top: Math.round(r.top), hidden: document.body.classList.contains('tbar-hide') }; });
        check(`${tag}: header sticks at the strip (or slid away)`, stuck.hidden || stuck.top >= inset - 1, 'top ' + stuck.top);
        await page.evaluate(() => window.scrollTo(0, 0));

        // the bottom: the settings sheet's last line and the toast clear the gesture bar
        await page.evaluate(() => window.dgToggleMenu && window.dgToggleMenu());
        await page.waitForTimeout(900);
        const sheet = await page.evaluate(() => {
          const pb = document.querySelector('#p-menu .pb');
          const cs = pb ? getComputedStyle(pb) : null;
          return { pad: cs ? (parseFloat(cs.paddingBottom) - 26) * (parseFloat(getComputedStyle(document.documentElement).zoom) || 1) : -1, sheetTop: Math.round(document.getElementById('p-menu').getBoundingClientRect().top) };
        });
        check(`${tag}: settings sheet bottom padding grows by the inset`, Math.abs(sheet.pad - inset) < 1.5, 'got ' + sheet.pad);
        check(`${tag}: settings sheet starts below the strip`, sheet.sheetTop >= inset, 'top ' + sheet.sheetTop);
        if (inset === 24 && !dark && lang === 'en') await page.screenshot({ path: path.join(OUT, `menu-${lang}-light-${inset}.png`) });
        await page.evaluate(() => window.dgToggleMenu && window.dgToggleMenu());
        if (!(inset === 0)) await page.screenshot({ path: path.join(OUT, `page-${lang}-${dark ? 'dark' : 'light'}-${inset}.png`) });
        await ctx.close();
      }
    }
  }
  await browser.close();
  console.log(failed ? `\n${failed} checks failed` : '\nall checks passed; screenshots in ' + OUT);
  process.exit(failed ? 1 : 0);
})();
