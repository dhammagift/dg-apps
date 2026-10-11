// Dictionary feature tour: the app driven the way a reader uses it, on a real emulator, one case after another, each
// case recorded as its own video (<out>/NN-name.mp4) with a screenshot at its end. Taps are real touches (adb input) on
// the elements' places on screen; the page is read over the WebView's DevTools socket, so this needs the DEBUG APK.
// Cases build on each other (the words looked up early are the history the shortcuts show later), so they run in order.
// A case fails on its own check or on a crash of the app in the log while it ran; the script fails if any case did.
//
//   node dict/test/emu-tour.js <debug apk> [out-dir]        (an emulator is up; Node 22+ for WebSocket)
const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const APK = process.argv[2];
const OUT = process.argv[3] || 'tour';
const PKG = 'gift.dhamma.pali';
if (!APK) { console.error('usage: node dict/test/emu-tour.js <debug apk> [out-dir]'); process.exit(2); }
fs.mkdirSync(OUT, { recursive: true });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const sh = (c, t = 60000) => { try { return execSync(c, { encoding: 'utf8', timeout: t, stdio: ['ignore', 'pipe', 'pipe'] }); } catch (e) { return (e.stdout || '') + (e.stderr || ''); } };
const adb = (a, t) => sh('adb ' + a, t);
const log = (s) => { console.log(s); fs.appendFileSync(path.join(OUT, 'log.txt'), s + '\n'); };

const [W, H] = (adb('shell wm size').match(/(\d+)x(\d+)\s*$/) || [0, 1080, 2400]).slice(1).map(Number);

// --- the page over DevTools -------------------------------------------------------------------------------------
let conn = null;   // { pid, ws, ev }
async function page() {
  const pid = adb(`shell pidof ${PKG}`).trim();
  if (!pid) throw new Error('the app is not running');
  if (conn && conn.pid === pid && conn.ws.readyState === 1) return conn;
  if (conn) try { conn.ws.close(); } catch (e) { /* gone */ }
  adb('forward --remove-all');
  adb(`forward tcp:9222 localabstract:webview_devtools_remote_${pid}`);
  let t = null;
  for (let i = 0; i < 20 && !t; i++) {
    try { t = (await (await fetch('http://127.0.0.1:9222/json')).json()).find((x) => x.type === 'page' && /localhost/.test(x.url)); } catch (e) { /* not up yet */ }
    if (!t) await sleep(1500);
  }
  if (!t) throw new Error('no page on the DevTools socket (a release APK has none)');
  log('  page: ' + t.url + (conn ? '' : ''));
  const ws = new WebSocket(t.webSocketDebuggerUrl);
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  let id = 0; const waiting = {};
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && waiting[d.id]) { waiting[d.id](d); delete waiting[d.id]; } };
  const send = (method, params) => new Promise((r) => { const i = ++id; waiting[i] = r; ws.send(JSON.stringify({ id: i, method, params })); setTimeout(() => { if (waiting[i]) { delete waiting[i]; r({ error: 'timeout' }); } }, 20000); });
  const ev = (expression) => send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true })
    .then((d) => (d.result && d.result.result ? d.result.result.value : undefined));
  conn = { pid, ws, ev, send };
  return conn;
}
const ev = async (js) => { try { return await (await page()).ev(js); } catch (e) { return undefined; } };
async function waitFor(js, sec = 10) {
  for (let i = 0; i < sec * 2; i++) { if (await ev(`Promise.resolve(${js}).then(function (v) { return !!v; }, function () { return false; })`)) return true; await sleep(500); }
  log('  not true after ' + sec + 's: ' + js);
  return false;
}
// Where the WebView starts on screen, from uiautomator (run 574: it sits under the status bar, 135 px down on the
// Pixel 7 image, and every tap aimed as if it began at 0 landed that much too high). Read again after a turn.
let wvTop = null, wvRot = null;
function webviewTop() {
  const rot = (adb('shell settings get system user_rotation').trim());
  if (wvTop !== null && wvRot === rot) return wvTop;
  adb('shell uiautomator dump /sdcard/wv.xml'); adb('pull /sdcard/wv.xml /tmp/tour-wv.xml');
  const xml = fs.existsSync('/tmp/tour-wv.xml') ? fs.readFileSync('/tmp/tour-wv.xml', 'utf8') : '';
  const m = xml.match(/class="android\.webkit\.WebView"[^>]*bounds="\[\d+,(\d+)\]/) || xml.match(/bounds="\[\d+,(\d+)\][^>]*class="android\.webkit\.WebView"/);
  wvTop = m ? +m[1] : 0; wvRot = rot;
  log('  the WebView starts at y=' + wvTop + (m ? '' : ' (not found in the dump, assumed)'));
  return wvTop;
}
// A real touch (adb input tap) on an element's centre. Screen px = CSS px x zoom x (screen width / innerWidth), the
// WebView filling the screen edge to edge. The page sets CSS zoom 110 % on <html>; an older WebView (113 on the CI
// image) gives getBoundingClientRect without that zoom, a newer one (128+) with it: the factor is innerWidth over the
// width <html> reports. (Runs 566-570, 2026-10-11: without it a tap on the menu button hit the history button next to it.)
async function tapEl(sel, nth = 0) {
  const c = await ev(`(function(){
    var el = document.querySelectorAll(${JSON.stringify(sel)})[${nth}]; if (!el) return null;
    el.scrollIntoView({ block: 'center' });
    var r = el.getBoundingClientRect(), f = innerWidth / document.documentElement.getBoundingClientRect().width;
    if (!window.__tourHook) { window.__tourHook = 1; addEventListener('pointerdown', function (e) { var t = e.target; window.__tourLast = { x: Math.round(e.clientX), y: Math.round(e.clientY), on: (t.id ? '#' + t.id : t.tagName) }; }, true); }
    return { x: r.left + r.width / 2, y: r.top + r.height / 2, f: f, iw: innerWidth };
  })()`);
  if (!c) { log('  nothing to tap: ' + sel); return false; }
  const k = (Math.abs(c.f - 1) < 0.02 ? 1 : c.f) * W / c.iw;
  const top = webviewTop();
  const sx = Math.round(c.x * k), sy = Math.round(top + c.y * k);
  adb(`shell input tap ${sx} ${sy}`);
  await sleep(700);
  // Where the touch landed, as the page saw it (pointerdown clientX/Y), next to where it was aimed: the log says
  // at once whether the mapping is off and by how much.
  const seen = await ev(`window.__tourLast ? JSON.stringify(window.__tourLast) : 'none'`);
  log(`  tap ${sel}: css ${Math.round(c.x)},${Math.round(c.y)} f=${c.f.toFixed(3)} iw=${c.iw} -> screen ${sx},${sy}; page saw ${seen}`);
  await ev(`window.__tourLast = null`);
  await sleep(800);
  return true;
}
// Native screen (launcher, shade, system dialogs): uiautomator.
function nativeNode(attr, rx) {
  adb('shell uiautomator dump /sdcard/ui.xml'); adb('pull /sdcard/ui.xml /tmp/tour-ui.xml');
  const xml = fs.existsSync('/tmp/tour-ui.xml') ? fs.readFileSync('/tmp/tour-ui.xml', 'utf8') : '';
  for (const m of xml.matchAll(/<node [^>]*>/g)) {
    const a = (m[0].match(new RegExp(attr + '="([^"]*)"')) || [])[1] || '';
    const b = m[0].match(/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/);
    if (b && new RegExp(rx).test(a)) return [(+b[1] + +b[3]) >> 1, (+b[2] + +b[4]) >> 1];
  }
  return null;
}
async function tapNative(attr, rx, hold) {
  const xy = nativeNode(attr, rx);
  if (!xy) { log('  nothing native to tap: ' + attr + ' ~ ' + rx); return false; }
  adb(hold ? `shell input swipe ${xy[0]} ${xy[1]} ${xy[0]} ${xy[1]} ${hold}` : `shell input tap ${xy[0]} ${xy[1]}`);
  await sleep(1500);
  return true;
}
const top = () => (adb('shell dumpsys activity activities').match(/(mResumedActivity|topResumedActivity).*/) || [''])[0];
const key = (k) => adb('shell input keyevent ' + k);
const typeAscii = (s) => adb(`shell input text '${s}'`);
const launch = async () => { adb(`shell monkey -p ${PKG} -c android.intent.category.LAUNCHER 1`); await sleep(6000); conn = null; };
const screen = () => ev(`document.body.dataset.screen`);
const word = () => ev(`(document.getElementById('whead-word') || {}).textContent`);
async function search(text) {   // the way a reader types: clear the box, tap it, type, Enter
  await ev(`(function(){ var b = document.getElementById('search-box'); b.value = ''; b.dispatchEvent(new Event('input', { bubbles: true })); })()`);
  for (let i = 0; i < 2; i++) {   // the box must have the focus, or the letters go to the page's keyboard shortcuts
    if (!(await tapEl('#search-box'))) return false;
    if (await ev(`document.activeElement === document.getElementById('search-box')`)) break;
    log('  the box did not take the focus, tapping again');
  }
  if (/^[\x20-\x7e]+$/.test(text)) typeAscii(text);
  else await (await page()).send('Input.insertText', { text });   // ā or Cyrillic: adb cannot type them
  await sleep(1200);
  key('KEYCODE_ENTER');
  return waitFor(`document.body.dataset.screen === 'entry'`, 15);
}
const net = (on) => { adb(`shell svc wifi ${on ? 'enable' : 'disable'}`); adb(`shell svc data ${on ? 'enable' : 'disable'}`); };
const menu = async () => (await tapEl('#menubtn')) && waitFor(`document.querySelector('#p-menu[data-open="true"]')`, 5);
const closeMenu = async () => { key('KEYCODE_BACK'); await sleep(1000); return waitFor(`!document.querySelector('.panel[data-open="true"]')`, 4); };
const clickText = (sel, rx) => ev(`(function(){ var l = [].filter.call(document.querySelectorAll(${JSON.stringify(sel)}), function (e) { return ${rx}.test(e.textContent.trim()); }); if (!l.length) return null; l[0].setAttribute('data-tour', '1'); return true; })()`)
  .then((ok) => ok && tapEl('[data-tour="1"]').then((r) => ev(`document.querySelector('[data-tour="1"]').removeAttribute('data-tour')`).then(() => r)));

// --- cases -------------------------------------------------------------------------------------------------------
const results = [];
let n = 0, lastFailed = false;
async function run(name, fn) {
  const id = String(++n).padStart(2, '0') + '-' + name;
  log('=== ' + id);
  adb('logcat -c');
  // After a failed case, start from the dictionary's start page (whatever it left open is gone; history stays). Not Esc:
  // Android treats it as Back, and two of them left the app.
  if (lastFailed) { adb(`shell am start -W -n ${PKG}/.MainActivity --es route /`); await sleep(4000); conn = null; }
  const rec = spawn('adb', ['shell', 'screenrecord', '--bit-rate', '2000000', '--time-limit', '170', '/sdcard/case.mp4'], { stdio: 'ignore' });
  await sleep(1000);
  let ok = false, why = '';
  try { ok = await fn(); if (!ok) why = 'check failed'; } catch (e) { why = 'error: ' + e.message; }
  await sleep(800);
  adb('shell pkill -INT screenrecord');
  await new Promise((r) => { rec.on('close', r); setTimeout(r, 6000); });
  await sleep(800);
  adb(`pull /sdcard/case.mp4 ${path.join(OUT, id + '.mp4')}`);
  sh(`adb exec-out screencap -p > ${path.join(OUT, id + '.png')}`);
  const lc = adb('logcat -d -v threadtime', 30000);
  fs.writeFileSync(path.join(OUT, id + '-logcat.txt'), lc);
  if (new RegExp(`FATAL EXCEPTION[\\s\\S]{0,400}Process: ${PKG.replace(/\./g, '\\.')}|ANR in ${PKG}`).test(lc)) { ok = false; why = (why ? why + '; ' : '') + 'crash/ANR in the log'; }
  const jsErr = (lc.match(/Capacitor\/Console.*(Uncaught|TypeError|ReferenceError|SyntaxError).*/g) || []).slice(0, 3);
  if (jsErr.length) log('  page errors: ' + jsErr.join(' | '));
  const line = (ok ? 'PASS ' : 'FAIL ') + id + (ok ? '' : ': ' + why);
  log(line); results.push(line); lastFailed = !ok;
}

(async () => {
  adb(`uninstall ${PKG}`);
  const inst = adb(`install -r ${APK}`, 120000);
  if (!/Success/.test(inst)) { log('install failed: ' + inst); process.exit(1); }
  log('webview: ' + (adb('shell dumpsys package com.google.android.webview').match(/versionName=\S+/) || ['?'])[0]);
  adb('shell settings put system accelerometer_rotation 0');
  adb('shell settings put secure show_ime_with_hard_keyboard 1');
  adb('shell settings put system show_touches 1'); adb('shell settings put system pointer_location 1');   // the videos show where each touch lands   // the soft keyboard (and the Pāli bar above it) shows

  await run('first-launch', async () => {
    await launch();
    if (!(await waitFor(`document.body.dataset.screen === 'start' && document.getElementById('search-box')`, 20))) return false;
    if (await ev(`!!document.querySelector('#dg-offline-invite:not([hidden])')`)) { log('  offline invite shown; answering "Not now"'); await tapEl('#dg-offline-invite-no'); }
    return true;
  });
  await run('search-velthuis', async () => {
    if (!(await tapEl('#search-box'))) return false;
    typeAscii('kacchapaa'); await sleep(1500);
    const v = await ev(`document.getElementById('search-box').value`);
    log('  typed kacchapaa, the box shows: ' + v);
    if (v !== 'kacchapā') return false;
    key('KEYCODE_ENTER');
    return (await waitFor(`document.body.dataset.screen === 'entry'`, 15)) && /kacchap/.test(await word());
  });
  await run('autocomplete', async () => {
    if (!(await tapEl('#search-box'))) return false;
    await ev(`(function(){ var b = document.getElementById('search-box'); b.value = ''; b.dispatchEvent(new Event('input', { bubbles: true })); })()`);
    typeAscii('dhamm'); await sleep(2000);
    if (!(await waitFor(`document.querySelector('ul.ui-autocomplete li.ui-menu-item')`, 8))) return false;
    const first = await ev(`document.querySelector('ul.ui-autocomplete li.ui-menu-item').textContent.trim()`);
    log('  first suggestion: ' + first);
    await tapEl('ul.ui-autocomplete li.ui-menu-item .ui-menu-item-wrapper');
    return (await waitFor(`document.body.dataset.screen === 'entry'`, 15)) && (await word()) === first;
  });
  await run('search-english', async () => (await search('tortoise')) && /tortoise/i.test((await word()) || ''));
  await run('search-russian', async () => (await search('черепаха')) && /черепаха/.test((await word()) || ''));
  await run('favorite-and-history', async () => {
    if (!(await search('sati'))) return false;
    await tapEl('#favbtn');
    if (!(await waitFor(`document.getElementById('favbtn').getAttribute('aria-pressed') === 'true'`, 4))) return false;
    if (!(await tapEl('#histbtn')) || !(await waitFor(`document.querySelector('#p-hist[data-open="true"]')`, 4))) return false;
    const lists = await ev(`JSON.stringify({ fav: [].map.call(document.querySelectorAll('#fav-list a[data-word]'), function (a) { return a.dataset.word; }), hist: [].map.call(document.querySelectorAll('#hist-list a[data-word]'), function (a) { return a.dataset.word; }) })`);
    log('  ' + lists);
    const l = JSON.parse(lists || '{}');
    const ok = (l.fav || []).includes('sati') && (l.hist || []).length >= 4;
    return (await closeMenu()) && ok;
  });
  await run('language-ru-en', async () => {
    if (!(await menu())) return false;
    if (!(await clickText('#p-menu .seg.big button', /^Ru$/))) return false;
    if (!(await waitFor(`document.documentElement.lang === 'ru'`, 15))) return false;
    sh(`adb exec-out screencap -p > ${path.join(OUT, 'ru.png')}`);
    if (!(await menu())) return false;
    if (!(await clickText('#p-menu .seg.big button', /^En$/))) return false;
    return waitFor(`document.documentElement.lang === 'en'`, 15);
  });
  await run('theme', async () => {
    if (!(await menu())) return false;
    await tapEl('#theme-seg button[data-theme="dark"]');
    if (!(await waitFor(`document.body.classList.contains('dark-mode')`, 4))) return false;
    sh(`adb exec-out screencap -p > ${path.join(OUT, 'dark.png')}`);
    await tapEl('#theme-seg button[data-theme="light"]');
    if (!(await waitFor(`!document.body.classList.contains('dark-mode')`, 4))) return false;
    await tapEl('#theme-seg button[data-theme="auto"]');
    return closeMenu();
  });
  await run('app-rows-and-update-check', async () => {
    if (!(await menu())) return false;
    const rows = await ev(`['#dg-shortcuts-row', '#dg-pali-row', '#dg-rate-row', '#dg-privacy-row', '#dg-version-row'].filter(function (s) { return !document.querySelector(s); }).join(',')`);
    if (rows) { log('  missing rows: ' + rows); return false; }
    log('  version row: ' + await ev(`document.querySelector('#dg-version-row').textContent.replace(/\\s+/g, ' ').trim()`));
    await tapEl('#dg-version-row');
    await waitFor(`/up to date|Update found|No connection|Could not check/.test(document.querySelector('#dg-version-row').textContent)`, 20);
    log('  after the check: ' + await ev(`document.querySelector('#dg-version-row em').textContent.trim()`));
    return closeMenu();
  });
  await run('launcher-shortcuts', async () => {
    key('KEYCODE_HOME'); await sleep(3000);
    const d = adb(`shell dumpsys shortcut ${PKG}`);
    fs.writeFileSync(path.join(OUT, 'shortcuts.txt'), d);
    const ids = [...new Set(d.match(/dg-dict-[\w-]+/g) || [])];
    log('  shortcuts: ' + ids.join(', '));
    if (ids.filter((x) => /^dg-dict-\d$/.test(x)).length < 3) return false;
    adb(`shell am start -W -n ${PKG}/.MainActivity -a ${PKG}.SHORTCUT --es route /kacchapa`); await sleep(5000); conn = null;
    return (await waitFor(`document.body.dataset.screen === 'entry'`, 15)) && /kacchapa/.test((await word()) || '');
  });
  await run('long-press-menu', async () => {
    key('KEYCODE_HOME'); await sleep(2000);
    for (let i = 0; i < 3 && !nativeNode('text', '^Dict\\.Dhamma\\.Gift$'); i++) { adb(`shell input swipe ${W >> 1} ${Math.round(H * 0.85)} ${W >> 1} ${Math.round(H * 0.2)} 300`); await sleep(2000); }
    if (!(await tapNative('text', '^Dict\\.Dhamma\\.Gift$', 1500))) return false;
    sh(`adb exec-out screencap -p > ${path.join(OUT, 'long-press.png')}`);
    if (!(await tapNative('text', '^sati$'))) return false;
    await sleep(4000); conn = null;
    return (await waitFor(`document.body.dataset.screen === 'entry'`, 15)) && (await word()) === 'sati';
  });
  await run('shortcuts-switch', async () => {
    await launch();
    if (!(await menu())) return false;
    await tapEl('#dg-shortcuts-toggle');
    await closeMenu(); key('KEYCODE_HOME'); await sleep(3000);
    const off = adb(`shell dumpsys shortcut ${PKG}`);
    const ok = /dg-dict-programmed-/.test(off);
    log('  switch off -> programmed shortcuts: ' + ok);
    await launch(); await menu(); await tapEl('#dg-shortcuts-toggle'); await closeMenu();
    return ok;
  });
  await run('find-on-page', async () => {
    if (!(await search('kacchapa'))) return false;
    if (!(await menu())) return false;
    if (!(await tapEl('#p-menu .mrow.first'))) return false;
    if (!(await waitFor(`document.querySelector('.dg-find-panel') && !document.querySelector('.dg-find-panel').hidden`, 6))) return false;
    typeAscii('kacch'); await sleep(1500);
    const c = await ev(`(document.querySelector('.dg-find-count') || {}).textContent`);
    log('  matches: ' + c);
    key('KEYCODE_BACK'); await sleep(1000);
    return !/^0\/0$/.test(c || '0/0') && (await waitFor(`document.querySelector('.dg-find-panel').hidden`, 4));
  });
  await run('pali-letters-bar', async () => {
    if (!(await tapEl('#search-box'))) return false;
    await ev(`(function(){ var b = document.getElementById('search-box'); b.value = 'kacchap'; b.dispatchEvent(new Event('input', { bubbles: true })); })()`);
    if (!(await waitFor(`document.querySelector('#dg-pali.on')`, 8))) return false;
    if (!(await clickText('#dg-pali button', /^ā$/))) return false;
    const v = await ev(`document.getElementById('search-box').value`);
    log('  box after tapping ā: ' + v);
    key('KEYCODE_BACK');
    return /ā$/.test(v || '');
  });
  await run('share-word', async () => {
    adb(`shell am start -W -a android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT kacchapa -n ${PKG}/.MainActivity`); await sleep(5000); conn = null;
    return (await waitFor(`document.body.dataset.screen === 'entry'`, 15)) && /kacchapa/.test((await word()) || '');
  });
  await run('text-selection', async () => {
    adb(`shell am start -W -a android.intent.action.PROCESS_TEXT -t text/plain --es android.intent.extra.PROCESS_TEXT dhamma -n ${PKG}/.ProcessTextActivity`); await sleep(5000); conn = null;
    return (await waitFor(`document.body.dataset.screen === 'entry'`, 15)) && /dhamma/.test((await word()) || '');
  });
  await run('quick-settings-tile', async () => {
    const comp = `${PKG}/.DgDictTileService`;
    adb(`shell cmd statusbar add-tile ${comp}`); await sleep(2500);
    if (nativeNode('text', '^[Aa]dd tile$')) await tapNative('text', '^[Aa]dd tile$');
    adb('shell cmd statusbar expand-settings'); await sleep(2500);
    sh(`adb exec-out screencap -p > ${path.join(OUT, 'tile-shade.png')}`);
    adb(`shell cmd statusbar click-tile ${comp}`); await sleep(5000); conn = null;
    log('  ' + top());
    return /gift\.dhamma\.pali/.test(top()) && (await waitFor(`document.body.dataset.screen === 'start'`, 15));
  });
  await run('offline-dictionary', async () => {
    if (!(await menu())) return false;
    await tapEl('#offline-dl-btn');
    if (!(await waitFor(`window.dgOffline && dgOffline.state().then(function (s) { return s === 'ready'; })`, 90))) return false;
    await closeMenu();
    net(false); await sleep(3000);
    let ok = await waitFor(`document.body.classList.contains('is-offline') || !navigator.onLine`, 15);
    ok = ok && (await search('kacchapa')) && (await waitFor(`document.querySelector('#dpd-results ul.offline-dpd-list')`, 10));
    log('  offline result: ' + await ev(`(document.querySelector('#dpd-results') || {}).textContent.slice(0, 120)`));
    net(true); await sleep(3000);
    return ok;
  });
  await run('no-connection-page', async () => {
    net(false); await sleep(3000);
    adb(`shell am start -W -n ${PKG}/.MainActivity --es route /mn1.1`); await sleep(6000); conn = null;
    const shown = await waitFor(`document.getElementById('dglsErr')`, 15);
    log('  ' + await ev(`(document.getElementById('dglsErr') || {}).textContent`));
    key('KEYCODE_BACK'); await sleep(2000);
    net(true); await sleep(3000);
    return shown;
  });
  await run('rotate', async () => {
    adb('shell settings put system user_rotation 1'); await sleep(4000);
    sh(`adb exec-out screencap -p > ${path.join(OUT, 'landscape.png')}`);
    adb('shell settings put system user_rotation 0'); await sleep(4000);
    const s = await ev(`window.visualViewport ? visualViewport.scale : 1`);
    log('  viewport scale after turning back: ' + s);
    return Math.abs((s || 1) - 1) < 0.03;
  });
  await run('back-button', async () => {
    await launch();
    if (!(await search('metta'))) return false;
    if (!(await menu())) return false;
    key('KEYCODE_BACK'); await sleep(1200);
    if (!(await waitFor(`!document.querySelector('.panel[data-open="true"]') && document.body.dataset.screen === 'entry'`, 4))) return false;   // the panel closes, the word stays
    key('KEYCODE_BACK'); await sleep(1500);
    log('  after Back from the word: ' + await screen() + ' ' + (await word()));
    for (let i = 0; i < 8 && /gift\.dhamma\.pali/.test(top()); i++) { key('KEYCODE_BACK'); await sleep(1500); }
    return !/gift\.dhamma\.pali/.test(top());   // Back from the start screen leaves the app
  });
  await run('clear-history', async () => {
    await launch();
    if (!(await menu())) return false;
    await tapEl('#clear-history-button');
    const ok = await waitFor(`!document.querySelector('#hist-list a[data-word]') && !document.querySelector('#fav-list a[data-word]')`, 5);
    await closeMenu();
    return ok;
  });

  fs.writeFileSync(path.join(OUT, 'results.txt'), results.join('\n') + '\n');
  console.log('\n' + results.join('\n'));
  const failed = results.filter((r) => r.startsWith('FAIL')).length;
  if (failed) { console.log(`::error::${failed} dictionary case(s) failed, see ${OUT}/results.txt`); process.exit(1); }
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
