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
  // window.restart(): a fresh worker, as a reload or a killed app would give
  await p.evaluate(() => {
    let w = null, n = 0; window.__progress = [];
    window.restart = async () => {
      if (w) { w.terminate(); await new Promise(r => setTimeout(r, 1500)); }
      w = new Worker('/offline/db-worker.js', { type: 'module' });
      w.addEventListener('message', e => { if (!e.data.id) window.__progress.push(e.data); });
    };
    window.call = (op, args) => new Promise((res, rej) => { const id = ++n; const h = e => { if (e.data.id === id) { w.removeEventListener('message', h); e.data.ok ? res(e.data.result) : rej(new Error(e.data.error)); } }; w.addEventListener('message', h); w.postMessage({ id, op, args }); });
    return window.restart();
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
  const expect = (ok, what) => { if (!ok) bad++; console.log(`${ok ? 'ok  ' : 'BAD '} ${what}`); };
  // The other Pali editions offline (owner 2026-11-01): the ed-bjt pack added, then sn56.11 with &editions=bjt from the
  // worker must carry the same Buddha Jayanti lines as the site's /api/text, and say the device holds bjt.
  const man0 = await p.evaluate(async (u) => (await fetch(u + '/packs-manifest.json', { cache: 'no-store' })).json(), PACKS);
  if (man0.packs.some(x => x.id === 'ed-bjt')) {
    await call('update', { distBase: '/mobile-data', packs: ['tr-ru', 'ed-bjt'], packsBase: PACKS });
    const off = await call('text', { suttaId: 'sn56.11', langs: 'ru', editions: 'bjt' });
    const on = await p.evaluate(async () => (await fetch('/api/text/sn56.11?langs=ru&editions=bjt')).json());
    const lines = (r) => (r.segments || []).filter(sg => sg.editions && sg.editions.bjt).map(sg => sg.segment + ' ' + sg.editions.bjt).join('\n');
    const a = lines(off), b = lines(on);
    expect(a && a === b, `editions offline: sn56.11 BJT ${a.split('\n').length} lines, ${a === b ? 'the same as the site' : 'DIFFERENT from the site (' + b.split('\n').length + ' lines there)'}`);
    expect(JSON.stringify(off.downloadedEditions || []).includes('bjt'), `downloadedEditions: ${JSON.stringify(off.downloadedEditions)}`);
  } else console.log('(no ed-bjt pack in the manifest: editions not checked)');
  // Default packs, no selection saved (Cakkhu's review 1): check and update must stay on packs, never the whole dg.db.gz.
  const keepSel = await call('update', { distBase: '/mobile-data', packsBase: PACKS });
  const onDisk = man0.packs.some(x => x.id === 'ed-bjt') ? '["root-ms","tr-ru","ed-bjt"]' : '["root-ms","tr-ru"]';   // the editions case added ed-bjt
  expect(JSON.stringify(keepSel.packs) === onDisk, `update with no selection keeps the packs on disk: ${JSON.stringify(keepSel.packs)}`);
  await call('update', { distBase: '/mobile-data', packs: [], packsBase: PACKS });
  const chk = await call('check', { distBase: '/mobile-data', packsBase: PACKS });
  expect(chk.current === true, `check with no selection: ${JSON.stringify(chk)}`);
  const upd0 = await call('update', { distBase: '/mobile-data', packsBase: PACKS });
  expect(JSON.stringify(upd0.packs) === '["root-ms"]' && !upd0.downloaded, `update with no selection stays on packs: ${JSON.stringify(upd0)}`);
  // Killed while unpacking (review 2): the archive is still beside the pack file. The next start must not adopt the
  // file; the next download unpacks the archive again.
  const man = await p.evaluate(async (u) => (await fetch(u + '/packs-manifest.json', { cache: 'no-store' })).json(), PACKS);
  const rm = man.packs.find(x => x.main);
  await p.evaluate(async ([u, name]) => {
    const buf = await (await fetch(u)).arrayBuffer();
    const fh = await (await navigator.storage.getDirectory()).getFileHandle(name, { create: true });
    const wr = await fh.createWritable(); await wr.write(buf); await wr.close();
  }, [new URL(rm.url, PACKS + '/').href, `dg-mobile.pack.${rm.id}.${rm.build_id}.gz.partial`]);
  await p.evaluate(() => window.restart());
  const reopened = await call('open', { distBase: '/mobile-data', download: false, packsBase: PACKS, packsOn: true });
  expect(reopened.present === false, `interrupted unpack is not adopted: ${JSON.stringify(reopened)}`);
  const t2 = Date.now();
  const again = await call('open', { distBase: '/mobile-data', download: true, packs: [], packsBase: PACKS, packsOn: true });
  const kac = await call('search', { q: 'kacchapa', langs: 'ru' });
  expect(again.present && kac.metadata.totalFiles > 0, `unpacked again in ${((Date.now() - t2) / 1000).toFixed(1)}s, search kacchapa ${kac.metadata.totalFiles} texts`);
  // Delete while a pack downloads (review 4): the download stops, nothing is left, the old set is not reopened.
  const pend = p.evaluate((P) => window.call('update', { distBase: '/mobile-data', packs: ['tr-en'], packsBase: P }).then(r => 'resolved ' + JSON.stringify(r), e => 'rejected ' + e.message), PACKS);
  await p.waitForTimeout(1500);
  console.log('delete during download:', JSON.stringify(await call('delete', { distBase: '/mobile-data' })));
  const upr = await pend;
  const st = await call('status', { distBase: '/mobile-data', wantManifest: false });
  expect(/rejected/.test(upr) && !st.present, `update ${upr.slice(0, 60)}; status ${JSON.stringify(st)}`);
  await p.evaluate(() => window.restart());
  const after = await call('open', { distBase: '/mobile-data', download: false, packsBase: PACKS, packsOn: true });
  expect(after.present === false, `after a restart nothing opens: ${JSON.stringify(after)}`);
  console.log('delete:', JSON.stringify(await call('delete', { distBase: '/mobile-data' })));
  console.log('status after delete:', JSON.stringify(await call('status', { distBase: '/mobile-data', wantManifest: false })));
  await b.close();
  console.log(bad ? `${bad} BAD` : 'all ok'); process.exitCode = bad ? 1 : 0;
})().catch(e => { console.log('FAIL', e.message); process.exit(1); });
