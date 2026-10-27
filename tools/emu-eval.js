// One expression in the app's WebView over DevTools (debug APK, adb already forwards tcp:9222), awaited; prints its value.
//
//   node tools/emu-eval.js '<expression>'
(async () => {
  let t;
  for (let i = 0; i < 20 && !t; i++) {
    try { t = (await (await fetch('http://127.0.0.1:9222/json')).json()).find((x) => x.type === 'page'); } catch (e) { /* not up yet */ }
    if (!t) await new Promise((r) => setTimeout(r, 1500));
  }
  if (!t) { console.log('FAIL no page target on the DevTools socket'); process.exit(1); }
  const ws = new WebSocket(t.webSocketDebuggerUrl);
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  ws.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: { expression: process.argv[2], awaitPromise: true, returnByValue: true } }));
  const d = await new Promise((r) => { ws.onmessage = (m) => { const x = JSON.parse(m.data); if (x.id === 1) r(x); }; });
  console.log(d.result && d.result.exceptionDetails ? 'ERROR ' + d.result.exceptionDetails.text : String(d.result && d.result.result ? d.result.result.value : ''));
  ws.close(); process.exit(0);
})();
