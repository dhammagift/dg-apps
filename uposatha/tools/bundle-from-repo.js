// Lays the calendar page out in snapshot/ from a dg-node checkout: no site, no browser, no network.
//
//   node tools/bundle-from-repo.js <dg-node dir> [outdir]        (default outdir: snapshot/)
//
// The list of files is tools/page-files.json (what the page loads, recorded once off the site: 60 files, every one
// byte-identical to the repository's own, the html up to the ?v= cache-busters the server adds). A URL is resolved
// the way dg-fastify.js mounts it (HTML_ASSET_URL_ROOTS). A file that is not there fails the build.
const fs = require('fs');
const path = require('path');

const ROOTS = {
    '/assets': ['public/overrides', 'siteroot/assets'],
    '/nodejs/res': ['search', 'configs/search'],
    '/settings': ['settings'],
};

function resolve(dgNode, url) {
    if (url === '/uposatha-calendar.html') return [path.join(dgNode, 'public/uposatha-calendar.html')];
    for (const [prefix, roots] of Object.entries(ROOTS)) {
        if (url.startsWith(prefix + '/')) return roots.map((r) => path.join(dgNode, r, url.slice(prefix.length)));
    }
    return [];
}

function bundle(dgNode, out) {
    const files = JSON.parse(fs.readFileSync(path.join(__dirname, 'page-files.json'), 'utf8'));
    fs.rmSync(out, { recursive: true, force: true });
    const missing = [];
    for (const url of files) {
        const src = resolve(dgNode, url).find((p) => fs.existsSync(p));
        if (!src) { missing.push(url); continue; }
        fs.mkdirSync(path.dirname(path.join(out, url)), { recursive: true });
        fs.copyFileSync(src, path.join(out, url));
    }
    if (missing.length) throw new Error('bundle-from-repo: not in ' + dgNode + ': ' + missing.join(', '));
    return files.length;
}

if (require.main === module) {
    const dgNode = process.argv[2];
    if (!dgNode) { console.error('usage: node tools/bundle-from-repo.js <dg-node dir> [outdir]'); process.exit(2); }
    try {
        console.log('bundle-from-repo: ' + bundle(path.resolve(dgNode), path.resolve(process.argv[3] || path.join(__dirname, '..', 'snapshot'))) + ' files');
    } catch (e) { console.error(e.message); process.exit(1); }
}
module.exports = { bundle };
