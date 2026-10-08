// The Pāli letters row (src/pali-bar.js) on the live dictionary page, in a phone-sized browser: it shows up with the field's focus,
// sits on the keyboard whichever way the keyboard is made known, inserts at the caret, pastes only on tap, and the menu flag turns it off.
//   PLAYWRIGHT_CORE=... node dict/test/probe-pali.js [site=https://dict.dhamma.gift] [outdir=/tmp/dict-pali]
const fs = require('fs');
const path = require('path');
const { chromium, devices } = require(process.env.PLAYWRIGHT_CORE || 'playwright-core');
const SITE = process.argv[2] || 'https://dict.dhamma.gift';
const OUT = process.argv[3] || '/tmp/dict-pali';
const BAR = fs.readFileSync(path.join(__dirname, '..', 'src', 'pali-bar.js'), 'utf8');
fs.mkdirSync(OUT, { recursive: true });
let failed = 0;
const check = (l, ok, d) => { if (!ok) failed++; console.log((ok ? 'ok   ' : 'FAIL ') + l + (ok ? '' : '  ' + d)); };

(async () => {
  const browser = await chromium.launch();
  for (const dark of [false, true]) {
    const ctx = await browser.newContext({ ...devices['Pixel 7'], colorScheme: dark ? 'dark' : 'light', permissions: ['clipboard-read', 'clipboard-write'] });
    const page = await ctx.newPage();
    await page.goto(SITE + '/ru/', { waitUntil: 'load' });
    await page.waitForTimeout(3500);
    if (dark) await page.evaluate(() => document.body.classList.add('dark-mode'));
    await page.evaluate(BAR);
    const tag = dark ? 'dark' : 'light';
    const input = page.locator('input[type=search], input[type=text]').first();
    await page.evaluate(() => document.activeElement && document.activeElement.blur());
    await page.waitForTimeout(300);
    await input.click();
    await input.fill('');
    await page.waitForTimeout(300);
    const st = () => page.evaluate(() => { const b = document.getElementById('dg-pali'); if (!b) return null; const r = b.getBoundingClientRect(); const cs = getComputedStyle(b); return { shown: b.classList.contains('on'), bottomGap: Math.round(innerHeight - r.bottom), buttons: [...b.querySelectorAll('button')].map((x) => x.textContent) }; });
    let s = await st();
    check(`${tag}: row shows with the field's focus`, s && s.shown, JSON.stringify(s));
    check(`${tag}: all Pāli letters are there`, s && ['ā', 'ī', 'ū', 'ṁ', 'ṅ', 'ñ', 'ṭ', 'ḍ', 'ṇ', 'ḷ'].every((c) => s.buttons.includes(c)), JSON.stringify(s && s.buttons));
    check(`${tag}: no keyboard known: sits at the bottom`, s && s.bottomGap === 0, 'gap ' + (s && s.bottomGap));
    await page.evaluate(() => window.__dgIme(300));        // overlay keyboard: the page is not resized
    s = await st();
    const z = await page.evaluate(() => parseFloat(document.documentElement.style.zoom) || 1);
    check(`${tag}: overlay keyboard 300px: lifted by it`, s && Math.abs(s.bottomGap - 300) < 3, 'gap ' + (s && s.bottomGap) + ' zoom ' + z);
    await page.locator('#dg-pali button', { hasText: 'ā' }).first().click();
    await page.locator('#dg-pali button', { hasText: 'ṁ' }).first().click();
    const v = await input.inputValue();
    check(`${tag}: taps insert at the caret`, v === 'āṁ', JSON.stringify(v));
    await page.evaluate(() => navigator.clipboard.writeText('dukkha'));
    await page.locator('#dg-pali .paste').click();
    await page.waitForTimeout(300);
    check(`${tag}: Paste inserts the clipboard on tap`, (await input.inputValue()) === 'āṁdukkha', await input.inputValue());
    await page.locator('#dg-pali .more').click();
    s = await st();
    check(`${tag}: "…" opens the second row`, s && s.buttons.includes('ś') && s.buttons.includes('ṃ'), JSON.stringify(s && s.buttons));
    await page.screenshot({ path: path.join(OUT, `bar-${tag}.png`) });
    await page.evaluate(() => window.__dgIme(0));
    s = await st();
    check(`${tag}: the keyboard goes down: the row goes with it`, s && !s.shown, JSON.stringify(s));
    await page.evaluate(() => window.__dgIme(300));
    s = await st();
    check(`${tag}: the keyboard comes back over the focused field: the row returns`, s && s.shown, JSON.stringify(s));
    check(`${tag}: Paste is an icon, not an emoji`, await page.evaluate(() => !!document.querySelector('#dg-pali .paste svg path') && !document.querySelector('#dg-pali .paste').textContent.trim()), '');
    await page.evaluate(() => { localStorage.setItem('dgPaliBar', 'off'); window.dispatchEvent(new Event('dg:pali-bar')); });
    s = await st();
    check(`${tag}: the menu switch hides it`, s && !s.shown, JSON.stringify(s));
    await ctx.close();
  }
  // In the app (Capacitor): nothing is drawn until the keyboard reports, then the row slides in; it goes with the keyboard.
  {
    const ctx = await browser.newContext({ ...devices['Pixel 7'] });
    await ctx.addInitScript(() => { window.Capacitor = { isNativePlatform: () => true, getPlatform: () => 'android', Plugins: {} }; });
    const page = await ctx.newPage();
    await page.goto(SITE + '/', { waitUntil: 'load' });
    await page.waitForTimeout(3500);
    await page.evaluate(BAR);
    await page.evaluate(() => document.activeElement && document.activeElement.blur());
    await page.locator('input[type=search], input[type=text]').first().click();
    await page.waitForTimeout(400);
    const on = () => page.evaluate(() => { const b = document.getElementById('dg-pali'); return !!b && b.classList.contains('on'); });
    const visible = () => page.evaluate(() => { const b = document.getElementById('dg-pali'); return !!b && getComputedStyle(b).opacity !== '0'; });
    check('app: no row before the keyboard has reported (no flash at the bottom)', !(await on()) && !(await visible()), 'on ' + (await on()));
    await page.evaluate(() => window.__dgIme(300));
    await page.waitForTimeout(500);
    check('app: the row slides in once the keyboard is up', await on() && await visible(), '');
    await page.evaluate(() => window.__dgIme(0));
    await page.waitForTimeout(500);
    check('app: the row goes with the keyboard', !(await on()), '');
    await page.evaluate(() => window.__dgIme(300));
    await page.waitForTimeout(500);
    check('app: and comes back with it', await on(), '');
    await ctx.close();
  }
  await browser.close();
  console.log(failed ? `\n${failed} checks failed` : '\nall checks passed; screenshots in ' + OUT);
  process.exit(failed ? 1 : 0);
})();
