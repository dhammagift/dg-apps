// Lays the dictionary's page (both languages) out in snapshot/ from a ddg-ui checkout: no site, no browser, no network.
//
//   node tools/bundle-from-repo.js <ddg-ui dir> <dg-node dir> [outdir]        (default outdir: snapshot/)
//
// The site is static files (ddg-ui's public/, which Apache serves as they are), so a file of the bundle is the
// repository's own file, at the path the site serves it from. What goes in is what the two pages (/ and /ru/) load,
// read from the files themselves:
//   html  src/href of every tag but <a> (an <a> leads to another page)
//   css   url(...), relative to the stylesheet
//   js    string literals that are paths under static/ ("./static/sutta_words.txt"), relative to the page that runs it
// /ru/'s static/ is a symlink to ../static in the repository; /ru/static/... is copied as real files here, so neither
// Capacitor's copy into the APK nor the native lookup has to follow a link. A file that is referenced and not in the
// checkout fails the build. A word's own page (/dhamma) is made by the server and is not part of the bundle.
//
// Find on the page is Dhamma.Gift's own (loaded on demand, from the page's origin): EXTRAS are taken from the dg-node
// checkout (DG_NODE_REF), where they live, or from tools/extra for what dg-node does not keep in git.
const fs = require('fs');
const path = require('path');

const PAGES = ['/index.html', '/ru/index.html'];
const SKIP = ['/static/sw.js', '/ru/static/sw.js'];   // no service worker in the app (src/site-no-sw.js); extra.js names it
// Referenced and missing on the site too (404 there): jQuery UI's stock theme names its icon sprites, the page draws its own icons.
const DEAD = /^(?:\/ru)?\/static\/images\/ui-icons_[0-9a-f]+_256x240\.png$/;
const EXTRAS = [
    ...['dg-page-find.js', 'dg-page-find-ui.js'].map((f) => '/assets/js/' + f),
    ...['gear', 'list-ul-solid-full', 'arrow-up-dark', 'xmark'].map((f) => '/assets/svg/' + f + '.svg'),
];
const LITERAL = /['"`]((?:\.\/|\/)?static\/[A-Za-z0-9_\-./]+\.[A-Za-z0-9]+)(?=['"`?#])/g;
const REFS = {
    html: [/<(?!a[\s>])[a-z]+\b[^>]*?\s(?:src|href)="([^"?#]+)/gi, LITERAL],
    css: [/url\(\s*['"]?([^'")?#]+)/g],
    js: [LITERAL],
};

// A reference as a path on the site, or null for what is not a file of this site.
function urlOf(ref, base) {
    if (/^(?:[a-z]+:|\/\/|#)/i.test(ref)) return null;
    return new URL(ref, 'http://x' + base).pathname;
}

function isFile(f) { try { return fs.statSync(f).isFile(); } catch (e) { return false; } }   // statSync follows links

// Everything the pages load, as { url: file }; missing: referenced and not there, with who referenced it.
function pageFiles(pub) {
    const files = new Map(), missing = new Map();
    for (const pageUrl of PAGES) {
        const pageDir = pageUrl.replace(/[^/]*$/, '');
        const queue = [[pageUrl, null]];
        while (queue.length) {
            const [url, from] = queue.shift();
            if (files.has(url) || SKIP.includes(url) || DEAD.test(url)) continue;
            const file = path.join(pub, decodeURIComponent(url));
            if (!isFile(file)) { missing.set(url, url + ' (in ' + from + ')'); continue; }
            files.set(url, file);
            const kind = path.extname(url).slice(1);
            for (const re of REFS[kind] || []) {
                for (const m of fs.readFileSync(file, 'utf8').matchAll(re)) {
                    // A stylesheet's url() is relative to the stylesheet; a script's string is fetched by the page.
                    const ref = urlOf(m[1], kind === 'css' ? url : pageDir);
                    if (ref && ref !== '/' && !ref.endsWith('/')) queue.push([ref, url]);
                }
            }
        }
    }
    return { files, missing: [...missing.values()] };
}

function bundle(ddgUi, dgNode, out) {
    const pub = path.join(ddgUi, 'public');
    if (!PAGES.every((p) => isFile(path.join(pub, p)))) throw new Error('bundle-from-repo: ' + pub + ' has no index.html and ru/index.html (not a ddg-ui checkout?)');
    const { files, missing } = pageFiles(pub);
    for (const url of EXTRAS) {
        const src = [path.join(dgNode, 'public/overrides', url.slice('/assets'.length)), path.join(__dirname, 'extra', url)].find(isFile);
        if (src) files.set(url, src); else missing.push(url + ' (not in ' + dgNode + ' or tools/extra)');
    }
    if (missing.length) throw new Error('bundle-from-repo: referenced and missing: ' + missing.join(', '));
    fs.rmSync(out, { recursive: true, force: true });
    for (const [url, src] of files) {
        fs.mkdirSync(path.dirname(path.join(out, url)), { recursive: true });
        fs.copyFileSync(src, path.join(out, url));
    }
    return [...files.keys()];
}

if (require.main === module) {
    const [ddgUi, dgNode, outDir] = process.argv.slice(2);
    if (!ddgUi || !dgNode) { console.error('usage: node tools/bundle-from-repo.js <ddg-ui dir> <dg-node dir> [outdir]'); process.exit(2); }
    try {
        console.log('bundle-from-repo: ' + bundle(path.resolve(ddgUi), path.resolve(dgNode), path.resolve(outDir || path.join(__dirname, '..', 'snapshot'))).length + ' files');
    } catch (e) { console.error(e.message); process.exit(1); }
}
module.exports = { bundle, pageFiles };
