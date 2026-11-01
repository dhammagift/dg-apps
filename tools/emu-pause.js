// Pauses between phrases run out with the screen off (owner 2026-11-01, Motorola, an A-B loop with a pause stopped until the app
// was opened again; Sadda's dg-node e6ebb6b ends a pause on the playing silence's timeupdate, not only on a timer the background
// WebView holds back). The app reads SN 56.11 with an 8 s pause after each phrase, the screen goes off for 75 s, and the reading
// must have gone on meanwhile. Debug APK, DevTools.
//
//   node tools/emu-pause.js <out-dir>
const fs = require('fs');
const { execSync } = require('child_process');
const OUT = process.argv[2] || 'shots';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failed = false;
const check = (ok, text) => { console.log((ok ? 'PASS ' : 'FAIL ') + text); if (!ok) failed = true; };
const shot = (name) => fs.writeFileSync(`${OUT}/pause-${name}.png`, execSync('adb exec-out screencap -p', { maxBuffer: 64 << 20 }));

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
  const has = await ev(`fetch('/read/js/voice.js', { cache: 'no-store' }).then(function (r) { return r.text(); }).then(function (t) { return t.indexOf('function mediaTimeout') !== -1; })`);
  console.log('voice.js with mediaTimeout (dg-node e6ebb6b): ' + has);
  await ev(`localStorage.setItem('dg.app.downloadDeclined', '1'); localStorage.setItem('paliToggle', 'pli-2nd'); location.assign('/sn56.11?lang=en')`);
  await sleep(3000);
  check(await waitFor(`!!document.querySelector('#sutta article .quote')`, 30000), 'SN 56.11 opened');
  await sleep(2000);
  // the reader's own Voice, as Alt+R / the speaker start it, with an 8 s pause after each phrase
  await ev(`window.TTS_SEGMENT_DELAY = 8000; (document.querySelector('#sutta .tts-speaker, #sutta [data-tts-start], .dg-title-speaker') || {}).click ? 0 : 0;
    var s = document.querySelector('#sutta .pli-lang.quote'); s.click(); 0`);
  await sleep(1200);
  await ev(`(document.querySelector('.dynamic-tts-btn') || document.getElementById('sm-audio') || {}).click && (document.querySelector('.dynamic-tts-btn') || document.getElementById('sm-audio')).click()`);
  check(await waitFor(`typeof ttsState !== 'undefined' && ttsState.speaking`, 30000), 'the voice started');
  await sleep(4000);
  const before = await ev(`ttsState.currentIndex`);
  shot('1-playing');
  execSync('adb shell input keyevent KEYCODE_SLEEP');
  console.log(`screen off at phrase ${before}`);
  await sleep(75000);
  execSync('adb shell input keyevent KEYCODE_WAKEUP'); execSync('adb shell wm dismiss-keyguard || true'); await sleep(1500);
  const after = await ev(`ttsState.currentIndex`), speaking = await ev(`!!ttsState.speaking`);
  shot('2-after');
  // 75 s with 8 s pauses and short phrases: at least 4 phrases, where held-back timers give 0 or 1
  check(after - before >= 4, `the reading went on with the screen off: phrase ${before} -> ${after} in 75 s (still speaking: ${speaking})`);
  await ev(`window.ttsStop ? ttsStop() : 0`);
  console.log(failed ? 'RESULT FAIL' : 'RESULT PASS');
  process.exit(failed ? 1 : 0);
})();
