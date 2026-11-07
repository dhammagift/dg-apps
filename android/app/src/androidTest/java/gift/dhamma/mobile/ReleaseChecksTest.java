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
        try (ActivityScenario<MainActivity> s = ActivityScenario.launch(MainActivity.class)) {
            s.onActivity(a -> { shots = new File(a.getExternalFilesDir(null), "shots"); shots.mkdirs(); });
            for (String k : new String[]{"animator_duration_scale", "transition_animation_scale", "window_animation_scale"}) sh("settings put global " + k + " 1");
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
            js(s, "(function(){window.__bare=0;window.__samples=0;window.__iv=setInterval(function(){var e=document.querySelector('#reader-toolbar .dg-external-links-toggle');if(!e)return;window.__samples++;var c=getComputedStyle(e);if(c.visibility==='visible'&&/239, 239, 239|240, 240, 240/.test(c.backgroundColor))window.__bare++},40);var a=document.querySelector('#next a');if(a)a.click();return !!a})()");
            boolean next = until(s, "/sn22\\.56/.test(location.pathname)", 30000);
            Thread.sleep(4000);
            String bare = js(s, "(function(){clearInterval(window.__iv);return window.__bare+' of '+window.__samples})()");
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

            // 7. The Uposatha page in the DG app animates the theme switch too
            js(s, "location.href='/uposatha-calendar'");
            until(s, "/uposatha/.test(location.pathname) && document.readyState === 'complete'", 30000);
            Thread.sleep(5000);
            js(s, "(function(){window.__vt2=0;var o=document.startViewTransition&&document.startViewTransition.bind(document);if(o)document.startViewTransition=function(f){window.__vt2++;return o(f)};var b=document.querySelector('#app-theme, .dg-theme-btn-home, #dg-theme-seg button:not([aria-pressed=true]), #theme-button');if(b)b.click();return !!b})()");
            Thread.sleep(1500);
            String vt2 = js(s, "String(window.__vt2)+' at '+location.pathname");
            check("09-uposatha-theme-circle", vt2 != null && !vt2.startsWith("0 ") && !vt2.startsWith("undefined"), "view transitions: " + vt2);
        }
        Log.i(TAG, "DONE " + (failed.isEmpty() ? "all passed" : failed.size() + " failed: " + failed));
        assertTrue("failed: " + failed, failed.isEmpty());
    }
}
