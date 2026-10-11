package gift.dhamma.uposatha;

import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.graphics.Point;
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
 * Firebase Test Lab flow on a real launcher, recorded as a video: the big widget is added, its three slides are switched, the calendar's
 * month is turned, the launcher's resize handles make it smaller and bigger, the widget's own settings are opened from the launcher and
 * changed (theme, transparency), a day is tapped (the app opens on it), then the other six widgets are added.
 * Every step is guarded: a failing step is logged (tag UpoFlow, "STEP name" with the time, so the video can be cut by cases) and the flow
 * goes on - but it is remembered, and so is every check() that did not hold: the test FAILS at the end with the list. (It used to pass
 * whatever happened; "the flow passed" then said nothing.) The checks are the things the owner found by hand on 2026-10-10: the launch
 * asked the site for fonts, a setting was lost without Done, a tap on a widget loaded the page again.
 * Screenshots and view dumps go to getExternalFilesDir(null)/shots of the app (pull that directory in Test Lab).
 */
@RunWith(AndroidJUnit4.class)
public class WidgetFlowTest {
    private static final String TAG = "UpoFlow";
    private static final String PKG = "gift.dhamma.uposatha";
    private static final Pattern NEXT = Pattern.compile(".*:id/sw_next");
    private static final Pattern PREV = Pattern.compile(".*:id/sw_prev");
    private static final Pattern CELL = Pattern.compile(".*:id/c[0-6]");
    private static final Pattern CONTENT = Pattern.compile("gift\\.dhamma\\.uposatha:id/w_c");
    /** A line only the widget's settings screen has (the app's own page has a "Theme" too). */
    private static final Pattern SETTINGS = Pattern.compile("(Background transparency|Прозрачность фона).*");
    private static final Pattern ADD = Pattern.compile("(?i)(add( automatically| to home screen)?|добавить.*|place automatically|confirm)");

    private UiDevice dev;
    private Context ctx;
    private File shots;
    private int n = 0;
    private long t0;

    private final java.util.List<String> failed = new java.util.ArrayList<>();

    private interface Step { void run() throws Exception; }

    private void check(String name, boolean ok, String detail) {
        Log.i(TAG, "CHECK " + (ok ? "ok" : "FAILED") + " " + name + (detail == null || detail.isEmpty() ? "" : ": " + detail));
        if (!ok) failed.add(name + (detail == null || detail.isEmpty() ? "" : " (" + detail + ")"));
    }

    /** One switch of the slides per widget that has one: a redraw must not leave a second copy in the launcher's views. */
    private void oneSwitchEach(String where) {
        int sw = dev.findObjects(By.res(NEXT)).size(), widgets = dev.findObjects(By.res(CONTENT)).size();
        check("the slides' switch is there once (" + where + ")", sw <= widgets, sw + " switches in " + widgets + " widgets");
    }

    /**
     * Every widget on the page is drawn for the shape it really has. A debug build says on each widget which of its sizes the launcher
     * took ("drawn for 82x115", WidgetViews.frame); a launcher that reports a cell lower than the real one (a Motorola razr) used to
     * get the design for the low cell, small in the middle of the real one. A launcher may show the whole view smaller than it is
     * laid out (Samsung One UI: 1.2 times, the same in both directions): that is its own scaling, the design is whole. So the two
     * directions are compared with each other: the height must not be more than 14 % lower than the width says.
     */
    private void drawnForItsSize(String where) {
        float d = ctx.getResources().getDisplayMetrics().density;
        int seen = 0;
        for (UiObject2 host : dev.findObjects(By.res(Pattern.compile("gift\\.dhamma\\.uposatha:id/sw_host")))) {
            String desc = host.getContentDescription();
            if (desc == null || !desc.startsWith("drawn for ")) continue;
            String[] wh = desc.substring(10).split("x");
            Rect b = host.getVisibleBounds();
            float realW = b.width() / d, realH = b.height() / d;
            float rw = Integer.parseInt(wh[0]) / realW, rh = Integer.parseInt(wh[1]) / realH;
            seen++;
            check("a widget is drawn for the shape it has (" + where + ": " + desc + ")", rh >= rw / 1.14f - 0.03f && rh <= rw * 1.04f + 0.03f,
                    "on the screen it is " + Math.round(realW) + "x" + Math.round(realH) + " dp");
        }
        Log.i(TAG, "SIZES " + where + ": " + seen + " widgets looked at");
    }

    private String logcat(String filter) {
        try { return dev.executeShellCommand("logcat -d -v brief " + filter); } catch (Throwable t) { return "logcat failed: " + t; }
    }

    private void step(String name, Step s) {
        Log.i(TAG, "STEP " + name + " at " + (System.currentTimeMillis() - t0) / 1000f + " s");
        try { s.run(); } catch (Throwable t) { Log.e(TAG, "STEP FAILED " + name + ": " + t); failed.add("step " + name + ": " + t); }
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

    /** The big widget: the one of ours on the screen with the most room. */
    private UiObject2 widget() {
        UiObject2 best = null;
        for (UiObject2 o : dev.findObjects(By.res(CONTENT))) {
            Rect b = o.getVisibleBounds();
            if (best == null || b.width() * b.height() > best.getVisibleBounds().width() * best.getVisibleBounds().height()) best = o;
        }
        return best;
    }

    private void nextPage() {
        dev.swipe(dev.getDisplayWidth() * 4 / 5, dev.getDisplayHeight() / 2, dev.getDisplayWidth() / 5, dev.getDisplayHeight() / 2, 20);
        sleep(2500);
    }

    /** Home, then on to the page of the home screen that has our big widget (a pinned widget may land on a page of its own). */
    private void toWidgetPage() {
        dev.pressHome();
        sleep(3000);
        for (int k = 0; k < 4 && widget() == null; k++) nextPage();
    }

    private Rect widgetOrLast(Rect last) {
        UiObject2 w = widget();
        return w != null ? w.getVisibleBounds() : last;
    }

    private void tap(Pattern res, String what) {
        UiObject2 o = dev.findObject(By.res(res));
        if (o != null) o.click(); else Log.w(TAG, "nothing to tap: " + what);
    }

    /** Asks the launcher to pin a widget and confirms its dialog, as a person does from the picker. */
    private void pin(String cls) {
        AppWidgetManager am = AppWidgetManager.getInstance(ctx);
        Log.i(TAG, "pin " + cls + ", supported: " + am.isRequestPinAppWidgetSupported());
        am.requestPinAppWidget(new ComponentName(ctx, PKG + "." + cls), null, null);
        sleep(2500);
        UiObject2 b = null;
        for (int k = 0; k < 8 && b == null; k++) {
            b = dev.findObject(By.text(ADD).clickable(true));
            if (b == null) b = dev.findObject(By.text(ADD));
            if (b == null) sleep(1000);
        }
        Log.i(TAG, "pin button: " + b);
        check("adding " + cls + ": the launcher's dialog with its Add button", b != null, "pin supported: " + am.isRequestPinAppWidgetSupported());
        if (b != null) b.click();
        sleep(2500);
        // Android 11 and older open the widget's settings when it is added (they do not know "configuration optional"): Back leaves
        // them, and the widget must stay (its settings are applied as they are chosen, there is nothing to confirm).
        if (dev.wait(Until.hasObject(By.text(SETTINGS)), 1500)) {
            Log.i(TAG, "the settings opened at the adding, leaving them with Back");
            dev.pressBack();
            sleep(2000);
        }
    }

    /** Long-presses the widget: the launcher shows its resize frame (handles) and, for a widget with settings, the edit button. */
    private Rect frame() {
        UiObject2 w = widget();
        if (w == null) { Log.w(TAG, "no widget to long-press"); return null; }
        Rect b = w.getVisibleBounds();
        dev.swipe(b.centerX(), b.top + b.height() / 5, b.centerX(), b.top + b.height() / 5, 120);   // a long press that does not start a drag
        sleep(2000);
        return b;
    }

    /** Drags one handle of the resize frame by a fraction of the widget's size. */
    private void drag(String edge, Rect b, float fx, float fy) {
        UiObject2 h = dev.findObject(By.res(Pattern.compile(".*:id/widget_resize_" + edge + "_handle")));
        Log.i(TAG, "resize " + edge + " handle " + h + " widget " + b);
        if (h == null || b == null) { dump("no-handle-" + edge); return; }
        Point c = h.getVisibleCenter();
        h.drag(new Point(c.x + Math.round(b.width() * fx), c.y + Math.round(b.height() * fy)), 400);
        sleep(2500);
    }

    @Test
    public void flow() {
        dev = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
        ctx = InstrumentationRegistry.getInstrumentation().getTargetContext();
        shots = new File(ctx.getExternalFilesDir(null), "shots");
        shots.mkdirs();
        t0 = System.currentTimeMillis();
        Log.i(TAG, "device " + android.os.Build.MANUFACTURER + " " + android.os.Build.MODEL + " api " + android.os.Build.VERSION.SDK_INT
                + " launcher " + dev.getLauncherPackageName() + " display " + dev.getDisplayWidth() + "x" + dev.getDisplayHeight());
        try { dev.executeShellCommand("pm grant " + PKG + " android.permission.POST_NOTIFICATIONS"); } catch (Throwable ignored) { }
        // Optional: gcloud ... --environment-variables theme=light|dark forces the system theme (the launcher and the page follow it).
        String theme = InstrumentationRegistry.getArguments().getString("theme");
        if (theme != null) {
            try { dev.executeShellCommand("cmd uimode night " + ("dark".equals(theme) ? "yes" : "no")); } catch (Throwable t) { Log.w(TAG, "theme: " + t); }
            sleep(1500);
        }
        dev.pressHome();
        sleep(1500);

        // 1. The app once: the page paints and hands the widgets their data.
        step("app-launch", () -> {
            Intent i = ctx.getPackageManager().getLaunchIntentForPackage(PKG);
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
            ctx.startActivity(i);
            dev.wait(Until.hasObject(By.pkg(PKG).depth(0)), 15000);
            sleep(10000);
        });

        // The launch asks the site for nothing. The page stays hidden until its fonts are in, and a file that is not in the bundle comes
        // from dhamma.gift (DgSitePlugin.proxy): with seven fonts missing the screen was blank for as long as the network took.
        String local = logcat("-s Capacitor:D"), cookies = logcat("-s CapacitorCookies:I");
        check("launch: the page came from the bundle", local.contains("Handling local request"), "");
        StringBuilder site = new StringBuilder();
        for (String line : cookies.split("\n")) {
            int at = line.indexOf("https://dhamma.gift/");
            if (at >= 0 && (line.contains("/assets/") || line.contains("/nodejs/") || line.contains("/settings/"))) site.append(line.substring(at).replace("'", "")).append(' ');
        }
        check("launch: nothing is asked from the site", site.length() == 0, site.toString().trim());

        // 2. The big widget is added.
        step("add-big-widget", () -> pin("WidgetProviderLarge"));
        step("home-with-big-widget", () -> { toWidgetPage(); dev.wait(Until.findObject(By.res(NEXT)), 8000); });
        dump("home-big");
        drawnForItsSize("the big widget as the launcher put it");
        step("leave-edit-mode", () -> { dev.pressBack(); sleep(1500); });   // Samsung leaves a new widget in its resize frame

        // 3. Its three slides: it opens on the calendar; forward to Uposatha, Day & night, and round to the calendar; then one back and forth.
        final Pattern GRID = Pattern.compile(".*:id/grid"), MONTH = Pattern.compile(".*:id/month");
        check("slides: the big widget opens on the calendar", dev.hasObject(By.res(GRID)), "");
        for (String s : new String[] { "uposatha", "daynight", "calendar" }) {
            step("slide-next-" + s, () -> { tap(NEXT, "next slide"); sleep(2200); });
            check("slides: a tap on the switch shows " + s, dev.hasObject(By.res(GRID)) == s.equals("calendar"), "");
        }
        step("slide-back", () -> { tap(PREV, "previous slide"); sleep(2200); });
        step("slide-forward", () -> { tap(NEXT, "next slide"); sleep(2200); });

        // 4. The calendar's own arrows: next month, the month after, and back.
        final String[] month = new String[2];
        UiObject2 m0 = dev.findObject(By.res(MONTH));
        month[0] = m0 == null ? null : m0.getText();
        step("month-next", () -> { tap(Pattern.compile(".*:id/nav_next"), "next month"); sleep(2000); });
        UiObject2 m1 = dev.findObject(By.res(MONTH));
        month[1] = m1 == null ? null : m1.getText();
        check("calendar: the arrow turns the month", month[0] != null && month[1] != null && !month[0].equals(month[1]), month[0] + " -> " + month[1]);
        step("month-next-2", () -> { tap(Pattern.compile(".*:id/nav_next"), "next month"); sleep(2000); });
        step("month-back", () -> { tap(Pattern.compile(".*:id/nav_prev"), "previous month"); sleep(1500); tap(Pattern.compile(".*:id/nav_prev"), "previous month"); sleep(2000); });

        // 5. The launcher's resize: lower (to about half), every slide at that size, then tall again.
        final Rect[] box = new Rect[1];
        step("resize-frame", () -> box[0] = frame());
        dump("resize-frame");
        step("resize-lower", () -> drag("bottom", box[0], 0, -0.45f));
        step("resize-leave", () -> { dev.pressBack(); sleep(2000); });
        for (String s : new String[] { "uposatha", "daynight", "calendar" }) step("low-slide-" + s, () -> { tap(NEXT, "next slide"); sleep(2200); });
        step("resize-frame-2", () -> box[0] = frame());
        step("resize-narrower", () -> drag("right", box[0], -0.45f, 0));
        step("resize-leave-2", () -> { dev.pressBack(); sleep(2000); });
        for (String s : new String[] { "uposatha", "daynight", "calendar" }) step("narrow-slide-" + s, () -> { tap(NEXT, "next slide"); sleep(2200); });
        step("resize-frame-3", () -> box[0] = frame());
        step("resize-wider", () -> drag("right", box[0], 1.2f, 0));
        step("resize-frame-4", () -> { if (!dev.hasObject(By.res(Pattern.compile(".*:id/widget_resize_bottom_handle")))) box[0] = frame(); else box[0] = widgetOrLast(box[0]); });
        step("resize-taller", () -> drag("bottom", box[0], 0, 1.3f));
        step("resize-leave-3", () -> { dev.pressBack(); sleep(2000); });

        // 6. The widget's own settings, opened from the launcher (the edit button of the resize frame); if this launcher has none, the same screen directly.
        step("settings-open", () -> {
            frame();
            UiObject2 edit = dev.findObject(By.res(Pattern.compile(".*:id/widget_reconfigure_button")));
            Log.i(TAG, "launcher's edit button: " + edit);
            if (edit != null) edit.click();
            sleep(2500);
            if (!dev.wait(Until.hasObject(By.text(SETTINGS)), 4000)) {
                dev.pressBack();
                int[] ids = AppWidgetManager.getInstance(ctx).getAppWidgetIds(new ComponentName(ctx, PKG + ".WidgetProviderLarge"));
                Log.i(TAG, "no settings from the launcher, opening them directly for " + java.util.Arrays.toString(ids));
                if (ids.length > 0) ctx.startActivity(new Intent(ctx, WidgetConfigActivity.class).putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, ids[0]).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
                sleep(3000);
            }
        });
        dump("settings");
        step("settings-dark", () -> { UiObject2 b = dev.findObject(By.text(Pattern.compile("Dark|Тёмная"))); if (b != null) b.click(); sleep(1800); });
        step("settings-transparency", () -> {
            UiObject2 bar = dev.findObject(By.clazz("android.widget.SeekBar"));
            Log.i(TAG, "transparency slider: " + bar);
            if (bar != null) { Rect r = bar.getVisibleBounds(); dev.swipe(r.left + r.width() / 20, r.centerY(), r.left + r.width() / 2, r.centerY(), 40); }
            sleep(1800);
        });
        step("settings-details-on", () -> {
            java.util.List<UiObject2> on = dev.findObjects(By.text(Pattern.compile("On|Вкл")));
            if (!on.isEmpty()) on.get(0).click();
            sleep(1800);
        });
        step("settings-done", () -> {
            UiObject2 b = dev.findObject(By.text(Pattern.compile("Done|Готово")));
            if (b != null) b.click(); else Log.w(TAG, "no Done button");
            sleep(2500);
        });
        step("home-after-settings", () -> toWidgetPage());
        for (String s : new String[] { "uposatha", "daynight", "calendar" }) step("dark-slide-" + s, () -> { tap(NEXT, "next slide"); sleep(2200); });

        // 7. A day of the calendar: the app opens on that day.
        step("day-tap", () -> {
            java.util.List<UiObject2> cells = dev.findObjects(By.res(CELL).clickable(true));
            Log.i(TAG, "day cells: " + cells.size());
            UiObject2 c = cells.isEmpty() ? null : cells.get(Math.min(cells.size() - 1, 17));   // the third week
            if (c != null) c.click();
            dev.wait(Until.hasObject(By.pkg(PKG).depth(0)), 8000);
            sleep(6000);
        });
        dump("after-day-tap");
        step("home-after-day", () -> toWidgetPage());

        // 8. The other six widgets, each added the way a person adds it: the launcher puts them on the next free place.
        for (String cls : new String[] { "WidgetProviderMoon", "WidgetProviderMoonUpo", "WidgetProviderSmall", "WidgetProviderDay", "WidgetProviderStrip", "WidgetProviderMedium" }) {
            step("add-" + cls.replace("WidgetProvider", "").toLowerCase(), () -> { pin(cls); dev.pressHome(); sleep(2500); });
        }
        dump("home-all");
        step("home-page-1", () -> { dev.pressHome(); sleep(1500); dev.pressHome(); sleep(2000); });
        step("home-page-2", () -> { nextPage(); });
        dump("home-page-2");
        drawnForItsSize("after the resizes and the settings");
        oneSwitchEach("the big widget after its slides, months and settings");
        if (dev.findObjects(By.res(NEXT)).isEmpty() || dev.findObjects(By.res(CONTENT)).size() < 2) step("home-page-3", () -> nextPage());
        // the 4x2 with its own three slides
        for (String s : new String[] { "daynight", "calendar", "uposatha" }) step("medium-slide-" + s, () -> {
            UiObject2 best = null;   // the lowest switch on the page is the last widget added (the 4x2)
            for (UiObject2 o : dev.findObjects(By.res(NEXT))) if (best == null || o.getVisibleBounds().top > best.getVisibleBounds().top) best = o;
            if (best != null) best.click(); else Log.w(TAG, "no switch on this page");
            sleep(2200);
        });
        step("home-page-next", () -> nextPage());

        // 9. The Moon's own setting is applied the moment it is chosen: Back leaves the screen, there is no Done to forget.
        final int[] moonIds = AppWidgetManager.getInstance(ctx).getAppWidgetIds(new ComponentName(ctx, PKG + ".WidgetProviderMoon"));
        check("moon widget: it was added", moonIds.length > 0, "");
        final UiObject2[] moon = new UiObject2[1];
        if (moonIds.length > 0) {
            check("moon settings: just the moon by default", !WidgetConfig.load(ctx, moonIds[0]).pct, "");
            step("moon-settings", () -> {
                ctx.startActivity(new Intent(ctx, WidgetConfigActivity.class).putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, moonIds[0]).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
                dev.wait(Until.hasObject(By.text(Pattern.compile("Lit percent|Процент освещённости"))), 6000);
            });
            step("moon-percent-on", () -> {
                UiObject2 on = dev.findObject(By.text(Pattern.compile("On|Вкл")));
                if (on != null) on.click(); else Log.w(TAG, "no On in the Moon's settings");
                sleep(1500);
            });
            check("moon settings: 'Saved' is shown at once", dev.hasObject(By.text(Pattern.compile(".*(Saved|Сохранено)"))), "");
            step("moon-settings-back", () -> { dev.pressBack(); sleep(1500); });
            check("moon settings: the choice is kept without Done", WidgetConfig.load(ctx, moonIds[0]).pct, "");
            final boolean[] pct = { false };
            step("moon-on-home", () -> {
                dev.pressHome();
                sleep(2500);
                dev.pressHome();
                sleep(1500);
                for (int k = 0; k < 5 && moon[0] == null; k++) {
                    for (UiObject2 o : dev.findObjects(By.res(CONTENT))) {   // the Moon: the widget with no text but its percent and the arrow
                        java.util.List<UiObject2> tv = o.findObjects(By.clazz("android.widget.TextView"));
                        if (tv.size() > 2) continue;
                        moon[0] = o;
                        for (UiObject2 t : tv) if (t.getText() != null && t.getText().matches("\\d+[.,]\\d\\d%")) pct[0] = true;
                    }
                    if (moon[0] == null) nextPage();
                }
            });
            dump("home-moon");
            check("moon widget: found on the home screen", moon[0] != null, "");
            check("moon widget: the percent is on the home screen, with hundredths", pct[0], "");
            oneSwitchEach("the page with the small widgets");
            drawnForItsSize("the page with the small widgets");
        }

        // 10. A tap on a widget while the app is alive: the open page goes to the place itself, nothing is loaded again.
        step("moon-tap", () -> {
            dev.executeShellCommand("logcat -c");
            UiObject2 w = moon[0] != null ? moon[0] : widget();
            if (w != null) w.click(); else Log.w(TAG, "no widget to tap");
            dev.wait(Until.hasObject(By.pkg(PKG).depth(0)), 8000);
            sleep(3000);
        });
        String route = logcat("-s DgWidget:I");
        check("widget tap: the app came to the front", dev.hasObject(By.pkg(PKG).depth(0)), "");
        check("widget tap: the open page went to the place itself", route.contains("the open page went there"), "");
        check("widget tap: the page was not loaded again", !route.contains("the page is loaded"), "");

        // 11. An address from outside (any app can start the launcher activity with any extra) is not opened in the app's window.
        step("foreign-route", () -> {
            dev.executeShellCommand("logcat -c");
            Intent i = ctx.getPackageManager().getLaunchIntentForPackage(PKG);
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).putExtra("route", "https://example.com/");
            ctx.startActivity(i);
            sleep(3000);
        });
        check("a foreign address in the route is refused", logcat("-s DgWidget:W").contains("route refused"), "");

        step("end", () -> sleep(1500));
        Log.i(TAG, "CHECKS FAILED: " + failed.size() + " " + failed);
        org.junit.Assert.assertTrue("failed: " + failed, failed.isEmpty());
    }
}
