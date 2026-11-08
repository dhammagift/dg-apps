package gift.dhamma.mobile;

import android.app.UiAutomation;
import android.os.ParcelFileDescriptor;
import android.util.Log;
import android.webkit.WebView;

import androidx.test.core.app.ActivityScenario;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.UiDevice;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.File;
import java.io.FileInputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.Assert.assertTrue;

/**
 * The checks of a test build in ONE run (owner 2026-11-07: «не тыкал по одной проверке, а прямо массово проверял всё»):
 * each case drives the page the way a reader would (its own buttons, through the page's JS), measures what the change is
 * about, saves a screenshot (the app's external files/shots, pulled by Test Lab) and logs "DgReleaseTest PASS|FAIL name -
 * detail". Every case runs even when one before it failed; the test fails at the end with the list.
 * Robo scripts could not do this: in a WebView they find buttons by their label only now and then (Test Lab 2026-11-07).
 */
@RunWith(AndroidJUnit4.class)
public class ReleaseChecksTest {
    private static final String TAG = "DgReleaseTest";
    private static File shots;
    private final List<String> failed = new ArrayList<>();

    private static String js(ActivityScenario<MainActivity> s, String code) throws InterruptedException {
        AtomicReference<String> out = new AtomicReference<>();
        CountDownLatch done = new CountDownLatch(1);
        s.onActivity(a -> {
            WebView w = a.getBridge().getWebView();
            w.evaluateJavascript(code, v -> { out.set(v); done.countDown(); });
        });
        done.await(20, TimeUnit.SECONDS);
        String v = out.get();
        // evaluateJavascript hands strings back JSON-quoted
        if (v != null && v.length() >= 2 && v.startsWith("\"") && v.endsWith("\"")) v = v.substring(1, v.length() - 1).replace("\\\"", "\"");
        return v;
    }

    // Polls a JS expression until it is "true" or the time runs out.
    private static boolean until(ActivityScenario<MainActivity> s, String cond, long ms) throws InterruptedException {
        long end = System.currentTimeMillis() + ms;
        while (System.currentTimeMillis() < end) {
            if ("true".equals(js(s, "(function(){try{return !!(" + cond + ")}catch(e){return false}})()"))) return true;
            Thread.sleep(500);
        }
        return false;
    }

    // A shell command as the test: Test Lab runs instrumentation with the system animations off, and the WebView then
    // reports prefers-reduced-motion, which the theme circle honours by not drawing (02 and 09 failed for that, 2026-11-07).
    private static String sh(String cmd) {
        UiAutomation ua = InstrumentationRegistry.getInstrumentation().getUiAutomation();
        StringBuilder out = new StringBuilder();
        try (ParcelFileDescriptor pfd = ua.executeShellCommand(cmd); FileInputStream in = new FileInputStream(pfd.getFileDescriptor())) {
            byte[] buf = new byte[4096]; int n;
            while ((n = in.read(buf)) > 0) out.append(new String(buf, 0, n));
        } catch (Exception e) { out.append("(failed: ").append(e.getMessage()).append(')'); }
        return out.toString().trim();
    }

    // A real tap on a page element (some handlers, the dictionary lookup's, answer only real touches): its centre in CSS px,
    // times the device pixel ratio, plus the WebView's place on the screen.
    private static void tapElement(ActivityScenario<MainActivity> s, String selector) throws InterruptedException {
        String r = js(s, "(function(){var e=document.querySelector(" + quote(selector) + ");if(!e)return '';var b=e.getBoundingClientRect();return (b.left+Math.min(24,b.width/2))+','+(b.top+b.height/2)+','+devicePixelRatio})()");
        if (r == null || r.isEmpty() || "null".equals(r)) return;
        String[] p = r.split(",");
        int[] at = new int[2];
        s.onActivity(a -> a.getBridge().getWebView().getLocationOnScreen(at));
        float dpr = Float.parseFloat(p[2]);
        UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()).click(at[0] + Math.round(Float.parseFloat(p[0]) * dpr), at[1] + Math.round(Float.parseFloat(p[1]) * dpr));
    }

    private static String quote(String v) { return "'" + v.replace("\\", "\\\\").replace("'", "\\'") + "'"; }

    private static void shot(String name) {
        UiDevice d = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
        try { d.takeScreenshot(new File(shots, name + ".png"), 0.6f, 70); } catch (Exception e) { Log.i(TAG, "screenshot " + name + ": " + e); }
    }

    private void check(String name, boolean ok, String detail) {
        Log.i(TAG, (ok ? "PASS " : "FAIL ") + name + " - " + detail);
        if (!ok) failed.add(name + ": " + detail);
        shot((ok ? "" : "FAIL-") + name);
    }

    @Test
    public void everythingInOneRun() throws Exception {
        // Before the app starts: the WebView reads prefers-reduced-motion when it is made, so animations switched on after the
        // launch still read as "reduce" and the theme circle is not drawn (02 and 09 in the CI run of DG 600: "reduced motion true").
        for (String k : new String[]{"animator_duration_scale", "transition_animation_scale", "window_animation_scale"}) sh("settings put global " + k + " 1");
        try (ActivityScenario<MainActivity> s = ActivityScenario.launch(MainActivity.class)) {
            s.onActivity(a -> { shots = new File(a.getExternalFilesDir(null), "shots"); shots.mkdirs(); });
            boolean up = until(s, "document.querySelector('#paliauto') && document.readyState === 'complete'", 60000);
            Thread.sleep(4000);
            // the first start's offline sheet: "Not now", as a reader who does not download right away
            js(s, "(function(){var b=[...document.querySelectorAll('button')].find(function(x){return /^(Not now|Не сейчас)$/.test(x.textContent.trim())});if(b)b.click();return !!b})()");
            Thread.sleep(1500);
            check("01-home", up, "the home page with its search field");

            // 1. The theme switch as a circle (View Transition) in the DG app, and the theme really changes
            js(s, "(function(){window.__vt=0;var o=document.startViewTransition&&document.startViewTransition.bind(document);if(o)document.startViewTransition=function(f){window.__vt++;return o(f)};window.__th0=document.documentElement.getAttribute('data-bs-theme')||'';return 1})()");
            js(s, "document.querySelector('.dg-theme-btn-home').click()");
            Thread.sleep(1500);
            js(s, "document.querySelector('.dg-theme-btn-home').click()");
            Thread.sleep(1500);
            String vt = js(s, "String(window.__vt)+' '+window.__th0+'->'+(document.documentElement.getAttribute('data-bs-theme')||'')+' (View Transitions '+(typeof document.startViewTransition)+', reduced motion '+matchMedia('(prefers-reduced-motion: reduce)').matches+', '+navigator.userAgent.match(/Chrome\\/[0-9]+/)+')'");
            check("02-theme-circle", vt != null && !vt.startsWith("0 ") && !vt.startsWith("undefined"), "view transitions and theme: " + vt);

            // 2. A text: the contents label in the header's size, External links shown with its own look
            js(s, "window.dgNavigateInternal('/sn22.55')");
            boolean text = until(s, "document.querySelector('#sutta [id*=\":\"]') && document.querySelector('#smart-toc-current')", 45000);
            Thread.sleep(2500);
            String sizes = js(s, "(function(){var t=getComputedStyle(document.querySelector('#smart-toc-current')).fontSize,e=document.querySelector('#reader-toolbar .dg-external-links-toggle'),c=getComputedStyle(e);return parseFloat(t)+' '+parseFloat(c.fontSize)+' '+c.visibility})()");
            boolean sizeOk = false;
            try { String[] p = sizes.split(" "); sizeOk = Float.parseFloat(p[0]) <= Float.parseFloat(p[1]) + 2.5f && "visible".equals(p[2]); } catch (Exception ignored) { }
            check("03-reader-header", sizeOk, "contents label px / External links px / visibility: " + sizes + " (text seen: " + text + ")");

            // 3. Next text: External links never painted bare (the browser's grey button) while the page changes
            // Sampled from here, not by a timer in the page: the next text is a new page load in the app, which took the page's own
            // counter with it ("undefined of undefined" in the CI run of DG 600).
            String looksBare = "(function(){var e=document.querySelector('#reader-toolbar .dg-external-links-toggle');if(!e)return 'none';var c=getComputedStyle(e);return c.visibility==='visible'&&/239, 239, 239|240, 240, 240/.test(c.backgroundColor)?'bare':'ok'})()";
            js(s, "(function(){var a=document.querySelector('#next a');if(a)a.click();return !!a})()");
            int bareN = 0, samples = 0;
            long end = System.currentTimeMillis() + 30000, settled = Long.MAX_VALUE;
            while (System.currentTimeMillis() < Math.min(end, settled)) {
                String v = js(s, looksBare);
                if ("bare".equals(v)) bareN++;
                if (!"none".equals(v) && v != null) samples++;
                if (settled == Long.MAX_VALUE && "true".equals(js(s, "String(/sn22\\.56/.test(location.pathname))"))) settled = System.currentTimeMillis() + 4000;
                Thread.sleep(40);
            }
            boolean next = settled != Long.MAX_VALUE;
            String bare = bareN + " of " + samples;
            check("04-next-no-bare-button", next && bare != null && bare.startsWith("0 "), "bare frames: " + bare + ", at " + js(s, "location.pathname"));

            // 4. Settings: the whole width on a phone; the offline picker opens without scrolling the page to the top
            js(s, "window.DgHome && window.DgHome.openSettingsSheet()");
            boolean sheet = until(s, "(function(){var f=document.querySelector('#dg-settings-sheet iframe');return f&&f.contentDocument&&f.contentDocument.querySelectorAll('button').length>5})()", 20000);
            Thread.sleep(1500);
            String width = js(s, "Math.round(document.getElementById('dg-settings-sheet').getBoundingClientRect().width)+' of '+innerWidth");
            check("05-settings-sheet", sheet, "sheet width " + width);
            String picker = js(s, "(function(){var d=document.querySelector('#dg-settings-sheet iframe').contentDocument;var b=[...d.querySelectorAll('button')].find(function(x){return /Choose|Выбрать|Change|Изменить/.test(x.textContent)&&x.offsetParent});if(!b)return 'no button';b.scrollIntoView({block:'center',behavior:'instant'});window.__pkb=b;return 'ok'})()");
            Thread.sleep(1500);
            js(s, "(function(){var w=document.querySelector('#dg-settings-sheet iframe').contentWindow;window.__pk=[w.scrollY];window.__pkb.click();return 1})()");
            Thread.sleep(1500);
            js(s, "(function(){var f=document.querySelector('#dg-settings-sheet iframe'),w=f.contentWindow,d=f.contentDocument;window.__pk.push(w.scrollY,!!(d.getElementById('pkDlg')||{}).open);return 1})()");
            String pk = js(s, "JSON.stringify(window.__pk)");
            boolean pkOk = false;
            try { String[] p = pk.replace("[", "").replace("]", "").split(","); pkOk = "ok".equals(picker) && Math.abs(Float.parseFloat(p[0]) - Float.parseFloat(p[1])) < 40 && "true".equals(p[2]); } catch (Exception ignored) { }
            check("06-offline-picker-keeps-place", pkOk, "scroll before, after, open: " + pk + " (" + picker + ")");
            js(s, "(function(){var d=document.querySelector('#dg-settings-sheet iframe').contentDocument;var g=d.getElementById('pkDlg');if(g&&g.open)g.close();return 1})()");
            js(s, "history.back()");
            Thread.sleep(2000);

            // 5. The "Update installed" notice: a Restart button and a close button, closing works
            js(s, "localStorage.setItem('dgSiteApplied','1');location.reload()");
            boolean notice = until(s, "[...document.querySelectorAll('button')].some(function(b){return /^(Restart|Перезапустить)$/.test(b.textContent.trim())})", 30000);
            Thread.sleep(700);
            shot("07a-update-notice");
            String closed = js(s, "(function(){var x=[...document.querySelectorAll('button[aria-label=\"Close\"],button[aria-label=\"Закрыть\"]')].find(function(b){return b.textContent.trim()==='✕'});if(!x)return 'no close';x.click();return [...document.querySelectorAll('button')].some(function(b){return /^(Restart|Перезапустить)$/.test(b.textContent.trim())})?'still there':'gone'})()");
            check("07-update-notice", notice && "gone".equals(closed), "Restart shown: " + notice + ", after ✕: " + closed);

            // 6. A DG glossary link in the dictionary opens the text in the reader, no reload
            js(s, "window.dgNavigateInternal('/mn9')");
            until(s, "document.querySelectorAll('#sutta .pli-lang').length > 4", 45000);
            Thread.sleep(2500);
            js(s, "(function(){var w=document.querySelectorAll('#sutta .pli-lang')[3];w.scrollIntoView({block:'center',behavior:'instant'});w.id='dg-test-word';return 1})()");
            Thread.sleep(800);
            tapElement(s, "#dg-test-word");
            boolean pop = until(s, "[...document.querySelectorAll('iframe')].some(function(f){return f.srcdoc&&f.offsetParent})", 15000);
            Thread.sleep(1000);
            shot("08a-lookup");
            js(s, "(function(){window.__mark=1;var f=[...document.querySelectorAll('iframe')].find(function(x){return x.srcdoc&&x.offsetParent});var d=f.contentDocument,p=d.createElement('p');p.innerHTML='<a class=\"dg-seg\" href=\"/mn10:1.1\" target=\"_top\" id=\"dgtest\">mn10</a>';d.body.prepend(p);d.getElementById('dgtest').click();return 1})()");
            boolean went = until(s, "/^\\/mn10/.test(location.pathname) && window.__mark === 1", 20000);
            check("08-dictionary-dg-link", pop && went, "popup " + pop + ", now at " + js(s, "location.pathname") + " without reload: " + went);

            // 6a. Differences of six editions (owner 2026-11-07, Trello qFyguxVl): the majority letter by letter, a word moved or
            // missing, joined/apart. mn88 3.4: SR "ānandoti" is the joined minority (its o|t marked), BJT's "nu kho" against
            // "no" (u and the extra kho), MS and PTS ("Ānando ti" goes with the majority) unmarked. Phone, then a tablet's size.
            String probe = "(function(){var s=document.getElementById('3.4');if(!s)return 'no 3.4';s.scrollIntoView({block:'center',behavior:'instant'});var o={};s.querySelectorAll('.dg-ed-line').forEach(function(l){o[l.dataset.ed]=[...l.querySelectorAll('mark.dg-ed-diff')].map(function(m){return m.textContent}).join('|')});var ok=o.th==='ot'&&/kho/.test(o.bjt||'')&&o.ms===''&&o.pts==='';return (ok?'ok ':'bad ')+JSON.stringify(o)})()";
            // opened inside the app ?diff=1 is not read (run 699: the switch stayed off, no marks): the switch is tapped, as a reader does
            // From a known state: Differences off, so the real tap below always happens (the CI run of 2026-11-08 found the switch
            // saved as on, skipped the tap, and the page drew no marks).
            js(s, "(function(){window.dgSetEditionsDiff&&window.dgSetEditionsDiff(false);return 1})()");
            js(s, "window.dgNavigateInternal('/mn88?editions=ms,bjt,my,th,mso,pts')");
            boolean btn = until(s, "document.getElementById('3.4') && document.querySelector('#dg-diff-btn:not([hidden])')", 60000);
            Thread.sleep(1500);
            // The button is brought on screen first: a tap at its place while it was scrolled away hit the text, and Differences
            // stayed off (08b/08c in the CI run of DG 600: no marks anywhere on the screenshot).
            Log.i(TAG, "08b before the tap: Differences " + js(s, "String(window.dgEditionsDiff())") + ", marks drawn " + js(s, "String(document.querySelectorAll('#sutta mark.dg-ed-diff').length)"));
            {
                js(s, "(function(){document.getElementById('dg-diff-btn').scrollIntoView({block:'center',behavior:'instant'});return 1})()");
                Thread.sleep(800);
                shot("08b-before-tap");
                // What is under the tap point, to tell a tap that missed from a button that does not answer (CI run of 2026-11-08:
                // brought on screen and tapped, Differences still off).
                Log.i(TAG, "08b tap target: " + js(s, "(function(){var e=document.getElementById('dg-diff-btn'),b=e.getBoundingClientRect(),x=b.left+Math.min(24,b.width/2),y=b.top+b.height/2,t=document.elementFromPoint(x,y);return JSON.stringify({rect:[b.left,b.top,b.width,b.height].map(Math.round),x:Math.round(x),y:Math.round(y),hit:t?(t.id||t.tagName)+'.'+t.className:null,inside:!!(t&&e.contains(t)),dpr:devicePixelRatio,zoom:getComputedStyle(document.documentElement).zoom,scrollY:Math.round(scrollY)})})()"));
                js(s, "(function(){window.__diffClicks=0;document.addEventListener('click',function(ev){if(ev.target.closest&&ev.target.closest('#dg-diff-btn'))window.__diffClicks++},true);return 1})()");
                tapElement(s, "#dg-diff-btn");
                Thread.sleep(1500);
                Log.i(TAG, "08b after the tap: clicks on the button " + js(s, "String(window.__diffClicks)") + ", Differences " + js(s, "String(window.dgEditionsDiff())"));
            }
            boolean marks = btn && until(s, "document.querySelectorAll('#sutta mark.dg-ed-diff').length > 20", 60000);
            js(s, probe);
            Thread.sleep(2500);
            String phone = js(s, probe);
            check("08b-differences-phone", marks && phone != null && phone.startsWith("ok "), "mn88 3.4 marks per edition: " + phone + " (Differences on: " + js(s, "String(window.dgEditionsDiff && window.dgEditionsDiff())") + ", marks on the page: " + js(s, "String(document.querySelectorAll('#sutta mark.dg-ed-diff').length)") + ")");
            sh("wm size 1600x2560");
            sh("wm density 320");
            Thread.sleep(4000);
            js(s, probe);
            Thread.sleep(2500);
            String tablet = js(s, probe);
            check("08c-differences-tablet", tablet != null && tablet.startsWith("ok "), "at " + js(s, "innerWidth+'x'+innerHeight") + ": " + tablet);
            sh("wm size reset");
            sh("wm density reset");
            Thread.sleep(3000);

            // 6b. A shared link's view inside the app (dg-node df1d21b): Differences off and lines chosen by the reader, then a link
            // with view=columns&diff=1 opened by the router (as a deep link is) - both apply for that visit
            js(s, "(function(){window.dgSetEditionsDiff(false);localStorage.setItem('viewMode','alternate');return 1})()");
            js(s, "window.dgNavigateInternal('/mn89?editions=ms,bjt,my,th,mso,pts&view=columns&diff=1')");
            boolean shared = until(s, "/mn89/.test(location.pathname) && document.querySelector('#sutta .dg-ed-line')", 60000)
                && until(s, "document.querySelectorAll('#sutta mark.dg-ed-diff').length > 5", 60000);
            Thread.sleep(1500);
            String view = js(s, "JSON.stringify({cols:document.getElementById('sutta').classList.contains('column-view'),diff:window.dgEditionsDiff(),marks:document.querySelectorAll('#sutta mark.dg-ed-diff').length})");
            check("08d-shared-link-view", shared && view != null && view.contains("\"cols\":true") && view.contains("\"diff\":true"), "mn89 with view=columns&diff=1 by the router: " + view);

            // 7. The Uposatha page in the DG app animates the theme switch too
            js(s, "location.href='/uposatha-calendar'");
            until(s, "/uposatha/.test(location.pathname) && document.readyState === 'complete'", 30000);
            Thread.sleep(5000);
            js(s, "(function(){window.__vt2=0;var o=document.startViewTransition&&document.startViewTransition.bind(document);if(o)document.startViewTransition=function(f){window.__vt2++;return o(f)};var b=document.querySelector('#app-theme, .dg-theme-btn-home, #dg-theme-seg button:not([aria-pressed=true]), #theme-button');if(b)b.click();return !!b})()");
            Thread.sleep(1500);
            String vt2 = js(s, "String(window.__vt2)+' at '+location.pathname");
            check("09-uposatha-theme-circle", vt2 != null && !vt2.startsWith("0 ") && !vt2.startsWith("undefined"), "view transitions: " + vt2);

            // 8. A TABLET, editions in columns, a range text (owner 2026-11-07, DG on his tablet, an1.11-20): the page stays
            // screen-wide (only the text scrolls sideways - it was 2331 px on 800, the header and the status-bar strip slid with
            // it and the pinch label went off screen), the header stays put while the columns scroll, the status-bar strip is
            // drawn, and the translation has its column. The emulator is made a tablet for this case (wm size/density).
            sh("wm size 1600x2560"); sh("wm density 320");
            Thread.sleep(3000);
            js(s, "window.dgNavigateInternal('/an1.11-20?editions=ms,bjt,my,th,mso,pts&view=columns&diff=1&mode=single&lang=en')");
            boolean grid = until(s, "document.querySelector('#sutta.dg-grid .dg-cols-head') && document.querySelectorAll('#sutta .dg-ed-line').length > 20", 45000);
            Thread.sleep(3000);
            String tab = js(s, "(function(){var se=document.scrollingElement,box=document.querySelector('#sutta.dg-grid > section.range, #sutta.dg-grid > article'),band=document.getElementById('dg-hero-band');"
                + "var before=band?Math.round(band.getBoundingClientRect().left):-1;if(box)box.scrollLeft=600;"
                + "var after=band?Math.round(band.getBoundingClientRect().left):-1;"
                + "var heads=[...document.querySelectorAll('.dg-cols-head [data-col-cell]')].map(function(c){return c.dataset.colCell});"
                + "var strip=getComputedStyle(document.body,'::before');"
                + "return JSON.stringify({w:se.scrollWidth,iw:innerWidth,minSide:Math.min(screen.width,screen.height),boxScrolled:box?box.scrollLeft:0,band:[before,after],tr:heads.some(function(k){return /^tr:/.test(k)}),heads:heads.length,strip:strip.content!=='none'&&strip.height})})()");
            boolean tabOk = false;
            try {
                org.json.JSONObject o = new org.json.JSONObject(tab);
                tabOk = grid && o.getInt("w") <= o.getInt("iw") + 2 && o.getInt("boxScrolled") > 0
                    && o.getJSONArray("band").getInt(0) == o.getJSONArray("band").getInt(1) && o.getBoolean("tr");
            } catch (Exception ignored) { }
            check("10-tablet-columns-range", tabOk, "grid " + grid + ": " + tab);
            js(s, "window.scrollTo(0, 1800)");
            Thread.sleep(1500);
            shot("10a-tablet-columns-scrolled");
            sh("wm size reset"); sh("wm density reset");
            Thread.sleep(2000);

            // 9. Back from a text opened from the results is ONE step (owner 2026-11-07, DG 594: two swipes - the app and the
            // results' own link handler both opened the text, two history entries)
            js(s, "window.dgNavigateInternal('/kacchapa?lang=ru')");
            boolean res = until(s, "document.querySelector('#results-tbody a[href*=\"mn129\"]')", 60000);
            js(s, "document.querySelector('#results-tbody a[href*=\"mn129\"]').scrollIntoView({block:'center',behavior:'instant'})");
            Thread.sleep(1500);
            tapElement(s, "#results-tbody a[href*=\"mn129\"]");
            boolean opened = until(s, "/mn129/.test(location.pathname) && document.querySelector('#sutta [id*=\":\"]')", 45000);
            Thread.sleep(2000);
            UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()).pressBack();
            boolean backOnce = until(s, "/kacchapa/.test(location.pathname) && document.body.classList.contains('dg-state-results')", 15000);
            check("11-back-from-text-once", res && opened && backOnce, "results " + res + ", text " + opened + ", one Back -> " + js(s, "location.pathname+' '+(document.body.className.match(/dg-state-\\w+/)||[''])[0]"));

            // 10. A dhamma.gift/ru/settings/ link opens the Settings sheet, not a search for "settings"; a pinch in the sheet
            // sizes the sheet itself, not only its text sample (owner 2026-11-07, DG 594 checklist)
            sh("am start -a android.intent.action.VIEW -d https://dhamma.gift/ru/settings/ -p gift.dhamma.mobile");
            boolean sheetOpen = until(s, "window.DgHome && DgHome.isSettingsSheetOpen() && document.querySelector('iframe[src*=\"settings\"]').contentDocument.getElementById('sizeVal')", 45000);
            Thread.sleep(2000);
            String where = js(s, "location.pathname+location.search+' '+(document.body.className.match(/dg-state-\\w+/)||[''])[0]");
            check("12-settings-link", sheetOpen, "at " + where);
            androidx.test.uiautomator.UiObject2 wv = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()).findObject(androidx.test.uiautomator.By.clazz("android.webkit.WebView"));
            if (wv != null) wv.pinchClose(0.6f);
            Thread.sleep(2000);
            String zoom = js(s, "(function(){var d=document.querySelector('iframe[src*=\"settings\"]').contentDocument;return localStorage.getItem('uiScale')+' '+(d.documentElement.style.zoom||'1')+' '+d.getElementById('sizeVal').textContent})()");
            boolean zoomOk = false;
            try { String[] z = zoom.split(" "); zoomOk = Integer.parseInt(z[0]) < 100 && Float.parseFloat(z[1]) < 0.99f && z[2].equals(z[0] + "%"); } catch (Exception ignored) { }
            check("13-settings-pinch", sheetOpen && zoomOk, "uiScale / sheet zoom / figure: " + zoom);
            js(s, "(function(){localStorage.setItem('uiScale','100');DgHome.closeSettingsSheet&&DgHome.closeSettingsSheet();return 1})()");
        }
        Log.i(TAG, "DONE " + (failed.isEmpty() ? "all passed" : failed.size() + " failed: " + failed));
        assertTrue("failed: " + failed, failed.isEmpty());
    }
}
