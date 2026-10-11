// Pull to refresh, the same in all three apps (owner, 2026-10-11: "нужно, чтобы можно было освежить
// страницу ... в браузере потянуть вниз и освежается"; "один общий код"). A WebView has no such gesture
// of its own, so a pull down from the very top of the page reloads it, as a browser does.
//
// Only a pull that starts on the page itself, already scrolled to the top: anything inside a fixed
// layer (a sheet, a popup, a toolbar, the player) keeps its own gestures, and so does any inner box
// that is scrolled. Included as /pull-refresh.js by Dhamma.Gift's page (build-page.js) and inlined
// by the dictionary's and Uposatha's bridges ("// @pull-refresh").
(function () {
    if (window.dgPullRefresh) return;
    window.dgPullRefresh = true;
    var PULL = 72, MAX = 110, SIZE = 38;
    var y0 = null, x0 = 0, dist = 0, dragging = false, ring = null;

    function blocked(t) {
        for (var n = t && t.nodeType === 1 ? t : t && t.parentElement; n && n !== document.documentElement; n = n.parentElement) {
            if (n.scrollTop > 0 || getComputedStyle(n).position === 'fixed') return true;
            if (n.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(n.tagName)) return true;
        }
        return (document.scrollingElement || document.documentElement).scrollTop > 0;
    }

    function make() {
        var cs = getComputedStyle(document.body);
        var bg = cs.backgroundColor;
        if (!bg || bg === 'transparent' || /rgba\(.*,\s*0\)$/.test(bg)) bg = getComputedStyle(document.documentElement).backgroundColor || '#fff';
        ring = document.createElement('div');
        ring.id = 'dg-ptr';
        ring.setAttribute('aria-hidden', 'true');
        ring.style.cssText = 'position:fixed;left:50%;top:calc(env(safe-area-inset-top,0px) - ' + SIZE + 'px);z-index:2147483000;'
            + 'width:' + SIZE + 'px;height:' + SIZE + 'px;margin-left:-' + (SIZE / 2) + 'px;border-radius:50%;'
            + 'display:flex;align-items:center;justify-content:center;pointer-events:none;'
            + 'background:' + bg + ';color:' + cs.color + ';box-shadow:0 2px 8px rgba(0,0,0,.28);opacity:0';
        // The arc-arrow of a browser's reload, drawn here so no app needs an icon file for it.
        ring.innerHTML = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">'
            + '<path d="M20 12a8 8 0 1 1-2.34-5.66"/><path d="M20 4v5h-5"/></svg>';
        document.body.appendChild(ring);
    }

    function paint(d, animate) {
        var p = Math.min(d / PULL, 1);
        ring.style.transition = animate ? 'transform .2s, opacity .2s' : 'none';
        ring.style.transform = 'translateY(' + Math.min(d, MAX) + 'px) rotate(' + (p * 270) + 'deg)';
        ring.style.opacity = d > 0 ? String(0.35 + 0.65 * p) : '0';
        ring.firstChild.style.opacity = p >= 1 ? '1' : '.55';
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
            if (!ring) make();
        }
        dist = Math.max(0, dy * 0.55);
        paint(dist, false);
    }, { passive: true });

    function end() {
        if (y0 === null) return;
        y0 = null;
        if (!dragging) return;
        dragging = false;
        if (dist >= PULL) {
            paint(PULL, true);
            ring.animate([{ transform: 'translateY(' + PULL + 'px) rotate(0deg)' }, { transform: 'translateY(' + PULL + 'px) rotate(360deg)' }],
                { duration: 700, iterations: Infinity });
            setTimeout(function () { location.reload(); }, 150);
        } else {
            paint(0, true);
        }
    }
    addEventListener('touchend', end, { passive: true });
    addEventListener('touchcancel', end, { passive: true });
})();
