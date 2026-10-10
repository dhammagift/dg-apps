// The calendar's bundle has every file its page references, and a missing one fails the build. No network, no browser.
//
//   node uposatha/test/bundle-files.js <dg-node dir>
//
// 1. bundle-from-repo.js lays the page out from the checkout (dg-node's scripts/uposatha-files.js lists the files);
// 2. read back from the bundle itself, every src/href of the page (but <a>) and every url() of its stylesheets is there;
// 3. the bundle stays small: a shared script that starts naming a big file for another page (the offline dictionary is
//    25 MB) would otherwise ride into the APK unnoticed — add it to SKIP in dg-node's uposatha-files.js;
// 4. a page that references a file the checkout does not have makes the build fail, naming the file.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { bundle } = require('../tools/bundle-from-repo');

const dgNode = path.resolve(process.argv[2] || process.env.DG_NODE_PATH || '');
if (!process.argv[2] && !process.env.DG_NODE_PATH) { console.error('usage: node uposatha/test/bundle-files.js <dg-node dir>'); process.exit(2); }
const MAX_MB = 8;

let failed = 0;
function check(name, ok, detail) {
    if (!ok) failed++;
    console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}${ok || !detail ? '' : '\n       ' + detail}`);
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'upo-bundle-'));
try {
    const out = path.join(tmp, 'snapshot');
    const count = bundle(dgNode, out);
    check(`the page is laid out (${count} files)`, fs.existsSync(path.join(out, 'uposatha-calendar.html')));

    const missing = [];
    const html = fs.readFileSync(path.join(out, 'uposatha-calendar.html'), 'utf8');
    for (const m of html.matchAll(/<(?!a[\s>])[a-z]+\b[^>]*?\s(?:src|href)="(\/(?!\/)[^"?#]*)/gi)) {
        if (!fs.existsSync(path.join(out, m[1]))) missing.push(m[1] + ' (page)');
    }
    const walk = (d) => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(path.join(d, e.name)) : [path.join(d, e.name)]));
    const all = walk(out);
    for (const css of all.filter((f) => f.endsWith('.css'))) {
        for (const m of fs.readFileSync(css, 'utf8').matchAll(/url\(\s*['"]?(\/(?!\/)[^'")?#]+)/g)) {
            if (!fs.existsSync(path.join(out, m[1]))) missing.push(m[1] + ' (' + path.relative(out, css) + ')');
        }
    }
    check('every file the page and its stylesheets reference is in the bundle', !missing.length, missing.join(', '));

    const bytes = all.reduce((s, f) => s + fs.statSync(f).size, 0);
    const biggest = all.sort((a, b) => fs.statSync(b).size - fs.statSync(a).size).slice(0, 5).map((f) => path.relative(out, f) + ' ' + (fs.statSync(f).size / 1048576).toFixed(2) + ' MB');
    check(`the bundle is under ${MAX_MB} MB (${(bytes / 1048576).toFixed(2)} MB)`, bytes < MAX_MB * 1048576, 'biggest: ' + biggest.join(', '));

    // A checkout of one page with a script that is not there: dg-node's own lister, the build must refuse it.
    const fake = path.join(tmp, 'dg-node');
    fs.mkdirSync(path.join(fake, 'scripts'), { recursive: true });
    fs.mkdirSync(path.join(fake, 'public/overrides/audio/parts'), { recursive: true });
    fs.copyFileSync(path.join(dgNode, 'scripts/uposatha-files.js'), path.join(fake, 'scripts/uposatha-files.js'));
    fs.writeFileSync(path.join(fake, 'public/uposatha-calendar.html'), '<script src="/assets/js/not-in-the-checkout.js"></script>');
    let error = '';
    try { bundle(fake, path.join(tmp, 'fake-out')); } catch (e) { error = e.message; }
    check('a referenced file that is not in the checkout fails the build', /not-in-the-checkout\.js/.test(error), error || 'the build passed');
} catch (e) {
    check('bundle-from-repo', false, e.message);
} finally {
    fs.rmSync(tmp, { recursive: true, force: true });
}
console.log(failed ? `\n${failed} check(s) failed` : '\nall checks passed');
process.exit(failed ? 1 : 0);
