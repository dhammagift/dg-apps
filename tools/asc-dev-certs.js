#!/usr/bin/env node
// Frees the Apple Development certificate slots CI runs use up (dg-apps#40).
//
// Every iOS release job archives on a fresh macOS runner with automatic signing and the App Store
// Connect API key, so Xcode creates a new "Apple Development" certificate each time. Nothing ever
// revoked them, and once the team hit Apple's limit every TestFlight upload failed with "Your
// account has reached the maximum number of certificates" (owner: "это можно автоматизировать?").
// The archive only needs that certificate while it runs; what reaches TestFlight is re-signed for
// distribution at export, so revoking it afterwards costs nothing.
//
// Only certificates Xcode made through the API key are touched ("Created via API" in the name) —
// a person's own development certificate from their Mac never is.
//
//   node tools/asc-dev-certs.js prune             before the archive: revoke CI certificates older
//                                                 than 3 h (older runs; a parallel job keeps its own)
//   node tools/asc-dev-certs.js cleanup <epoch>   after the export: revoke CI certificates created
//                                                 since <epoch> (seconds) — this job's own
//
// Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (the .p8). Never fails the job: a problem here is
// printed as a warning and the archive either works anyway or fails with Apple's own message.
'use strict';
const crypto = require('crypto');
const fs = require('fs');

const API = 'https://api.appstoreconnect.apple.com/v1';
const YEAR_MS = 365 * 24 * 3600 * 1000;   // development certificates live one year
const KEEP_MS = 3 * 3600 * 1000;

function b64url(buf) { return Buffer.from(buf).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_'); }

function token() {
    const now = Math.floor(Date.now() / 1000);
    const head = b64url(JSON.stringify({ alg: 'ES256', kid: process.env.ASC_KEY_ID, typ: 'JWT' }));
    const body = b64url(JSON.stringify({ iss: process.env.ASC_ISSUER_ID, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' }));
    const sig = crypto.sign('sha256', Buffer.from(head + '.' + body), { key: fs.readFileSync(process.env.ASC_KEY_PATH, 'utf8'), dsaEncoding: 'ieee-p1363' });
    return head + '.' + body + '.' + b64url(sig);
}

async function main() {
    const [mode, since] = process.argv.slice(2);
    if (mode !== 'prune' && mode !== 'cleanup') throw new Error('usage: prune | cleanup <epoch-seconds>');
    const auth = { Authorization: 'Bearer ' + token() };
    const res = await fetch(API + '/certificates?filter[certificateType]=DEVELOPMENT,IOS_DEVELOPMENT&limit=200', { headers: auth });
    if (!res.ok) throw new Error('list: HTTP ' + res.status + ' ' + (await res.text()).slice(0, 300));
    const certs = (await res.json()).data || [];
    const now = Date.now();
    for (const c of certs) {
        const a = c.attributes || {};
        const label = a.name || a.displayName || '';
        const created = Date.parse(a.expirationDate) - YEAR_MS;
        const fromCi = /created via api/i.test(label + ' ' + (a.displayName || ''));
        const revoke = fromCi && (mode === 'prune' ? now - created > KEEP_MS : created >= Number(since) * 1000 - 60000);
        console.log(`${revoke ? 'revoke' : 'keep  '}  ${label}  (created ~${new Date(created).toISOString().slice(0, 16)})`);
        if (!revoke) continue;
        const del = await fetch(API + '/certificates/' + c.id, { method: 'DELETE', headers: auth });
        if (!del.ok) console.log('   ! HTTP ' + del.status + ' ' + (await del.text()).slice(0, 200));
    }
}

main().catch(e => { console.log('::warning::asc-dev-certs: ' + e.message); });
