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
  // The WebView's own place on the screen (below the status bar here: run 92 tapped one bar's height too high).
  execSync('adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true');
  const wv = (execSync('adb shell cat /sdcard/ui.xml').toString().match(/class="android\.webkit\.WebView"[^>]*bounds="\[(\d+),(\d+)\]/) || [0, 0, 0]).slice(1).map(Number);
  console.log(`the WebView starts at ${wv.join(',')}`);
  // Chrome without its first-run screens (a debug app's command line), so the Custom Tab shows the page itself, and the page read
  // over Chrome's own DevTools socket: its address and title, so a 404 or a wrong page is a FAIL, not "Chrome is on top" (owner).
  execSync('adb shell am set-debug-app --persistent com.android.chrome');
  execSync(`adb shell "echo '_ --disable-fre --no-default-browser-check --no-first-run' > /data/local/tmp/chrome-command-line"`);
  execSync('adb shell am force-stop com.android.chrome');
  const TITLE = { principles: 'Principles of Translation', rationale: 'Rationale for Consistent Translation' };
  const chromePage = async (doc) => {
    for (let k = 0; k < 40; k++) {   // Chrome's first start opens its DevTools socket late (the first tap had the page on screen, not yet the socket)
      try {
        execSync('adb forward tcp:9223 localabstract:chrome_devtools_remote');
        const p = (await (await fetch('http://127.0.0.1:9223/json')).json()).find((x) => x.type === 'page' && x.url.includes('/docs/' + doc));
        if (p && p.title && p.title !== p.url) return p;
      } catch (e) { /* Chrome not up yet */ }
      await sleep(1000);
    }
    return null;
  };
  for (const doc of ['principles', 'rationale']) for (let i = 1; i <= 3; i++) {
    const name = `materials -> ${doc}, tap ${i}`;
    if (top() !== 'gift.dhamma.mobile') { execSync('adb shell input keyevent 4'); await sleep(2500); }
    if (top() !== 'gift.dhamma.mobile') { execSync('adb shell monkey -p gift.dhamma.mobile -c android.intent.category.LAUNCHER 1 > /dev/null'); await sleep(4000); }
    if (!(await waitFor(`!!document.querySelector('.dg-tile[data-tile="materials"]')`, 15000))) { await ev(`location.assign('/')`); await sleep(4000); }
    // The tap point (the WebView's place plus CSS px * devicePixelRatio), or null while the row is not what is on screen there.
    // Back from the Custom Tab finds the sheet still open: the tile is tapped only when it is not (a tap would close it, run 94).
    const rowAt = `(async function () { var a = document.querySelector('a.dg-sheet-row[href="/docs/${doc}"]'); if (!a) return null;
      a.scrollIntoView({ block: 'center' }); await new Promise(function (r) { setTimeout(r, 600); });
      var b = a.getBoundingClientRect(), x = b.left + b.width / 2, y = b.top + b.height / 2, hit = document.elementFromPoint(x, y);
      if (!hit || !a.contains(hit)) return null;
      return Math.round(${wv[0]} + x * devicePixelRatio) + ' ' + Math.round(${wv[1]} + y * devicePixelRatio); })()`;
    let at = await ev(rowAt);
    if (!at) { await ev(`document.querySelector('.dg-tile[data-tile="materials"]').click()`); await sleep(1500); at = await ev(rowAt); }
    if (!at) { shot(`docs-${doc}-${i}-norow`); check(false, `${name}: no /docs/${doc} row in the sheet`); continue; }
    execSync(`adb shell input tap ${at}`); await sleep(3500);
    const app = top(), page = app === 'gift.dhamma.mobile' ? await ev(`location.pathname + location.search`) : '';
    const tab = app === 'com.android.chrome' ? await chromePage(doc) : null;
    shot(`docs-${doc}-${i}`);
    check(tab && tab.title.startsWith(TITLE[doc]), `${name}: on top ${app}${page ? ', the app shows ' + page : ''}${tab ? `, the tab: ${tab.url} "${tab.title}"` : ', no /docs/' + doc + ' page in Chrome'}`);
    // Back, again while Chrome is still on top: its first Custom Tab shows a "Minimize tab" tip, and the first Back only closes it.
    for (let k = 0; k < 3 && top() !== 'gift.dhamma.mobile'; k++) { execSync('adb shell input keyevent 4'); await sleep(2500); }
    check(top() === 'gift.dhamma.mobile', `${name}: Back returns to the app (${top()})`);
  }

  // A dhamma.gift link from outside (an App Link) to a page the site serves itself opens in Chrome, not as a search in the app
  // (owner, 2026-10-29: dhamma.gift/api-docs/ did). The list is read from dg-node at build time (build-assets.js SITE_PREFIXES).
  {
    execSync('adb shell am start -W -a android.intent.action.VIEW -d https://dhamma.gift/api-docs/ gift.dhamma.mobile > /dev/null');
    let tab = null;
    for (let k = 0; k < 30 && !tab; k++) {
      try {
        execSync('adb forward tcp:9223 localabstract:chrome_devtools_remote');
        tab = (await (await fetch('http://127.0.0.1:9223/json')).json()).find((x) => x.type === 'page' && x.url.includes('/api-docs') && x.title && x.title !== x.url) || null;
      } catch (e) { /* Chrome not up yet */ }
      if (!tab) await sleep(1000);
    }
    shot('applink-api-docs');
    check(tab && /API/.test(tab.title), `App Link dhamma.gift/api-docs/: on top ${top()}${tab ? `, the tab: ${tab.url} "${tab.title}"` : ', no /api-docs page in Chrome'}`);
    for (let k = 0; k < 3 && top() !== 'gift.dhamma.mobile'; k++) { execSync('adb shell input keyevent 4'); await sleep(2500); }
    if (top() !== 'gift.dhamma.mobile') { execSync('adb shell monkey -p gift.dhamma.mobile -c android.intent.category.LAUNCHER 1 > /dev/null'); await sleep(4000); }
  }

  // Firebase's sign-in handler (/__/auth/handler) from outside must not open the app's search (f3-sadda2 2026-10-31): Chrome on top.
  {
    execSync('adb shell am start -W -a android.intent.action.VIEW -d "https://dhamma.gift/__/auth/handler" gift.dhamma.mobile > /dev/null');
    let away = null;
    for (let k = 0; k < 20 && !away; k++) { await sleep(1000); const t = top(); if (t && t !== 'gift.dhamma.mobile') away = t; }
    const page = away ? '' : await ev(`location.pathname + location.search`);
    shot('applink-auth-handler');
    check(!!away, `App Link dhamma.gift/__/auth/handler: on top ${away || 'the app, at ' + page}`);
    for (let k = 0; k < 3 && top() !== 'gift.dhamma.mobile'; k++) { execSync('adb shell input keyevent 4'); await sleep(2500); }
    if (top() !== 'gift.dhamma.mobile') { execSync('adb shell monkey -p gift.dhamma.mobile -c android.intent.category.LAUNCHER 1 > /dev/null'); await sleep(4000); }
  }

  // A link to a page under /assets opens that page, not the reader (owner 2026-10-31: the editor's link opened the sutta).
  {
    execSync('adb shell am start -W -a android.intent.action.VIEW -d "https://dhamma.gift/assets/lbl.html?s=mn10" gift.dhamma.mobile > /dev/null');
    await sleep(6000);
    const where = top() === 'gift.dhamma.mobile' ? await ev(`location.pathname + location.search`) : 'on top: ' + top();
    shot('applink-assets-lbl');
    check(/^\/assets\/lbl\.html/.test(where), `App Link dhamma.gift/assets/lbl.html?s=mn10: the app shows ${where}`);
    await ev(`location.assign('/')`); await sleep(4000);
  }

  // Memo -> download the audio (dg-apps#58): an Android WebView ignores <a download> of a blob, so the bridge writes the mp3 to the
  // cache and opens the share sheet (shareMemoMp3). The sheet on top within a minute is a PASS; Back closes it.
  await ev(`location.assign('/memo/index.html?text=' + encodeURIComponent('atthi imasmiṁ kāye kesā lomā'))`); await sleep(5000);
  await ev(`document.getElementById('btn_download_audio').click()`);
  let sheet = null;
  for (let i = 0; i < 30 && !sheet; i++) { await sleep(2000); const t = top(); if (t && t !== 'gift.dhamma.mobile') sheet = t; }
  shot('memo-download');
  check(!!sheet, `memo: download the audio opens the share sheet (${sheet || 'nothing on top of the app in 60 s'})`);
  if (sheet) { execSync('adb shell input keyevent 4'); await sleep(2500); }

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
    await ev(`(document.querySelector('.voice-link') || document.querySelector('.voice-start-btn')).click()`); await sleep(2500);
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

  // The voice reads down the column it was started on (dg-node 9376884 / 397345a, Cakkhu 2026-10-31): the second translation's
  // speaker in multi mode reads that translation, an edition's speaker reads that edition's lines (BJT online in the app).
  const stopVoice = () => ev(`(document.querySelector('.close-tts-btn') || {click: function () {}}).click()`);
  const nowItem = () => ev(`(function () { if (typeof ttsState === 'undefined' || !ttsState.speaking) return null;
    var it = ttsState.playlist[ttsState.currentIndex] || {}; return JSON.stringify({ lang: it.lang, text: String(it.text || '').slice(0, 200) }); })()`)
    .then((v) => (v ? JSON.parse(v) : null));
  if (await open('/sn56.11?lang=ru&mode=multi&langs=ru,en', '2nd') && await waitFor(`document.querySelectorAll('#sutta .title-play-btn').length > 1`, 15000)) {
    await ev(`(function () { var b = Array.from(document.querySelectorAll('#sutta .title-play-btn')).filter(function (e) { return !e.closest('.pli-lang'); }); b[1].click(); })()`);
    await waitFor(`typeof ttsState !== 'undefined' && ttsState.speaking`, 15000); await sleep(1500);
    const it = await nowItem(); shot('12-voice-second-translation');
    check(it && it.lang === 'en', `voice: the second translation's speaker (ru,en) reads ${it ? it.lang + ' "' + it.text.slice(0, 40) + '"' : 'nothing'}, want en`);
    await stopVoice(); await sleep(1500);
  } else check(false, 'voice: sn56.11 in multi ru,en or its translation speakers did not load');

  if (await open('/sn56.11?lang=ru&editions=ms,bjt', 'pli-2nd') && await waitFor(`!!document.querySelector('.dg-ed-speaker[data-ed="bjt"] .title-play-btn')`, 20000)) {
    await ev(`document.querySelector('.dg-ed-speaker[data-ed="bjt"] .title-play-btn').click()`);
    await waitFor(`typeof ttsState !== 'undefined' && ttsState.speaking`, 15000); await sleep(1500);
    const it = await nowItem();
    const where = it ? JSON.parse(await ev(`(function (t) { var n = function (s) { return String(s).toLowerCase().replace(/[^\\p{L}]+/gu, ''); }, w = n(t);
      var has = function (ed) { return Array.from(document.querySelectorAll('#sutta .dg-ed-line[data-ed="' + ed + '"]')).some(function (e) { return n(e.textContent).indexOf(w) !== -1; }); };
      return JSON.stringify({ bjt: has('bjt'), ms: has('ms') }); })(${JSON.stringify(it.text)})`)) : {};
    shot('13-voice-edition-bjt');
    check(it && where.bjt && !where.ms, `voice: the BJT speaker reads ${it ? '"' + it.text.slice(0, 50) + '"' : 'nothing'} (in a BJT line ${where.bjt}, in an MS line ${where.ms})`);
    await stopVoice(); await sleep(1500);
  } else check(false, 'voice: sn56.11 with the BJT edition or its speaker did not load');

  // Translations window, "↺ Default" in multi mode (owner's iPhone, build 567: it did nothing - a reload to /sn56.11 is no file in
  // the WebView; dg-node home.js now reloads through /?_nativeRoute=). Back on the reader, without mode/langs, one translation.
  if (await open('/sn56.11?lang=ru&mode=multi&langs=ru,en', '2nd')) {
    await ev(`window.__beforeReset = 1; (document.querySelector('.dg-lpill-more') || {click: function () {}}).click()`);
    const has = await waitFor(`!!document.querySelector('[data-ts-reset]')`, 8000);
    shot('14-translations-window');
    if (has) {
      await ev(`document.querySelector('[data-ts-reset]').click()`); await sleep(4000);
      await waitFor(`!window.__beforeReset && !!document.querySelector('#sutta article .quote')`, 25000);
      const st = JSON.parse(await ev(`JSON.stringify({ reloaded: !window.__beforeReset, url: location.pathname + location.search, mode: localStorage.getItem('dgReaderMode'),
        langs: Array.from(new Set(Array.from(document.querySelectorAll('#sutta article p .quote:not(.pli-lang)')).filter(function (e) { return e.offsetParent; })
          .map(function (e) { return (e.className.match(/(\\w+)-lang/) || [])[1]; }))) })`));
      shot('15-translations-default');
      check(st.reloaded && /^\/sn56\.11/.test(st.url) && !/[?&](mode|langs)=/.test(st.url) && st.langs.length === 1,
        `translations window, Default: reloaded ${st.reloaded}, at ${st.url}, mode ${st.mode}, translations shown ${st.langs.join(',')}`);
    } else check(false, 'translations window: no "↺ Default" button after the ⋯ pill');
  } else check(false, 'translations window: sn56.11 in multi ru,en did not load');

  ws.close();
  finished = true;
  console.log(failed ? 'RESULT FAIL' : 'RESULT PASS');
  process.exit(failed ? 1 : 0);
})();
