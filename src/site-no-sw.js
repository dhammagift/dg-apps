// Shared by the bundled-page apps (Uposatha, Dict): the page is bundled in the APK and the site's own service worker must
// not run in the app. Pasted into each bridge by its build.js at the marker "// @site-updater" (Dict adds site-updater.js to it).
//
// Uses the bridge's Cap (window.Capacitor).
  // ---- no service worker ---------------------------------------------------------------------
  //
  // The site's page registers its own service worker (/sw.js, its caching for the website). In the app the
  // files come from the APK and DgSite, and a second layer of caching on top of them would decide what the
  // reader sees behind our back: registrations are swallowed here.
  if (navigator.serviceWorker && typeof navigator.serviceWorker.register === 'function') {
    navigator.serviceWorker.register = function () {
      return Promise.resolve({ scope: '/', update: function () { return Promise.resolve(); }, unregister: function () { return Promise.resolve(true); } });
    };
  }
