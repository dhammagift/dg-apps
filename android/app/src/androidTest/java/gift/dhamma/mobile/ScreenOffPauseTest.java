package gift.dhamma.mobile;

import android.util.Log;
import android.webkit.WebView;

import androidx.test.core.app.ActivityScenario;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.UiDevice;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.Assert.assertTrue;

/**
 * Pauses between phrases run out with the screen off (owner 2026-11-01/02, Motorola: an A-B loop with a pause stopped until
 * the app was opened again). On a real phone in Test Lab: SN 56.11 read with an 8 s pause after each phrase, the screen off
 * for 90 s, then the reading must have moved on. The emulator never held the timers back, so only a phone can tell.
 * Progress goes to logcat under DgPauseTest.
 */
@RunWith(AndroidJUnit4.class)
public class ScreenOffPauseTest {
    private static final String TAG = "DgPauseTest";

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

    private static int number(String v) {
        try { return (int) Double.parseDouble(v.replace("\"", "")); } catch (Exception e) { return -1; }
    }

    // The owner's own case: an A-B loop on one line with a 10 s pause between passes (Sadda's recipe, DOM only, 2026-11-02).
    // Passes are counted from the voice's own console line "[dg-voice] loop <n> <ms>".
    @Test
    public void abLoopPausesRunOutWithTheScreenOff() throws Exception {
        UiDevice device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
        try (ActivityScenario<MainActivity> s = ActivityScenario.launch(MainActivity.class)) {
            Thread.sleep(15000);
            js(s, "localStorage.setItem('dg.app.downloadDeclined','1'); localStorage.setItem('paliToggle','pli-2nd'); localStorage.setItem('dg_tts_segment_delay','0'); location.assign('/sn56.11?lang=en'); 1");
            Thread.sleep(15000);
            js(s, "window.__loops = 0; var o = console.log; console.log = function () { if (String(arguments[0]).indexOf('[dg-voice] loop') === 0) window.__loops++; return o.apply(console, arguments); }; 1");
            String line = "document.querySelector('[id=\"1.1\"] .pli-lang')";
            js(s, line + ".click(); 1");
            Thread.sleep(1500);
            js(s, "document.querySelector('.dynamic-tts-btn').click(); 1");
            Thread.sleep(4000);
            js(s, "var p = document.querySelector('.play-main-button'); p && p.click(); 1");
            Thread.sleep(1500);
            js(s, "document.getElementById('ab-loop-toggle-btn').click(); 1");
            Thread.sleep(1500);
            js(s, "var m = document.getElementById('mem-interval'); m.innerText = '10'; m.dispatchEvent(new Event('input', { bubbles: true })); m.dispatchEvent(new Event('focusout', { bubbles: true })); 1");
            Thread.sleep(800);
            js(s, line + ".click(); 1");
            Thread.sleep(800);
            js(s, line + ".click(); 1");
            Thread.sleep(30000);
            int before = number(js(s, "window.__loops || 0"));
            Log.i(TAG, "A-B loop: " + before + " passes in 30 s; screen off for 90 s");
            assertTrue("the A-B loop did not run (0 passes in 30 s)", before >= 1);
            device.sleep();
            Thread.sleep(90000);
            device.wakeUp();
            Thread.sleep(2000);
            int after = number(js(s, "window.__loops || 0"));
            Log.i(TAG, "A-B loop, screen on again: passes " + before + " -> " + after + ", status: " + js(s, "(document.getElementById('mem-status') || {}).textContent"));
            // a pass is the line (a few s) plus 10 s of pause: 90 s hold 5 or more, held-back timers 0 or 1
            assertTrue("the A-B loop stopped with the screen off: passes " + before + " -> " + after, after - before >= 4);
        }
    }

    @Test
    public void pausesRunOutWithTheScreenOff() throws Exception {
        UiDevice device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
        try (ActivityScenario<MainActivity> s = ActivityScenario.launch(MainActivity.class)) {
            Thread.sleep(15000);
            js(s, "localStorage.setItem('dg.app.downloadDeclined','1'); localStorage.setItem('paliToggle','pli-2nd'); location.assign('/sn56.11?lang=en'); 1");
            Thread.sleep(15000);
            // the reader's own voice from a line, as a tap and its play button start it, with an 8 s pause after each phrase
            js(s, "window.TTS_SEGMENT_DELAY = 8000; var q = document.querySelector('#sutta .pli-lang.quote'); q && q.click(); 1");
            Thread.sleep(1500);
            js(s, "var b = document.querySelector('.dynamic-tts-btn') || document.getElementById('sm-audio'); b && b.click(); 1");
            Thread.sleep(8000);
            int before = number(js(s, "(typeof ttsState !== 'undefined' && ttsState.speaking) ? ttsState.currentIndex : -1"));
            Log.i(TAG, "speaking, phrase " + before + "; screen off for 90 s");
            assertTrue("the voice did not start", before >= 0);
            device.sleep();
            Thread.sleep(90000);
            device.wakeUp();
            Thread.sleep(2000);
            int after = number(js(s, "(typeof ttsState !== 'undefined') ? ttsState.currentIndex : -1"));
            String speaking = js(s, "(typeof ttsState !== 'undefined') && !!ttsState.speaking");
            Log.i(TAG, "screen on again: phrase " + before + " -> " + after + ", still speaking " + speaking);
            // 90 s with 8 s pauses and short phrases: 5 or more; timers held back give 0 or 1
            assertTrue("the reading stopped with the screen off: phrase " + before + " -> " + after, after - before >= 5);
        }
    }
}
