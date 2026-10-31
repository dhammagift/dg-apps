// The offline packs the way a reader gets them (owner 2026-10-31: «сам попробуй перед тем, как говорить, что готово» - the
// worker-level packs-check passed while the site's own picker could not download a single pack): Settings -> the picker ->
// Buddha Jayanti ticked -> Download, then with the network off sn56.11 &editions=bjt must come from the device.
//   node tools/packs-ui-check.js [site]      (a fresh browser profile each run; exits 1 on a failure)
const { chromium, devices } = require('/usr/lib/node_modules/@playwright/cli/node_modules/playwright');
const BASE = process.argv[2] || 'https://test.dhamma.gift';
const PROFILE = require('fs').mkdtempSync(require('os').tmpdir() + '/packs-ui-');
(async () => {
  const c = await chromium.launchPersistentContext(PROFILE, { ...devices['Pixel 7'], colorScheme: 'dark' });
  const errs = [];
  c.on('console', m => /error|fail/i.test(m.type() + m.text()) && errs.push(m.text().slice(0, 200)));
  const p = c.pages()[0] || await c.newPage();
  await p.goto(BASE + '/settings/', { waitUntil: 'networkidle' });
  await p.waitForTimeout(2500);
  await p.click('#dgOfflineLibBtn'); await p.waitForTimeout(1200);
  // tick the Buddha Jayanti row
  const ticked = await p.evaluate(() => { const li = [...document.querySelectorAll('#pkDlg li')].find(l => /Buddha Jayanti|Будда Джаянти/.test(l.textContent)); const cb = li && li.querySelector('input[type=checkbox]'); if (!cb) return 'no row'; cb.click(); return 'ticked ' + cb.checked; });
  console.log('picker:', ticked, '| go:', await p.locator('#pkGo').textContent());
  await p.screenshot({ path: 'real-3-picker-bjt.png' });
  await p.click('#pkGo');
  let st = '';
  for (let i = 0; i < 24; i++) { await p.waitForTimeout(5000); st = await p.evaluate(() => localStorage.getItem('dg.offline.state') || ''); if (/ed-bjt/.test(st)) break; }
  console.log('state:', st.slice(0, 200));
  const pg = c.pages()[c.pages().length - 1];
  await c.setOffline(true);
  const r = await pg.evaluate(async () => { try { const j = await (await fetch('/api/text/sn56.11?langs=ru&editions=bjt')).json(); const segs = (j.segments || []).filter(s => s.editions && s.editions.bjt); return 'offline: ' + segs.length + ' BJT lines, downloadedEditions ' + JSON.stringify(j.downloadedEditions) + ', first: ' + (segs[0] ? segs[0].editions.bjt.slice(0, 60) : '-'); } catch (e) { return 'ERR ' + e.message; } });
  console.log(r);
  const ok = /^offline: [1-9]\d* BJT lines, downloadedEditions \["bjt"\]/.test(r) && /ed-bjt/.test(st);
  const r2 = await pg.evaluate(async () => { try { const res = await fetch('/api/text/sn56.11?langs=ru&editions=th'); return 'not downloaded (th) offline: HTTP ' + res.status; } catch (e) { return 'not downloaded (th) offline: ' + e.message; } });
  console.log(r2);
  await c.setOffline(false);
  await c.close();
  console.log('errors:', errs.filter(e => !/wake lock/i.test(e)).slice(0, 8).join(' || ') || 'none');
  console.log(ok ? 'all ok' : 'FAIL'); process.exitCode = ok ? 0 : 1;
})();
