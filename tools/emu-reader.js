// The reader fixes of dg-node 8309381 / e8cef22 / 0d1bd23 in the app's own WebView (the cases of dg-node's test/reader-smoke.js,
// which runs them on the site): translation only no longer sits 2em right, a Vinaya text with no ru shows the English, Vinaya ids
// keep the reader's state alone, and Voice / Alt+R start in the translation after a tap on the title's Pali speaker.
// A screenshot per case. Debug APK only (DevTools socket on tcp:9222).
//
//   node tools/emu-reader.js <out-dir>
const fs = require('fs');
const { execSync } = require('child_process');
const OUT = process.argv[2] || 'shots';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failed = false;
const check = (ok, text) => { console.log((ok ? 'PASS ' : 'FAIL ') + text); if (!ok) failed = true; };
const shot = (name) => fs.writeFileSync(`${OUT}/reader-${name}.png`, execSync('adb exec-out screencap -p', { maxBuffer: 64 << 20 }));

// [path, stored Pali toggle ('pli-2nd' both, '2nd' translation only), translation lang expected] - as in reader-smoke.js
const CASES = [
  ['/sn56.11?lang=ru', 'pli-2nd', 'ru'],
  ['/sn56.11?lang=ru', '2nd', 'ru'],
  ['/mn10?lang=en', '2nd', 'en'],
  ['/an1.1-10?lang=ru', 'pli-2nd', 'ru'],
  ['/pli-tv-bu-vb-pj1?lang=ru', 'pli-2nd', null],
  ['/pli-tv-bu-vb-sk63?lang=ru', 'pli-2nd', 'en'],
  ['/pli-tv-bu-vb-sk63?lang=ru', '2nd', 'en'],
  ['/pli-tv-kd1?lang=en', '2nd', 'en'],
];

const CHECK = `(function (toggle, lang) {
  var errs = [];
  var states = Array.from(document.body.classList).filter(function (c) { return /^dg-state-/.test(c); });
  if (states.join() !== 'dg-state-reader') errs.push('body states: ' + states.join(' '));
  var sutta = document.getElementById('sutta');
  var shown = function (sel) { return Array.from(sutta.querySelectorAll(sel)).filter(function (e) { return e.offsetParent && e.textContent.trim(); }); };
  var pli = shown('article p .pli-lang.quote'), trn = shown('article p .quote:not(.pli-lang)');
  if (toggle === '2nd' && pli.length) errs.push('Pali hidden but ' + pli.length + ' Pali lines shown');
  if (toggle !== '2nd' && !pli.length) errs.push('no Pali shown');
  if (lang && !trn.some(function (e) { return e.classList.contains(lang + '-lang'); })) errs.push('no ' + lang + ' translation shown');
  if (!pli.length && !trn.length) errs.push('blank text');
  var first = trn[0] || pli[0], p = first && first.closest('p');
  if (p) {
    var dx = first.getBoundingClientRect().left - p.getBoundingClientRect().left - parseFloat(getComputedStyle(p).paddingLeft);
    if (Math.abs(dx) > 10) errs.push('text shifted ' + Math.round(dx) + 'px in its paragraph');
    var art = sutta.querySelector('article').getBoundingClientRect().left;
    if (first.getBoundingClientRect().left - art > 10) errs.push('text ' + Math.round(first.getBoundingClientRect().left - art) + 'px right of the article');
  }
  if (document.documentElement.scrollWidth > innerWidth + 1) errs.push('horizontal scroll');
  return JSON.stringify({ errs: errs, pli: pli.length, trn: trn.length, langs: Array.from(new Set(trn.map(function (e) { return (e.className.match(/(\\w+)-lang/) || [])[1]; }))) });
})`;

(async () => {
  let t;
  for (let i = 0; i < 20 && !t; i++) {
    try { t = (await (await fetch('http://127.0.0.1:9222/json')).json()).find((x) => x.type === 'page'); } catch (e) { /* not up yet */ }
    if (!t) await sleep(1500);
  }
  if (!t) { console.log('FAIL no page target on the DevTools socket'); process.exit(1); }
  console.log('page: ' + t.url);
  const ws = new WebSocket(t.webSocketDebuggerUrl);
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  let id = 0; const waiting = {};
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && waiting[d.id]) { waiting[d.id](d); delete waiting[d.id]; } };
  const send = (method, params) => new Promise((r) => { const i = ++id; waiting[i] = r; ws.send(JSON.stringify({ id: i, method, params })); });
  const ev = (expression) => send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true })
    .then((d) => (d.result && d.result.result ? d.result.result.value : null));
  const waitFor = async (expr, ms) => { for (let i = 0; i < ms / 500; i++) { if (await ev(expr)) return true; await sleep(500); } return false; };
  const open = async (path, toggle) => {
    await ev(`localStorage.setItem('paliToggle', ${JSON.stringify(toggle)}); localStorage.removeItem('tts_preferred_mode'); location.assign(${JSON.stringify(path)})`);
    await sleep(3000);
    return waitFor(`!!document.querySelector('#sutta article .quote')`, 25000);
  };

  for (const [n, [path, toggle, lang]] of CASES.entries()) {
    const name = `${path} pali=${toggle}`;
    if (!(await open(path, toggle))) { shot(`${n + 1}-noload`); check(false, `${name}: the text did not load`); continue; }
    await sleep(1500);
    const r = JSON.parse(await ev(`${CHECK}(${JSON.stringify(toggle)}, ${JSON.stringify(lang)})`));
    shot(`${n + 1}-${path.replace(/\W+/g, '-').replace(/^-|-$/g, '')}-${toggle}`);
    check(!r.errs.length, `${name}: Pali lines ${r.pli}, translation lines ${r.trn} (${r.langs.join(',') || 'none'})${r.errs.length ? ' - ' + r.errs.join('; ') : ''}`);
  }

  // Voice: the title's Pali speaker plays Pali but is not saved as the mode; Voice and Alt+R then start in the translation.
  if (await open('/sn56.11?lang=ru', 'pli-2nd') && await waitFor(`!!document.querySelector('.pli-lang .title-play-btn')`, 15000)) {
    const mode = () => ev(`typeof ttsState !== 'undefined' && ttsState.speaking ? ttsState.langSettings : null`);
    const stop = () => ev(`(document.querySelector('.close-tts-btn') || {click: function () {}}).click()`);
    await ev(`document.querySelector('.pli-lang .title-play-btn').click()`);
    const spoke = await waitFor(`typeof ttsState !== 'undefined' && ttsState.speaking`, 15000);
    shot('9-voice-title-speaker');
    check(spoke, `voice: the title's Pali speaker starts (${spoke ? await mode() : 'not speaking'})`);
    check((await ev(`localStorage.getItem('tts_preferred_mode')`)) !== 'pi', `voice: the speaker did not save Pali as the mode (tts_preferred_mode=${await ev(`localStorage.getItem('tts_preferred_mode')`)})`);
    await stop(); await sleep(1500);
    await ev(`document.querySelector('.voice-link').click()`); await sleep(2500);
    const v = await mode(); shot('10-voice-link');
    check(v === 'trn', `voice: Voice after the speaker plays ${v}, want trn`);
    await stop(); await sleep(1500);
    for (const type of ['keyDown', 'keyUp']) await send('Input.dispatchKeyEvent', { type, modifiers: 1, key: 'r', code: 'KeyR', windowsVirtualKeyCode: 82 });
    await sleep(2500);
    const a = await mode(); shot('11-voice-alt-r');
    check(a === 'trn', `voice: Alt+R after the speaker plays ${a}, want trn`);
    await stop();
  } else check(false, 'voice: sn56.11 or its title speaker did not load');

  ws.close();
  console.log(failed ? 'RESULT FAIL' : 'RESULT PASS');
  process.exit(failed ? 1 : 0);
})();
