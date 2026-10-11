// Lays the dictionary's page out in snapshot/ from a ddg-ui checkout and a dg-node checkout: no site, no browser, no network.
//
//   node tools/bundle-from-repo.js <ddg-ui dir> <dg-node dir> [outdir]        (default outdir: snapshot/)
//
// dict.dhamma.gift is ddg-ui's public/ served as static files (Apache DocumentRoot), so a page URL is that file;
// ru/static is a symlink to ../static in git and resolves the same way. /assets/* is Find on the page, Dhamma.Gift's
// own (dg-node public/overrides). The list is tools/page-files.json: what tools/snapshot.js recorded off the site, all
// byte-identical to the repositories. A file that is not there fails the build.
const fs = require('fs');
const path = require('path');

function resolve(ddgUi, dgNode, url) {
    if (url.startsWith('/assets/')) return [path.join(dgNode, 'public/overrides', url.slice('/assets'.length))];
    return [path.join(ddgUi, 'public', url)];
}

function bundle(ddgUi, dgNode, out) {
    const files = JSON.parse(fs.readFileSync(path.join(__dirname, 'page-files.json'), 'utf8'));
    fs.rmSync(out, { recursive: true, force: true });
    const missing = [];
    for (const url of files) {
        // tools/extra: xmark.svg, which dg-node does not keep in git (its siteroot/assets is the legacy tree).
        const src = resolve(ddgUi, dgNode, url).concat(path.join(__dirname, 'extra', url)).find((p) => fs.existsSync(p));
        if (!src) { missing.push(url); continue; }
        fs.mkdirSync(path.dirname(path.join(out, url)), { recursive: true });
        fs.copyFileSync(src, path.join(out, url));
    }
    if (missing.length) throw new Error('bundle-from-repo: not in ' + ddgUi + ' or ' + dgNode + ': ' + missing.join(', '));
    return files.length;
}

if (require.main === module) {
    const [ddgUi, dgNode, out] = process.argv.slice(2);
    if (!ddgUi || !dgNode) { console.error('usage: node tools/bundle-from-repo.js <ddg-ui dir> <dg-node dir> [outdir]'); process.exit(2); }
    try {
        console.log('bundle-from-repo: ' + bundle(path.resolve(ddgUi), path.resolve(dgNode), path.resolve(out || path.join(__dirname, '..', 'snapshot'))) + ' files');
    } catch (e) { console.error(e.message); process.exit(1); }
}
module.exports = { bundle };
