// The dictionary's bundle has every file its two pages reference, and a missing one fails the build. No network, no browser.
//
//   node dict/test/bundle-files.js <ddg-ui dir> <dg-node dir>
//
// 1. bundle-from-repo.js lays both pages out from the checkouts;
// 2. read back from the bundle itself, every local src/href of each page (but <a>) and every url() of the stylesheets
//    resolves to a file of the bundle (relative paths as the browser resolves them; /ru/static/ is answered from /static/,
//    as the app does), and /ru/static/ is not a second copy;
// 3. the bundle stays small (a big file newly referenced by a script would ride into the APK unnoticed);
// 4. a page that references a file the checkout does not have makes the build fail, naming the file.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { bundle } = require('../tools/bundle-from-repo');

const [ddgUi, dgNode] = process.argv.slice(2).map((p) => path.resolve(p));
if (!ddgUi || !dgNode) { console.error('usage: node dict/test/bundle-files.js <ddg-ui dir> <dg-node dir>'); process.exit(2); }
const MAX_MB = 8;

let failed = 0;
function check(name, ok, detail) {
    if (!ok) failed++;
    console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}${ok || !detail ? '' : '\n       ' + detail}`);
}
// /ru/static/ is answered from /static/ by the app (DgSitePlugin.serve, DgSiteRouter).
const local = (ref, base) => (/^(?:[a-z]+:|\/\/|#)/i.test(ref) ? null : new URL(ref, 'http://x' + base).pathname.replace(/^\/ru\/static\//, '/static/'));
// The same dead references bundle-from-repo.js lets through (404 on the site too): jQuery UI's stock icon sprites.
const DEAD = /\/static\/images\/ui-icons_[0-9a-f]+_256x240\.png$/;

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'dict-bundle-'));
try {
    const out = path.join(tmp, 'snapshot');
    const urls = bundle(ddgUi, dgNode, out);
    check(`both pages are laid out (${urls.length} files)`, ['index.html', 'ru/index.html'].every((p) => fs.existsSync(path.join(out, p))));

    const missing = [];
    for (const page of ['/index.html', '/ru/index.html']) {
        const html = fs.readFileSync(path.join(out, page), 'utf8');
        for (const m of html.matchAll(/<(?!a[\s>])[a-z]+\b[^>]*?\s(?:src|href)="([^"?#]+)/gi)) {
            const u = local(m[1], page);
            if (u && !fs.existsSync(path.join(out, u))) missing.push(u + ' (' + page + ')');
        }
    }
    for (const css of urls.filter((u) => u.endsWith('.css'))) {
        for (const m of fs.readFileSync(path.join(out, css), 'utf8').matchAll(/url\(\s*['"]?([^'")?#]+)/g)) {
            const u = local(m[1], css);
            if (u && !DEAD.test(u) && !fs.existsSync(path.join(out, u))) missing.push(u + ' (' + css + ')');
        }
    }
    check('every file the pages and their stylesheets reference is in the bundle', !missing.length, missing.join(', '));
    check('the ru page\'s static/ is not a second copy', !fs.existsSync(path.join(out, 'ru/static')));
    check('no link is left in the bundle (Capacitor and the native lookup see real files)', urls.every((u) => !fs.lstatSync(path.join(out, u)).isSymbolicLink()));

    const bytes = urls.reduce((s, u) => s + fs.statSync(path.join(out, u)).size, 0);
    check(`the bundle is under ${MAX_MB} MB (${(bytes / 1048576).toFixed(2)} MB)`, bytes < MAX_MB * 1048576);

    // A ddg-ui of two pages, one with a stylesheet that is not there: the build must refuse it.
    const fake = path.join(tmp, 'ddg-ui');
    fs.mkdirSync(path.join(fake, 'public/ru'), { recursive: true });
    fs.writeFileSync(path.join(fake, 'public/index.html'), '<link rel="stylesheet" href="static/not-in-the-checkout.css">');
    fs.writeFileSync(path.join(fake, 'public/ru/index.html'), '<p>ru</p>');
    let error = '';
    try { bundle(fake, dgNode, path.join(tmp, 'fake-out')); } catch (e) { error = e.message; }
    check('a referenced file that is not in the checkout fails the build', /not-in-the-checkout\.css/.test(error), error || 'the build passed');
} catch (e) {
    check('bundle-from-repo', false, e.message);
} finally {
    fs.rmSync(tmp, { recursive: true, force: true });
}
console.log(failed ? `\n${failed} check(s) failed` : '\nall checks passed');
process.exit(failed ? 1 : 0);
