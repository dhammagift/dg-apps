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

// [path, stored Pali toggle ('pli-2nd' both, '2nd' translation only), translation lang expected, has mp3s on test] - as in
// reader-smoke.js. Under every text the Principles line; the mp3 line comes after the text from the site's /api/text-online (dg-node dgTextOnline).
const CASES = [
  ['/sn56.11?lang=ru', 'pli-2nd', 'ru', true],
  ['/sn56.11?lang=ru', '2nd', 'ru', true],
  ['/mn10?lang=en', '2nd', 'en', true],
  ['/an1.1-10?lang=ru', 'pli-2nd', 'ru', true],
  ['/pli-tv-bu-vb-pj1?lang=ru', 'pli-2nd', null, true],
  ['/pli-tv-bu-vb-sk63?lang=ru', 'pli-2nd', 'en', true],
  ['/pli-tv-bu-vb-sk63?lang=ru', '2nd', 'en', true],
  ['/pli-tv-kd1?lang=en', '2nd', 'en', false],
  // Thai is not in the app's ru+en library: the text comes from the site, its popover lists th (dg-node: ?lang= went to the slice)
  ['/sn56.11?lang=th', 'pli-2nd', 'th', true],
];

const CHECK = `(function (toggle, lang, audio) {
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
  if (!sutta.querySelector('.dg-principles a')) errs.push('no Principles line');
  if (lang && !((window.READER_MODE || {}).availableLangs || []).includes(lang)) errs.push('the popover has no ' + lang + ' (availableLangs ' + (window.READER_MODE || {}).availableLangs + ')');
  if (audio !== !!sutta.querySelector('.dg-audio-mp3 a[href$=".mp3"]')) errs.push(audio ? 'no mp3 line' : 'an mp3 line');
  return JSON.stringify({ errs: errs, pli: pli.length, trn: trn.length, langs: Array.from(new Set(trn.map(function (e) { return (e.className.match(/(\\w+)-lang/) || [])[1]; }))) });
})`;

let finished = false;
process.on('exit', (code) => { if (!finished && !code) { console.log('FAIL the script stopped before its end'); process.exitCode = 1; } });

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
  // A call the WebView never answers (Input.dispatchKeyEvent did, run 90) is a FAIL, not a silent exit 0 of an empty event loop.
  const send = (method, params) => new Promise((r) => {
    const i = ++id; waiting[i] = r; ws.send(JSON.stringify({ id: i, method, params }));
    setTimeout(() => { if (waiting[i]) { console.log(`FAIL DevTools ${method} got no answer in 30 s`); process.exit(1); } }, 30000);
  });
  const ev = (expression) => send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true })
    .then((d) => (d.result && d.result.result ? d.result.result.value : null));
  const waitFor = async (expr, ms) => { for (let i = 0; i < ms / 500; i++) { if (await ev(expr)) return true; await sleep(500); } return false; };
  const open = async (path, toggle) => {
    await ev(`localStorage.setItem('paliToggle', ${JSON.stringify(toggle)}); localStorage.removeItem('tts_preferred_mode'); location.assign(${JSON.stringify(path)})`);
    await sleep(3000);
    return waitFor(`!!document.querySelector('#sutta article .quote')`, 25000);
  };

  // Home -> Materials -> Principles / Rationale, three real taps each from the first one after the start: the site's page in a
  // Custom Tab (another app on top), never the search in the app (owner 2026-10-27: once the search, once the page). Back returns.
  const top = () => (execSync('adb shell dumpsys activity activities').toString()
    .match(/(?:topResumedActivity=|mResumedActivity: )ActivityRecord\{\S+ \S+ ([^\/\s]+)\//) || [])[1];
  for (const doc of ['principles', 'rationale']) for (let i = 1; i <= 3; i++) {
    const name = `materials -> ${doc}, tap ${i}`;
    if (top() !== 'gift.dhamma.mobile') { execSync('adb shell input keyevent 4'); await sleep(2500); }
    if (!(await waitFor(`!!document.querySelector('.dg-tile[data-tile="materials"]')`, 15000))) { await ev(`location.assign('/')`); await sleep(4000); }
    await ev(`document.querySelector('.dg-tile[data-tile="materials"]').click()`); await sleep(1500);
    // Edge to edge (API 35+): the WebView starts at the screen's top left, so CSS px * devicePixelRatio is the tap point.
    const at = await ev(`(async function () { var a = document.querySelector('a.dg-sheet-row[href="/docs/${doc}"]'); if (!a) return null;
      a.scrollIntoView({ block: 'center' }); await new Promise(function (r) { setTimeout(r, 600); });
      var b = a.getBoundingClientRect(); return Math.round((b.left + b.width / 2) * devicePixelRatio) + ' ' + Math.round((b.top + b.height / 2) * devicePixelRatio); })()`);
    if (!at) { shot(`docs-${doc}-${i}-norow`); check(false, `${name}: no /docs/${doc} row in the sheet`); continue; }
    execSync(`adb shell input tap ${at}`); await sleep(3500);
    const app = top(), page = app === 'gift.dhamma.mobile' ? await ev(`location.pathname + location.search`) : '';
    shot(`docs-${doc}-${i}`);
    check(app && app !== 'gift.dhamma.mobile', `${name}: on top ${app}${page ? ', the app shows ' + page : ''}`);
    execSync('adb shell input keyevent 4'); await sleep(2500);
    check(top() === 'gift.dhamma.mobile', `${name}: Back returns to the app (${top()})`);
  }

  // A language switch on the home page (dhamma-i18n dispatches dhamma:languagechange, also at every start): the bridge's listener
  // read SHORTCUTS_MAX from another function scope and threw a ReferenceError each time (99af3d2).
  await ev(`location.assign('/')`); await sleep(4000);
  for (const lang of ['ru', 'en']) {
    const errs = JSON.parse(await ev(`(async function () { var errs = [], on = function (e) { errs.push(e.message); };
      window.addEventListener('error', on);
      try { await window.setSiteLanguage(${JSON.stringify(lang)}); } catch (e) { errs.push(String(e)); }
      await new Promise(function (r) { setTimeout(r, 500); }); window.removeEventListener('error', on);
      return JSON.stringify(errs.concat(document.documentElement.lang === ${JSON.stringify(lang)} ? [] : ['html lang ' + document.documentElement.lang])); })()`));
    shot(`home-lang-${lang}`);
    check(!errs.length, `home: switched to ${lang}${errs.length ? ' - errors: ' + errs.join('; ') : ', no error'}`);
  }

  for (const [n, [path, toggle, lang, audio]] of CASES.entries()) {
    const name = `${path} pali=${toggle}`;
    if (!(await open(path, toggle))) { shot(`${n + 1}-noload`); check(false, `${name}: the text did not load`); continue; }
    await sleep(1500);
    const r = JSON.parse(await ev(`${CHECK}(${JSON.stringify(toggle)}, ${JSON.stringify(lang)}, ${audio})`));
    shot(`${n + 1}-${path.replace(/\W+/g, '-').replace(/^-|-$/g, '')}-${toggle}`);
    // the lines under the text, a second screenshot
    // (again until it stays in view: the page still grows under a long text, run 90 shot blank screens)
    await ev(`(async function () { var e = document.querySelector('#sutta .dg-principles'); if (!e) return;
      for (var i = 0; i < 20; i++) { e.scrollIntoView({ block: 'center' }); await new Promise(function (r) { setTimeout(r, 400); });
        var b = e.getBoundingClientRect(); if (b.top >= 0 && b.bottom <= innerHeight + 2) return; } })()`); await sleep(1000);
    shot(`${n + 1}-${path.replace(/\W+/g, '-').replace(/^-|-$/g, '')}-${toggle}-end`);
    check(!r.errs.length, `${name}: Pali lines ${r.pli}, translation lines ${r.trn} (${r.langs.join(',') || 'none'})${r.errs.length ? ' - ' + r.errs.join('; ') : ''}`);
  }

  // Settings: no Thai interface in the apps (owner 2026-10-26), Thai texts stay.
  await ev(`location.assign('/settings/index.html')`); await sleep(4000);
  const th = await ev(`document.querySelector('#uiLang') ? Array.from(document.querySelectorAll('#uiLang option')).map(function (o) { return o.value; }).join(',') : null`);
  shot('settings-ui-lang');
  check(th === 'en,ru', `settings: the interface languages are ${th}, want en,ru`);

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
    // The page's own key event: the WebView leaves CDP's Input.dispatchKeyEvent unanswered (run 90). settings.js reads altKey and code only.
    await ev(`document.dispatchEvent(new KeyboardEvent('keydown', { key: 'r', code: 'KeyR', altKey: true, bubbles: true }))`);
    await sleep(2500);
    const a = await mode(); shot('11-voice-alt-r');
    check(a === 'trn', `voice: Alt+R after the speaker plays ${a}, want trn`);
    await stop();
  } else check(false, 'voice: sn56.11 or its title speaker did not load');

  ws.close();
  finished = true;
  console.log(failed ? 'RESULT FAIL' : 'RESULT PASS');
  process.exit(failed ? 1 : 0);
})();
