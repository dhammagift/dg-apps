// Another sutta opened in place while the player reads (owner, 2026-10-09, build 533: sn12.2 reading, dn22 typed into the search box,
// sn12.2 is still read). The site stops the old playlist on 'suttaLoaded' (dg-node 4b18309); this checks the same in the app's WebView,
// playing and paused, and reports what Play reads afterwards. Debug APK only (DevTools socket on tcp:9222).
//
//   node tools/emu-switch.js <out-dir>
const fs = require('fs');
const OUT = process.argv[2] || 'shots';
const res = [];
const say = (s) => { console.log(s); res.push(s); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failed = false;
const check = (ok, text) => { say((ok ? 'PASS ' : 'FAIL ') + text); if (!ok) failed = true; };

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
    .then((d) => (d.result && d.result.result ? d.result.result.value : JSON.stringify(d.error || d)));
  const state = async () => JSON.parse(await ev(`(function(){
    var ts = (typeof ttsState !== 'undefined') ? ttsState : {};
    var cur = ts.playlist && ts.playlist[ts.currentIndex];
    function a(x) { return x ? (x.paused ? 'paused@' : 'playing@') + Math.round(x.currentTime * 10) / 10 : null; }
    return JSON.stringify({ url: location.pathname + location.search, slugOnPage: window._currentSlug || null, ttsSlug: ts.currentSlug || null,
      speaking: !!ts.speaking, paused: !!ts.paused, listLen: (ts.playlist || []).length, current: cur ? String(cur.id) : null,
      googleAudio: a(ts.googleAudio), mediaSession: navigator.mediaSession && navigator.mediaSession.playbackState,
      heading: (document.querySelector('.sutta-title, h1, .sutta-heading') || {}).textContent || null });
  })()`));
  const openDn22 = () => ev(`(function(){ var i = document.getElementById('paliauto'); if (!i) return 'no #paliauto';
    i.value = 'dn22'; i.dispatchEvent(new Event('input', { bubbles: true }));
    var b = document.getElementById('searchbtn'); if (!b) return 'no #searchbtn'; b.click(); return 'submitted'; })()`);

  for (const scenario of ['playing', 'paused']) {
    say('=== ' + scenario + ': sn12.2 -> dn22 in the search box');
    await ev(`location.assign('/sn12.2')`); await sleep(10000);
    say('start: ' + await ev(`(function(){ var l = document.querySelector('.voice-link'); if (!l) return 'no .voice-link'; l.click(); return 'clicked'; })()`));
    let s;
    for (let i = 0; i < 30; i++) { await sleep(2000); s = await state(); if (s.googleAudio && s.googleAudio.startsWith('playing@') && s.mediaSession === 'playing') break; }
    say('reading sn12.2: ' + JSON.stringify(s));
    check(!!(s.googleAudio && s.googleAudio.startsWith('playing@')), 'sn12.2 is read aloud before the switch');
    if (scenario === 'paused') {
      say('pause: ' + await ev(`(function(){ var b = document.querySelector('.play-main-button'); if (!b) return 'no button'; b.click(); return 'clicked'; })()`));
      await sleep(2000); say('paused: ' + JSON.stringify(await state()));
    }
    say('search: ' + await openDn22());
    await sleep(9000);
    s = await state(); say('after the switch: ' + JSON.stringify(s));
    fs.writeFileSync(`${OUT}/switch-${scenario}-after.json`, JSON.stringify(s));
    check(/dn22/i.test(s.slugOnPage || '') || /dn22/i.test(s.url), 'dn22 is on the page (' + s.url + ', slug ' + s.slugOnPage + ')');
    check(!(s.googleAudio && s.googleAudio.startsWith('playing@')), 'the old sutta is not playing any more');
    check(!s.listLen || /dn22/i.test(s.ttsSlug || ''), 'the playlist was dropped or belongs to dn22 (list ' + s.listLen + ', slug ' + s.ttsSlug + ')');
    // Play: the main button, then what it reads
    say('play: ' + await ev(`(function(){ var b = document.querySelector('.play-main-button'); if (!b) return 'no button'; b.click(); return 'clicked'; })()`));
    for (let i = 0; i < 15; i++) { await sleep(2000); s = await state(); if (s.googleAudio && s.googleAudio.startsWith('playing@')) break; }
    say('after Play: ' + JSON.stringify(s));
    // segment ids are bare ('0.1'), so the sutta is told by the player's slug and by the list length (dn22 has far more segments than sn12.2: 393 vs 79)
    check(/dn22/i.test(s.ttsSlug || '') && s.listLen > 200, 'Play reads dn22 (slug ' + s.ttsSlug + ', ' + s.listLen + ' segments)');
    await ev(`typeof stopPlayback === 'function' && stopPlayback()`);
  }
  fs.writeFileSync(`${OUT}/switch-result.txt`, res.join('\n') + '\n');
  ws.close();
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.log('FAIL ' + e.message); fs.writeFileSync(`${OUT}/switch-result.txt`, res.join('\n') + '\nFAIL ' + e.message + '\n'); process.exit(1); });
