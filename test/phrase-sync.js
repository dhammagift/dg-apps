// Cloud sync by secret passphrase, end to end on the live site the app talks to (the app's sign-in page is the same
// page): two "devices" sign in with one phrase, what A changes B gets, and both sign out. No check covered sign-in at
// all (owner 2026-11-01: «только фраза... которую вы тоже не проверяете?»). Google and Apple need a real account and
// the app's registered signature, so they are not here.
// Usage: node test/phrase-sync.js [origin]   (default https://test.dhamma.gift)
const { chromium, devices } = require('/usr/lib/node_modules/@playwright/cli/node_modules/playwright');
const PHRASE = 'Dg-Check-Phrase-7419', URL = process.argv[2] || 'https://test.dhamma.gift';
const login = async (p) => {
  await p.goto(URL + '/login', { waitUntil: 'networkidle' });
  await p.fill('#sync-phrase-input', PHRASE); await p.click('#btn-phrase-login'); await p.waitForTimeout(1500);
  if (await p.isVisible('#btn-modal-merge')) await p.click('#btn-modal-merge');
  await p.waitForSelector('#sync-logged-in:not(.d-none)', { timeout: 20000 });
};
(async () => {
  const b = await chromium.launch(); let fail = 0;
  const A = await (await b.newContext({ ...devices['Pixel 7'] })).newPage(), B = await (await b.newContext({ ...devices['Pixel 7'] })).newPage();
  await login(A);
  const want = Math.random() < 0.5 ? 'columns' : 'lines';
  await A.evaluate((v) => localStorage.setItem('viewMode', v), want);
  await A.evaluate(() => forceSyncNow()); await A.waitForTimeout(4000);
  await login(B); await B.waitForTimeout(5000);
  const got = await B.evaluate(() => localStorage.getItem('viewMode'));
  const ok = got === want; if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'} phrase sync: A set viewMode=${want}, B signed in with the same phrase got ${got}`);
  for (const [n, p] of [['A', A], ['B', B]]) { await p.evaluate(() => syncLogout()); await p.waitForTimeout(2500);
    const out = await p.evaluate(() => !document.getElementById('sync-logged-out').classList.contains('d-none') && !localStorage.getItem('dg_cloud_session'));
    if (!out) fail++; console.log(`${out ? 'PASS' : 'FAIL'} phrase logout on ${n}`); }
  await b.close(); process.exit(fail ? 1 : 0);
})();
