package gift.dhamma.mobile;

import android.app.UiAutomation;
import android.os.ParcelFileDescriptor;
import android.util.Log;
import android.webkit.WebView;

import androidx.test.core.app.ActivityScenario;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.By;
import androidx.test.uiautomator.UiDevice;
import androidx.test.uiautomator.UiObject2;
import androidx.test.uiautomator.Until;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.File;
import java.io.FileInputStream;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import java.util.regex.Pattern;

import static org.junit.Assert.assertTrue;

/**
 * The notification player on a real phone (owner 2026-11-04: the emulator's tray case, Google voices, failed three times on 577 -
 * its shade dump /sdcard/n.xml was never written). SN 56.11 read with the page's own (Google) audio, then Pause and Play on the
 * shade, as a reader does it. Steps to logcat under DgTrayTest, screenshots to the app's files/shots.
 */
@RunWith(AndroidJUnit4.class)
public class TrayPlayerTest {
    private static final String TAG = "DgTrayTest";

    private static String js(ActivityScenario<MainActivity> s, String code) throws InterruptedException {
        AtomicReference<String> out = new AtomicReference<>();
        CountDownLatch done = new CountDownLatch(1);
        s.onActivity(a -> {
            WebView w = a.getBridge().getWebView();
            w.evaluateJavascript(code, v -> { out.set(v); done.countDown(); });
        });
        done.await(20, TimeUnit.SECONDS);
        return out.get();
    }

    private static String sh(String cmd) {
        UiAutomation ua = InstrumentationRegistry.getInstrumentation().getUiAutomation();
        StringBuilder out = new StringBuilder();
        try (ParcelFileDescriptor pfd = ua.executeShellCommand(cmd); FileInputStream in = new FileInputStream(pfd.getFileDescriptor())) {
            byte[] buf = new byte[8192]; int n;
            while ((n = in.read(buf)) > 0) out.append(new String(buf, 0, n));
        } catch (Exception e) { out.append("(failed: ").append(e.getMessage()).append(')'); }
        return out.toString();
    }

    private static final String STATE = "(function(){ function a(x){ return x ? (x.paused ? 'paused@' : 'playing@') + Math.round(x.currentTime*10)/10 : null; }"
        + " var ts = (typeof ttsState !== 'undefined') ? ttsState : {}; var sh = window.sharedGoogleAudio;"
        + " return JSON.stringify({ mediaSession: navigator.mediaSession && navigator.mediaSession.playbackState, googleAudio: a(ts.googleAudio),"
        + " sharedGoogleAudio: sh && sh.src && !/^data:/.test(sh.src) ? a(sh) : null, speaking: !!ts.speaking, paused: !!ts.paused }); })()";

    private static boolean audible(String st) { return st != null && st.contains("playing@"); }

    private static File shots;
    private static void shot(UiDevice d, String name) {
        try { d.takeScreenshot(new File(shots, name + ".png"), 0.5f, 60); } catch (Exception e) { Log.i(TAG, "screenshot " + name + ": " + e); }
    }

    private static UiObject2 shadeButton(UiDevice d, String tag, Pattern label) {
        d.openNotification();
        d.wait(Until.hasObject(By.pkg("com.android.systemui")), 5000);
        try { Thread.sleep(2500); } catch (InterruptedException ignored) { }
        shot(d, "shade-" + tag);
        // the emulator's way: what the shell dump says (it never wrote the file on the CI emulator)
        Log.i(TAG, tag + " | uiautomator dump: " + sh("uiautomator dump /sdcard/n.xml").trim() + " | file: " + sh("ls -la /sdcard/n.xml").trim());
        UiObject2 b = d.wait(Until.findObject(By.desc(label).clickable(true)), 8000);
        if (b == null) b = d.findObject(By.text(label));
        if (b == null) {
            StringBuilder seen = new StringBuilder();
            for (UiObject2 o : d.findObjects(By.pkg("com.android.systemui"))) {
                String l = o.getContentDescription() != null ? o.getContentDescription() : o.getText();
                if (l != null && seen.length() < 800) seen.append(l).append(" | ");
            }
            Log.i(TAG, tag + " | no " + label + " on the shade; labels: " + seen);
        }
        return b;
    }

    @Test
    public void shadePauseAndPlayWithGoogleVoices() throws Exception {
        UiDevice d = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
        try (ActivityScenario<MainActivity> s = ActivityScenario.launch(MainActivity.class)) {
            s.onActivity(a -> { shots = new File(a.getExternalFilesDir(null), "shots"); shots.mkdirs(); });
            Thread.sleep(15000);
            js(s, "localStorage.setItem('dg.app.downloadDeclined','1'); location.assign('/sn56.11'); 1");
            Thread.sleep(15000);
            Log.i(TAG, "page: " + js(s, "location.href"));
            Log.i(TAG, "start: " + js(s, "(function(){ var l = document.querySelector('.voice-link') || document.querySelector('.voice-start-btn'); if (!l) return 'no voice link'; l.click(); return 'clicked'; })()"));
            String st = null;
            for (int i = 0; i < 30; i++) { Thread.sleep(2000); st = js(s, STATE); if (audible(st) && st.contains("mediaSession\\\":\\\"playing")) break; }
            Log.i(TAG, "reading: " + st);
            shot(d, "1-reading");
            assertTrue("the page did not start reading: " + st, audible(st));

            UiObject2 pause = shadeButton(d, "pause", Pattern.compile("(?i)^(pause|пауза|приостановить)$"));
            assertTrue("no Pause button on the shade", pause != null);
            pause.click();
            Thread.sleep(2500);
            shot(d, "2-after-pause");
            d.pressBack();
            st = js(s, STATE);
            Log.i(TAG, "after Pause: " + st);
            assertTrue("Pause on the shade did not pause: " + st, st.contains("paused") && !audible(st));

            UiObject2 play = shadeButton(d, "play", Pattern.compile("(?i)^(play|воспроизвести|воспроизведение)$"));
            assertTrue("no Play button on the shade", play != null);
            play.click();
            Thread.sleep(3500);
            shot(d, "3-after-play");
            d.pressBack();
            st = js(s, STATE);
            Log.i(TAG, "after Play: " + st);
            assertTrue("Play on the shade did not resume: " + st, audible(st));
            Log.i(TAG, "PASS shade Pause and Play with Google voices");
        }
    }
}
