// The reader as a person uses it, clicked through in a browser on the live site (default https://test.dhamma.gift) over a
// matrix: phone and desktop, light and dark, lines and columns, one / two / four Pali editions. Every check here was a bug
// someone found by hand first (owner 2026-11-01: «что ещё вы не проверяете?»):
//  - the contents open under their button, never over the search field, and fit the screen
//  - a text without headings still lists its points (start, 25/50/75 %, the end) - off-screen lines were dropped
//  - a tapped line is visibly highlighted (a drawn box with the highlight colour), also in the columns with editions
//  - "External links" opens its menu with links, and its button never animates its colours in
//  - the toolbar is drawn whole (no lone button while the page is still parsed)
// Usage: node test/reader-ui.js [origin]
const { chromium, devices } = require('/usr/lib/node_modules/@playwright/cli/node_modules/playwright');
const ORIGIN = process.argv[2] || 'https://test.dhamma.gift';
let fails = 0;
const check = (ok, what) => { if (!ok) fails++; console.log(`${ok ? 'PASS' : 'FAIL'} ${what}`); };

async function open(ctx, path, mode) {
  const p = await ctx.newPage();
  await p.goto(ORIGIN + '/', { waitUntil: 'domcontentloaded' });
  await p.evaluate((m) => { localStorage.setItem('viewMode', m); localStorage.setItem('dg.app.downloadDeclined', '1'); }, mode);
  await p.goto(ORIGIN + path, { waitUntil: 'networkidle' });
  await p.waitForSelector('#sutta article .quote, #sutta span[id]', { timeout: 30000 });
  await p.waitForTimeout(1500);
  return p;
}

(async () => {
  const b = await chromium.launch();
  for (const dev of ['Pixel 7', 'Desktop Chrome']) for (const scheme of ['light', 'dark']) {
    const ctx = await b.newContext({ ...devices[dev], colorScheme: scheme });
    const tag = `${dev === 'Pixel 7' ? 'phone' : 'desktop'} ${scheme}`;

    // contents: under the button, inside the screen, with points for a text without headings
    for (const [path, min] of [['/mn56?lang=en', 5], ['/sn56.11?lang=en', 3], ['/dn2?lang=en', 30]]) {
      const p = await open(ctx, path, 'lines');
      await p.click('#smart-toc-btn'); await p.waitForTimeout(600);
      const r = await p.evaluate(() => {
        const b = document.getElementById('smart-toc-btn').getBoundingClientRect(), t = document.getElementById('smart-toc-panel').getBoundingClientRect();
        return { below: t.top >= b.bottom - 1, inside: t.left >= 0 && t.right <= innerWidth + 1, items: document.querySelectorAll('#smart-toc-panel .toc-item').length };
      });
      check(r.below && r.inside, `${tag} ${path}: the contents open under their button, inside the screen (${JSON.stringify(r)})`);
      check(r.items >= min, `${tag} ${path}: the contents list ${r.items} points, want ${min}+`);
      await p.close();
    }

    // a tapped line is highlighted, visibly, in every layout
    for (const eds of ['', 'ms,bjt', 'ms,bjt,my,th']) for (const mode of ['lines', 'columns']) {
      const p = await open(ctx, `/dn17?lang=en${eds ? '&editions=' + eds : ''}`, mode);
      await p.evaluate(() => {
        const s = [...document.querySelectorAll('#sutta .dg-ed-line, #sutta .pli-lang')].filter((e) => e.textContent.trim().length > 40 && e.getBoundingClientRect().height)[8];
        s.setAttribute('data-tap', '1'); s.scrollIntoView({ block: 'center' });
      });
      await p.waitForTimeout(400);
      await p.click('[data-tap]', { position: { x: 15, y: 10 } }); await p.waitForTimeout(700);   // a real tap at the line's start (the page's zoom included)
      const h = await p.evaluate(() => {
        const a = document.querySelector('#sutta .active-word'); if (!a) return { none: true };
        const shown = getComputedStyle(a).display === 'contents' ? [...a.children] : [a];
        const drawn = shown.filter((e) => { const r = e.getBoundingClientRect(), bg = getComputedStyle(e).backgroundColor; return r.width > 20 && r.height > 10 && !/rgba\(0, 0, 0, 0\)|transparent/.test(bg); });
        return { drawn: drawn.length };
      });
      check(h.drawn > 0, `${tag} ${mode} editions ${eds || 'none'}: the tapped line is highlighted (${JSON.stringify(h)})`);
      await p.close();
    }

    // External links: no colour easing, and the menu opens with links
    {
      const p = await open(ctx, '/mn56?lang=en', 'lines');
      const tr = await p.evaluate(() => getComputedStyle(document.querySelector('.dg-external-links-toggle')).transitionProperty);
      check(!/color|all/.test(tr), `${tag}: External links does not ease its colours in (transition: ${tr})`);
      await p.click('.dg-external-links-toggle'); await p.waitForTimeout(500);
      const n = await p.evaluate(() => [...document.querySelectorAll('.dg-external-links-menu a')].filter((a) => a.getBoundingClientRect().height).length);
      check(n >= 3, `${tag}: External links opens ${n} links`);
      await p.close();
    }
    await ctx.close();
  }

  // the offline-voice card has its colours on every page that plays (memo has no home.css: it was a bare line of text)
  for (const scheme of ['light', 'dark']) {
    const ctx = await b.newContext({ ...devices['Pixel 7'], colorScheme: scheme }); const p = await ctx.newPage();
    for (const path of ['/memo/?q=sn35.243']) {   // (the reader loads voice.css only with the voice)
      await p.goto(ORIGIN + path, { waitUntil: 'networkidle' }); await p.waitForTimeout(1500);
      const bg = await p.evaluate(() => { document.body.insertAdjacentHTML('beforeend', '<div class="tts-card on" id="__card">x</div>');
        return getComputedStyle(document.getElementById('__card')).backgroundColor; });
      check(!/rgba\(0, 0, 0, 0\)|transparent/.test(bg), `${scheme} ${path}: the offline-voice card has a background (${bg})`);
    }
    await ctx.close();
  }

  // the toolbar is never shown half-parsed (a slow phone: CPU x6), sampled on every frame
  {
    const ctx = await b.newContext({ ...devices['Pixel 7'] }); const p = await ctx.newPage();
    const cdp = await ctx.newCDPSession(p); await cdp.send('Emulation.setCPUThrottlingRate', { rate: 6 });
    await p.addInitScript(() => {
      window.__half = 0;
      const tick = () => { const t = document.getElementById('reader-toolbar');
        if (t && !t.querySelector('#smart-toc-btn') && getComputedStyle(t).visibility !== 'hidden' && t.getBoundingClientRect().height) window.__half++;
        if (!document.getElementById('smart-toc-btn')) requestAnimationFrame(tick); };
      requestAnimationFrame(tick);
    });
    let half = 0;
    for (let i = 0; i < 3; i++) { await p.goto(ORIGIN + '/dn2?lang=en&n=' + i, { waitUntil: 'load' }); half += await p.evaluate(() => window.__half); }
    check(half === 0, `the reader toolbar is never drawn half-parsed (${half} frames in 3 loads)`);
    await ctx.close();
  }
  await b.close();
  console.log(fails ? `reader-ui: ${fails} FAILED` : 'reader-ui: all checks passed');
  process.exit(fails ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
