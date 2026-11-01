// "Compare" in the app, end to end as a person does it (owner 2026-11-01, a blocker: «пока не покажешь видео»): the app first
// takes the site's current reader files (the version row's check + Update, as the owner does), then on SN 56.11 a tap on a line,
// its link, the menu's Compare: the text opens in multi at that line with the Differences on and marked. Debug APK, DevTools.
//
//   node tools/emu-compare.js <out-dir>
const fs = require('fs');
const { execSync } = require('child_process');
const OUT = process.argv[2] || 'shots';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failed = false;
const check = (ok, text) => { console.log((ok ? 'PASS ' : 'FAIL ') + text); if (!ok) failed = true; };
const shot = (name) => fs.writeFileSync(`${OUT}/compare-${name}.png`, execSync('adb exec-out screencap -p', { maxBuffer: 64 << 20 }));
const tap = (x, y) => execSync(`adb shell input tap ${Math.round(x)} ${Math.round(y)}`);

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
  // the WebView's place on the screen, for real taps (CSS px * devicePixelRatio + its top)
  execSync('adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1 || true');
  const wv = (execSync('adb shell cat /sdcard/ui.xml').toString().match(/class="android\.webkit\.WebView"[^>]*bounds="\[(\d+),(\d+)\]/) || [0, 0, 0]).slice(1).map(Number);
  const screenAt = async (sel, dx, dy) => JSON.parse(await ev(`(function () { var e = document.querySelector(${JSON.stringify(sel)}); if (!e) return 'null';
    var r = e.getBoundingClientRect(); return JSON.stringify([${wv[0]} + (r.left + ${dx}) * devicePixelRatio, ${wv[1]} + (r.top + ${dy}) * devicePixelRatio]); })()`));

  // 1. the site's reader files, as the owner takes them: check, then Update (the page reloads on them)
  await waitFor(`typeof window.__dgCheckSiteUpdate === 'function'`, 20000);
  const upd = await ev(`window.__dgCheckSiteUpdate().then(function (r) { return r.state; })`);
  console.log('site update: ' + upd);
  if (upd === 'new') {
    await waitFor(`!!document.querySelector('#dg-upd button')`, 15000);
    await ev(`document.querySelector('#dg-upd button').click()`);
    await sleep(8000);
  }
  const has = await ev(`fetch('/reader/common.js', { cache: 'no-store' }).then(function (r) { return r.text(); }).then(function (t) { return t.indexOf('mode=multi&diff=1') !== -1; })`);
  check(has === true, `the app serves the site's reader with Compare's ?diff=1 (update: ${upd})`);

  // 2. a single reading of SN 56.11, a real tap on a line, its link, Compare
  await ev(`localStorage.setItem('dg.app.downloadDeclined', '1'); localStorage.removeItem('dgEditionsDiff'); localStorage.removeItem('dgEditionsMulti'); location.assign('/sn56.11?lang=en')`);
  await sleep(3000);
  check(await waitFor(`!!document.querySelector('#sutta span[id] .copyLink')`, 30000), 'SN 56.11 opened');
  await ev(`(function () { var s = Array.from(document.querySelectorAll('#sutta span[id]')).filter(function (e) { return e.querySelector('.copyLink') && e.textContent.trim().length > 40; })[5];
    s.setAttribute('data-seg', '1'); s.scrollIntoView({ block: 'center' }); })()`);
  await sleep(1500);
  shot('1-text');
  const line = await screenAt('[data-seg] .pli-lang', 30, 10);
  tap(line[0], line[1]); await sleep(1500);
  await ev(`document.querySelector('[data-seg] .copyLink-start, [data-seg] .copyLink').dispatchEvent(new MouseEvent('click', { bubbles: true }))`);
  await sleep(1500);
  shot('2-menu');
  const cmp = await screenAt('#sm-compare', 40, 12);
  check(!!cmp, 'the line menu shows Compare');
  if (cmp) tap(cmp[0], cmp[1]);
  await sleep(4000);
  check(await waitFor(`!!document.querySelector('#sutta .dg-ed-line')`, 40000), 'Compare opened the editions');
  await sleep(4000);
  const r = JSON.parse(await ev(`JSON.stringify({ url: location.pathname + location.search, eds: new Set(Array.from(document.querySelectorAll('#sutta .dg-ed-line')).map(function (e) { return e.dataset.ed; })).size,
    diff: typeof window.dgEditionsDiff === 'function' ? window.dgEditionsDiff() : null, toggle: !!(document.querySelector('.dg-diff-toggle input, [role="switch"][aria-checked="true"]') || {}).checked })`) || '{}');
  shot('3-compare');
  check(r.diff === true && r.eds > 1, `Compare: ${r.eds} editions, Differences ${r.diff ? 'on' : 'off'} (${r.url})`);
  await sleep(3000);
  shot('4-compare-later');
  console.log(failed ? 'RESULT FAIL' : 'RESULT PASS');
  process.exit(failed ? 1 : 0);
})();
