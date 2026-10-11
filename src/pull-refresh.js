// Pull to refresh, the same in all three apps (owner, 2026-10-11: "нужно, чтобы можно было освежить
// страницу ... в браузере потянуть вниз и освежается"; "один общий код"). Included as /pull-refresh.js by
// Dhamma.Gift's page (build-page.js) and inlined by the dictionary's and Uposatha's bridges ("// @pull-refresh").
//
// The gesture and the spinner are the apps': a Chrome-style circle over the page on iOS (DgPullHold/DgPullCircle in the
// bridge view controller), SwipeRefreshLayout on Android (DgPullHoldPlugin.java). A spinner drawn here, over a held picture
// of the page, "дергается ... выглядит кошмарно дешево" (owner, TestFlight). The app freezes the page as it is,
// reloads it under the picture, and lets go once the new page says it is ready, so the content just changes.
//
// What is left to the page: (1) whether a pull may refresh at all — only one that starts on the page itself,
// scrolled to the top; anything inside a fixed layer (a sheet, a popup, a toolbar, the player), a field or a
// scrolled box keeps its own gestures; (2) saying when the new page is ready: loaded, with its fonts, painted.
(function () {
    if (window.dgPullRefresh) return;
    window.dgPullRefresh = true;
    var android = window.DgPullHold;   // a JavaScript interface
    var ios = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.dgPullHold;
    if (!android && !ios) return;      // a browser has its own pull to refresh
    var allowed = false;

    function blocked(t) {
        for (var n = t && t.nodeType === 1 ? t : t && t.parentElement; n && n !== document.documentElement; n = n.parentElement) {
            if (n.scrollTop > 0 || getComputedStyle(n).position === 'fixed') return true;
            if (n.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(n.tagName)) return true;
        }
        return (document.scrollingElement || document.documentElement).scrollTop > 0;
    }

    // Decided when the finger lands and told to the app before it takes the drag over (on Android with the address,
    // so the answer is known to be this page's, not the one before it).
    addEventListener('touchstart', function (e) {
        allowed = e.touches.length === 1 && !blocked(e.target);
        if (android) android.setAllowed(allowed, location.href); else ios.postMessage({ op: 'allowed', value: allowed });
    }, { passive: true, capture: true });

    // Every page says it once; with no refresh under way the app ignores it.
    var sent = false;
    function ready() {
        if (sent) return;
        sent = true;
        requestAnimationFrame(function () { requestAnimationFrame(function () {
            if (android) android.release(); else ios.postMessage({ op: 'release' });
        }); });
    }
    function loaded() { (document.fonts && document.fonts.ready || Promise.resolve()).then(ready, ready); }
    if (document.readyState === 'complete') loaded(); else addEventListener('load', loaded);
})();
