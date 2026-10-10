// The shared site updater (src/site-updater.js) as the apps use it: nothing is taken without a good signature on the site's
// list, from a site that is not newer than the bundle, or whose bytes differ from the list; a write that fails takes the
// round back; the boot guard counts starts of the app, not page loads. Run: node test/site-updater.test.js
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const nodeCrypto = require('crypto');

const KEY = nodeCrypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
const OTHER = nodeCrypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
const PUB = KEY.publicKey.export({ type: 'spki', format: 'der' }).toString('base64');
const code = fs.readFileSync(path.join(__dirname, '..', 'src', 'site-updater.js'), 'utf8')
    .replace(/var SITE_PUBLIC_KEY = '[^']+'/, `var SITE_PUBLIC_KEY = '${PUB}'`);
const sha = (text) => nodeCrypto.createHash('sha256').update(text).digest('hex');
const ORIGIN = 'https://dhamma.gift';

function signed(list, key = KEY.privateKey) {
    const text = JSON.stringify(list);
    return { signed: text, sig: nodeCrypto.sign('sha256', Buffer.from(text), { key, dsaEncoding: 'ieee-p1363' }).toString('base64') };
}

function page({ ls = {}, ss = {}, plugin, fetchFn, config = {}, readyState = 'complete' }) {
    const timers = [], docListeners = {};
    const win = { __DG_APP_VERSION__: ls.dgAppVersion || '1.0.1', crypto: nodeCrypto.webcrypto, addEventListener() {} };
    const localStorage = { setItem: (k, v) => { ls[k] = String(v); }, removeItem: (k) => { delete ls[k]; }, getItem: (k) => (k in ls ? ls[k] : null) };
    const sessionStorage = { setItem: (k, v) => { ss[k] = String(v); }, removeItem: (k) => { delete ss[k]; }, getItem: (k) => (k in ss ? ss[k] : null) };
    const document = { readyState, visibilityState: 'visible', addEventListener: (t, f) => { (docListeners[t] = docListeners[t] || []).push(f); } };
    const body = new Function('Cap', 'store', 'SITE_CONFIG', 'window', 'document', 'navigator', 'fetch', 'localStorage', 'sessionStorage', 'crypto',
        'TextDecoder', 'TextEncoder', 'btoa', 'atob', 'console', 'setTimeout', code + '\nreturn updateSite;');
    const update = body({ Plugins: { DgSite: plugin } }, (k) => localStorage.getItem(k),
        Object.assign({ site: ORIGIN, urlFor: (p) => p, silent: true }, config), win, document, { onLine: true }, fetchFn,
        localStorage, sessionStorage, nodeCrypto.webcrypto, TextDecoder, TextEncoder, (s) => Buffer.from(s, 'binary').toString('base64'),
        (s) => Buffer.from(s, 'base64').toString('binary'), { log() {} }, (f, ms) => { timers.push(f); return timers.length; });
    return { update, ls, ss, timers, hide: () => { document.visibilityState = 'hidden'; (docListeners.visibilitychange || []).forEach((f) => f()); } };
}

function dgPlugin(log, { failPut = 0 } = {}) {
    let puts = 0;
    return {
        put: async (o) => { if (++puts === failPut) throw new Error('ENOSPC'); log.push('put ' + o.path); },
        commit: async () => { log.push('commit'); }, discard: async () => { log.push('discard'); },
        apply: async () => { log.push('apply'); }, clear: async () => { log.push('clear'); },
    };
}

async function check({ siteFiles, list, env, bundleCommit = 'b0', bundleTime = 1000, gateOpen = true, failPath, plugin, manual, force = true, ls = { dgAppVersion: '1.0.1' } }) {
    const log = [];
    const bundleFiles = { '/read/js/voice.js': 'old voice', '/read/css/voice.css': 'same css' };
    const site = siteFiles || { '/read/js/voice.js': 'new voice', '/read/css/voice.css': 'same css' };
    const hashes = {};
    for (const [p, t] of Object.entries(site)) hashes[p] = sha(t);
    const theList = list || { origin: ORIGIN, commit: 'c2', commitTime: 2000, contains: ['c2', 'c1', 'b0'], hashes };
    const bundle = { files: Object.keys(bundleFiles), hashes: Object.fromEntries(Object.entries(bundleFiles).map(([p, t]) => [p, sha(t)])), ids: ['a'] };
    if (bundleCommit) bundle.commit = bundleCommit; else bundle.built = new Date(bundleTime * 1000).toISOString();
    const fetchFn = async (url) => {
        log.push('fetch ' + url.replace(ORIGIN, ''));
        if (url === '/site-manifest.json') return { ok: true, json: async () => bundle };
        if (url === ORIGIN + '/app-site-manifest.json') return env === null ? { ok: false, status: 404 } : { ok: true, json: async () => env || signed(theList) };
        const p = url.replace(ORIGIN, '');
        if (p === failPath) throw new Error('offline');
        const served = (failPath === 'tamper:' + p) ? 'tampered' : site[p];
        return { ok: true, status: 200, arrayBuffer: async () => new Uint8Array(Buffer.from(served)).buffer };
    };
    const pg = page({ ls, plugin: plugin ? plugin(log) : dgPlugin(log), fetchFn, config: { manual, gate: async () => gateOpen } });
    const res = await pg.update(force);
    return { res, log, ls: pg.ls };
}

(async () => {
    let r = await check({ gateOpen: false });
    assert.ok(!r.log.some((l) => l.startsWith('put')), 'gate closed: nothing applied');

    r = await check({});
    assert.deepStrictEqual(r.log.filter((l) => /^(put|commit|fetch \/read)/.test(l)), ['fetch /read/js/voice.js', 'put /read/js/voice.js', 'commit'],
        'only the changed file is fetched (the list says the css is the same) and stored, then committed');
    assert.strictEqual(r.res.state, 'new');
    assert.strictEqual(r.ls.dgSiteFresh, 'pending', 'serving from the next start');
    assert.ok(r.ls.dgSiteCheckedAt, 'a complete check is stamped');

    r = await check({ failPath: '/read/js/voice.js' });
    assert.ok(!r.log.some((l) => l.startsWith('put')), 'a failed fetch: all or nothing');
    assert.strictEqual(r.res.state, 'failed');
    assert.ok(!r.ls.dgSiteCheckedAt, 'a failed check is not stamped');

    r = await check({ manual: true, force: false });
    assert.deepStrictEqual(r.log, [], 'manual mode: a check nobody asked for fetches nothing');
    r = await check({ manual: true, force: true });
    assert.ok(r.log.includes('put /read/js/voice.js'), 'manual mode: the person asks, the changed file is put');

    r = await check({ env: { signed: JSON.stringify({ origin: ORIGIN, commitTime: 2000, hashes: {} }) } });
    assert.ok(!r.log.some((l) => /^(put|fetch \/read)/.test(l)) && r.res.state === 'failed', 'an unsigned list: nothing');
    r = await check({ env: null });
    assert.ok(!r.log.some((l) => /^(put|fetch \/read)/.test(l)) && r.res.state === 'failed', 'no list on the site: nothing');
    const sh = { '/read/js/voice.js': sha('new voice'), '/read/css/voice.css': sha('same css') };
    r = await check({ env: signed({ origin: ORIGIN, commit: 'x', commitTime: 2000, hashes: sh }, OTHER.privateKey) });
    assert.ok(!r.log.some((l) => /^(put|fetch \/read)/.test(l)) && r.res.state === 'failed', 'signed with another key: nothing');
    r = await check({ list: { origin: 'https://test.dhamma.gift', commit: 'x', commitTime: 2000, hashes: sh } });
    assert.ok(!r.log.some((l) => /^(put|fetch \/read)/.test(l)) && r.res.state === 'failed', "another site's list: nothing");
    r = await check({ bundleCommit: 'c2' });
    assert.ok(!r.log.some((l) => /^(put|fetch \/read)/.test(l)) && r.res.state === 'current', 'the site is at the bundle\'s own commit: nothing');
    r = await check({ bundleCommit: 'f9' });
    assert.ok(!r.log.some((l) => /^(put|fetch \/read)/.test(l)) && r.res.state === 'current', 'the site does not descend from the bundle (it is older or elsewhere): nothing');
    r = await check({ bundleCommit: null, bundleTime: 1000 });
    assert.ok(r.log.includes('put /read/js/voice.js'), 'no commit in the bundle (Dict, Uposatha): a site commit after the build is newer');
    r = await check({ bundleCommit: null, bundleTime: 2000 });
    assert.ok(!r.log.some((l) => /^(put|fetch \/read)/.test(l)), 'no commit in the bundle: a site commit before the build is not newer');
    r = await check({ bundleCommit: null, bundleTime: 0 });
    assert.ok(!r.log.some((l) => /^(put|fetch \/read)/.test(l)), 'a bundle of unknown age: nothing');
    r = await check({ failPath: 'tamper:/read/js/voice.js' });
    assert.ok(!r.log.some((l) => l.startsWith('put')) && r.res.state === 'failed', 'bytes that differ from the signed list: nothing');

    // Two changed files, the second write fails: the round is taken back.
    const two = { '/read/js/voice.js': 'new voice', '/read/css/voice.css': 'new css' };
    r = await check({ siteFiles: two, plugin: (log) => dgPlugin(log, { failPut: 2 }) });
    assert.ok(r.log.includes('discard') && !r.log.includes('commit'), 'Dhamma.Gift: the kept-apart round is discarded');
    assert.ok(!r.ls.dgSiteHashes && r.res.state === 'failed', 'nothing recorded as applied');
    r = await check({ siteFiles: two, plugin: (log) => { let n = 0; return { put: async (o) => { if (++n === 2) throw new Error('ENOSPC'); log.push('put ' + o.path); }, clear: async () => { log.push('clear'); } }; } });
    assert.ok(r.log.includes('clear'), 'a DgSite without rounds (Dict, Uposatha): everything downloaded goes');

    // The boot guard: loads within one run of the app are one start; three starts that never ran for a few seconds roll back.
    const log = [];
    const ls = { dgSiteFresh: 'pending', dgAppVersion: '1.0.1' };
    const noFetch = async () => { throw new Error('no network in this test'); };
    let ss = {};
    for (let i = 0; i < 5; i++) page({ ls, ss, plugin: dgPlugin(log), fetchFn: noFetch, readyState: 'loading' });   // a run with reloads, all < 4 s
    assert.strictEqual(ls.dgSiteBoots, '1', 'five page loads in one run are one start');
    ss = {}; page({ ls, ss, plugin: dgPlugin(log), fetchFn: noFetch, readyState: 'loading' });
    assert.strictEqual(ls.dgSiteBoots, '2');
    ss = {}; const run3 = page({ ls, ss, plugin: dgPlugin(log), fetchFn: noFetch, readyState: 'loading' });
    await new Promise((res) => setImmediate(res));
    assert.ok(log.includes('clear') && ls.dgSiteBroke === '1', 'the third start that never settled puts the bundle back');
    void run3;

    const ls2 = { dgSiteFresh: 'pending', dgAppVersion: '1.0.1' }, log2 = [];
    const ok = page({ ls: ls2, ss: {}, plugin: dgPlugin(log2), fetchFn: noFetch });
    ok.timers.forEach((f) => f());   // the page ran for a few seconds
    assert.strictEqual(ls2.dgSiteFresh, '0', 'a page that ran for a few seconds proves the files');
    const ls3 = { dgSiteFresh: '1', dgSiteBoots: '1', dgAppVersion: '1.0.1' };
    page({ ls: ls3, ss: {}, plugin: dgPlugin([]), fetchFn: noFetch, readyState: 'loading' }).hide();
    assert.strictEqual(ls3.dgSiteFresh, '0', 'leaving the app (hidden) proves them too');

    console.log('site-updater: all checks passed');
})().catch((e) => { console.error(e); process.exit(1); });
