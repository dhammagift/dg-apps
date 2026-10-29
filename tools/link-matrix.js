// Every shape a link or a shared text takes into the site (and the app, which hands shares to the same ?q= page): the text
// it should open, or a search. Run before a dg-node rollout and a DG build: node tools/link-matrix.js https://test.dhamma.gift
const { chromium } = require('/usr/lib/node_modules/@playwright/cli/node_modules/playwright');
const q = (t) => '/?q=' + encodeURIComponent(t);
const CASES = [ // [path, expect: 'text:<id>' | 'search']
  ['/mn102:12.6', 'text:mn102'], ['/mn102%3A12.6', 'text:mn102'], ['/mn102%3a12.6', 'text:mn102'], ['/MN102:12.6', 'text:mn102'],
  ['/mn102#12.6', 'text:mn102'], [q('mn102:12.6'), 'text:mn102'], [q('"mn102:12.6"'), 'text:mn102'], [q('MN 102'), 'text:mn102'],
  [q('"mn102:12.6"\n https://sci.dhamma.gift/x#:~:text=mn102%3A12.6'), 'text:mn102'], [q('«mn102:12.6»'), 'text:mn102'],
  ['/sn56.11', 'text:sn56.11'], ['/sn56.11:1.1', 'text:sn56.11'], ['/SN56.11', 'text:sn56.11'], ['/sn%2056.11', 'text:sn56.11'],
  [q('SN 56.11'), 'text:sn56.11'], ['/ru/sn56.11', 'text:sn56.11'], ['/sn56.11?lang=ru', 'text:sn56.11'],
  ['/an1.9', 'text:an1.1-10'], ['/dhp5', 'text:dhp1-20'], ['/an1.1-10:3.1', 'text:an1.1-10'],
  ['/bu-pj1', 'text:bu-pj1'], ['/pli-tv-bu-vb-pj1:1.1', 'text:pli-tv-bu-vb-pj1'], ['/dn22:12.1', 'text:dn22'],
  [q('dn22 12.1'), 'any'], [q('„mn102:12.6“'), 'text:mn102'], [q('https://dhamma.gift/sn56.11?lang=ru'), 'text:sn56.11'], [q('Majjhima'), 'search'], ['/kacchapa', 'search'], ['/%D1%87%D0%B5%D1%80%D0%B5%D0%BF%D0%B0%D1%85%D0%B0', 'search'], [q('черепаха'), 'search'],
  [q('СН 22.104'), 'text:sn22.104'], [q('CH 22.104'), 'text:sn22.104'], [q('СH 22.104'), 'text:sn22.104'], ['/' + encodeURIComponent('МН 102'), 'text:mn102'], ['/CH%2022.104', 'text:sn22.104'],
  [q('"kacchapa"\nhttps://dhamma.gift/kacchapa'), 'search'], ['/mn102:12.6?lang=ru', 'text:mn102'], [q('https://dhamma.gift/mn102:12.6'), 'text:mn102'],
];
(async () => {
  const base = process.argv[2], b = await chromium.launch(); let bad = 0;
  for (const [path, want] of CASES) {
    const c = await b.newContext(); const p = await c.newPage();
    try { await p.goto(base + path, { waitUntil: 'domcontentloaded' }); } catch (e) {}
    await p.waitForTimeout(4500);
    const got = await p.evaluate(() => {
      const st = Array.from(document.body.classList).find((x) => /^dg-state-/.test(x)) || '';
      const art = document.querySelector('#sutta article'); const id = art && (art.id || (art.querySelector('[id]') || {}).id || '');
      return { st: st.replace('dg-state-', ''), id: (location.pathname.split('/').pop().split(/:|%3a/i)[0] || ''), url: location.pathname + location.search, has: !!(art && art.textContent.trim()) };
    }).catch((e) => ({ st: 'error', url: String(e).slice(0, 60) }));
    const ok = want === 'any' ? got.st !== 'error' : want === 'search' ? got.st === 'results' || got.st === 'home' : got.st === 'reader' && got.has && decodeURIComponent(got.url).toLowerCase().includes(want.slice(5).toLowerCase());
    if (!ok) bad++;
    console.log(`${ok ? 'ok  ' : 'BAD '} ${JSON.stringify(path).slice(0, 70).padEnd(72)} -> ${got.st} ${got.url}`);
    await c.close();
  }
  console.log(`${CASES.length - bad}/${CASES.length} ok`); await b.close(); process.exitCode = bad ? 1 : 0;
})();
