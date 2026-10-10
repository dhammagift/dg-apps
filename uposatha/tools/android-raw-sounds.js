// The page's sounds that are also the reminders' sounds ship ONCE in the Android app (dg-apps U17: ~1.7 MB twice).
//
// Notification channels can only play a resource (res/raw/<name>.mp3), so that copy stays; the page's copy of the same file
// (assets/public/assets/{sounds,repeat-timer/sound,audio/parts}/<name>.mp3, from www/) is taken out of the Android project
// after `cap copy`/`cap sync` (package.json "capacitor:copy:after"), and DgSitePlugin answers the page's request for it from
// res/raw. Only a byte-identical copy is removed: a sound the site changed stays in the assets and is served from there.
// www/ itself is untouched (iOS has no res/raw: its page plays the www copies).
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const RAW = path.join(ROOT, 'android', 'app', 'src', 'main', 'res', 'raw');
const ASSETS = path.join(ROOT, 'android', 'app', 'src', 'main', 'assets', 'public', 'assets');
const DIRS = ['sounds', 'repeat-timer/sound', 'audio/parts'];   // the same as RAW_SOUND in DgSitePlugin.java

function dropCopies() {
    let removed = 0, bytes = 0;
    for (const dir of DIRS) {
        const full = path.join(ASSETS, dir);
        if (!fs.existsSync(full)) continue;
        for (const name of fs.readdirSync(full)) {
            const m = /^([a-z0-9]+)\.mp3$/.exec(name);
            const raw = m && path.join(RAW, name);
            if (!raw || !fs.existsSync(raw)) continue;
            const copy = fs.readFileSync(path.join(full, name));
            if (!copy.equals(fs.readFileSync(raw))) continue;
            fs.unlinkSync(path.join(full, name));
            removed++; bytes += copy.length;
        }
    }
    return { removed, bytes };
}

if (require.main === module) {
    if (process.env.CAPACITOR_PLATFORM_NAME && process.env.CAPACITOR_PLATFORM_NAME !== 'android') process.exit(0);
    const { removed, bytes } = dropCopies();
    console.log(`android-raw-sounds: ${removed} sound(s) served from res/raw instead of the assets (${bytes} bytes saved)`);
}
module.exports = { dropCopies };
