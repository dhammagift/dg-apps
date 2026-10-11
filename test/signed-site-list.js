// For the bundle browser tests: the site's signed /app-site-manifest.json (what dg-node scripts/site-manifest.js serves),
// signed with a throwaway P-256 key. The page gets the public half through the updater's test hook (window.__dgSiteKey,
// set by an init script before the bridge runs; honoured on 127.0.0.1 only, see src/site-updater.js).
const crypto = require('crypto');

function siteSigner() {
    const key = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
    const pub = key.publicKey.export({ type: 'spki', format: 'der' }).toString('base64');
    return {
        initScript: `window.__dgSiteKey = ${JSON.stringify(pub)};`,
        // hashes: { site path: sha256 }; the site's commit is a minute later than now, so it is newer than any bundle built before.
        envelope(origin, hashes) {
            const text = JSON.stringify({ origin, commit: 'feedbeef', commitTime: Math.floor(Date.now() / 1000) + 60, contains: [], hashes });
            return JSON.stringify({ signed: text, sig: crypto.sign('sha256', Buffer.from(text), { key: key.privateKey, dsaEncoding: 'ieee-p1363' }).toString('base64') });
        },
    };
}

const sha256 = (body) => crypto.createHash('sha256').update(body).digest('hex');

module.exports = { siteSigner, sha256 };
