// Reader toolbar icons stay what they are after the toggles (owner, 2026-10-10/12, APKs 533/601: after a tap on the
// dictionary or variants toggle the eye, columns, multi-select and compass icons all showed table-list.svg). dg-node 4cb77c7
// draws them as inline SVG; this checks that in the app's WebView: every icon is an inline copy of the file its <img> names,
// before and after each toggle, with the Voice player open as in the owner's screenshot. A screenshot after each step.
// Debug APK only (DevTools socket on tcp:9222).
//
//   node tools/emu-icons.js <out-dir>
const fs = require('fs');
const { execSync } = require('child_process');
const OUT = process.argv[2] || 'shots';
const res = [];
const say = (s) => { console.log(s); res.push(s); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failed = false;
const check = (ok, text) => { say((ok ? 'PASS ' : 'FAIL ') + text); if (!ok) failed = true; };
const rawShot = (name) => fs.writeFileSync(`${OUT}/icons-${name}.png`, execSync('adb exec-out screencap -p', { maxBuffer: 64 << 20 }));

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
  // Each toolbar icon: the file its <img> names, whether the <img> is hidden, and whether the inline copy is that file's SVG
  // (same path data as the file fetched now) and on screen.
  const icons = async () => JSON.parse(await ev(`(async function(){
    var out = [];
    for (var img of document.querySelectorAll('#reader-toolbar > a > img')) {
      var src = img.getAttribute('src'), box = img.nextElementSibling, svg = box && box.classList.contains('dg-ic') && box.querySelector('svg');
      var file = await (await fetch(src)).text();
      var d = svg ? Array.from(svg.querySelectorAll('path,circle')).map(function (p) { return p.getAttribute('d') || p.getAttribute('cx'); }).join('|') : '';
      var want = Array.from(new DOMParser().parseFromString(file, 'image/svg+xml').querySelectorAll('path,circle')).map(function (p) { return p.getAttribute('d') || p.getAttribute('cx'); }).join('|');
      var r = box ? box.getBoundingClientRect() : { width: 0, height: 0 };
      out.push({ file: src.replace(/^.*\\//, '').replace(/\\?.*/, ''), imgHidden: getComputedStyle(img).display === 'none', inline: !!svg, same: !!svg && d === want, size: Math.round(r.width) + 'x' + Math.round(r.height) });
    }
    return JSON.stringify(out);
  })()`));
  const verify = async (step) => {
    const list = await icons();
    say(step + ': ' + list.map((i) => i.file + (i.same ? '' : ' (WRONG)')).join(', '));
    check(list.length >= 5, step + ': the toolbar has its icons (' + list.length + ')');
    list.forEach((i) => check(i.inline && i.same && i.imgHidden && i.size !== '0x0', step + ': ' + i.file + ' is drawn inline from its own file (' + i.size + ')'));
    return list;
  };
  // The header hides while the page scrolls under the reader: back to the top so the toolbar is in the picture.
  const shot = async (name) => { await ev(`window.scrollTo(0, 0)`); await sleep(1800); rawShot(name); };
  const click = (sel) => ev(`(function(){ var b = document.querySelector(${JSON.stringify(sel)}); if (!b) return 'no ${sel}'; b.click(); return 'clicked'; })()`);

  await ev(`location.assign('/pli-tv-bu-pm')`); await sleep(12000);
  await shot('1-reader'); await verify('reader');
  say('voice: ' + await click('.voice-link')); await sleep(5000);
  // Paused, the player stays open and the page stops scrolling along (the owner's screenshot had it open).
  say('pause: ' + await click('.play-main-button')); await sleep(1500);
  await shot('2-voice-open'); await verify('voice open');
  say('dictionary: ' + await click('#reader-toolbar .toggle-dict-btn')); await sleep(2500);
  await shot('3-dictionary-toggled'); const a = await verify('dictionary toggled');
  say('dictionary: ' + await click('#reader-toolbar .toggle-dict-btn')); await sleep(2500);
  await shot('4-dictionary-back'); const b = await verify('dictionary back');
  check(a.find((i) => /^comment/.test(i.file)).file !== b.find((i) => /^comment/.test(i.file)).file, 'the dictionary icon itself changes with the toggle');
  say('variants: ' + await click('#toggle-variants')); await sleep(2500);
  await shot('5-variants-toggled'); await verify('variants toggled');
  say('variants: ' + await click('#toggle-variants')); await sleep(2500);
  await shot('6-variants-back'); await verify('variants back');
  say('scroll'); await ev(`window.scrollBy(0, 1500)`); await sleep(1500); await ev(`window.scrollBy(0, -1500)`); await sleep(2000);
  await shot('7-after-scroll'); await verify('after a scroll');
  await ev(`typeof stopPlayback === 'function' && stopPlayback()`);
  fs.writeFileSync(`${OUT}/icons-result.txt`, res.join('\n') + '\n');
  ws.close();
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.log('FAIL ' + e.message); fs.writeFileSync(`${OUT}/icons-result.txt`, res.join('\n') + '\nFAIL ' + e.message + '\n'); process.exit(1); });
