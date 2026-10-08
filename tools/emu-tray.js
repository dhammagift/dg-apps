// The notification player of the Dhamma.Gift app, driven the way a reader does it (owner, 2026-10-08: "в плеере в шторке play/pause не
// работает, на сайте работает"). Reads the sutta aloud, then taps Pause and Play on the notification shade of a real emulator, and
// reports what the page and the audio did after each tap. Debug APK only (the page is reached over the WebView's DevTools socket).
//
//   node tools/emu-tray.js <out-dir>      (adb already forwards tcp:9222 to the app's webview_devtools_remote socket)
const { execSync } = require('child_process');
const fs = require('fs');
const OUT = process.argv[2] || 'shots';
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
    var a = Array.prototype.slice.call(document.querySelectorAll('audio')).concat(window.sharedGoogleAudio ? [window.sharedGoogleAudio] : []);
    var speech = a.filter(function (x) { return !/silence/.test(x.src) && !/^data:/.test(x.src) && x.src; });
    return JSON.stringify({ mediaSession: navigator.mediaSession && navigator.mediaSession.playbackState,
      speechAudio: speech.map(function (x) { return (x.paused ? 'paused@' : 'playing@') + Math.round(x.currentTime * 10) / 10; }),
      silence: a.filter(function (x) { return /silence/.test(x.src); }).map(function (x) { return x.paused ? 'paused' : 'playing'; }),
      playBtnOn: Array.prototype.map.call(document.querySelectorAll('.play-main-button'), function (b) { return b.classList.contains('on'); }),
      hasPlayer: !!document.querySelector('.play-main-button'), url: location.pathname });
  })()`);

  // 1. read aloud
  say('start: ' + await ev(`(function(){ var l = document.querySelector('.voice-link'); if (!l) return 'no .voice-link'; l.click(); return 'clicked'; })()`));
  let s;
  for (let i = 0; i < 30; i++) { await sleep(2000); s = await state(); const o = JSON.parse(s); if (o.speechAudio.some((x) => x.startsWith('playing@')) && o.mediaSession === 'playing') break; }
  say('reading: ' + s);
  const playing0 = JSON.parse(s);
  const reading = playing0.mediaSession === 'playing' && playing0.speechAudio.some((x) => x.startsWith('playing@'));
  say(reading ? 'PASS the page is reading aloud' : 'FAIL the page did not start reading');

  // 2. taps on the notification shade
  function shade(tag) {
    sh('adb shell cmd statusbar expand-notifications'); try { execSync('sleep 2'); } catch (e) { /* ignore */ }
    fs.writeFileSync(`${OUT}/shade-${tag}.png`, execSync('adb exec-out screencap -p', { maxBuffer: 1 << 26 }));
    sh('adb shell uiautomator dump /sdcard/n.xml'); return sh('adb shell cat /sdcard/n.xml');
  }
  function tap(xml, names, tag) {
    fs.writeFileSync(`${OUT}/shade-${tag}.xml`, xml);
    const re = /<node[^>]*?(?:text|content-desc)="([^"]*)"[^>]*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"[^>]*>/g;
    let m, found = null; const seen = [];
    while ((m = re.exec(xml))) { seen.push(m[1]); if (!found && names.test(m[1])) found = m; }
    if (!found) { say('shade (' + tag + ') has no ' + names + '; labels seen: ' + seen.filter(Boolean).slice(0, 25).join(' | ')); return false; }
    const x = Math.round((+found[2] + +found[4]) / 2), y = Math.round((+found[3] + +found[5]) / 2);
    sh(`adb shell input tap ${x} ${y}`); say(`tapped "${found[1]}" at ${x},${y}`); return true;
  }
  const collapse = () => { try { sh('adb shell cmd statusbar collapse'); } catch (e) { /* ignore */ } };

  let xml = shade('1-pause');
  const pausedTap = tap(xml, /^pause$/i, '1-pause');
  await sleep(2000); collapse();
  s = await state(); say('after Pause: ' + s);
  const o1 = JSON.parse(s);
  const paused = o1.mediaSession === 'paused' && !o1.speechAudio.some((x) => x.startsWith('playing@'));
  say(pausedTap && paused ? 'PASS Pause in the notification pauses the reading' : 'FAIL Pause in the notification did not pause the reading');

  xml = shade('2-play');                    // right away, as the owner does it
  const playTap = tap(xml, /^play$/i, '2-play');
  await sleep(3000); collapse();
  s = await state(); say('after Play: ' + s);
  const o2 = JSON.parse(s);
  const resumed = o2.mediaSession === 'playing' && o2.speechAudio.some((x) => x.startsWith('playing@'));
  say(playTap && resumed ? 'PASS Play in the notification resumes the reading' : 'FAIL Play in the notification did not resume the reading');

  fs.writeFileSync(`${OUT}/tray-result.txt`, res.join('\n') + '\n');
  ws.close();
  process.exit(pausedTap && paused && playTap && resumed ? 0 : 1);
})().catch((e) => { console.log('FAIL ' + e.message); fs.writeFileSync(`${OUT}/tray-result.txt`, res.join('\n') + '\nFAIL ' + e.message + '\n'); process.exit(1); });
