// Selectable offline packs, end to end in Chromium: dg-node's db-worker.js (no app.js on the page) downloads the packs,
// opens them as main + ATTACH, and its offline search must equal the site's; then a pack is dropped and all deleted.
// node tools/packs-check.js [site] [packs base]   (defaults: test.dhamma.gift and its own mobile-data)
const { chromium } = require('/usr/lib/node_modules/@playwright/cli/node_modules/playwright');
const BASE = process.argv[2] || 'https://test.dhamma.gift';
const PACKS = process.argv[3] || (BASE + '/mobile-data');
(async () => {
  const b = await chromium.launch(); const c = await b.newContext(); const p = await c.newPage();
  p.on('console', m => { if (/dg-offline|error/i.test(m.text())) console.log('  [page]', m.text().slice(0, 200)); });
  await p.goto(BASE + '/robots.txt');
  await p.evaluate(() => {
    const w = new Worker('/offline/db-worker.js', { type: 'module' }); let n = 0; window.__progress = [];
    w.addEventListener('message', e => { if (!e.data.id) window.__progress.push(e.data); });
    window.call = (op, args) => new Promise((res, rej) => { const id = ++n; const h = e => { if (e.data.id === id) { w.removeEventListener('message', h); e.data.ok ? res(e.data.result) : rej(new Error(e.data.error)); } }; w.addEventListener('message', h); w.postMessage({ id, op, args }); });
  });
  const call = (op, args) => p.evaluate(([op, args]) => window.call(op, args), [op, args]);
  let bad = 0;
  const t0 = Date.now();
  const opened = await call('open', { distBase: '/mobile-data', download: true, packs: ['tr-ru', 'tr-small'], packsBase: PACKS });
  console.log('open:', JSON.stringify(opened), ((Date.now() - t0) / 1000).toFixed(0) + 's');
  const prog = await p.evaluate(() => window.__progress);
  const dl = prog.filter(m => m.type === 'downloading').map(m => `${m.index}/${m.count} ${m.pack}`);
  const pr = prog.filter(m => m.type === 'progress' && m.total > 0);
  console.log('packs downloaded:', dl.join(', '), '| progress msgs', pr.length, 'monotonic', pr.every((m, i) => !i || m.loaded >= pr[i - 1].loaded || m.pack !== pr[i - 1].pack), 'last', JSON.stringify(prog[prog.length - 1]));
  console.log('status:', JSON.stringify(await call('status', { distBase: '/mobile-data', wantManifest: false })));
  for (const [q, langs] of [['kacchapa', 'ru'], ['dukkha', 'ru,sr'], ['kacch.*a', 'ru'], ['metta', 'pl']]) {
    const off = await call('search', { q, langs });
    const on = await p.evaluate(async ([q, langs]) => (await fetch(`/search?q=${encodeURIComponent(q)}&langs=${langs}`)).json(), [q, langs]).catch(() => null);
    const f = r => r && r.metadata ? `${r.metadata.totalFiles}/${r.metadata.totalMatches}` : '?';
    if (f(off) !== f(on)) bad++;
    console.log(`${f(off) === f(on) ? 'ok  ' : 'BAD '} search ${q} [${langs}] offline ${f(off)} online ${f(on)}`);
  }
  const text = await call('text', { suttaId: 'dn22', langs: 'ru,sr' });
  console.log('text dn22:', text.segments.length, 'segments, availableLangs', JSON.stringify(text.availableLangs), 'ru seg1:', JSON.stringify((text.segments[1] || {}).translations).slice(0, 120));
  console.log('check:', JSON.stringify(await call('check', { distBase: '/mobile-data', packsBase: PACKS })));
  // drop tr-small: an update to a smaller selection only unlinks
  const t1 = Date.now();
  const upd = await call('update', { distBase: '/mobile-data', packs: ['tr-ru'], packsBase: PACKS });
  console.log('update to [tr-ru]:', JSON.stringify(upd), ((Date.now() - t1) / 1000).toFixed(1) + 's');
  const dn = await call('text', { suttaId: 'dn22', langs: 'ru,sr' });
  console.log('dn22 languages after removing tr-small:', JSON.stringify(dn.availableLangs), dn.availableLangs.includes('sr') ? 'BAD: sr still there' : 'ok');
  if (dn.availableLangs.includes('sr')) bad++;
  console.log('delete:', JSON.stringify(await call('delete', { distBase: '/mobile-data' })));
  console.log('status after delete:', JSON.stringify(await call('status', { distBase: '/mobile-data', wantManifest: false })));
  await b.close();
  console.log(bad ? `${bad} BAD` : 'all ok'); process.exitCode = bad ? 1 : 0;
})().catch(e => { console.log('FAIL', e.message); process.exit(1); });
