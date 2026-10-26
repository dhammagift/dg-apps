// "Text size" (settings, 70-150 %, localStorage uiScale applied as CSS zoom) in each browser on macOS: the owner saw it
// change nothing in Dhamma.Gift for iPad on a Mac, whose WKWebView is macOS's WebKit - real Safari here is that engine.
// Steps as a reader does them: open a text, open the settings sheet, press + five times, close the sheet, then reload.
// Each step: the root zoom, the first translation line's box, a screenshot. Numbers to read, not a pass/fail.
//
//   node tools/zoom-probe.js <out-dir> [browsers]     browsers: chrome,firefox,webkit,safari (safari: safaridriver on :4444)
const fs = require('fs');
const OUT = process.argv[2] || 'zoom';
const BROWSERS = (process.argv[3] || 'chrome,firefox,webkit,safari').split(',');
const URL = process.env.PROBE_URL || 'https://test.dhamma.gift/sn56.11?lang=ru';
const SIZES = { wide: [1280, 800], narrow: [390, 844] };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
fs.mkdirSync(OUT, { recursive: true });

const MEASURE = `(function () {
  var r = document.documentElement, e = document.querySelector('#sutta article .ru-lang, #sutta article .quote');
  var b = e ? e.getBoundingClientRect() : null, f = document.querySelector('#dg-settings-sheet iframe');
  var fd = f && !f.closest('[hidden]') && f.contentDocument;
  return JSON.stringify({ uiScale: localStorage.getItem('uiScale'), zoom: r.style.zoom || '', sheetZoom: r.dataset.dgSheetZoom,
    line: b ? Math.round(b.width) + 'x' + Math.round(b.height) : null, font: e ? getComputedStyle(e).fontSize : null,
    supportsZoom: !!(window.CSS && CSS.supports('zoom', '1.5')), inner: innerWidth,
    sheet: fd ? { val: (fd.querySelector('#sizeVal') || {}).textContent, zoom: fd.documentElement.style.zoom || '' } : null });
})()`;
const SHEET = (js) => `(function () { var f = document.querySelector('#dg-settings-sheet iframe'), d = f && f.contentDocument; if (!d) return 'no sheet'; ${js} })()`;

// One driver shape for Playwright and WebDriver: goto, js (returns a value), shot, close.
async function playwright(name, w, h) {
  const pw = require('playwright');
  const type = name === 'chrome' ? pw.chromium : pw[name];
  const b = await type.launch(name === 'chrome' ? { channel: 'chrome' } : {});
  const p = await (await b.newContext({ viewport: { width: w, height: h } })).newPage();
  return {
    goto: (u) => p.goto(u, { waitUntil: 'domcontentloaded' }),
    js: (s) => p.evaluate(s),
    shot: (f) => p.screenshot({ path: f }),
    close: () => b.close(),
  };
}
async function safari(w, h) {
  const WD = 'http://127.0.0.1:4444';
  const call = async (method, path, body) => {
    const r = await fetch(WD + path, { method, headers: { 'content-type': 'application/json' }, body: body && JSON.stringify(body) });
    const j = await r.json(); if (j.value && j.value.error) throw new Error(j.value.message); return j.value;
  };
  const s = (await call('POST', '/session', { capabilities: { alwaysMatch: { browserName: 'safari' } } })).sessionId;
  await call('POST', `/session/${s}/window/rect`, { width: w, height: h + 90 }); // + the toolbar
  return {
    goto: (u) => call('POST', `/session/${s}/url`, { url: u }),
    js: (src) => call('POST', `/session/${s}/execute/sync`, { script: 'return ' + src, args: [] }),
    shot: async (f) => fs.writeFileSync(f, Buffer.from(await call('GET', `/session/${s}/screenshot`), 'base64')),
    close: () => call('DELETE', `/session/${s}`),
  };
}

(async () => {
  for (const name of BROWSERS) for (const [size, [w, h]] of Object.entries(SIZES)) {
    const tag = `${name}-${size}`, log = (step, v) => console.log(`${tag.padEnd(16)} ${step.padEnd(14)} ${v}`);
    let d;
    try {
      d = name === 'safari' ? await safari(w, h) : await playwright(name, w, h);
      await d.goto(URL); await d.js(`(localStorage.clear(), 1)`); await d.goto(URL); await sleep(6000);
      log('100%', await d.js(MEASURE)); await d.shot(`${OUT}/${tag}-1-start.png`);
      await d.js(`(window.DgHome.openSettingsSheet(), 1)`); await sleep(4000);
      for (let i = 0; i < 5; i++) { await d.js(SHEET(`d.querySelector('#sizePlus').click(); return 1;`)); await sleep(400); }
      await sleep(1500);
      log('sheet +5', await d.js(MEASURE)); await d.shot(`${OUT}/${tag}-2-sheet.png`);
      await d.js(SHEET(`d.querySelector('#sheetClose').click(); return 1;`)); await sleep(2500);
      log('sheet closed', await d.js(MEASURE)); await d.shot(`${OUT}/${tag}-3-closed.png`);
      await d.goto(URL); await sleep(6000);
      log('reloaded', await d.js(MEASURE)); await d.shot(`${OUT}/${tag}-4-reloaded.png`);
    } catch (e) { log('ERROR', e.message.split('\n')[0]); }
    if (d) await d.close().catch(() => {});
  }
})();
