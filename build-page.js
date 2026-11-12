// Generates www/index.html from dg-node's search/index.html.
//
// This script is the reason the app's main page can stop being a hand-made copy. It used to be
// copied by hand — build-assets.js's header referenced a "build-page.js" that was never written —
// and by the time the app moved out of dg-node that copy had drifted 147 lines behind the site,
// of which only 4 were intentional. Every one of the other ~143 was a site fix the app shipped
// without.
//
// The real delta between the site's page and the app's page is exactly two edits:
//
//   1. three <script> tags at the very top of <head> — app.js must install its fetch shim before
//      any other script on the page can issue a request, and native-bridge/offline-status hook
//      external links and download progress;
//   2. the service-worker registration block is dropped — there is no dg-light.js here to serve
//      /sw.js, and a SW would only compete with app.js's own fetch interception.
//
// Both are applied here, declaratively, so the page can never drift again.
//
// Anchors: if dg-node's search/index.html carries a `<!-- dg:app-scripts -->` marker we insert
// there; otherwise we insert right after <head>. The marker is the preferred form (it makes the
// insertion point explicit on the site's side) but is deliberately NOT required, so this repo
// builds against an unmodified dg-node checkout.
//
// Usage: node build-page.js

const fs = require('fs');
const path = require('path');
const { WWW, requireNodeRoot, f } = require('./paths');

const { makeAppPage } = require('./src/page-transforms');

function main() {
    requireNodeRoot();
    const src = f('search/index.html');
    let html = fs.readFileSync(src, 'utf8');
    const before = html.length;

    html = makeAppPage(html);

    fs.mkdirSync(WWW, { recursive: true });
    const dest = path.join(WWW, 'index.html');
    fs.writeFileSync(dest, html, 'utf8');
    console.log(`Page: ${path.relative(process.cwd(), dest)} <- ${src} (${before} -> ${html.length} bytes)`);
}

main();
