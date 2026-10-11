// Lays the calendar page out in snapshot/ from a dg-node checkout: no site, no browser, no network.
//
//   node tools/bundle-from-repo.js <dg-node dir> [outdir]        (default outdir: snapshot/)
//
// The list of files is dg-node's own: its scripts/uposatha-files.js reads the page, the stylesheets it links and the
// scripts it loads, and resolves every URL the way dg-fastify.js mounts it. A file the page starts to load is in the next
// build without anyone editing a list here (a hand-kept page-files.json did that until 2026-10: it had missed the new
// logo, two meal-time sounds and the renamed fonts). A file that is in neither dg-node nor tools/extra fails the build.
const fs = require('fs');
const path = require('path');

function pageFiles(dgNode) {
    const lister = path.join(dgNode, 'scripts', 'uposatha-files.js');
    if (!fs.existsSync(lister)) throw new Error('bundle-from-repo: ' + lister + ' is missing (dg-node older than the generated list?)');
    return require(lister).pageFiles(dgNode);
}

function bundle(dgNode, out) {
    const files = pageFiles(dgNode);
    fs.rmSync(out, { recursive: true, force: true });
    const missing = [];
    for (const { url, file } of files) {
        // The icons (assets/js/fontawesome-local.js) are dg-node's own build (npm run build-icons in the checkout, as the
        // workflow does), the set the site and Dhamma.Gift use. tools/extra: the two files that are in no dg-node checkout,
        // taken from the site once: settings/scripts.json (written by the running server) and assets/sounds/gong.mp3 (the
        // legacy tree). ponytail: they go stale if the site changes them; refresh them from the site then.
        const src = [file && path.join(dgNode, file), path.join(__dirname, 'extra', url)].find((p) => p && fs.existsSync(p));
        if (!src) { missing.push(url); continue; }
        fs.mkdirSync(path.dirname(path.join(out, url)), { recursive: true });
        fs.copyFileSync(src, path.join(out, url));
    }
    if (missing.length) throw new Error('bundle-from-repo: not in ' + dgNode + ' or tools/extra: ' + missing.join(', '));
    return files.length;
}

if (require.main === module) {
    const dgNode = process.argv[2];
    if (!dgNode) { console.error('usage: node tools/bundle-from-repo.js <dg-node dir> [outdir]'); process.exit(2); }
    try {
        console.log('bundle-from-repo: ' + bundle(path.resolve(dgNode), path.resolve(process.argv[3] || path.join(__dirname, '..', 'snapshot'))) + ' files');
    } catch (e) { console.error(e.message); process.exit(1); }
}
module.exports = { bundle, pageFiles };
