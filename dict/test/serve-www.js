// The bundled dictionary (www/) served the way the app serves it: a directory's index.html, else the file, and /ru/static/
// answered from /static/ (DgSitePlugin.serve, DgSiteRouter: the ru page's files ship once). Used by bundle-ui.js, and by
// bridge-ui.js in CI:  node dict/test/serve-www.js dict/www 8191
const fs = require('fs');
const path = require('path');
const http = require('http');

const TYPES = { html: 'text/html', js: 'application/javascript', css: 'text/css', json: 'application/json', svg: 'image/svg+xml', woff2: 'font/woff2', png: 'image/png', txt: 'text/plain' };

function serveWww(www) {
    return http.createServer((req, res) => {
        const url = new URL(req.url, 'http://x');
        let file = path.join(www, decodeURIComponent(url.pathname).replace(/^\/ru\/static\//, '/static/'));
        if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
        if (!file.startsWith(www) || !fs.existsSync(file)) { res.writeHead(404); return res.end(); }
        res.writeHead(200, { 'content-type': TYPES[path.extname(file).slice(1)] || 'application/octet-stream' });
        fs.createReadStream(file).pipe(res);
    });
}

module.exports = { serveWww, TYPES };

if (require.main === module) {
    const port = +process.argv[3] || 8191;
    serveWww(path.resolve(process.argv[2] || path.join(__dirname, '..', 'www'))).listen(port, '127.0.0.1', () => console.log('up ' + port));
}
