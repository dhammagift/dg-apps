package gift.dhamma.uposatha;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.appwidget.AppWidgetProviderInfo;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.os.Bundle;
import android.widget.RemoteViews;

import java.util.ArrayList;
import java.util.List;

import org.json.JSONObject;

/**
 * The Uposatha home-screen widgets: seven separate widgets in the picker (the subclasses WidgetProviderMoon .. WidgetProviderLarge),
 * each one thing and one design that is scaled to the cell (WidgetViews), drawn from the data the app keeps in SharedPreferences
 * (DgWidgetPlugin). This class finds the size the launcher gave, hands it to WidgetViews, and plans the next update. It never computes
 * the moon, the sun or an Uposatha.
 *
 * Taps: a widget opens the app on its own tab (home / parts / cal); in the calendar each day opens the calendar on that day and the
 * two arrows turn the month inside the widget (a broadcast; the app does not open). The two big widgets (4x2, 4x4) keep the three
 * slides of the first version (Uposatha, Day & night, Calendar) with a switch at the bottom: a small widget is one thing, a big one
 * with one thing wastes its room (owner, 2026-10-10). The 4x2 opens on the Uposatha, the 4x4 on the calendar. The widget's own settings: WidgetConfigActivity.
 */
public class WidgetProvider extends AppWidgetProvider {
    static final String PREFS = "dg_widget", KEY_DATA = "data";
    static final String ACTION_NAV = "gift.dhamma.uposatha.widget.NAV";
    static final String ACTION_SLIDE = "gift.dhamma.uposatha.widget.CYCLE";   // the name of the first version: a tap that is still on a screen keeps working
    static final String ACTION_TICK = "gift.dhamma.uposatha.widget.TICK";
    /** The calendar can be turned this many months ahead (the data reaches about eleven weeks). */
    static final int MONTHS_AHEAD = 2;
    /** The picker's entries, in the order of WidgetPlan.MOON .. CAL. The 2x2, 4x2 and 4x4 keep the class names of the first version, so a widget that is already on a screen stays. */
    static final Class<?>[] PROVIDERS = { WidgetProviderMoon.class, WidgetProviderMoonUpo.class, WidgetProviderSmall.class, WidgetProviderStrip.class,
            WidgetProviderMedium.class, WidgetProviderDay.class, WidgetProviderLarge.class };
    private static final String[] TAB = { "home", "home", "home", "home", "home", "parts", "cal" };

    @Override
    public void onUpdate(Context ctx, AppWidgetManager mgr, int[] ids) {
        for (int id : ids) update(ctx, mgr, id);
        schedule(ctx);
    }

    @Override
    public void onAppWidgetOptionsChanged(Context ctx, AppWidgetManager mgr, int id, Bundle options) {
        update(ctx, mgr, id);
    }

    @Override
    public void onDeleted(Context ctx, int[] ids) {
        WidgetConfig.forget(ctx, ids);
    }

    @Override
    public void onDisabled(Context ctx) {
        AppWidgetManager mgr = AppWidgetManager.getInstance(ctx);
        if (allIds(ctx, mgr).length > 0) return;   // one kind is gone, another is still on a screen
        AlarmManager am = ctx.getSystemService(AlarmManager.class);
        if (am != null) am.cancel(tickIntent(ctx));
    }

    /** Every widget is drawn on this one thread (or under DRAW, see update()). */
    private static final java.util.concurrent.ExecutorService WORK = java.util.concurrent.Executors.newSingleThreadExecutor();
    private static final Object DRAW = new Object();

    /**
     * Drawing a widget makes bitmaps and measures text, and a broadcast arrives on the app's MAIN thread: seven widgets, each in two
     * orientations, held up the app's own start (owner, 2026-10-10: a blank screen between the splash and the page). So the work is
     * done on a thread of its own and the broadcast is finished from there.
     */
    @Override
    public void onReceive(Context ctx, Intent intent) {
        final PendingResult pending = goAsync();
        final Context app = ctx.getApplicationContext();
        WORK.execute(() -> {
            try { handle(app, intent); }
            catch (RuntimeException e) { android.util.Log.w("DgWidget", "broadcast failed: " + e); }
            finally { pending.finish(); }
        });
    }

    private void handle(Context ctx, Intent intent) {
        String action = intent == null ? null : intent.getAction();
        if (ACTION_SLIDE.equals(action)) {
            int id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID);
            if (id != AppWidgetManager.INVALID_APPWIDGET_ID) {
                SharedPreferences p = prefs(ctx);
                p.edit().putInt("layer_" + id, (slideOf(ctx, AppWidgetManager.getInstance(ctx), id) + (intent.getIntExtra("dir", 1) < 0 ? 2 : 1)) % 3).apply();   // the left half goes back, the right half forward
                tapped(ctx, AppWidgetManager.getInstance(ctx), id, intent);
            }
            return;
        }
        if (ACTION_NAV.equals(action)) {
            int id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID);
            if (id != AppWidgetManager.INVALID_APPWIDGET_ID) {
                int off = Math.max(0, Math.min(MONTHS_AHEAD, monthOff(ctx, id) + (intent.getIntExtra("dir", 1) < 0 ? -1 : 1)));
                prefs(ctx).edit().putInt("mon_" + id, off).putString("mon_day_" + id, today()).apply();
                tapped(ctx, AppWidgetManager.getInstance(ctx), id, intent);
            }
            return;
        }
        if (ACTION_TICK.equals(action) || Intent.ACTION_BOOT_COMPLETED.equals(action) || Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)
                || Intent.ACTION_TIME_CHANGED.equals(action) || Intent.ACTION_TIMEZONE_CHANGED.equals(action)) {
            refreshAll(ctx);
            return;
        }
        super.onReceive(ctx, intent);
    }

    // ------------------------------------------------------------------ data and drawing

    static SharedPreferences prefs(Context ctx) {
        return ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    static JSONObject readData(Context ctx) {
        String s = prefs(ctx).getString(KEY_DATA, null);
        if (s == null) return null;
        try { return new JSONObject(s); } catch (Exception e) { return null; }
    }

    private static String today() {
        return new java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(new java.util.Date());
    }

    /** The month the calendar widget is turned to: 0 = this month. A turn lasts for the day it was made on, then the widget is back on today. */
    static int monthOff(Context ctx, int id) {
        SharedPreferences p = prefs(ctx);
        return today().equals(p.getString("mon_day_" + id, "")) ? Math.max(0, Math.min(MONTHS_AHEAD, p.getInt("mon_" + id, 0))) : 0;
    }

    /** The slide a big widget shows (0 Uposatha, 1 Day & night, 2 Calendar): the 4x2 opens on the Uposatha, the 4x4 on the calendar, then wherever it was left. */
    static int slideOf(Context ctx, AppWidgetManager mgr, int id) {
        int s = prefs(ctx).getInt("layer_" + id, kindOf(mgr, id) == WidgetPlan.CAL ? 2 : 0);
        return ((s % 3) + 3) % 3;
    }

    /** Which widget an id is (WidgetPlan.MOON .. CAL), from the provider it was added with. */
    static int kindOf(AppWidgetManager mgr, int id) {
        AppWidgetProviderInfo info = mgr.getAppWidgetInfo(id);
        String cls = info == null || info.provider == null ? "" : info.provider.getClassName();
        for (int i = 0; i < PROVIDERS.length; i++) if (PROVIDERS[i].getName().equals(cls)) return i;
        return WidgetPlan.UPO;
    }

    /** The ids of every Uposatha widget on the screen: the picker's entries share this code. */
    static int[] allIds(Context ctx, AppWidgetManager mgr) {
        int total = 0;
        int[][] per = new int[PROVIDERS.length][];
        for (int i = 0; i < PROVIDERS.length; i++) { per[i] = mgr.getAppWidgetIds(new ComponentName(ctx, PROVIDERS[i])); total += per[i].length; }
        int[] out = new int[total];
        int at = 0;
        for (int[] a : per) { System.arraycopy(a, 0, out, at, a.length); at += a.length; }
        return out;
    }

    /** Redraws every widget on the screen and plans the next redraw (new data, boot, update, a tick). */
    static void refreshAll(Context ctx) {
        AppWidgetManager mgr = AppWidgetManager.getInstance(ctx);
        for (int id : allIds(ctx, mgr)) update(ctx, mgr, id);
        schedule(ctx);
    }

    /**
     * The sizes (dp, width x height) this widget really has: [0] in the orientation the phone is in now, [1] in the other one when
     * it differs. The launcher's own numbers, the same on every Android: portrait is (min width, max height), landscape is
     * (max width, min height). The design is scaled to each of them, so these have to be the real sizes, not a grid of guesses.
     */
    static List<int[]> sizesDp(Context ctx, AppWidgetManager mgr, int id) {
        Bundle o = mgr.getAppWidgetOptions(id);
        int[] d = defaultSize(kindOf(mgr, id));
        int minW = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0), maxW = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0);
        int minH = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0), maxH = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0);
        int[] port = { minW > 0 ? minW : d[0], maxH > 0 ? maxH : d[1] };
        int[] land = { maxW > 0 ? maxW : port[0], minH > 0 ? minH : port[1] };
        boolean landscape = landscape(ctx);
        int[] now = landscape ? land : port, other = landscape ? port : land;
        List<int[]> out = new ArrayList<>();
        out.add(now);
        if (Math.abs(other[0] - now[0]) >= 4 || Math.abs(other[1] - now[1]) >= 4) out.add(other);
        return out;
    }

    private static boolean landscape(Context ctx) { return ctx.getResources().getConfiguration().orientation == Configuration.ORIENTATION_LANDSCAPE; }

    /** The size a widget is drawn for when the launcher says nothing (dp): about its own cells on a phone. */
    static int[] defaultSize(int kind) {
        switch (kind) {
            case WidgetPlan.MOON: return new int[] { 60, 100 };
            case WidgetPlan.MOONUPO: return new int[] { 140, 100 };
            case WidgetPlan.UPO: return new int[] { 150, 200 };
            case WidgetPlan.STRIP: return new int[] { 290, 100 };
            case WidgetPlan.CAL: return new int[] { 290, 430 };
            default: return new int[] { 290, 200 };
        }
    }

    static void update(Context ctx, AppWidgetManager mgr, int id) {
        synchronized (DRAW) { draw(ctx, mgr, id, 0, 0); }   // the page's thread (DgWidgetPlugin) and the settings screen draw too
    }

    /**
     * A tap on the switch of the slides or on a month arrow. The tap says which of the widget's sizes the launcher is showing (each
     * size has its own intents, see slide()): the answer is drawn for that size and the reported one only, not for all nine - a
     * third of a second instead of most of a second on a phone. The next tick draws all the sizes again.
     */
    private static void tapped(Context ctx, AppWidgetManager mgr, int id, Intent intent) {
        synchronized (DRAW) { draw(ctx, mgr, id, intent.getIntExtra("w", 0), intent.getIntExtra("h", 0)); }
    }

    private static void draw(Context ctx, AppWidgetManager mgr, int id, int shownW, int shownH) {
        try {
            int kind = kindOf(mgr, id);
            List<int[]> sizes = sizesDp(ctx, mgr, id);
            JSONObject data = readData(ctx);
            long now = System.currentTimeMillis();
            WidgetConfig cfg = WidgetConfig.load(ctx, id);
            int mon = kind == WidgetPlan.CAL || kind == WidgetPlan.UPO_M ? monthOff(ctx, id) : 0;
            int slide = slideOf(ctx, mgr, id);   // only the big widgets with the three slides use it
            int[] sz = sizes.get(0);
            if (android.os.Build.VERSION.SDK_INT >= 31) {
                // One RemoteViews per size the widget may really have (WidgetPlan.sizes: the reported one, taller ones, and each of them
                // a little narrower), plus the other orientation; the launcher takes the nearest that fits the view it really has.
                // After a tap only the size the tap came from is drawn again. Refused (too many pictures): the pair below.
                try {
                    long t0 = android.os.SystemClock.uptimeMillis();
                    WidgetViews.bitmapBytes = 0;
                    WidgetMoon.maxPx = 420;
                    WidgetMoon.shared = true;
                    java.util.Map<android.util.SizeF, RemoteViews> map = new android.util.ArrayMap<>();
                    int[][] all = WidgetPlan.sizes(sz[0], sz[1]);
                    for (int i = 0; i < all.length; i++) {
                        int[] c = all[i];
                        if (i > 0 && shownH > 0 && !(c[0] == shownW && c[1] == shownH)) continue;   // a tap: only the size it came from (and the reported one)
                        map.put(new android.util.SizeF(c[2], c[3]), WidgetViews.build(ctx, id, kind, c[0], c[1], data, now, cfg, mon, slide));
                    }
                    if (sizes.size() > 1) {
                        int[] ot = sizes.get(1);
                        android.util.SizeF key = new android.util.SizeF(ot[0] - 2, ot[1]);
                        if (!map.containsKey(key)) map.put(key, WidgetViews.build(ctx, id, kind, ot[0], ot[1], data, now, cfg, mon, slide));
                    }
                    mgr.updateAppWidget(id, new RemoteViews(map));
                    android.util.Log.i("DgWidget", "widget " + id + ": " + map.size() + " sizes from " + sz[0] + "x" + sz[1] + " dp, " + (WidgetViews.bitmapBytes >> 10) + " KB of pictures, " + (android.os.SystemClock.uptimeMillis() - t0) + " ms");
                    return;
                } catch (RuntimeException e) {
                    android.util.Log.w("DgWidget", "the sizes were refused (" + (WidgetViews.bitmapBytes >> 10) + " KB of pictures), the two orientations instead: " + e);
                } finally {
                    WidgetMoon.maxPx = 640;
                    WidgetMoon.shared = false;
                }
            }
            if (sizes.size() > 1) {
                // Below Android 12, or the sizes above were refused: one RemoteViews per orientation, and the launcher takes the one of
                // ITS orientation. Refused too: the view of this orientation alone - a widget that is wrong after a turn is better
                // than a blank one.
                try {
                    int[] ot = sizes.get(1);
                    WidgetViews.bitmapBytes = 0;
                    RemoteViews cur = WidgetViews.build(ctx, id, kind, sz[0], sz[1], data, now, cfg, mon, slide);
                    RemoteViews oth = WidgetViews.build(ctx, id, kind, ot[0], ot[1], data, now, cfg, mon, slide);
                    mgr.updateAppWidget(id, landscape(ctx) ? new RemoteViews(cur, oth) : new RemoteViews(oth, cur));
                    return;
                } catch (RuntimeException e) {
                    android.util.Log.w("DgWidget", "both orientations were refused (" + (WidgetViews.bitmapBytes >> 10) + " KB of pictures), one instead: " + e);
                }
            }
            mgr.updateAppWidget(id, WidgetViews.build(ctx, id, kind, sz[0], sz[1], data, now, cfg, mon, slide));
        } catch (RuntimeException e) {
            android.util.Log.w("DgWidget", "update failed: " + e);
        }
    }

    static String route(int kind, String day) {
        String tab = TAB[Math.max(0, Math.min(TAB.length - 1, kind))];
        return "/uposatha-calendar?app=1&tab=" + tab + (day != null ? "&day=" + day : "") + ("home".equals(tab) ? "&moon=1" : "");   // a tap on a moon widget lands on the moon, which plays its cycle once
    }

    static PendingIntent openApp(Context ctx, int widgetId, int slot, String route) {
        Intent i = new Intent(ctx, WidgetOpenActivity.class);   // not MainActivity: see WidgetOpenActivity
        i.setAction("gift.dhamma.uposatha.WIDGET");
        i.putExtra("route", route);
        i.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        // The intents differ only in an extra, which PendingIntent ignores: the request code tells them apart.
        return PendingIntent.getActivity(ctx, widgetId * 64 + slot, i, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    /** The switch of the 4x2's three slides: the one before (-1) or after (+1). */
    static PendingIntent slide(Context ctx, int id, int dir, int drawnW, int drawnH) {
        Intent i = new Intent(ctx, WidgetProvider.class);
        i.setAction(ACTION_SLIDE);
        i.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id);
        i.putExtra("dir", dir);
        // Each size the widget is drawn for has its own intent (the data tells them apart, extras do not): the tap brings back the
        // height of the view the launcher is showing.
        i.putExtra("w", drawnW);
        i.putExtra("h", drawnH);
        i.setData(android.net.Uri.parse("dgwidget://slide/" + id + "/" + dir + "/" + drawnW + "x" + drawnH));
        return PendingIntent.getBroadcast(ctx, id * 2 + (dir < 0 ? 1 : 0), i, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    /** The calendar's arrows: the month before (-1) or after (+1), inside the widget. */
    static PendingIntent nav(Context ctx, int id, int dir, int drawnW, int drawnH) {
        Intent i = new Intent(ctx, WidgetProvider.class);
        i.setAction(ACTION_NAV);
        i.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id);
        i.putExtra("dir", dir);
        i.putExtra("w", drawnW);
        i.putExtra("h", drawnH);
        i.setData(android.net.Uri.parse("dgwidget://nav/" + id + "/" + dir + "/" + drawnW + "x" + drawnH));
        // The two intents differ only in an extra, which PendingIntent ignores: the request code tells them apart.
        return PendingIntent.getBroadcast(ctx, id * 2 + (dir < 0 ? 1 : 0), i, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    // ------------------------------------------------------------------ the plan: one alarm, always the next moment that matters

    private static PendingIntent tickIntent(Context ctx) {
        Intent i = new Intent(ctx, WidgetProvider.class).setAction(ACTION_TICK);
        return PendingIntent.getBroadcast(ctx, 0, i, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    /**
     * Next redraw: the earliest of the counter's next change (hourly, on the counter's own minute), the time-left line
     * (every 15 minutes) and the next event in the data (dawn, noon, sunset, a part border, an Uposatha start or end).
     * An inexact alarm that can run in Doze; an event gets an exact one only where the app may already schedule them
     * (USE_EXACT_ALARM is in the manifest for the reminders), never a new permission. The alarm is RTC, not wake-up: a sleeping
     * phone shows nothing, and the first moment it is awake again the overdue alarm redraws the widget.
     */
    static void schedule(Context ctx) {
        AlarmManager am = ctx.getSystemService(AlarmManager.class);
        if (am == null) return;
        PendingIntent pi = tickIntent(ctx);
        am.cancel(pi);
        AppWidgetManager mgr = AppWidgetManager.getInstance(ctx);
        if (allIds(ctx, mgr).length == 0) return;
        long now = System.currentTimeMillis();
        WidgetModel m = WidgetModel.parse(readData(ctx), now);
        long at = now + WidgetFormat.HOUR;   // no data: look again in an hour (it may have arrived)
        boolean event = false;
        if (m != null) {
            long quarter = now + 15 * WidgetFormat.MIN - (now % (15 * WidgetFormat.MIN)) + 1000;
            long flip = now + WidgetFormat.untilCounterChanges(m.counterTarget() - now);
            long ev = m.nextEvent();
            at = Math.min(quarter, flip);
            if (ev != Long.MAX_VALUE && ev + 1000 <= at) { at = ev + 1000; event = true; }
        }
        if (at < now + 5000) at = now + 5000;
        boolean exact = event && (android.os.Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms());
        if (exact) am.setExactAndAllowWhileIdle(AlarmManager.RTC, at, pi);
        else am.setAndAllowWhileIdle(AlarmManager.RTC, at, pi);
    }
}
