package gift.dhamma.uposatha;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.os.Bundle;
import android.util.ArrayMap;
import android.util.SizeF;
import android.widget.RemoteViews;

import java.util.ArrayList;
import java.util.List;

import org.json.JSONObject;

/**
 * The Uposatha home-screen widget: three layers (Uposatha + kala, Day and night, Month) at three sizes, built by WidgetViews as real
 * views (TextViews, weights: the launcher reflows them to any size) from the data the app keeps in SharedPreferences (DgWidgetPlugin).
 * This class picks the sizes, hands them to WidgetViews, and plans the next update. It never computes the moon, the sun or an Uposatha.
 *
 * Taps: the dots strip cycles the layer of THIS widget (a broadcast; the app does not open); anything else opens the app on the
 * layer's tab (home / parts / cal); in the month layer (medium, large) each day number opens the calendar on that day.
 */
public class WidgetProvider extends AppWidgetProvider {
    static final String PREFS = "dg_widget", KEY_DATA = "data";
    static final String ACTION_CYCLE = "gift.dhamma.uposatha.widget.CYCLE";
    static final String ACTION_TICK = "gift.dhamma.uposatha.widget.TICK";
    private static final String[] TAB = { "home", "parts", "cal" };

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
        SharedPreferences.Editor e = prefs(ctx).edit();
        for (int id : ids) e.remove("layer_" + id);
        e.apply();
    }

    @Override
    public void onDisabled(Context ctx) {
        AlarmManager am = ctx.getSystemService(AlarmManager.class);
        if (am != null) am.cancel(tickIntent(ctx));
    }

    @Override
    public void onReceive(Context ctx, Intent intent) {
        String action = intent == null ? null : intent.getAction();
        if (ACTION_CYCLE.equals(action)) {
            int id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID);
            if (id != AppWidgetManager.INVALID_APPWIDGET_ID) {
                SharedPreferences p = prefs(ctx);
                int dir = intent.getIntExtra("dir", 1) < 0 ? WidgetViews.LAYERS - 1 : 1;   // the left half goes back, the right half forward
                p.edit().putInt("layer_" + id, (p.getInt("layer_" + id, 0) + dir) % WidgetViews.LAYERS).apply();
                update(ctx, AppWidgetManager.getInstance(ctx), id);
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

    /** The ids of every Uposatha widget on the screen: the three picker entries (2x2, 4x2, 4x4) share this code. */
    static int[] allIds(Context ctx, AppWidgetManager mgr) {
        Class<?>[] cls = { WidgetProviderSmall.class, WidgetProviderMedium.class, WidgetProviderLarge.class };
        int total = 0;
        int[][] per = new int[cls.length][];
        for (int i = 0; i < cls.length; i++) { per[i] = mgr.getAppWidgetIds(new ComponentName(ctx, cls[i])); total += per[i].length; }
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
     * The sizes (dp, width x height) this widget can really have right now. Android 12+ lists them (OPTION_APPWIDGET_SIZES: one per
     * orientation, from the launcher's own grid) and the launcher picks the matching RemoteViews itself; before that, the two numbers
     * of the current orientation. Each entry gets its own RemoteViews (its own decisions: how many rows, which lines); the views themselves reflow
     * to whatever size the launcher really gives, so nothing is ever stretched. A Motorola launcher reported sizes the old two-number
     * way read wrongly, so the list is the source.
     */
    static List<int[]> sizesDp(Context ctx, AppWidgetManager mgr, int id) {
        Bundle o = mgr.getAppWidgetOptions(id);
        List<int[]> out = new ArrayList<>();
        if (android.os.Build.VERSION.SDK_INT >= 31) {
            ArrayList<SizeF> list = o.getParcelableArrayList(AppWidgetManager.OPTION_APPWIDGET_SIZES);
            if (list != null) {
                for (SizeF f : list) {
                    int w = Math.round(f.getWidth()), h = Math.round(f.getHeight());
                    if (w < 40 || h < 40) continue;
                    boolean dup = false;
                    for (int[] x : out) if (Math.abs(x[0] - w) < 6 && Math.abs(x[1] - h) < 6) dup = true;
                    if (!dup && out.size() < 3) out.add(new int[] { w, h });
                }
            }
        }
        if (out.isEmpty()) {
            boolean port = ctx.getResources().getConfiguration().orientation != Configuration.ORIENTATION_LANDSCAPE;
            int w = o.getInt(port ? AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH : AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0);
            int h = o.getInt(port ? AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT : AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0);
            out.add(new int[] { w > 0 ? w : 160, h > 0 ? h : 160 });
        }
        return out;
    }

    static void update(Context ctx, AppWidgetManager mgr, int id) {
        try {
            List<int[]> sizes = sizesDp(ctx, mgr, id);
            JSONObject data = readData(ctx);
            long now = System.currentTimeMillis();
            WidgetModel model = WidgetModel.parse(data, now);
            int layer = model == null ? 0 : prefs(ctx).getInt("layer_" + id, 0) % WidgetViews.LAYERS;
            if (android.os.Build.VERSION.SDK_INT >= 31) {
                // One RemoteViews per size of the grid; the launcher takes the largest that fits the widget's real size and reflows it.
                // Too much for the launcher (the update is refused: too many pictures, too big a transaction): then ONE view for the size the
                // launcher reports - a widget that is a little less clever is better than a blank one.
                try {
                    ArrayMap<SizeF, RemoteViews> map = new ArrayMap<>();
                    WidgetViews.bitmapBytes = 0;
                    for (int[] sz : WidgetPlan.grid()) map.put(new SizeF(sz[0], sz[1]), WidgetViews.build(ctx, id, sz[0], sz[1], data, now, layer));
                    android.util.Log.i("DgWidget", "update " + id + ": " + map.size() + " sizes, moon pictures " + (WidgetViews.bitmapBytes >> 10) + " KB");
                    mgr.updateAppWidget(id, new RemoteViews(map));
                    return;
                } catch (RuntimeException e) {
                    android.util.Log.w("DgWidget", "the grid of sizes was refused (" + (WidgetViews.bitmapBytes >> 10) + " KB of pictures), one size instead: " + e);
                }
            }
            int[] sz = sizes.get(0);
            mgr.updateAppWidget(id, WidgetViews.build(ctx, id, sz[0], sz[1], data, now, layer));
        } catch (RuntimeException e) {
            android.util.Log.w("DgWidget", "update failed: " + e);
        }
    }

    static String route(int layer, String day) {
        return "/uposatha-calendar?app=1&tab=" + TAB[layer] + (day != null ? "&day=" + day : "") + (layer == 0 ? "&moon=1" : "");   // a tap on the first layer lands on the moon, which plays its cycle once
    }

    static PendingIntent openApp(Context ctx, int widgetId, int slot, String route) {
        Intent i = new Intent(ctx, MainActivity.class);
        i.setAction("gift.dhamma.uposatha.WIDGET");
        i.putExtra("route", route);
        i.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        // The intents differ only in an extra, which PendingIntent ignores: the request code tells them apart.
        return PendingIntent.getActivity(ctx, widgetId * 64 + slot, i, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    static PendingIntent cycle(Context ctx, int id, int dir) {
        Intent i = new Intent(ctx, WidgetProvider.class);
        i.setAction(ACTION_CYCLE);
        i.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id);
        i.putExtra("dir", dir);
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
