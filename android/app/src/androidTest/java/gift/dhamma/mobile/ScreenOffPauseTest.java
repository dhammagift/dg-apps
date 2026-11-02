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

import android.app.UiAutomation;
import android.os.ParcelFileDescriptor;
import java.io.FileInputStream;

/**
 * Pauses between phrases run out with the screen off (owner 2026-11-01/02, Motorola: an A-B loop with a pause stopped until
 * the app was opened again). On a real phone in Test Lab: SN 56.11 read with a 60 s pause after each phrase, the screen off
 * for 5 minutes, then the reading must have moved on. The emulator never held the timers back, so only a phone can tell.
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

    // A shell command as the test (dumpsys): its output, also into logcat
    private static String sh(String cmd) {
        UiAutomation ua = InstrumentationRegistry.getInstrumentation().getUiAutomation();
        StringBuilder out = new StringBuilder();
        try (ParcelFileDescriptor pfd = ua.executeShellCommand(cmd); FileInputStream in = new FileInputStream(pfd.getFileDescriptor())) {
            byte[] buf = new byte[8192]; int n;
            while ((n = in.read(buf)) > 0) out.append(new String(buf, 0, n));
        } catch (Exception e) { out.append("(failed: ").append(e.getMessage()).append(')'); }
        return out.toString();
    }
    private static void state(String when) {
        Log.i(TAG, when + " | deep idle: " + sh("dumpsys deviceidle get deep").trim() + " | light: " + sh("dumpsys deviceidle get light").trim());
        for (String line : sh("dumpsys activity services gift.dhamma.mobile").split("\n"))
            if (line.toLowerCase().contains("foreground")) Log.i(TAG, when + " | service: " + line.trim());
        for (String line : sh("dumpsys power").split("\n"))
            if (line.contains("dg:") || line.toLowerCase().contains("read-aloud")) Log.i(TAG, when + " | wake lock: " + line.trim());
        // the app process and the WebView's renderer (a sandboxed process of its own): process state, adj, frozen
        for (String line : sh("dumpsys activity processes gift.dhamma.mobile").split("\n")) {
            String l = line.toLowerCase();
            if (l.contains("procstate") || l.contains("curadj") || l.contains("frozen") || l.contains("sandboxed_process") || l.contains("processrecord"))
                Log.i(TAG, when + " | process: " + line.trim());
        }
    }
    // A phone on battery, its screen off, going into Doze - as the owner's Motorola; Test Lab's phones sit on USB power and
    // never get there by themselves (Sadda 2026-11-02: the PASS on 569 meant nothing)
    private static void sleepLikeAPhoneInAPocket(UiDevice device, long ms) throws Exception {
        sh("dumpsys battery unplug");
        sh("dumpsys deviceidle enable");
        // Battery Saver on, as on the owner's phone (instrumentation argument saver=1)
        boolean saver = "1".equals(InstrumentationRegistry.getArguments().getString("saver"));
        if (saver) Log.i(TAG, "battery saver on: " + sh("cmd power set-mode 1").trim() + " | low_power=" + sh("settings get global low_power").trim());
        // the owner's way: the app sent home first, then the screen off (an instrumentation argument, so a run picks it
        // without a new build: -e home 1)
        if ("1".equals(InstrumentationRegistry.getArguments().getString("home"))) {
            device.pressHome();
            Thread.sleep(3000);
            state("app sent home");
        }
        device.sleep();
        Thread.sleep(3000);
        state("screen off, before Doze");
        Log.i(TAG, "light Doze: " + sh("dumpsys deviceidle step light").trim());
        Thread.sleep(ms / 3);
        Log.i(TAG, "deep Doze: " + sh("dumpsys deviceidle force-idle").trim());
        state("in Doze");
        Thread.sleep(ms - ms / 3);
        state("end of the sleep");
        sh("dumpsys deviceidle unforce");
        if (saver) sh("cmd power set-mode 0");
        sh("dumpsys battery reset");
        device.wakeUp();
    }

    private static int number(String v) {
        try { return (int) Double.parseDouble(v.replace("\"", "")); } catch (Exception e) { return -1; }
    }

    // The owner's own case: an A-B loop on one line with a 180 s pause between passes (Sadda's recipe, DOM only, 2026-11-02;
    // the owner: 90 s tells little, a pause of 3 minutes at least). The screen goes off for 7 minutes.
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
            // the voice really speaking before it is paused: on a slower phone (Pixel 8a, DG 569) a late start of the
            // player came after the A-B start and switched the loop off (Sadda's reading of the logcat)
            for (int i = 0; i < 30 && !"true".equals(js(s, "!!(window.ttsAPI && ttsAPI.getState && ttsAPI.getState().speaking)")); i++) Thread.sleep(1000);
            Thread.sleep(2000);
            js(s, "var p = document.querySelector('.play-main-button'); p && p.click(); 1");
            Thread.sleep(1500);
            js(s, "document.getElementById('ab-loop-toggle-btn').click(); 1");
            Thread.sleep(1500);
            js(s, "var m = document.getElementById('mem-interval'); m.innerText = '10'; m.dispatchEvent(new Event('input', { bubbles: true })); m.dispatchEvent(new Event('focusout', { bubbles: true })); 1");
            Thread.sleep(800);
            js(s, line + ".click(); 1");
            Thread.sleep(800);
            js(s, line + ".click(); 1");
            // the loop running with the screen ON first (a 10 s pause, a second pass), so a failure below can only come from
            // the screen being off; then the pause the owner uses, 180 s
            for (int i = 0; i < 60 && number(js(s, "window.__loops || 0")) < 2; i++) Thread.sleep(1000);
            assertTrue("the A-B loop did not reach a second pass with the screen on", number(js(s, "window.__loops || 0")) >= 2);
            js(s, "var m = document.getElementById('mem-interval'); m.innerText = '180'; m.dispatchEvent(new Event('input', { bubbles: true })); m.dispatchEvent(new Event('focusout', { bubbles: true })); 1");
            Thread.sleep(1000);
            int before = number(js(s, "window.__loops || 0"));
            Log.i(TAG, "A-B loop: " + before + " passes with the screen on (10 s pause), now 180 s; screen off for 420 s");
            sleepLikeAPhoneInAPocket(device, 420000);
            Thread.sleep(2000);
            int after = number(js(s, "window.__loops || 0"));
            Log.i(TAG, "A-B loop, screen on again: passes " + before + " -> " + after + ", status: " + js(s, "(document.getElementById('mem-status') || {}).textContent"));
            // a pass is the line (a few s) plus 180 s of pause: 420 s hold 2, a pause held back holds none
            assertTrue("the A-B loop stopped with the screen off: passes " + before + " -> " + after, after - before >= 2);
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
            // the pause as the settings keep it (seconds): window.TTS_SEGMENT_DELAY alone was overwritten from storage (run on 569)
            js(s, "localStorage.setItem('dg_tts_segment_delay', '60'); window.TTS_SEGMENT_DELAY = 60000; var q = document.querySelector('#sutta .pli-lang.quote'); q && q.click(); 1");
            Thread.sleep(1500);
            js(s, "var b = document.querySelector('.dynamic-tts-btn') || document.getElementById('sm-audio'); b && b.click(); 1");
            Thread.sleep(8000);
            int before = number(js(s, "(typeof ttsState !== 'undefined' && ttsState.speaking) ? ttsState.currentIndex : -1"));
            Log.i(TAG, "speaking, phrase " + before + "; screen off for 300 s");
            assertTrue("the voice did not start", before >= 0);
            sleepLikeAPhoneInAPocket(device, 300000);
            Thread.sleep(2000);
            int after = number(js(s, "(typeof ttsState !== 'undefined') ? ttsState.currentIndex : -1"));
            String speaking = js(s, "(typeof ttsState !== 'undefined') && !!ttsState.speaking");
            Log.i(TAG, "screen on again: phrase " + before + " -> " + after + ", still speaking " + speaking);
            // 300 s with 60 s pauses and short phrases: 4 or more; timers held back give 0 or 1
            assertTrue("the reading stopped with the screen off: phrase " + before + " -> " + after, after - before >= 4);
        }
    }
}
