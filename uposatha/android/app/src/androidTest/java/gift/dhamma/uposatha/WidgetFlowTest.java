package gift.dhamma.uposatha;

import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.graphics.Rect;
import android.util.Log;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.By;
import androidx.test.uiautomator.UiDevice;
import androidx.test.uiautomator.UiObject2;
import androidx.test.uiautomator.Until;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.File;
import java.util.regex.Pattern;

/**
 * Firebase Test Lab flow, recorded as a video: the moon on the calendar page, the Uposatha list, adding the home-screen widget,
 * cycling its layers, tapping a day. Every step is guarded: a failing step is logged (tag UpoFlow) and the flow goes on.
 * Screenshots and view dumps go to getExternalFilesDir(null)/shots of the app (pull that directory in Test Lab).
 */
@RunWith(AndroidJUnit4.class)
public class WidgetFlowTest {
    private static final String TAG = "UpoFlow";
    private static final String PKG = "gift.dhamma.uposatha";
    // The big moon of the Summary section (fractions of the screen), tuned on the first runs.
    private static final float MOON_X = 0.5f, MOON_Y = 0.23f;
    private static final Pattern DOTS = Pattern.compile(".*:id/w_dots");
    private static final Pattern CELL = Pattern.compile(".*:id/c[0-9][0-9]");

    private UiDevice dev;
    private Context ctx;
    private File shots;
    private int n = 0;

    private interface Step { void run() throws Exception; }

    private void step(String name, Step s) {
        Log.i(TAG, "STEP " + name);
        try { s.run(); } catch (Throwable t) { Log.e(TAG, "STEP FAILED " + name + ": " + t); }
        shot(name);
    }

    private void shot(String name) {
        try { dev.takeScreenshot(new File(shots, String.format("%02d-%s.png", n++, name))); }
        catch (Throwable t) { Log.e(TAG, "shot failed " + name + ": " + t); }
    }

    private void dump(String name) {
        try { dev.dumpWindowHierarchy(new File(shots, name + ".xml")); } catch (Throwable t) { Log.e(TAG, "dump failed: " + t); }
    }

    private void sleep(long ms) { try { Thread.sleep(ms); } catch (InterruptedException ignored) { } }

    private void tapFrac(float fx, float fy) {
        dev.click(Math.round(dev.getDisplayWidth() * fx), Math.round(dev.getDisplayHeight() * fy));
    }

    /** Runs JS in the app's WebView (the test runs in the app's process) and returns the JSON result, or null. */
    private String webEval(String js, int[] webViewOrigin) {
        final String[] out = { null };
        final java.util.concurrent.CountDownLatch done = new java.util.concurrent.CountDownLatch(1);
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
            try {
                java.util.Collection<android.app.Activity> r = androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry.getInstance()
                        .getActivitiesInStage(androidx.test.runner.lifecycle.Stage.RESUMED);
                if (r.isEmpty()) { done.countDown(); return; }
                android.webkit.WebView wv = ((MainActivity) r.iterator().next()).getBridge().getWebView();
                if (webViewOrigin != null) { int[] xy = new int[2]; wv.getLocationOnScreen(xy); webViewOrigin[0] = xy[0]; webViewOrigin[1] = xy[1]; }
                wv.evaluateJavascript(js, v -> { out[0] = v; done.countDown(); });
            } catch (Throwable t) { Log.w(TAG, "webEval failed: " + t); done.countDown(); }
        });
        try { done.await(5, java.util.concurrent.TimeUnit.SECONDS); } catch (InterruptedException ignored) { }
        return out[0];
    }

    @Test
    public void flow() {
        dev = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
        ctx = InstrumentationRegistry.getInstrumentation().getTargetContext();
        shots = new File(ctx.getExternalFilesDir(null), "shots");
        shots.mkdirs();
        Log.i(TAG, "device " + android.os.Build.MANUFACTURER + " " + android.os.Build.MODEL + " api " + android.os.Build.VERSION.SDK_INT
                + " launcher " + dev.getLauncherPackageName() + " display " + dev.getDisplayWidth() + "x" + dev.getDisplayHeight());
        try { dev.executeShellCommand("pm grant " + PKG + " android.permission.POST_NOTIFICATIONS"); } catch (Throwable ignored) { }
        // The page skips the moon cycle under prefers-reduced-motion, which WebView takes from the animation scales (Test Lab may set them to 0).
        for (String k : new String[] { "window_animation_scale", "transition_animation_scale", "animator_duration_scale" }) {
            try {
                Log.i(TAG, k + " was " + dev.executeShellCommand("settings get global " + k).trim());
                dev.executeShellCommand("settings put global " + k + " 1");
            } catch (Throwable t) { Log.w(TAG, "scale " + k + ": " + t); }
        }
        // Optional: gcloud ... --environment-variables theme=light|dark forces the system theme (both launchers and the page follow it).
        String theme = InstrumentationRegistry.getArguments().getString("theme");
        if (theme != null) {
            try { dev.executeShellCommand("cmd uimode night " + ("dark".equals(theme) ? "yes" : "no")); } catch (Throwable t) { Log.w(TAG, "theme: " + t); }
            sleep(1500);
        }
        dev.pressHome();
        sleep(1500);

        step("launch", () -> {
            Intent i = ctx.getPackageManager().getLaunchIntentForPackage(PKG);
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
            ctx.startActivity(i);
            dev.wait(Until.hasObject(By.pkg(PKG).depth(0)), 15000);
            sleep(9000);   // splash, the page paints, the bridge hands the widget its data
        });
        dump("page-summary");

        step("moon-before-tap", () -> sleep(500));
        step("moon-tap", () -> {
            // Where the moon is, and whether the page would skip the cycle (prefers-reduced-motion); if so, switch that query off for the page.
            int[] o = new int[2];
            String info = webEval("(function(){var r=matchMedia('(prefers-reduced-motion: reduce)').matches;"
                    + "if(r){var q=window.matchMedia;window.matchMedia=function(s){return /reduced-motion/.test(s)?{matches:false,media:s,addListener:function(){},removeListener:function(){},addEventListener:function(){},removeEventListener:function(){}}:q.call(window,s);};}"
                    + "var m=document.querySelector('#t-moon dg-moon'),b=m?m.getBoundingClientRect():null;"
                    + "return JSON.stringify({reduced:r,dpr:devicePixelRatio,rect:b?[b.x,b.y,b.width,b.height]:null});})()", o);
            Log.i(TAG, "moon info " + info + " webview at " + o[0] + "," + o[1]);
            int x = Math.round(dev.getDisplayWidth() * MOON_X), y = Math.round(dev.getDisplayHeight() * MOON_Y);
            try {
                java.util.regex.Matcher m = Pattern.compile("\"dpr\":([0-9.]+),\"rect\":\\[([-0-9.]+),([-0-9.]+),([-0-9.]+),([-0-9.]+)\\]").matcher(info.replace("\\", ""));
                if (m.find() && Float.parseFloat(m.group(4)) > 0) {
                    float d = Float.parseFloat(m.group(1));
                    x = Math.round(o[0] + (Float.parseFloat(m.group(2)) + Float.parseFloat(m.group(4)) / 2) * d);
                    y = Math.round(o[1] + (Float.parseFloat(m.group(3)) + Float.parseFloat(m.group(5)) / 2) * d);
                }
            } catch (Throwable t) { Log.w(TAG, "moon rect parse: " + t); }
            Log.i(TAG, "moon tap at " + x + "," + y);
            dev.click(x, y);
            sleep(700);
        });
        step("moon-cycle-mid", () -> sleep(900));
        step("moon-cycle-end", () -> sleep(1500));

        step("tab-uposathas", () -> { tapFrac(0.43f, 0.925f); sleep(2500); });   // bottom navigation, second button
        dump("page-list");
        step("tab-uposathas-scroll", () -> {
            dev.swipe(dev.getDisplayWidth() / 2, dev.getDisplayHeight() * 3 / 4, dev.getDisplayWidth() / 2, dev.getDisplayHeight() / 3, 25);
            sleep(1500);
        });

        step("pin-request", () -> {
            AppWidgetManager am = AppWidgetManager.getInstance(ctx);
            Log.i(TAG, "pin supported: " + am.isRequestPinAppWidgetSupported());
            am.requestPinAppWidget(new ComponentName(ctx, "gift.dhamma.uposatha.WidgetProvider"), null, null);
            sleep(2500);
        });
        dump("pin-dialog");
        step("pin-confirm", () -> {
            Pattern p = Pattern.compile("(?i)(add( automatically| to home screen)?|добавить.*|place automatically|confirm)");
            UiObject2 b = null;
            for (int k = 0; k < 8 && b == null; k++) {
                b = dev.findObject(By.text(p).clickable(true));
                if (b == null) b = dev.findObject(By.text(p));
                if (b == null) sleep(1000);
            }
            Log.i(TAG, "pin button: " + b);
            if (b != null) b.click();
            sleep(2500);
        });

        step("home", () -> { dev.pressHome(); sleep(4000); });
        dump("home");
        step("widget-first", () -> {
            UiObject2 d = dev.wait(Until.findObject(By.res(DOTS)), 8000);
            Log.i(TAG, "dots strip: " + d + (d != null ? " " + d.getVisibleBounds() : ""));
            sleep(2000);
        });
        // Samsung One UI leaves the new widget in edit mode (resize frame with handles): widen it from there, then leave the edit mode
        // (while it lasts, taps on the widget do nothing). Pixel launcher has no such state and skips the first part.
        step("widget-widen-after-add", () -> {
            UiObject2 h = dev.findObject(By.res(Pattern.compile(".*:id/widget_resize_right_handle")));
            Log.i(TAG, "edit mode right handle after add: " + h);
            if (h != null) {
                h.drag(new android.graphics.Point(dev.getDisplayWidth() - 40, h.getVisibleCenter().y), 300);
                sleep(2000);
            }
        });
        step("widget-leave-edit", () -> { dev.pressBack(); sleep(2000); });
        for (int k = 2; k <= 3; k++) {
            final int layer = k;
            step("widget-layer" + layer, () -> {
                UiObject2 d = dev.findObject(By.res(DOTS));
                if (d != null) d.click(); else Log.w(TAG, "no dots strip to tap");
                sleep(2500);
            });
        }
        dump("widget-month");
        // The default 2x2 month layer has one tap area only: widen the widget (long press, drag the right handle) to get the day cells.
        step("widget-resize", () -> {
            UiObject2 w = dev.findObject(By.res(Pattern.compile(".*:id/w_tap")));
            if (w == null) { Log.w(TAG, "no widget to resize"); return; }
            Rect b = w.getVisibleBounds();
            if (b.width() > dev.getDisplayWidth() * 0.6) { Log.i(TAG, "widget is wide already"); return; }
            w.longClick();
            sleep(2000);
            dump("resize-frame");
            // Launcher3/Pixel launcher: the resize frame has handles with ids widget_resize_*_handle. Without them (other launchers) skip.
            UiObject2 h = dev.findObject(By.res(Pattern.compile(".*:id/widget_resize_right_handle")));
            Log.i(TAG, "right handle: " + h);
            if (h != null) {
                h.drag(new android.graphics.Point(dev.getDisplayWidth() - 40, h.getVisibleCenter().y), 300);
                sleep(2000);
                UiObject2 w2 = dev.findObject(By.res(Pattern.compile(".*:id/w_tap")));
                Log.i(TAG, "widget width after resize: " + (w2 == null ? -1 : w2.getVisibleBounds().width()) + " (was " + b.width() + ")");
            }
            shot("widget-resized");
            dev.click(dev.getDisplayWidth() / 2, dev.getDisplayHeight() * 2 / 3);   // leave the resize mode
            sleep(2500);
        });
        dump("widget-month-wide");
        step("widget-day-tap", () -> {
            java.util.List<UiObject2> cells = dev.findObjects(By.res(CELL).clickable(true));
            Log.i(TAG, "day cells: " + cells.size());
            UiObject2 c = null;
            for (UiObject2 x : cells) if (x.getResourceName().endsWith("c22")) c = x;   // row 3, Wednesday
            if (c == null && !cells.isEmpty()) c = cells.get(cells.size() / 2);
            if (c == null) c = dev.findObject(By.res(Pattern.compile(".*:id/w_tap")));   // 2x2: one tap area for the whole month layer
            Log.i(TAG, "day cell: " + c + (c != null ? " " + c.getVisibleBounds() : ""));
            if (c != null) c.click();
            dev.wait(Until.hasObject(By.pkg(PKG).depth(0)), 8000);
            sleep(5000);
        });
        dump("after-day-tap");
        step("after-day-tap-wait", () -> sleep(2000));
    }
}
