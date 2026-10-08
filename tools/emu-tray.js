// The notification player of the Dhamma.Gift app, driven the way a reader does it (owner, 2026-10-08: "в плеере в шторке play/pause не
// работает, на сайте работает"). Reads the sutta aloud, then taps Pause and Play on the notification shade of a real emulator, and
// reports what the page and the audio did after each tap. Debug APK only (the page is reached over the WebView's DevTools socket).
//
//   node tools/emu-tray.js <out-dir>      (adb already forwards tcp:9222 to the app's webview_devtools_remote socket)
const { execSync } = require('child_process');
const fs = require('fs');
const OUT = process.argv[2] || 'shots';
// Which voice engine reads: neural/Google (the page's own audio, default) or native (the OS text-to-speech through DgTtsPlugin).
const ENGINE = process.argv[3] || 'audio';
const res = [];
const say = (s) => { console.log(s); res.push(s); };
const sh = (c) => execSync(c, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function target() {
  for (let i = 0; i < 20; i++) {
    try {
      const list = await (await fetch('http://127.0.0.1:9222/json')).json();
      const t = list.find((x) => x.type === 'page' && /localhost|dhamma\.gift/.test(x.url)) || list.find((x) => x.type === 'page');
      if (t) return t;
    } catch (e) { /* not up yet */ }
    await sleep(1500);
  }
  throw new Error('no page target on the DevTools socket');
}

(async () => {
  const t = await target();
  say('page: ' + t.url);
  const ws = new WebSocket(t.webSocketDebuggerUrl);
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  let id = 0; const waiting = {};
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && waiting[d.id]) { waiting[d.id](d); delete waiting[d.id]; } };
  const ev = (expression) => new Promise((r) => { const i = ++id; waiting[i] = r; ws.send(JSON.stringify({ id: i, method: 'Runtime.evaluate', params: { expression, awaitPromise: true, returnByValue: true } })); })
    .then((d) => (d.result && d.result.result ? d.result.result.value : d.error));
  const state = () => ev(`(function(){
    function a(x) { return x ? (x.paused ? 'paused@' : 'playing@') + Math.round(x.currentTime * 10) / 10 : null; }
    var ts = (typeof ttsState !== 'undefined') ? ttsState : {};
    var shared = window.sharedGoogleAudio;
    return JSON.stringify({ mediaSession: navigator.mediaSession && navigator.mediaSession.playbackState,
      googleAudio: a(ts.googleAudio), sharedGoogleAudio: shared && shared.src && !/^data:/.test(shared.src) ? a(shared) : null,
      silence: (typeof silenceAudio !== 'undefined') ? a(silenceAudio) : null,
      speaking: !!ts.speaking, paused: !!ts.paused, playBtnOn: Array.prototype.map.call(document.querySelectorAll('.play-main-button'), function (b) { return b.classList.contains('on'); }) });
  })()`);
  const audible = (o) => ENGINE === 'native' ? (o.speaking && !o.paused) : [o.googleAudio, o.sharedGoogleAudio].some((x) => x && x.startsWith('playing@'));

  // 1. read aloud
  if (ENGINE === 'native') {
    say('engine: native (OS voices): ' + await ev(`(function(){ localStorage.setItem('tts_native_trn_enabled','true'); localStorage.setItem('tts_native_pali_enabled','true'); return 'set'; })()`));
    await ev('location.reload()'); await sleep(8000);
  }
  say('start: ' + await ev(`(function(){ var l = document.querySelector('.voice-link'); if (!l) return 'no .voice-link'; l.click(); return 'clicked'; })()`));
  let s;
  for (let i = 0; i < 30; i++) { await sleep(2000); s = await state(); const o = JSON.parse(s); if (audible(o) && o.mediaSession === 'playing') break; }
  say('reading: ' + s);
  const playing0 = JSON.parse(s);
  const reading = playing0.mediaSession === 'playing' && audible(playing0);
  say(reading ? 'PASS the page is reading aloud' : 'FAIL the page did not start reading');

  // 2. taps on the notification shade
  function shade(tag) {
    sh('adb shell cmd statusbar expand-notifications'); try { execSync('sleep 2'); } catch (e) { /* ignore */ }
    fs.writeFileSync(`${OUT}/shade-${tag}.png`, execSync('adb exec-out screencap -p', { maxBuffer: 1 << 26 }));
    sh('adb shell uiautomator dump /sdcard/n.xml'); return sh('adb shell cat /sdcard/n.xml');
  }
  function tap(xml, names, tag) {
    fs.writeFileSync(`${OUT}/shade-${tag}.xml`, xml);
    let found = null; const seen = [];
    for (const m of xml.matchAll(/<node[^>]*>/g)) {
      const at = Object.fromEntries([...m[0].matchAll(/([\w-]+)="([^"]*)"/g)].map((k) => [k[1], k[2]]));
      const label = at['content-desc'] || at.text || '';
      if (label) seen.push(label);
      if (!found && at.bounds && names.test(label) && at.clickable === 'true') found = { label, b: at.bounds.match(/\d+/g).map(Number) };
    }
    if (!found) { say('shade (' + tag + ') has no ' + names + '; labels seen: ' + seen.slice(0, 30).join(' | ')); return false; }
    const x = Math.round((found.b[0] + found.b[2]) / 2), y = Math.round((found.b[1] + found.b[3]) / 2);
    sh(`adb shell input tap ${x} ${y}`); say(`tapped "${found.label}" at ${x},${y}`); return true;
  }
  const collapse = () => { try { sh('adb shell cmd statusbar collapse'); } catch (e) { /* ignore */ } };

  let xml = shade('1-pause');
  const pausedTap = tap(xml, /^pause$/i, '1-pause');
  await sleep(2000); collapse();
  s = await state(); say('after Pause: ' + s);
  const o1 = JSON.parse(s);
  const paused = o1.mediaSession === 'paused' && !audible(o1);
  say(pausedTap && paused ? 'PASS Pause in the notification pauses the reading' : 'FAIL Pause in the notification did not pause the reading');

  try { fs.writeFileSync(`${OUT}/focus-after-pause.txt`, sh('adb shell dumpsys audio | grep -iA25 "Audio Focus stack"')); } catch (e) { /* ignore */ }
  xml = shade('2-play');                    // right away, as the owner does it
  const playTap = tap(xml, /^play$/i, '2-play');
  await sleep(3000); collapse();
  s = await state(); say('after Play: ' + s);
  try { fs.writeFileSync(`${OUT}/focus-after-play.txt`, sh('adb shell dumpsys audio | grep -iA25 "Audio Focus stack"')); fs.writeFileSync(`${OUT}/media-session.txt`, sh('adb shell dumpsys media_session | head -120')); } catch (e) { /* ignore */ }
  const o2 = JSON.parse(s);
  const resumed = o2.mediaSession === 'playing' && audible(o2);
  say(playTap && resumed ? 'PASS Play in the notification resumes the reading' : 'FAIL Play in the notification did not resume the reading');

  fs.writeFileSync(`${OUT}/tray-result.txt`, res.join('\n') + '\n');
  ws.close();
  process.exit(pausedTap && paused && playTap && resumed ? 0 : 1);
})().catch((e) => { console.log('FAIL ' + e.message); fs.writeFileSync(`${OUT}/tray-result.txt`, res.join('\n') + '\nFAIL ' + e.message + '\n'); process.exit(1); });
