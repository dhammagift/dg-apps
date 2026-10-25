// Uposatha: the settings a phone gets back from Android's backup on a fresh install (owner's phone, 2026-10-25), written into the
// page's storage over the WebView's DevTools socket, then the page is reloaded. Reminders of every kind are on, on the alarm
// source, the place is found by the phone and not known yet: at the reload the page schedules before the notification
// permission is given and plans again when the place arrives (the crash loop of "500 alarms"). Debug APK only.
//
//   node tools/emu-upo-seed.js [place]      (adb already forwards tcp:9222 to the app's webview_devtools_remote socket)
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  let t;
  for (let i = 0; i < 20 && !t; i++) {
    try { t = (await (await fetch('http://127.0.0.1:9222/json')).json()).find((x) => x.type === 'page'); } catch (e) { /* not up yet */ }
    if (!t) await sleep(1500);
  }
  if (!t) { console.log('FAIL no page target on the DevTools socket'); process.exit(1); }
  const ws = new WebSocket(t.webSocketDebuggerUrl);
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  const settings = {
    dgUposathaRemind: JSON.stringify({ on: true, lead: 24, day: true, dayAt: '06:00', d8: true, d14: true, d15: true, sound: 'gong' }),
    dgUposathaMeal: JSON.stringify({ rem: true, lead: 30, days: 'all', snd: 'vikala', beg: true, begLead: 0, begSnd: 'gong3' }),
    dgUposathaParts: JSON.stringify({ rem: true, which: 'both', days: 'all', snd: 'gong' }),
    dgUposathaSoundStream: 'alarm',
    dgUposathaLocAuto: '1',
  };
  // "place": only report the place the page found (the second plan of the case comes from it)
  const expression = process.argv[2] === 'place' ? `'place: ' + localStorage.getItem('dgUposathaLoc')` : `(function(){ var s = ${JSON.stringify(settings)}; for (var k in s) localStorage.setItem(k, s[k]);
    ['dgUposathaLoc', 'dgUposathaLocAt', 'dgUposathaNotified'].forEach(function (k) { localStorage.removeItem(k); });
    setTimeout(function () { location.reload(); }, 100); return location.href; })()`;
  ws.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: { expression, returnByValue: true } }));
  const answer = await new Promise((r) => { ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id === 1) r(d); }; });
  const value = answer.result && answer.result.result && answer.result.result.value;
  console.log(process.argv[2] === 'place' ? value : 'seeded ' + Object.keys(settings).join(', ') + ' on ' + JSON.stringify(value));
  ws.close();
  process.exit(0);
})();
