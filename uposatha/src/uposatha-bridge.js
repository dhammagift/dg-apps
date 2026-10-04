// Uposatha app-only additions to the site's calendar page.
//
// NOT part of the website. This file ships inside the Android app and MainActivity injects it into
// the page at document start (WebViewCompat.addDocumentStartJavaScript, with a WebViewListener
// re-inject on page load for WebViews older than Chrome 105). The page is bundled in the APK (www/ is
// a snapshot of the site's calendar page, taken at build time), so there is nothing to patch at build
// time; this reaches into the running page, and without the Capacitor runtime (the same page in a
// browser) it returns at once.
//
// The page draws its own app layer (?app=1: tabs, the Rate Us row, the version row). What is here is
// only what a page cannot do: the back button, the launcher shortcuts, the tab a shortcut asks for,
// the sound source, keeping the bundled page up to date, and the rating invitation. The reminders themselves are the page's own
// (LocalNotifications, scheduled from uposatha-calendar.js); this file has no part in them.
(function () {
  'use strict';

  var Cap = window.Capacitor;
  if (!Cap || typeof Cap.getPlatform !== 'function') return;
  var PLATFORM = Cap.getPlatform();
  if (PLATFORM !== 'android' && PLATFORM !== 'ios') return;
  var IOS = PLATFORM === 'ios';   // on iOS: no Back button, no notification channels or streams, no launcher icon change

  // The launch splash is native on Android (the animated mark of the system splash screen, res/drawable/
  // dg_splash_icon.xml), so nothing is drawn here: a web splash on top of it made the app slower to open and
  // the page under it showed a scroll strip.

  var STORE_URL = IOS ? 'https://apps.apple.com/app/id6816601259' : 'https://play.google.com/store/apps/details?id=gift.dhamma.uposatha';
  // Set when the reader taps Rate Us (the page's own row, #up-rate) or "Rate" in the invitation: whoever
  // has tapped it is never invited again.
  var RATE_FLAG = 'dgRateUsTapped';
  var SHORTCUTS_MAX = 3;   // the launcher's menu holds four entries: Calendar and the next three Uposatha days (all dynamic, so each icon is a moon of its own day)

  // The page is bundled, so it is at the app's own origin: /, /index.html, /uposatha-calendar (and .html).
  var CALENDAR_PATH = /^\/(uposatha-calendar(\.html)?\/?|index\.html)?$/;
  var onCalendar = CALENDAR_PATH.test(location.pathname);

  // Android (dg-apps#54): the page draws under the system bars, as on iOS (DgSiteRouter adds the
  // same at serve time). With viewport-fit=cover Capacitor's SystemBars passes the insets through
  // to the page (WebView 140+) instead of padding the window, so the strips under the clock and the
  // navigation bar are the page's own paint, and a theme switch repaints them in the same frame.
  // Patched here, as the parser inserts the tag, so the bundled copy and a downloaded one are alike.
  if (!IOS && onCalendar) coverViewport();
  function coverViewport() {
    function patch() {
      var m = document.querySelector('meta[name=viewport]');
      if (!m) return false;
      var c = m.getAttribute('content') || '';
      if (!/viewport-fit\s*=\s*cover/.test(c)) m.setAttribute('content', c + ', viewport-fit=cover');
      return true;
    }
    if (patch()) return;
    var mo = new MutationObserver(function () { if (patch()) mo.disconnect(); });
    mo.observe(document, { childList: true, subtree: true });
  }

  // The page's own rule (uposatha-calendar.js: ?lang=, then the stored dhammaLanguage, then the phone's
  // language) — not <html lang>, which the page sets late.
  function isRu() {
    var m = /[?&]lang=(\w\w)/.exec(location.search);
    var l = (m && m[1]) || '';
    if (!l) { try { l = localStorage.getItem('dhammaLanguage') || ''; } catch (e) { /* no storage */ } }
    return /^ru/i.test(l || navigator.language || '');
  }

  // The page's own splash (app-refresh.js) no longer auto-fires in the app — Android's native
  // launch splash (the animated system splash) already covers a cold start, and the page's copy
  // right after it made every launch show two. Nothing to signal from here any more.

  // ---- the bundled page: no service worker, kept up to date -------------------------------------
  var SITE_CONFIG = {
    site: 'https://dhamma.gift',   // where the page comes from: the production site (owner, 2026-09-30)
    // The page's file in the bundle is /uposatha-calendar.html; on the site it is /uposatha-calendar.
    urlFor: function (path) { return path === '/uposatha-calendar.html' ? '/uposatha-calendar' : path; },
    // The code (html, css, js) is what the build took from the repository; only the texts (json) follow the site.
    updatable: function (path) { return /\.json$/.test(path); }
  };
  // @site-updater (inlined from src/site-updater.js by uposatha/build.js)

  // ---- an app, not a page ----------------------------------------------------------------------
  //
  // A web page lets the reader select anything with a long press, flashes a tap highlight and offers
  // the browser's menu on links; an app does none of it. Text can be selected only where it is text to
  // take away: the quotes of the slideshow, any Pali (the page marks Pali with .pli-lang / lang="pi"), sutta names
  // and anything else the page marks with class="selectable" (or data-selectable), and the fields. Everything else is not selectable. Only on the calendar page: the other pages of
  // the site the app may pass through (dhamma.gift/4as) are the reader's own business.
  if (onCalendar) {
    var feel = document.createElement('style');
    feel.id = 'dg-native-feel';
    feel.textContent = 'html{-webkit-tap-highlight-color:transparent;-webkit-touch-callout:none}'
      + 'html body,html body *{-webkit-user-select:none;user-select:none}'
      + 'html body input,html body textarea,html body [contenteditable],html body .pli-lang,html body [lang="pi"],'
      + 'html body .selectable,html body [data-selectable],html body .selectable *,html body [data-selectable] *,'
      + 'html body #slides,html body #slides *{-webkit-user-select:text;user-select:text;-webkit-touch-callout:default}';
    (function put() {
      if (document.documentElement) document.documentElement.appendChild(feel);
      else new MutationObserver(function (m, mo) { if (document.documentElement) { mo.disconnect(); put(); } }).observe(document, { childList: true });
    })();
  }

  // ---- the tab a launcher shortcut asks for ------------------------------------------------
  //
  // A shortcut opens /uposatha-calendar?app=1&tab=cal. The page keeps its current tab in
  // localStorage (dgUposathaTab, and dgUposathaView for the two views of the calendar) and reads it
  // when it starts, so setting it here, before the page's own scripts run, is all it takes.
  (function () {
    if (!onCalendar) return;
    var m = /[?&]tab=(home|list|cal|parts)\b/.exec(location.search);
    if (!m) return;
    try {
      localStorage.setItem('dgUposathaTab', m[1]);
      if (m[1] === 'list' || m[1] === 'cal') localStorage.setItem('dgUposathaView', m[1]);
    } catch (e) { /* no storage: the page opens on its last tab */ }
  })();

  // ---- launcher shortcuts: the next three Uposatha days ------------------------------------------
  //
  // The page's own calendar code (UposathaCore, loaded by the page) works the days out for the
  // settings the reader made — time zone, scheme, place — which live in the page's localStorage.
  // Pushed when the page has loaded and again when the app goes to the background (the day may have
  // changed since); pushed even when empty, which is what clears an earlier run's entries.

  function store(key) { try { return localStorage.getItem(key); } catch (e) { return null; } }

  // ---- the moon's phase as icons ---------------------------------------------------------------------
  //
  // The reminder's status-bar icon and the shortcuts show the moon of THEIR day, not a fixed one. Index 0..7 = new,
  // waxing crescent, first quarter, waxing gibbous, full, waning gibbous, last quarter, waning crescent — the page's own
  // eight shapes (uposatha-calendar.js). The drawables (res/drawable-*/ic_stat_moon_N, shortcut_moon_N) are drawn as in
  // the Northern Hemisphere, so the Southern one asks for the mirrored index.

  var SOUTHERN_ZONE = /^(Australia|Antarctica)\/|^Pacific\/(Auckland|Chatham|Fiji|Tongatapu|Apia|Noumea|Tahiti|Port_Moresby)|^Africa\/(Johannesburg|Maseru|Mbabane|Windhoek|Harare|Lusaka|Maputo)|^America\/(Sao_Paulo|Argentina|Buenos_Aires|Santiago|Lima|La_Paz|Asuncion|Montevideo)/;

  function isSouth() {
    var h = store('dgUposathaHemisphere');
    if (h) return h === 'south';
    return SOUTHERN_ZONE.test(store('dgUposathaTz') || (Intl.DateTimeFormat().resolvedOptions().timeZone || ''));
  }

  function moonIndexAt(date) {
    var A = window.Astronomy, angle;
    if (A && typeof A.MoonPhase === 'function') angle = A.MoonPhase(date);
    else angle = (((date.getTime() - 947182440000) / 86400000 / 29.530588853) % 1 + 1) % 1 * 360;   // no astronomy library: the mean month, good to about a day
    return Math.floor(((angle + 22.5) % 360) / 45) % 8;
  }

  function moonName(prefix, i) { return prefix + '_' + (isSouth() ? (8 - i) % 8 : i); }

  // The shape an Uposatha day is drawn with (as in the page): the 8th a quarter, the 14th the last shape before full/new, the 15th full (waxing half) or new.
  function uposathaMoonIndex(tithi) {
    var n = tithi <= 15 ? tithi : tithi - 15, waxing = tithi <= 15;
    return waxing ? (n === 8 ? 2 : n === 14 ? 3 : 4) : (n === 8 ? 6 : n === 14 ? 7 : 0);
  }

  function nextUposathas() {
    var C = window.UposathaCore;
    if (!C || typeof C.dataset !== 'function') return [];
    var lang = isRu() ? 'ru' : 'en';
    var tz = store('dgUposathaTz') || (Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC');
    var sutta = store('dgUposathaSutta') !== '0';
    var loc = null;
    try { loc = JSON.parse(store('dgUposathaLoc')); } catch (e) { /* no place set */ }
    var today = C.localDay(new Date(), tz);
    var data = C.dataset(C.ymdAdd(today, -1), C.ymdAdd(today, 75), { tz: tz, sutta: sutta, loc: loc });
    var names = C.NAMES[lang];
    var tomorrow = C.ymdAdd(today, 1), yesterday = C.ymdAdd(today, -1);
    var out = [];
    data.rows.forEach(function (r) {
      if (out.length >= SHORTCUTS_MAX || !r.uposatha) return;
      // By the suttas an Uposatha begins in the evening of its date, so the row of YESTERDAY is the one
      // that is in force today; either way "today" and "tomorrow" are named as such, and never left out.
      var when;
      if (r.ymd === today || (sutta && r.ymd === yesterday)) when = lang === 'ru' ? 'Сегодня' : 'Today';
      else if (r.ymd === tomorrow) when = lang === 'ru' ? 'Завтра' : 'Tomorrow';
      else if (r.ymd > today) {
        var parts = r.ymd.split('-').map(Number);
        when = new Intl.DateTimeFormat(lang, { day: 'numeric', month: 'short', timeZone: 'UTC' }).format(new Date(Date.UTC(parts[0], parts[1] - 1, parts[2])));
      } else return;
      // Which day it is, short (the launcher clips a label at ~25 characters): "Day 14/15", "14/15-й день" by the
      // suttas, the phase ("Full moon") in the modern scheme.
      var kind = '';
      try {
        var nums = sutta && r.names ? r.names.map(C.dayNo) : [];
        kind = nums.length ? (lang === 'ru' ? nums.join('/') + '-й день' : 'Day ' + nums.join('/')) : C.nameOf(names, r, sutta);
      } catch (e) { /* the date alone will do */ }
      out.push({
        id: 'dg-uposatha-' + out.length,
        label: kind ? when + ' · ' + kind : when,
        route: '/uposatha-calendar?app=1&tab=list',
        icon: moonName('shortcut_moon', rowMoon(r, sutta)),
        rank: 10 + out.length
      });
    });
    return out;
  }

  function rowMoon(r, sutta) {
    try {
      if (sutta && r.names && r.names.length) return uposathaMoonIndex(r.names[0]);
      if (typeof r.phase === 'number') return [0, 2, 4, 6][r.phase];
    } catch (e) { /* the icon of the day it is */ }
    return moonIndexAt(r.at || new Date());
  }

  function pushShortcuts() {
    var plugin = Cap.Plugins && Cap.Plugins.DgShortcuts;
    if (!plugin || typeof plugin.set !== 'function') return;
    var items = [];
    try { items = nextUposathas(); } catch (e) { console.log('[dg-uposatha-shortcuts] failed to work out the days:', (e && e.message) || e); }
    // The Calendar entry is dynamic too (it was the one static shortcut), so that its icon can be the moon of today.
    items.unshift({
      id: 'dg-calendar',
      label: isRu() ? 'Календарь' : 'Calendar',
      route: '/uposatha-calendar?app=1&tab=cal',
      icon: moonName('shortcut_moon', moonIndexAt(new Date())),
      rank: 0
    });
    Promise.resolve(plugin.set({ items: items })).catch(function (e) {
      console.log('[dg-uposatha-shortcuts] set failed:', (e && e.message) || e);
    });
  }

  // ---- the sound source: the alarm stream or the notification stream --------------------------
  //
  // A channel plays its sound on an audio stream fixed when the channel is created, and
  // LocalNotifications creates every channel on the NOTIFICATION stream: with the notification volume
  // down, or the phone on silent, the reminder arrives and the gong does not. The same sound on the ALARM
  // stream plays at the alarm volume, like a clock. So the app keeps a setting (localStorage
  // dgUposathaSoundStream: 'notification' by default, or 'alarm'), and every sound has a second channel
  // with the suffix "-alarm" (DgSoundPlugin). The page creates channels and schedules notifications
  // through LocalNotifications without knowing about any of this; here the two calls are wrapped:
  // createChannel is made natively on the chosen stream, and schedule's channelId gets the suffix.
  var STREAM_KEY = 'dgUposathaSoundStream';
  function alarmStream() { return store(STREAM_KEY) === 'alarm'; }

  var NATIVE_ID_BASE = 7000;   // the page's ids for its reminders (uposatha-calendar.js: NATIVE_ID_BASE + list index; the test reminder is 7990)

  // Every reminder has an id of its own, made from its minute (owner: "the sound was there, the notification was not").
  // The page numbers its reminders by their place in the list (the next one is always 7000), and re-plans after each
  // one fires, so the next reminder took the id of the one in the tray and replaced it; the tray was also emptied
  // before every re-plan so that the replacement would not arrive silent. Now nothing in the tray is touched: an id
  // is the minute it rings at (and the place within that minute: the meal and a part of the day can share one), so
  // a reminder never lands on another. getPending/cancel are translated back, so the page still cancels by its range.
  var UNIQUE_BASE = 1000000;
  function isUnique(id) { return id >= UNIQUE_BASE && id < UNIQUE_BASE + 1000000; }
  function uniqueId(n) {
    if (!(n.id >= NATIVE_ID_BASE && n.id < NATIVE_ID_BASE + 100)) return n.id;   // the test reminders (7990+) keep theirs
    var at = n.schedule && n.schedule.at ? new Date(n.schedule.at).getTime() : 0;
    return UNIQUE_BASE + (Math.floor(at / 60000) % 100000) * 10 + (n.id % 10);
  }
  var pendingAlias = {};   // the page's id -> ours, from the last getPending the page saw
  function pageView(p) {
    pendingAlias = {};
    var k = 0;
    var list = ((p && p.notifications) || []).map(function (n) {
      if (!isUnique(n.id) || k >= 100) return n;
      var alias = NATIVE_ID_BASE + k++;
      pendingAlias[alias] = n.id;
      return Object.assign({}, n, { id: alias });
    });
    return Object.assign({}, p, { notifications: list });
  }
  // An alias stands for one of ours; an id from before this change (7000+, still pending after an update) is cancelled as itself too.
  function nativeIds(ids) {
    var out = [];
    ids.forEach(function (id) { if (pendingAlias[id] != null) out.push(pendingAlias[id]); out.push(id); });
    return out;
  }

  // What the page last asked of the plugin, so a change of the source can be applied without reloading the page:
  // the channels it made (by their own id) and the reminders it scheduled (as it passed them, unmapped).
  var lastChannels = {};
  var lastSchedule = null;

  // Do Not Disturb: reminders should sound through it. Only the reader can allow that (a system page the app opens);
  // while the access is not there the channels are the plain ones, and when it arrives they are made again under other
  // ids (a channel's override cannot be changed afterwards): "-dnd".
  var dndGranted = false;
  function refreshDnd() {
    var DS = Cap.Plugins && Cap.Plugins.DgSound;
    if (!DS || typeof DS.dndAccess !== 'function') return Promise.resolve();
    return DS.dndAccess().then(function (r) {
      var granted = !!(r && r.granted);
      var changed = granted !== dndGranted;
      dndGranted = granted;
      paintDndRow();
      return changed ? restream() : null;
    }).catch(function () { /* the plugin cannot tell: the plain channels */ });
  }

  // ---- asking for the access -------------------------------------------------------------------
  //
  // A reminder that arrives with no sound is a note nobody hears, so the access is asked for, in plain words, when
  // reminders are on and it is not there: a sheet (the rating invitation's design) with a button to the system page.
  // Not on every start: once a week until it is given, once per session at most. The settings row stays.
  var DND_ASK_EVERY = 7 * 86400000;
  var dndAskedThisSession = false;

  function maybeAskDnd() {
    if (dndAskedThisSession || dndGranted || document.getElementById('dgrAsk')) return;
    var DS = Cap.Plugins && Cap.Plugins.DgSound;
    if (!DS || typeof DS.requestDndAccess !== 'function') return;
    if (Date.now() - (parseInt(store('dgDndAskedAt'), 10) || 0) < DND_ASK_EVERY) return;
    dndAskedThisSession = true;
    try { localStorage.setItem('dgDndAskedAt', String(Date.now())); } catch (e) { /* asked again next time */ }
    var ru = isRu();
    var style = document.createElement('style');
    style.textContent = RATE_PROMPT_CSS;
    document.head.appendChild(style);
    var overlay = document.createElement('div');
    overlay.id = 'dgrAsk';   // the rating sheet's styles, and its Back-button handling (closeRatePrompt)
    overlay.innerHTML = '<div class="dgr-sheet" role="alertdialog" aria-modal="true" aria-labelledby="dgrTitle">'
      + '<div class="dgr-eyebrow"></div><p class="dgr-title" id="dgrTitle"></p><p class="dgr-body"></p>'
      + '<div class="dgr-actions"><button type="button" class="dgr-ghost"></button><button type="button" class="dgr-primary"></button></div></div>';
    overlay.querySelector('.dgr-eyebrow').textContent = ru ? 'Напоминания' : 'Reminders';
    overlay.querySelector('.dgr-title').textContent = ru ? 'Чтобы напоминание было слышно' : 'So that a reminder is heard';
    overlay.querySelector('.dgr-body').textContent = ru
      ? 'Пока включён режим «Не беспокоить», напоминание приходит без звука. Разрешите Uposatha звучать в этом режиме: откроются настройки Android, включите переключатель для Uposatha и вернитесь.'
      : 'While Do Not Disturb is on, a reminder arrives with no sound. Allow Uposatha to sound in it: Android settings open, switch it on for Uposatha and come back.';
    overlay.querySelector('.dgr-ghost').textContent = ru ? 'Позже' : 'Later';
    overlay.querySelector('.dgr-primary').textContent = ru ? 'Разрешить' : 'Allow';
    document.body.appendChild(overlay);
    requestAnimationFrame(function () { overlay.classList.add('show'); });
    function close() { overlay.classList.remove('show'); setTimeout(function () { overlay.remove(); }, 200); }
    overlay.querySelector('.dgr-ghost').addEventListener('click', close);
    overlay.addEventListener('click', function (ev) { if (ev.target === overlay) close(); });
    overlay.querySelector('.dgr-primary').addEventListener('click', function () { DS.requestDndAccess(); close(); });
  }

  // "Alarm" as the source means the reminder is played the way an alarm clock plays: the notification is silent (the banner
  // and the tray entry), and DgAlarm sets an exact alarm that plays the sound on the ALARM stream, which Do Not Disturb
  // lets through and phone makers' notification layers do not touch. The sound's name comes from the channel the page chose.
  var RAW_OF = { gong: 'gong', gong2: 'gong2', gong3: 'gong3', gong4: 'gong4', gong5: 'gong5', bell: 'church' };
  // The spoken names of the parts of the night and day ("part-<name>") and the Vinaya's vikala are res/raw files of their own name.
  var RAW_SPOKEN = { pubbanha: 1, majjhanhika: 1, sayanha: 1, pathama: 1, majjhima: 1, pacchima: 1, vikala: 1 };
  function alarmPlugin() { var p = Cap.Plugins && Cap.Plugins.DgAlarm; return p && typeof p.schedule === 'function' ? p : null; }
  function directAlarm() { return alarmStream() && !!alarmPlugin(); }
  function rawSoundOf(channelId) {
    if (/^uposatha-own-/.test(channelId || '')) return 'own';
    var m = /^uposatha-(?:part-)?([a-z0-9]+)-v\d/.exec(channelId || '');
    if (!m) return '';
    return RAW_OF[m[1]] || (RAW_SPOKEN[m[1]] ? m[1] : '');
  }

  function wrapLocalNotifications() {
    var plugins = Cap.Plugins;
    var LN = plugins && plugins.LocalNotifications;
    if (!LN || LN.__dgWrapped) return;
    var sound = function () { return plugins.DgSound; };
    var suffixed = function (id) {
      if (!id || id.indexOf('uposatha-') !== 0 || /-(alarm|dnd)$/.test(id)) return id;
      // The reader's own sound has both streams made by DgSound at the pick; the built-in ones are made here.
      var own = id.indexOf('uposatha-own-') === 0;
      return id + (alarmStream() ? '-alarm' : '') + (dndGranted && !own ? '-dnd' : '');
    };
    plugins.LocalNotifications = new Proxy(LN, {
      get: function (target, key) {
        if (key === '__dgWrapped') return true;
        if (key === 'createChannel') {
          return function (ch) {
            lastChannels[ch.id] = ch;
            if (!sound() || typeof sound().channel !== 'function') return target.createChannel(ch);
            // Made natively, on the stream the reader chose, asking to sound through Do Not Disturb.
            return sound().channel({ id: suffixed(ch.id), name: ch.name + (alarmStream() ? (isRu() ? ' (будильник)' : ' (alarm)') : ''), sound: directAlarm() ? '' : (ch.sound || ''),
              importance: ch.importance, vibration: !!ch.vibration, stream: alarmStream() ? 'alarm' : 'notification', bypass: true });
          };
        }
        if (key === 'schedule') {
          return function (o) {
            lastSchedule = o;
            // The picture of the reminders (docs/launch-screens/uposatha-notification.png: the mirror, the bowl, the brush),
            // shown at the right of the notification; the sound channel is the reader's.
            var list = ((o && o.notifications) || []).map(function (n) {
              var at = n.schedule && n.schedule.at ? new Date(n.schedule.at) : null;
              // The status-bar icon is the moon of the day the reminder is for.
              var moon = at && !isNaN(at) ? { smallIcon: moonName('ic_stat_moon', moonIndexAt(at)) } : {};
              return Object.assign({ largeIcon: 'uposatha_notification' }, moon, n, { id: uniqueId(n), channelId: suffixed(n.channelId) });
            });
            // The plugin posts every notification "alert once": one that REPLACES a notification of the same id still in the
            // tray makes no sound. With an id per minute (uniqueId) a reminder never replaces another, so the tray is left alone.
            // The sound itself, on the alarm stream, at the same minute.
            var alarm = alarmPlugin();
            var items = directAlarm() ? ((o && o.notifications) || []).map(function (n) {
              var at = n.schedule && n.schedule.at ? new Date(n.schedule.at).getTime() : 0;
              return { id: uniqueId(n), at: at, sound: rawSoundOf(n.channelId) };
            }).filter(function (i) { return i.at > 0 && i.sound; }) : [];
            return Promise.resolve(items.length ? alarm.schedule({ items: items }) : null).then(function () { return target.schedule(Object.assign({}, o, { notifications: list })); }).then(function (res) {
              if (list.length) setTimeout(function () { refreshDnd().then(maybeAskDnd); }, 2500);   // the page has settled; is the access there?
              return res;
            });
          };
        }
        if (key === 'cancel') {
          return function (o) {
            var alarm = alarmPlugin();
            var ids = nativeIds(((o && o.notifications) || []).map(function (n) { return n.id; }));
            if (alarm && ids.length) alarm.cancel({ ids: ids });
            return target.cancel({ notifications: ids.map(function (id) { return { id: id }; }) });
          };
        }
        if (key === 'getPending') return function () { return target.getPending().then(pageView); };
        var v = target[key];
        return typeof v === 'function' ? v.bind(target) : v;
      }
    });
  }

  // ---- iOS: the reminders ----------------------------------------------------------------------
  //
  // iOS has no notification channels: a sound is a property of each notification, a file in the app (the .caf made from the same
  // sounds, www/ios-sounds/). DgNotify (DgApp.swift) sets the notifications itself, as Time Sensitive ones, so that they get through
  // a Focus; the page keeps calling LocalNotifications as it does on Android and this turns its calls into DgNotify's.
  function wrapIosNotifications() {
    var plugins = Cap.Plugins;
    var LN = plugins && plugins.LocalNotifications;
    if (!LN || LN.__dgWrapped) return;
    var N = function () { var p = plugins.DgNotify; return p && typeof p.schedule === 'function' ? p : null; };
    plugins.LocalNotifications = new Proxy(LN, {
      get: function (target, key) {
        if (key === '__dgWrapped') return true;
        if (!N()) { var v0 = target[key]; return typeof v0 === 'function' ? v0.bind(target) : v0; }
        if (key === 'createChannel') return function (ch) { lastChannels[ch.id] = ch; return Promise.resolve(); };
        if (key === 'schedule') {
          return function (o) {
            lastSchedule = o;
            var items = ((o && o.notifications) || []).map(function (n) {
              var at = n.schedule && n.schedule.at ? new Date(n.schedule.at).getTime() : 0;
              return { id: uniqueId(n), title: n.title || '', body: n.body || '', at: at, sound: rawSoundOf(n.channelId) === 'own' ? '' : rawSoundOf(n.channelId) };
            }).filter(function (i) { return i.at > 0; });
            return N().schedule({ items: items }).then(function () { return { notifications: items.map(function (i) { return { id: i.id }; }) }; });
          };
        }
        if (key === 'cancel') return function (o) { return N().cancel({ ids: nativeIds(((o && o.notifications) || []).map(function (n) { return n.id; })) }); };
        if (key === 'getPending') return function () { return N().getPending().then(pageView); };
        var v = target[key];
        return typeof v === 'function' ? v.bind(target) : v;
      }
    });
  }

  // A Home Screen quick action opens a route: at a cold start the plugin has it waiting, while the app runs it tells the page.
  function wireIosShortcutTaps() {
    var S = Cap.Plugins && Cap.Plugins.DgShortcuts;
    if (!S) return;
    function go(route) {
      if (!route) return;
      try { var u = new URL(route, location.href); if (u.pathname + u.search === location.pathname + location.search) return; } catch (e) { /* a route the URL parser refuses is still tried */ }
      location.href = route;
    }
    if (typeof S.addListener === 'function') S.addListener('shortcut', function (ev) { go(ev && ev.route); });
    if (typeof S.launchRoute === 'function') Promise.resolve(S.launchRoute()).then(function (r) { go(r && r.route); }).catch(function () { /* none waiting */ });
  }

  // The source changed: make the channels of the other stream, take back the reminders that are set and set them again on
  // those channels — no reload of the page. (The page schedules only when its own reminders change, so it would never do
  // this itself.) What the page has asked of the plugin since it started is what is replayed; it asks at every start.
  function restream() {
    var LN = Cap.Plugins && Cap.Plugins.LocalNotifications;
    if (!LN) return Promise.resolve();
    return Promise.all(Object.keys(lastChannels).map(function (id) { return LN.createChannel(lastChannels[id]); }))
      .then(function () { return LN.getPending(); })
      .then(function (p) {
        var ours = ((p && p.notifications) || []).filter(function (n) { return n.id >= NATIVE_ID_BASE && n.id < NATIVE_ID_BASE + 100; }).map(function (n) { return { id: n.id }; });
        return ours.length ? LN.cancel({ notifications: ours }) : null;
      })
      // What is replayed is only what is still ahead: LocalNotifications fires an `at` already in the past at once (its own
      // catch-up), so replaying a schedule that has since partly come due would ring for reminders the reader has already
      // heard. The sound source is a setting of the moment, not a reason to repeat a reminder.
      .then(function () {
        var items = ((lastSchedule && lastSchedule.notifications) || []).filter(function (n) {
          var at = n.schedule && n.schedule.at ? new Date(n.schedule.at).getTime() : 0;
          return at > Date.now();
        });
        return items.length ? LN.schedule(Object.assign({}, lastSchedule, { notifications: items })) : null;
      })
      .catch(function (e) { console.log('[dg-uposatha-stream] could not move the reminders:', (e && e.message) || e); });
  }

  // At once, before the page's own scripts reach for the plugin (start() below tries again should Capacitor not have registered it yet).
  if (onCalendar) { if (IOS) wrapIosNotifications(); else wrapLocalNotifications(); }   // at once: the page schedules at its own start

  // The setting itself, in the settings drawer under the page's own sound row. Changing it moves the reminders
  // to the other channels at once (restream above), without reloading the page.
  //
  // The page may rebuild or clone its drawer (a language switch redraws it), and a listener on the
  // select would be lost with the node: the change is caught at the document instead, and the row is
  // put back whenever the page's sound row is there without it.
  function streamRow() {
    var ru = isRu();
    var row = document.createElement('div');
    row.id = 'dg-stream-row';
    row.innerHTML = '<p class="dg-drawer-subtitle"></p><select class="dg-field-input" id="dg-stream"></select>'
      + '<p class="dg-drawer-subtitle dg-stream-note" style="font-weight:400;opacity:.75;margin-top:6px"></p>';
    row.querySelector('.dg-drawer-subtitle').textContent = ru ? 'Источник звука' : 'Sound source';
    var select = row.querySelector('select');
    [['notification', ru ? 'Уведомления' : 'Notifications'], ['alarm', ru ? 'Будильник' : 'Alarm']].forEach(function (o) {
      var opt = document.createElement('option');
      opt.value = o[0];
      opt.textContent = o[1];
      select.appendChild(opt);
    });
    select.value = alarmStream() ? 'alarm' : 'notification';
    row.querySelector('.dg-stream-note').textContent = ru
      ? 'Будильник звучит как будильник: громкостью будильника и сквозь «Не беспокоить».'
      : 'The alarm sounds like an alarm clock: at the alarm volume, and through Do Not Disturb.';
    return row;
  }

  function dndRow() {
    var ru = isRu();
    var row = document.createElement('div');
    row.id = 'dg-dnd-row';
    row.innerHTML = '<p class="dg-drawer-subtitle"></p><button type="button" class="pillbtn" id="dg-dnd-btn"></button>'
      + '<p class="dg-drawer-subtitle dg-dnd-note" style="font-weight:400;opacity:.75;margin-top:6px"></p>';
    row.querySelector('.dg-drawer-subtitle').textContent = ru ? 'Звук при «Не беспокоить»' : 'Sound in Do Not Disturb';
    row.querySelector('.dg-dnd-note').textContent = ru
      ? 'Иначе при включённом «Не беспокоить» напоминание придёт без звука. Разрешить может только владелец телефона, в настройках Android.'
      : 'Without it, a reminder arrives with no sound while Do Not Disturb is on. Only the phone\'s owner can allow it, in Android settings.';
    return row;
  }

  function paintDndRow() {
    var btn = document.getElementById('dg-dnd-btn');
    if (!btn) return;
    var ru = isRu();
    btn.textContent = dndGranted ? (ru ? 'Разрешено ✓' : 'Allowed ✓') : (ru ? 'Разрешить в настройках' : 'Allow in settings');
    btn.disabled = false;
  }

  function ensureStreamRow() {
    var anchor = document.getElementById('rem-sound-row');
    if (!anchor || document.getElementById('dg-stream-row')) return;
    var stream = streamRow();
    anchor.parentNode.insertBefore(stream, anchor.nextSibling);
    stream.parentNode.insertBefore(dndRow(), stream.nextSibling);
    paintDndRow();
  }

  function watchStreamRow() {
    document.addEventListener('change', function (e) {
      var t = e.target;
      if (!t || t.id !== 'dg-stream') return;
      try { localStorage.setItem(STREAM_KEY, t.value); } catch (err) { /* no storage: the choice is lost */ }
      restream();
    }, true);
    document.addEventListener('click', function (e) {
      var b = e.target && e.target.closest && e.target.closest('#dg-dnd-btn');
      var DS = Cap.Plugins && Cap.Plugins.DgSound;
      if (b && DS && typeof DS.requestDndAccess === 'function') DS.requestDndAccess();
    }, true);
    // Back from the system's settings page: has the access been given?
    document.addEventListener('visibilitychange', function () { if (document.visibilityState === 'visible') refreshDnd(); });
    refreshDnd();
    ensureStreamRow();
    new MutationObserver(ensureStreamRow).observe(document.documentElement, { childList: true, subtree: true });
  }

  // ---- Back --------------------------------------------------------------------------------
  //
  // Capacitor's default with no listener is a bare WebView.goBack() and nothing else: on the
  // page's first screen Back does nothing at all. Steps, in order: the rating sheet; the settings
  // drawer; any tab but the first goes back to the first; browser history; leave the app.
  function wireBackButton() {
    var App = Cap.Plugins && Cap.Plugins.App;
    if (!App || typeof App.addListener !== 'function') return;
    App.addListener('backButton', function (ev) {
      if (closeRatePrompt()) return;
      if (document.body.classList.contains('dg-drawer-open')) {
        var close = document.querySelector('#dg-drawer .dg-drawer-close');
        if (close) { close.click(); return; }
      }
      var tab = document.body.getAttribute('data-app-tab');
      if (tab && tab !== 'home') {
        var home = document.querySelector('#appnav [data-tab="home"]');
        if (home) { home.click(); return; }
      }
      if (ev && ev.canGoBack) { window.history.back(); return; }
      App.exitApp();
    });
  }

  function rateUsUrl() { return STORE_URL; }
  // The calendar page only: the invitation must not appear on a page of the site the app merely
  // passed through (a shortcut can open dhamma.gift/4as inside this WebView).
  var RATE_HOME = CALENDAR_PATH;

  // @rate-prompt (inlined from src/native-bridge.js by uposatha/build.js)

  // The OS status/navigation bars (dg-apps#54). One owner per platform:
  //   * Android: DgInsets.setTheme sets the icons AND the window colour in one native call. Not
  //     Capacitor's SystemBars.setStyle: that one ends by repainting the window in the SYSTEM's
  //     background (SystemBars.java, setStyle -> decorView.setBackgroundColor(windowBackground)),
  //     so on a light phone a dark page got white strips above and below it, and on a dark phone a
  //     light page got black ones (owner's screenshots) — whichever call landed last won.
  //   * iOS: SystemBars.setStyle (one status bar; the bar names are ignored there).
  // The colour is the page's own background (--dg-page, also the navy "lunar" look), read from the
  // layout, so the window under the bars is never a different shade from the page.
  // Sent only when it changes, and again when the app comes back to the front.
  function rgbOf(c) {
    var m = /^rgba?\(\s*(\d+)[,\s]+(\d+)[,\s]+(\d+)(?:[,\s/]+([\d.]+))?/.exec(c || '');
    return m ? [+m[1], +m[2], +m[3], m[4] == null ? 1 : +m[4]] : null;
  }
  function pageColor() {
    var hex = pageColorOnly();
    // The menu open on a WebView older than 140: the window is padded natively and its colour is the strip under the
    // clock, so it takes the menu's dimming as well (the tablet screenshot: a white strip over the dimmed page).
    var scrim = document.body.classList.contains('dg-drawer-open') && document.getElementById('dg-drawer-backdrop');
    var dim = scrim && rgbOf(getComputedStyle(scrim).backgroundColor);
    if (!hex || !dim || !dim[3]) return hex;
    var base = [1, 3, 5].map(function (i) { return parseInt(hex.substr(i, 2), 16); });
    return '#' + base.map(function (v, i) { return ('0' + Math.round(v * (1 - dim[3]) + dim[i] * dim[3]).toString(16)).slice(-2); }).join('');
  }
  function pageColorOnly() {
    var c = getComputedStyle(document.body).backgroundColor || '';
    var m = /^rgba?\(\s*(\d+)[,\s]+(\d+)[,\s]+(\d+)/.exec(c);
    var rgb = m ? [+m[1], +m[2], +m[3]] : null;
    if (!rgb) {
      // color-mix() comes back as color(srgb r g b) with 0..1 channels
      m = /^color\(srgb\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)/.exec(c);
      if (m) rgb = [m[1], m[2], m[3]].map(function (v) { return Math.round(Math.min(1, +v) * 255); });
    }
    if (!rgb) return '';
    return '#' + rgb.map(function (v) { return ('0' + v.toString(16)).slice(-2); }).join('');
  }
  function syncSystemBars(force) {
    if (!document.body) return;
    var root = document.documentElement;
    var theme = root.getAttribute('data-theme') || root.getAttribute('data-bs-theme');
    var dark = (theme || (document.body.classList.contains('dark') ? 'dark' : '')) === 'dark';
    var color = pageColor() || (dark ? '#111111' : '#ffffff');
    var key = dark + color;
    if (!force && key === lastBarStyle) return;
    lastBarStyle = key;
    var Insets = Cap.Plugins && Cap.Plugins.DgInsets;
    if (!IOS && Insets && typeof Insets.setTheme === 'function') {
      Insets.setTheme({ dark: dark, color: color }).catch(function () { lastBarStyle = ''; });
      return;
    }
    var SystemBars = Cap.Plugins && Cap.Plugins.SystemBars;
    if (!SystemBars || typeof SystemBars.setStyle !== 'function') return;
    var style = dark ? 'DARK' : 'LIGHT';
    SystemBars.setStyle({ style: style, bar: 'StatusBar' }).catch(function () { lastBarStyle = ''; });
    SystemBars.setStyle({ style: style, bar: 'NavigationBar' }).catch(function () { lastBarStyle = ''; });
  }
  var lastBarStyle = '';

  // ---- links and sharing (dg-apps#56) -------------------------------------------------------------
  // The page lives at the app's own origin (https://uposatha.dhamma.gift), which is not a site: a
  // path of the site opened here (the menu's Help, window.open('/docs/uposatha/')) fell back to the
  // calendar itself, and Share then handed out that address. Every such path goes to dhamma.gift.
  function pageRu() { return /^ru/i.test(document.documentElement.lang || '') || (!document.documentElement.lang && isRu()); }
  function siteUrl(url) {
    var u;
    try { u = new URL(url, location.href); } catch (e) { return url; }
    if (u.origin !== location.origin || CALENDAR_PATH.test(u.pathname)) return url;
    return SITE_CONFIG.site + u.pathname + u.search + u.hash;
  }
  // What Share hands out (owner): the app's page in the docs, which leads to both stores and opens
  // in a browser or in Dhamma.Gift alike.
  function shareUrl() { return SITE_CONFIG.site + (pageRu() ? '/ru' : '') + '/docs/uposatha'; }

  function wireLinksAndShare() {
    var open = window.open;
    window.open = function (url) {
      var args = Array.prototype.slice.call(arguments);
      if (typeof url === 'string' && url) args[0] = siteUrl(url);
      return open.apply(window, args);
    };
    // The system share sheet. iOS has navigator.share; Android's WebView does not, so both share
    // buttons (the page's and the menu's) fell back to "Link copied". DgShare is the native sheet.
    var send = typeof navigator.share === 'function' ? navigator.share.bind(navigator) : null;
    var Share = Cap.Plugins && Cap.Plugins.DgShare;
    if (!send && Share && typeof Share.share === 'function') send = function (d) { return Share.share(d); };
    if (!send) return;
    navigator.share = function (data) {
      return send({ title: (data && data.title) || 'Uposatha', url: shareUrl() });
    };
  }

  // ---- the theme switch: a circle from the tap (dg-apps#55, as in Telegram) ---------------------
  // The page switches the theme synchronously (setTheme / themeswitch.js), so the same click is
  // replayed inside a View Transition and the new theme is revealed through a growing circle. The
  // system bars follow in the same frame (syncSystemBars, from the observer). No View Transitions
  // (WebView < 111, iOS < 18) or reduced motion: the plain instant switch, as before.
  function animateThemeSwitch() {
    if (typeof document.startViewTransition !== 'function') return;
    var replaying = false, running = false;
    document.addEventListener('click', function (e) {
      if (replaying || running) return;
      var btn = e.target && e.target.closest && e.target.closest('#app-theme, #dg-theme-seg button');
      if (!btn) return;
      if (btn.id === 'app-theme' && document.body.classList.contains('dg-drawer-open')) return;   // the share button there
      if (btn.getAttribute('aria-pressed') === 'true') return;
      if (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches) return;
      e.preventDefault();
      e.stopImmediatePropagation();
      // From the button's centre (owner), in the transition layer's own pixels: the page's font size zooms <html>, and
      // the layer's clip-path is zoomed with it, so the centre and the radius are divided by the zoom (without it the
      // circle started 10% off to the side). The radius reaches the farthest corner of the SCREEN: on a phone the
      // snapshot is the large viewport, taller than innerHeight, and a smaller circle stopped short of the bottom.
      var r = btn.getBoundingClientRect();
      var zoom = parseFloat(getComputedStyle(document.documentElement).zoom) || 1;
      var x = r.left + r.width / 2, y = r.top + r.height / 2;
      var w = Math.max(innerWidth, document.documentElement.clientWidth), h = Math.max(innerHeight, screen.height || 0, document.documentElement.clientHeight);
      var radius = Math.hypot(Math.max(x, w - x), Math.max(y, h - y)) + 2;
      x /= zoom; y /= zoom; radius /= zoom;
      running = true;
      // the page's own colour transitions (the top bar fades its background) would show mid-way in the circle
      document.documentElement.classList.add('dg-theme-vt');
      var vt = document.startViewTransition(function () {
        replaying = true;
        try { btn.click(); } finally { replaying = false; }
      });
      vt.ready.then(function () {
        document.documentElement.animate(
          { clipPath: ['circle(0px at ' + x + 'px ' + y + 'px)', 'circle(' + radius + 'px at ' + x + 'px ' + y + 'px)'] },
          { duration: 1000, easing: 'cubic-bezier(.2, 0, 0, 1)', fill: 'both', pseudoElement: '::view-transition-new(root)' });   // tuned with the owner on a demo page
      }).catch(function () {});
      function done() { running = false; document.documentElement.classList.remove('dg-theme-vt'); }
      vt.finished.then(done, done);
    }, true);
  }
  function watchSystemBars() {
    syncSystemBars(true);
    var mo = new MutationObserver(function () { syncSystemBars(false); });
    mo.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme', 'data-bs-theme'] });
    // body.dark and the navy look (body[data-look]) change the page colour too
    mo.observe(document.body, { attributes: true, attributeFilter: ['class', 'data-look', 'data-theme'] });
    document.addEventListener('visibilitychange', function () { if (document.visibilityState === 'visible') syncSystemBars(true); });
    window.addEventListener('focus', function () { syncSystemBars(true); });
    // The inset is re-read when the view changes (rotation, a cutout moving to the side): the bar
    // padding lives in a style tag of its own, so a stale value would stay for the whole session.
    window.addEventListener('resize', function () { applyTopInset(); syncSystemBars(false); });
  }

  // The page's own top bar (.tbar, sticky at top: 0) has no top inset: the site never needed one
  // while Capacitor kept the WebView inside the safe area. Edge to edge (dg-apps#41) that padding is
  // gone on BOTH platforms, so the bar would sit behind the clock / Dynamic Island.
  //
  // The padding is the pattern Capacitor's own SystemBars documentation prescribes (system-bars.md,
  // "Android Note"): the plugin injects --safe-area-inset-* on Android — as a fallback for WebViews
  // below version 140, whose env() is broken — and env() is what iOS uses, live in the engine.
  //
  //   padding-top: calc(10px + var(--safe-area-inset-top, env(safe-area-inset-top, 0px)))
  //
  // It is CSS only: no number is measured and written once at load. That measurement was a race —
  // run 448 probed before WKWebView reported the inset, got 0, wrote no padding, and the bar sat
  // under the clock, while runs 445/446 measured 62px from the same build and looked right.
  var insetsDiag = { plugin: false, answer: null };

  function applyTopInset() {
    if (!document.body) return;
    var css = document.getElementById('dg-safe-top');
    if (!css) { css = document.createElement('style'); css.id = 'dg-safe-top'; document.head.appendChild(css); }
    // The top bar, and the burger menu's drawer (the reader pads its own drawer the same way:
    // dg-node home.css, html.dg-app #dg-drawer{padding-top: var(--dg-sat)}). Without it the drawer
    // opens under the clock on Android — the main screen looked right while the menu did not.
    // Every inset is divided by --dg-zoom: the page's font-size setting zooms <html> (home.js,
    // applyUiScale sets zoom and --dg-zoom), so a CSS px there is the zoomed one while the inset is
    // a viewport measurement. The site divides its own --dg-sat/--dg-sab exactly so (home.css);
    // without it the padding would grow with the font size and the bar would sit lower each step.
    var TOP_PAD = 4;   // px above the bar's content row; the site's own 10px made the app bar sit lower than WhatsApp/Notion
    var SAT = 'var(--safe-area-inset-top, env(safe-area-inset-top, 0px)) / var(--dg-zoom, 1)';
    var SAL = 'var(--safe-area-inset-left, env(safe-area-inset-left, 0px)) / var(--dg-zoom, 1)';
    var SAR = 'var(--safe-area-inset-right, env(safe-area-inset-right, 0px)) / var(--dg-zoom, 1)';
    // The top bar, and the burger menu's drawer (the reader pads its own drawer the same way:
    // dg-node home.css, html.dg-app #dg-drawer{padding-top: var(--dg-sat)}). Without it the drawer
    // opens under the clock on Android — the main screen looked right while the menu did not.
    css.textContent = 'body.app .tbar{padding-top:calc(' + TOP_PAD + 'px + ' + SAT + ')}'
      + 'body.app #dg-drawer{padding-top:calc(' + SAT + ')}'
      // Owner: the chosen half of a segmented control (language, theme, week start) is grey
      // (--dg-surface-active) while a switched-on toggle is the accent green (--dg-toggle-row
      // [aria-pressed=true] .dg-tgl{background:var(--dg-accent)}). One colour for both states.
      + 'body.app .dg-segmented button[aria-pressed="true"],body.app .segrow button[aria-pressed="true"]'
      + '{background:var(--dg-accent);color:var(--dg-on-accent,#fff)}'
      + 'body.app .dg-segmented button[aria-pressed="true"] .dg-seg-ic{color:inherit}'
      + 'body.app .dg-segmented button[aria-pressed="true"] svg{color:inherit}'
      // The page's own side panel (uposatha-calendar.css .drawer/.panel, padding 16px 18px 30px)
      // is fixed at top: 0 as well — the same trap the burger menu fell into.
      + 'body.app .drawer,body.app .panel{padding-top:calc(16px + ' + SAT + ')}'
      // Landscape on a phone with a camera cutout: the insets move to the sides. The page's content
      // is inset, and so is the drawer (fixed, right: 0), which would otherwise sit under the cutout.
      // The page's content spans the viewport, so both sides are inset. The drawer only touches the
      // RIGHT edge (right: 0): padding it on the left as well drew an empty band between the page and
      // the drawer's content — the "лишние полоски" the owner saw on a tablet in landscape, where the
      // side navigation bar makes those insets non-zero.
      + 'body.app{padding-left:calc(' + SAL + ');padding-right:calc(' + SAR + ')}'
      + 'body.app #dg-drawer{padding-right:calc(' + SAR + ')}'
      // The tab bar's own z-index (app-nav.css: 1090) is above the drawer's (dg-node home.css:
      // 1085), so the pill bar was drawn over the open burger menu — badly visible in landscape,
      // where the menu is narrow and the screen short. While the menu is open (the page sets
      // body.dg-drawer-open), the bar has no business on screen.
      // The two "time for food" reminders: the list of leads sat flush against the switch above it (owner's screenshot).
      + 'body.app #mbeg-lead,body.app #mrem-lead{margin-top:14px}'
      + 'body.app.dg-drawer-open .appnav{display:none}'
      // The top bar is a floating pill like the tab bar below (dg-apps#54, owner: "as in Telegram, the text should be seen
      // where the beard was"): no solid band under the clock, the page shows through above and around the pill.
      + 'body.app .tbar,body.app.scrolled .tbar{background:transparent;box-shadow:none}'
      + 'body.app .tbar>*{position:relative}'
      + 'body.app .tbar::before{content:"";position:absolute;left:10px;right:10px;top:calc(' + SAT + ' + 2px);bottom:2px;border-radius:30px;'
      + 'background:color-mix(in srgb,var(--dg-surface) 80%,transparent);-webkit-backdrop-filter:blur(18px) saturate(1.6);backdrop-filter:blur(18px) saturate(1.6);'
      + 'border:1px solid var(--dg-border);box-shadow:0 8px 24px rgba(0,0,0,.12)}'
      // "Link copied" from the menu's share (settings.js showBubbleNotification): its styles are
      // the site's (extrastyles.css), which this page does not load, so it was a bare full-width bar.
      // It and the page's own toast sit above the tab bar, not under it.
      + 'body.app .bubble-notification,body.app .toast{position:fixed;left:50%;right:auto;top:auto;bottom:calc(96px + var(--safe-area-inset-bottom, env(safe-area-inset-bottom, 0px)));'
      + 'max-width:calc(100% - 32px);transform:translate(-50%,20px);background:var(--dg-navy,#1d2b4a);color:#fff;padding:9px 16px;border-radius:999px;'
      + 'font-size:13px;line-height:1.35;text-align:center;box-shadow:0 6px 20px rgba(0,0,0,.2);opacity:0;pointer-events:none;transition:opacity .2s,transform .2s;z-index:2000}'
      + 'body.app .bubble-notification.show,body.app .toast.on{opacity:1;transform:translate(-50%,0)}'
      // the theme circle (animateThemeSwitch): the new theme is clipped in over the old one
      + '::view-transition-old(root),::view-transition-new(root){animation:none;mix-blend-mode:normal}'
      + 'html.dg-theme-vt *{transition:none!important}';
    // iOS: ask the app for the web view's own insets, at the moment the page is ready. Android's
    // SystemBars plugin injects the same variables itself (and env() covers the modern WebViews),
    // so this only runs where the plugin exists.
    // Android (dg-apps#54): no second source. The page is viewport-fit=cover there and Capacitor's
    // SystemBars passes the insets through (WebView 140+: env() and --safe-area-inset-*), or pads
    // the window itself and writes 0 (older WebViews). Asking natively as well was the double gap.
    var Insets = IOS && Cap.Plugins && Cap.Plugins.DgInsets;
    insetsDiag = { plugin: !!Insets, answer: null };
    if (Insets && typeof Insets.get === 'function') {
      Insets.get().then(function (i) {
        insetsDiag.answer = i;
        var root = document.documentElement;
        ['top', 'right', 'bottom', 'left'].forEach(function (k) {
          var v = Math.round((i && i[k]) || 0);
          if (v > 0) root.style.setProperty('--safe-area-inset-' + k, v + 'px');
          else root.style.removeProperty('--safe-area-inset-' + k);
        });
        setTimeout(function () { reportInset(effectiveInset()); }, 30);
      }).catch(function () { setTimeout(function () { reportInset(effectiveInset()); }, 30); });
    }
    var top = effectiveInset();
    if (top > 0) document.body.classList.add('dg-safe-top-on');
    setTimeout(function () { reportInset(top); }, 60);
  }

  // The page's own measurements, for an automated proof. DgSelfTest is registered in DEBUG builds
  // only (uposatha/ios/App/App/DgSelfTestPlugin.swift), so a shipped app and Android ignore this.
  // The inset the page really ended up with: what the bar's own padding comes to, whichever source
  // supplied it (the live env(), the plugin's variable, or nothing at all). Read from the layout, so
  // a probe that ran too early cannot flatter it.
  function effectiveInset() {
    var bar = document.querySelector('.tbar');
    if (!bar) return 0;
    return Math.max(0, Math.round((parseFloat(getComputedStyle(bar).paddingTop) || 0) - 4));
  }

  // Where a proof reads the page's own measurements from: the iOS DEBUG plugin writes a file in the
  // app's Documents; on Android the same JSON goes through DgSite (files/site/), which the emulator
  // check reads with `adb shell run-as`. A shipped app has neither, and loses nothing.
  function sendReport(obj) {
    var Self = Cap.Plugins && Cap.Plugins.DgSelfTest;
    if (Self && typeof Self.report === 'function') { Self.report(obj).catch(function () {}); return; }
    var Site = Cap.Plugins && Cap.Plugins.DgSite;
    if (!Site || typeof Site.put !== 'function' || typeof window.btoa !== 'function') return;
    try {
      Site.put({ path: '/dg-edgetoedge.json', data: window.btoa(unescape(encodeURIComponent(JSON.stringify(obj)))) })
        .catch(function () {});
    } catch (e) { /* no transport: a release build without the proof plugins */ }
  }

  function reportInset(top) {
    var meta = document.querySelector('meta[name=viewport]');
    var bar = document.querySelector('.tbar');
    var rect = bar ? bar.getBoundingClientRect() : null;
    // The burger menu's drawer: its content must clear the status bar too (it is the failure the
    // owner hit on Android — the page looked right, the menu opened under the clock).
    var drawer = document.getElementById('dg-drawer');
    var drawerRect = drawer ? drawer.getBoundingClientRect() : null;
    var drawerPad = drawer ? (parseFloat(getComputedStyle(drawer).paddingTop) || 0) : 0;
    // The bar is sticky at top: 0 and its padding is what keeps it clear of the status bar, so what
    // matters is where its CONTENT starts, not the (always 0) top of the element.
    var padTop = bar ? (parseFloat(getComputedStyle(bar).paddingTop) || 0) : 0;
    sendReport({
      topInset: effectiveInset(),
      // What the native side answered (diagnostics for the iOS proof: the env() value there cannot
      // be trusted, so the answer and whether the plugin exists are the things to look at).
      insetsPlugin: insetsDiag.plugin,
      insetsAnswer: insetsDiag.answer,
      // Portrait or landscape: the iPhone app is portrait only now, and the proof judges the
      // portrait state (the last write used to be a landscape one with top 0, which read as a
      // failure of the page).
      orientation: window.innerWidth > window.innerHeight ? 'landscape' : 'portrait',
      viewportFit: !!(meta && /viewport-fit\s*=\s*cover/.test(meta.getAttribute('content') || '')),
      barTop: rect ? Math.round(rect.top + padTop) : -1,
      barContentTop: rect ? Math.round(rect.top + padTop) : -1,
      barBottom: rect ? Math.round(rect.bottom) : -1,
      drawerOpen: !!(drawer && !drawer.hasAttribute('hidden')),
      drawerContentTop: drawerRect ? Math.round(drawerRect.top + drawerPad) : -1,
      theme: document.documentElement.getAttribute('data-theme') || ''
    });
  }

  function start() {
    if (!onCalendar) { if (!IOS) wireBackButton(); return; }
    watchSystemBars();
    applyTopInset();
    wireLinksAndShare();
    animateThemeSwitch();
    if (IOS) { wrapIosNotifications(); wireIosShortcutTaps(); }
    else { wireBackButton(); wrapLocalNotifications(); watchStreamRow(); }
    // #up-rate's href is dg-node's own static markup (uposatha-calendar.html) — the Play Store URL,
    // because the page has no way to know which platform loaded it. On iOS that sent a reader
    // straight into a Play Store 404 in Safari (dg-apps#38: "Ссылка в рейтинге ведёт на гугл"). One
    // native fact the page cannot have on its own; this is the one place that supplies it.
    if (IOS) {
        var rateRow = document.getElementById('up-rate');
        if (rateRow) rateRow.href = STORE_URL;
    }
    // The page's own Rate Us row: note the tap, so the invitation never asks someone who has been.
    document.addEventListener('click', function (e) {
      var a = e.target && e.target.closest && e.target.closest('#up-rate');
      if (a) { try { localStorage.setItem(RATE_FLAG, '1'); } catch (err) { /* no storage */ } }
    }, true);
    // UposathaCore is loaded by the page: give it until the page has finished loading.
    function afterLoad() {
      pushShortcuts();
      setTimeout(updateSite, 6000);
      applyTopInset();
      // ?drawer=1: the proof opens the burger menu itself (Android: android-screens mode=edgetoedge).
      // A tap cannot be aimed at a WebView element from adb, and a check that guesses coordinates
      // ends up testing the guess.
      if (/[?&]drawer=1/.test(location.search)) {
        var burger = document.getElementById('b-menu');
        if (burger) { burger.click(); setTimeout(function () { reportInset(effectiveInset()); }, 700); }
      }
    }
    if (document.readyState === 'complete') afterLoad();
    else window.addEventListener('load', afterLoad, { once: true });
    document.addEventListener('visibilitychange', function () { if (document.visibilityState === 'hidden') pushShortcuts(); });
    if (!IOS) maybeAskForRating();   // (iOS: when the App Store listing exists and has its address)
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
