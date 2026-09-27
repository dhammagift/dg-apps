#!/usr/bin/env node
// Turns the built www/ into the App Store screenshot-tour bundle: appends tour.js to the dictionary page. The
// only edit, and only to BUILD OUTPUT — www/ is generated, so nothing here touches a committed source file and a
// shipped build is never made this way. Mirrors uposatha/test/ios-sim/prepare-www.js.
//
//   node test/ios-sim/prepare-www.js [--www www]
const fs = require('fs');
const path = require('path');

const REPO = path.join(__dirname, '..', '..');
function arg(name, fallback) { const i = process.argv.indexOf('--' + name); return i > -1 && process.argv[i + 1] ? process.argv[i + 1] : fallback; }
const WWW = path.resolve(REPO, arg('www', 'www'));
const PAGE = path.join(WWW, 'index.html');

if (!fs.existsSync(PAGE)) { console.error('prepare-www: no built page at ' + PAGE + ' — build www first'); process.exit(1); }

fs.copyFileSync(path.join(__dirname, 'tour.js'), path.join(WWW, 'ios-tour.js'));
let page = fs.readFileSync(PAGE, 'utf8');
if (page.indexOf('ios-tour.js') !== -1) { console.error('prepare-www: ' + PAGE + ' already carries the tour script — rebuild www'); process.exit(1); }
if (!page.includes('</body>')) { console.error('prepare-www: ' + PAGE + ' has no </body> to append the tour to'); process.exit(1); }
page = page.replace('</body>', '<script src="/ios-tour.js"></script>\n</body>');
fs.writeFileSync(PAGE, page);
console.log('ready: ' + PAGE + ' now loads the screenshot tour');
