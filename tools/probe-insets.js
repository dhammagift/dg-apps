// Run in the page (playwright-cli eval) of a served www/: lists visible elements that start above the status strip (must be empty).
() => {
  window.Capacitor = { Plugins: { SystemBars: { setStyle: () => Promise.resolve() } }, getPlatform: () => 'android' };
  document.documentElement.style.setProperty('--safe-area-inset-top', '24px');
  return new Promise(res => {
    const s = document.createElement('script'); s.src = '/native-bridge.js?x=' + Date.now();
    s.onload = () => setTimeout(() => {
      const strip = document.getElementById('dg-edge-strip');
      const h = strip ? strip.offsetHeight : -1;
      const hits = [];
      for (const el of document.body.getElementsByTagName('*')) {
        if (el === strip) continue;
        const cs = getComputedStyle(el); const r = el.getBoundingClientRect();
        if (r.height < 4 || r.width < 4 || cs.visibility === 'hidden' || cs.display === 'none') continue;
        if (r.top < h - 1 && r.bottom > 1 && r.top >= -1) {
          const t = (el.innerText || el.getAttribute('aria-label') || el.tagName).trim().slice(0, 25);
          hits.push(el.tagName + (el.id ? '#' + el.id : '') + ' top=' + Math.round(r.top) + ' pos=' + cs.position + ' "' + t + '"');
        }
      }
      res({ strip: h, bg: strip && strip.style.background, under: hits.slice(0, 4) });
    }, 2200);
    document.body.appendChild(s);
  });
}
