// Pull to refresh, the same in all three apps (owner, 2026-10-11: "нужно, чтобы можно было освежить
// страницу ... в браузере потянуть вниз и освежается"; "один общий код"). A WebView has no such gesture
// of its own, so a pull down from the very top of the page reloads it, as a browser does.
//
// Only a pull that starts on the page itself, already scrolled to the top: anything inside a fixed
// layer (a sheet, a popup, a toolbar, the player) keeps its own gestures, and so does any inner box
// that is scrolled. Included as /pull-refresh.js by Dhamma.Gift's page (build-page.js) and inlined
// by the dictionary's and Uposatha's bridges ("// @pull-refresh"); all three run it before the page
// draws anything (a <script> at the top of <head>, a document-start script).
//
// The reload itself must not show. A bare reload painted blank, then the page in fallback fonts without
// its icons, then jumped when the fonts arrived ("передергивается ... как дешевый HTML"); a fade over it
// was "дорогое мелькание". The owner's way: the page stays exactly as it is, and the new one just appears.
// So the app holds a picture of the page on screen, with this spinner cut out of it and turning, reloads
// the page under the picture, and the new page lets go of it once it has loaded with its fonts
// (DgPullHoldPlugin.java on Android, DgPullHold in the iOS bridge view controller). With no native
// side (a browser, an older app) it is a plain reload.
(function () {
    if (window.dgPullRefresh) return;
    window.dgPullRefresh = true;
    var PULL = 72, MAX = 110, SIZE = 38, KEY = 'dgPullRefresh';
    var y0 = null, x0 = 0, dist = 0, dragging = false, ring = null;

    function nativeHold(msg) {
        if (window.DgPullHold) {   // Android: a JavaScript interface
            if (msg.op === 'hold') window.DgPullHold.hold(msg.x, msg.y, msg.size); else window.DgPullHold.release();
            return true;
        }
        var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.dgPullHold;
        if (h) { h.postMessage(msg); return true; }   // iOS: a script message handler
        return false;
    }

    // The new page after a pull: let go of the picture once this page is ready to be seen whole.
    (function arrive() {
        var t = 0;
        try { t = +sessionStorage.getItem(KEY) || 0; sessionStorage.removeItem(KEY); } catch (e) {}
        if (!t || Date.now() - t > 10000) return;
        var done = false;
        function release() {
            if (done) return;
            done = true;
            requestAnimationFrame(function () { requestAnimationFrame(function () {
                setTimeout(function () { nativeHold({ op: 'release' }); }, 50);
            }); });
        }
        function loaded() { (document.fonts && document.fonts.ready || Promise.resolve()).then(release, release); }
        if (document.readyState === 'complete') loaded(); else addEventListener('load', loaded);
    })();

    function blocked(t) {
        for (var n = t && t.nodeType === 1 ? t : t && t.parentElement; n && n !== document.documentElement; n = n.parentElement) {
            if (n.scrollTop > 0 || getComputedStyle(n).position === 'fixed') return true;
            if (n.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(n.tagName)) return true;
        }
        return (document.scrollingElement || document.documentElement).scrollTop > 0;
    }

    function makeRing() {
        var cs = getComputedStyle(document.body), bg = cs.backgroundColor;
        if (!bg || bg === 'transparent' || /rgba\(.*,\s*0\)$/.test(bg)) bg = getComputedStyle(document.documentElement).backgroundColor;
        if (!bg || bg === 'transparent' || /rgba\(.*,\s*0\)$/.test(bg)) bg = '#fff';
        var d = document.createElement('div');
        d.setAttribute('aria-hidden', 'true');
        d.style.cssText = 'position:fixed;left:50%;top:calc(env(safe-area-inset-top,0px) - ' + SIZE + 'px);z-index:2147483001;'
            + 'width:' + SIZE + 'px;height:' + SIZE + 'px;margin-left:-' + (SIZE / 2) + 'px;border-radius:50%;'
            + 'display:flex;align-items:center;justify-content:center;pointer-events:none;'
            + 'background:' + bg + ';color:' + cs.color + ';box-shadow:0 2px 8px rgba(0,0,0,.28);opacity:0';
        // The arc-arrow of a browser's reload, drawn here so no app needs an icon file for it: the arc
        // grows with the pull and the arrowhead appears once a release would reload.
        d.innerHTML = '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">'
            + '<circle cx="12" cy="12" r="8" stroke-dasharray="0 60" transform="rotate(-18 12 12)"/><path d="M10 1.5l3.5 2.5-3.5 2.5" opacity="0"/></svg>';
        document.body.appendChild(d);
        return d;
    }

    function paint(d, animate) {
        var p = Math.min(d / PULL, 1);
        ring.style.transition = animate ? 'transform .2s, opacity .2s' : 'none';
        ring.style.transform = 'translateY(' + Math.min(d, MAX) + 'px) rotate(' + (p * 270) + 'deg)';
        ring.style.opacity = d > 0 ? String(0.35 + 0.65 * p) : '0';
        ring.querySelector('circle').setAttribute('stroke-dasharray', (p * 40.2).toFixed(1) + ' 60');
        ring.querySelector('path').setAttribute('opacity', p >= 1 ? '1' : '0');
    }

    addEventListener('touchstart', function (e) {
        y0 = null;
        if (e.touches.length !== 1 || blocked(e.target)) return;
        y0 = e.touches[0].clientY; x0 = e.touches[0].clientX; dist = 0; dragging = false;
    }, { passive: true });

    addEventListener('touchmove', function (e) {
        if (y0 === null) return;
        if (e.touches.length !== 1) { y0 = null; if (ring) paint(0, true); return; }
        var dy = e.touches[0].clientY - y0, dx = e.touches[0].clientX - x0;
        if (!dragging) {
            if (Math.abs(dy) < 10 && Math.abs(dx) < 10) return;
            if (dy <= 0 || Math.abs(dx) > dy || (document.scrollingElement || document.documentElement).scrollTop > 0) { y0 = null; return; }
            dragging = true;
            if (ring) ring.remove();
            ring = makeRing();
        }
        dist = Math.max(0, dy * 0.55);
        paint(dist, false);
    }, { passive: true });

    function end() {
        if (y0 === null) return;
        y0 = null;
        if (!dragging) return;
        dragging = false;
        if (dist < PULL) return void paint(0, true);
        paint(PULL, false);
        ring.animate([{ transform: 'translateY(' + PULL + 'px) rotate(0deg)' }, { transform: 'translateY(' + PULL + 'px) rotate(360deg)' }],
            { duration: 700, iterations: Infinity });
        // Two frames: the spinner is on screen, at rest, before the picture is taken of it.
        requestAnimationFrame(function () { requestAnimationFrame(function () {
            try { sessionStorage.setItem(KEY, String(Date.now())); } catch (e) {}
            // The ring's centre does not move as it turns (its bounding box does), so its square is around that
            // centre; its side is SIZE times the page's CSS zoom (Dhamma.Gift and the dictionary zoom <html>).
            var r = ring.getBoundingClientRect(), cx = r.left + r.width / 2, cy = r.top + r.height / 2;
            var side = SIZE * (ring.currentCSSZoom || 1);
            if (!nativeHold({ op: 'hold', x: cx - side / 2, y: cy - side / 2, size: side })) location.reload();
        }); });
    }
    addEventListener('touchend', end, { passive: true });
    addEventListener('touchcancel', end, { passive: true });
})();
