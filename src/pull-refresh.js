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
// The reload itself must not show (owner on the first build: "страница вся передергивается ... как
// какой-то дешевый HTML"): a reloaded page first paints blank, then in fallback fonts without its
// icons, then jumps when its fonts arrive. So the page fades under a cover of its own background with
// the spinner on it, the reload happens under that cover, and the new page carries the same cover from
// its first frame (sessionStorage) until it has loaded with its fonts, then fades in whole.
(function () {
    if (window.dgPullRefresh) return;
    window.dgPullRefresh = true;
    var PULL = 72, MAX = 110, SIZE = 38, KEY = 'dgPullRefresh';
    var y0 = null, x0 = 0, dist = 0, dragging = false, ring = null;

    function colors() {
        var cs = getComputedStyle(document.body), bg = cs.backgroundColor;
        if (!bg || bg === 'transparent' || /rgba\(.*,\s*0\)$/.test(bg)) bg = getComputedStyle(document.documentElement).backgroundColor;
        if (!bg || bg === 'transparent' || /rgba\(.*,\s*0\)$/.test(bg)) bg = '#fff';
        return { bg: bg, fg: cs.color };
    }

    function el(css, html) {
        var d = document.createElement('div');
        d.setAttribute('aria-hidden', 'true');
        d.style.cssText = css;
        if (html) d.innerHTML = html;
        (document.body || document.documentElement).appendChild(d);
        return d;
    }

    function makeRing(c) {
        // The arc-arrow of a browser's reload, drawn here so no app needs an icon file for it: the arc
        // grows with the pull and the arrowhead appears once a release would reload.
        return el('position:fixed;left:50%;top:calc(env(safe-area-inset-top,0px) - ' + SIZE + 'px);z-index:2147483001;'
            + 'width:' + SIZE + 'px;height:' + SIZE + 'px;margin-left:-' + (SIZE / 2) + 'px;border-radius:50%;'
            + 'display:flex;align-items:center;justify-content:center;pointer-events:none;'
            + 'background:' + c.bg + ';color:' + c.fg + ';box-shadow:0 2px 8px rgba(0,0,0,.28);opacity:0',
            '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">'
            + '<circle cx="12" cy="12" r="8" stroke-dasharray="0 60" transform="rotate(-18 12 12)"/><path d="M10 1.5l3.5 2.5-3.5 2.5" opacity="0"/></svg>');
    }

    function paint(d, animate) {
        var p = Math.min(d / PULL, 1);
        ring.style.transition = animate ? 'transform .2s, opacity .2s' : 'none';
        ring.style.transform = 'translateY(' + Math.min(d, MAX) + 'px) rotate(' + (p * 270) + 'deg)';
        ring.style.opacity = d > 0 ? String(0.35 + 0.65 * p) : '0';
        ring.querySelector('circle').setAttribute('stroke-dasharray', (p * 40.2).toFixed(1) + ' 60');
        ring.querySelector('path').setAttribute('opacity', p >= 1 ? '1' : '0');
    }

    function spin() {
        paint(PULL, false);
        ring.animate([{ transform: 'translateY(' + PULL + 'px) rotate(0deg)' }, { transform: 'translateY(' + PULL + 'px) rotate(360deg)' }],
            { duration: 700, iterations: Infinity });
    }

    function cover(c, opacity) {
        return el('position:fixed;inset:0;z-index:2147483000;pointer-events:none;background:' + c.bg + ';opacity:' + opacity + ';transition:opacity .2s');
    }

    // The new page after a pull: the cover and the spinner from the first frame, off once it is ready.
    (function arrive() {
        var c = null;
        try { c = JSON.parse(sessionStorage.getItem(KEY) || 'null'); sessionStorage.removeItem(KEY); } catch (e) {}
        if (!c || Date.now() - c.t > 10000) return;
        function show() {
            if (!document.documentElement) return void requestAnimationFrame(show);
            var veil = cover(c, 1);
            ring = makeRing(c);
            spin();
            var shown = Date.now(), done = false;
            function reveal() {
                if (done) return;
                done = true;
                setTimeout(function () {
                    requestAnimationFrame(function () { requestAnimationFrame(function () {
                        veil.style.transition = 'opacity .25s';
                        veil.style.opacity = '0';
                        ring.getAnimations().forEach(function (a) { a.cancel(); });
                        paint(0, true);
                        setTimeout(function () { veil.remove(); }, 300);
                    }); });
                }, Math.max(0, 250 - (Date.now() - shown)));
            }
            function loaded() {
                (document.fonts && document.fonts.ready || Promise.resolve()).then(reveal, reveal);
            }
            if (document.readyState === 'complete') loaded(); else addEventListener('load', loaded);
            setTimeout(reveal, 5000);
        }
        show();
    })();

    function blocked(t) {
        for (var n = t && t.nodeType === 1 ? t : t && t.parentElement; n && n !== document.documentElement; n = n.parentElement) {
            if (n.scrollTop > 0 || getComputedStyle(n).position === 'fixed') return true;
            if (n.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(n.tagName)) return true;
        }
        return (document.scrollingElement || document.documentElement).scrollTop > 0;
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
            ring = makeRing(colors());
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
        var c = colors();
        spin();
        var veil = cover(c, 0);
        requestAnimationFrame(function () { veil.style.opacity = '1'; });
        try { sessionStorage.setItem(KEY, JSON.stringify({ bg: c.bg, fg: c.fg, t: Date.now() })); } catch (e) {}
        setTimeout(function () { location.reload(); }, 220);
    }
    addEventListener('touchend', end, { passive: true });
    addEventListener('touchcancel', end, { passive: true });
})();
