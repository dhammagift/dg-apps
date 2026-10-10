// The shared site updater (src/site-updater.js) as the Dhamma.Gift app uses it: gate closed = nothing applied, changed file = DgSite.put,
// one failed fetch = nothing applied. Run: node test/site-updater.test.js
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const code = fs.readFileSync(path.join(__dirname, '..', 'src', 'site-updater.js'), 'utf8');

async function run({ gateOpen, failPath, manual, force = true }) {
    const puts = [], ls = {};
    const sha = async (text) => Buffer.from(await require('crypto').subtle.digest('SHA-256', Buffer.from(text))).toString('hex');
    const site = { '/read/js/voice.js': 'new voice', '/read/css/voice.css': 'same css' };
    const manifest = { files: Object.keys(site), hashes: { '/read/js/voice.js': await sha('old voice'), '/read/css/voice.css': await sha('same css') }, ids: ['a'] };
    const win = { __DG_APP_VERSION__: '1.0.1', crypto: require('crypto').webcrypto, addEventListener() {} };
    const fetchFn = async (url) => {
        if (url === '/site-manifest.json') return { ok: true, json: async () => manifest };
        const p = url.replace('https://dhamma.gift', '');
        if (p === failPath) throw new Error('offline');
        return { ok: true, status: 200, arrayBuffer: async () => new Uint8Array(Buffer.from(site[p])).buffer };
    };
    const body = new Function('Cap', 'store', 'SITE_CONFIG', 'window', 'document', 'navigator', 'fetch', 'localStorage', 'crypto', 'TextDecoder', 'btoa', 'console',
        code + '\nreturn updateSite;');
    const Cap = { Plugins: { DgSite: { put: async (o) => { puts.push(o.path); }, clear: async () => {} } } };
    const store = (k) => ls[k] || null;
    const localStorage = { setItem: (k, v) => { ls[k] = v; }, removeItem: (k) => { delete ls[k]; }, getItem: (k) => ls[k] || null };
    const config = { site: 'https://dhamma.gift', urlFor: (p) => p, silent: true, manual, gate: async () => gateOpen };
    const update = body(Cap, store, config, win, { addEventListener() {}, visibilityState: 'visible' }, { onLine: true }, fetchFn, localStorage,
        require('crypto').webcrypto, TextDecoder, (s) => Buffer.from(s, 'binary').toString('base64'), { log() {} });
    const res = await update(force);
    return { res, puts };
}

(async () => {
    let r = await run({ gateOpen: false });
    assert.deepStrictEqual(r.puts, [], 'gate closed: nothing applied');
    r = await run({ gateOpen: true });
    assert.deepStrictEqual(r.puts, ['/read/js/voice.js'], 'only the changed file is put');
    r = await run({ gateOpen: true, failPath: '/read/css/voice.css' });
    assert.deepStrictEqual(r.puts, [], 'a failed fetch: all or nothing');
    assert.strictEqual(r.res.state, 'failed');
    r = await run({ gateOpen: true, manual: true, force: false });
    assert.deepStrictEqual(r.puts, [], 'manual mode: a check nobody asked for fetches and applies nothing');
    r = await run({ gateOpen: true, manual: true, force: true });
    assert.deepStrictEqual(r.puts, ['/read/js/voice.js'], 'manual mode: the person asks, the changed file is put');
    console.log('site-updater: 5 checks passed');
})().catch((e) => { console.error(e); process.exit(1); });
