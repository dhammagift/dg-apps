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
import android.graphics.Bitmap;
import android.os.Bundle;
import android.util.ArrayMap;
import android.util.SizeF;
import android.widget.RemoteViews;

import java.util.ArrayList;
import java.util.List;

import org.json.JSONObject;

/**
 * The Uposatha home-screen widget: three layers (Uposatha + kala, Day and night, Month) at three sizes, each a picture drawn by
 * WidgetRenderer from the data the app keeps in SharedPreferences (DgWidgetPlugin). This class puts the picture on the screen,
 * wires the taps, and plans the next redraw. It never computes the moon, the sun or an Uposatha.
 *
 * Taps: the dots strip cycles the layer of THIS widget (a broadcast; the app does not open); anything else opens the app on the
 * layer's tab (home / parts / cal); in the month layer (medium, large) each day number opens the calendar on that day.
 */
public class WidgetProvider extends AppWidgetProvider {
    static final String PREFS = "dg_widget", KEY_DATA = "data";
    static final String ACTION_CYCLE = "gift.dhamma.uposatha.widget.CYCLE";
    static final String ACTION_TICK = "gift.dhamma.uposatha.widget.TICK";
    private static final String[] TAB = { "home", "parts", "cal" };
    private static final int[] LAYOUT = { R.layout.widget_s, R.layout.widget_m, R.layout.widget_l };

    // The picture of the month grid is a 6 x 7 set of tap targets (res/layout/widget_grid_*.xml); ids by row and column.
    private static final int[][] CELL = {
            { R.id.c00, R.id.c01, R.id.c02, R.id.c03, R.id.c04, R.id.c05, R.id.c06 },
            { R.id.c10, R.id.c11, R.id.c12, R.id.c13, R.id.c14, R.id.c15, R.id.c16 },
            { R.id.c20, R.id.c21, R.id.c22, R.id.c23, R.id.c24, R.id.c25, R.id.c26 },
            { R.id.c30, R.id.c31, R.id.c32, R.id.c33, R.id.c34, R.id.c35, R.id.c36 },
            { R.id.c40, R.id.c41, R.id.c42, R.id.c43, R.id.c44, R.id.c45, R.id.c46 },
            { R.id.c50, R.id.c51, R.id.c52, R.id.c53, R.id.c54, R.id.c55, R.id.c56 } };
    private static final int[] ROW = { R.id.r0, R.id.r1, R.id.r2, R.id.r3, R.id.r4, R.id.r5 };

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
                int dir = intent.getIntExtra("dir", 1) < 0 ? WidgetRenderer.LAYERS - 1 : 1;   // the left half goes back, the right half forward
                p.edit().putInt("layer_" + id, (p.getInt("layer_" + id, 0) + dir) % WidgetRenderer.LAYERS).apply();
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
     * of the current orientation. A picture drawn for another size than the one it is shown at is stretched (a Motorola launcher
     * reported sizes the old two-number way read wrongly: a squeezed moon), so the list is the source.
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
            int layer = model == null ? 0 : prefs(ctx).getInt("layer_" + id, 0) % WidgetRenderer.LAYERS;
            RemoteViews rv;
            if (android.os.Build.VERSION.SDK_INT >= 31 && sizes.size() > 1) {
                // One RemoteViews per size; the launcher shows the one that fits. A RemoteViews may carry only so many bitmap pixels
                // (about 1.5 screens): each size gets its share of it (two pictures, light and dark, per size).
                ArrayMap<SizeF, RemoteViews> map = new ArrayMap<>();
                for (int[] sz : sizes) map.put(new SizeF(sz[0], sz[1]), build(ctx, id, sz[0], sz[1], sizes.size(), data, model, layer, now));
                rv = new RemoteViews(map);
            } else {
                int[] sz = sizes.get(0);
                rv = build(ctx, id, sz[0], sz[1], 1, data, model, layer, now);
            }
            mgr.updateAppWidget(id, rv);
        } catch (RuntimeException e) {
            android.util.Log.w("DgWidget", "update failed: " + e);
        }
    }

    /** The widget for one size: the layout of its class, both pictures, the taps. */
    private static RemoteViews build(Context ctx, int id, int wDp, int hDp, int shares, JSONObject data, WidgetModel model, int layer, long now) {
        int cls = WidgetRenderer.sizeClass(wDp, hDp);
        RemoteViews rv = new RemoteViews(ctx.getPackageName(), LAYOUT[cls]);
        // Both themes are drawn; the layout (res/layout and res/layout-night) shows the one that matches the launcher's theme,
        // so a switch of the system theme needs no redraw.
        float scale = WidgetRenderer.scaleFor(ctx, wDp, hDp, 3.2e6f / (2 * shares));
        Bitmap light = WidgetRenderer.render(ctx, data, layer, wDp, hDp, false, now, scale);
        Bitmap dark = WidgetRenderer.render(ctx, data, layer, wDp, hDp, true, now, scale);
        rv.setImageViewBitmap(R.id.w_img_light, light);
        rv.setImageViewBitmap(R.id.w_img_dark, dark);

        rv.setOnClickPendingIntent(R.id.w_tap, openApp(ctx, id, 0, route(model == null ? 0 : layer, null)));
        if (model != null) {
            rv.setViewVisibility(R.id.w_dots, android.view.View.VISIBLE);
            rv.setOnClickPendingIntent(R.id.w_dots_prev, cycle(ctx, id, -1));
            rv.setOnClickPendingIntent(R.id.w_dots_next, cycle(ctx, id, 1));
        } else {
            rv.setViewVisibility(R.id.w_dots, android.view.View.GONE);   // nothing to cycle: a tap anywhere opens the app
        }
        boolean month = model != null && layer == 2 && cls != WidgetRenderer.SMALL;
        if (cls != WidgetRenderer.SMALL) {
            rv.setViewVisibility(R.id.w_grid, month ? android.view.View.VISIBLE : android.view.View.GONE);
            if (month) wireGrid(ctx, rv, id, model, cls, wDp, hDp);
        }
        return rv;
    }

    /** Each day number of the month grid is its own target; empty cells open the calendar like the rest of the layer. */
    private static void wireGrid(Context ctx, RemoteViews rv, int id, WidgetModel m, int cls, int wDp, int hDp) {
        int[] mo = WidgetModel.month(m.today, m.weekStart);   // year, month, offset, days, rows
        // The grid's padding from the picture's own geometry: left, top (+ header), right, and what is left under the rows.
        float[] g = WidgetRenderer.monthGeo(ctx, cls, wDp, hDp, mo[4]);
        float dens = ctx.getResources().getDisplayMetrics().density;
        rv.setViewPadding(R.id.w_grid, Math.round(g[0] * dens), Math.round((g[1] + g[3]) * dens), Math.round(g[2] * dens),
                Math.max(0, Math.round((hDp - g[1] - g[3] - mo[4] * g[4]) * dens)));
        PendingIntent rest = openApp(ctx, id, 2, route(2, null));
        for (int r = 0; r < 6; r++) {
            rv.setViewVisibility(ROW[r], r < mo[4] ? android.view.View.VISIBLE : android.view.View.GONE);
            for (int c = 0; c < 7; c++) {
                int d = r * 7 + c - mo[2] + 1;
                if (d < 1 || d > mo[3]) rv.setOnClickPendingIntent(CELL[r][c], rest);
                else rv.setOnClickPendingIntent(CELL[r][c], openApp(ctx, id, 3 + d, route(2, WidgetModel.ymd(mo[0], mo[1], d))));
            }
        }
    }

    static String route(int layer, String day) {
        return "/uposatha-calendar?app=1&tab=" + TAB[layer] + (day != null ? "&day=" + day : "") + (layer == 0 ? "&moon=1" : "");   // a tap on the first layer lands on the moon, which plays its cycle once
    }

    private static PendingIntent openApp(Context ctx, int widgetId, int slot, String route) {
        Intent i = new Intent(ctx, MainActivity.class);
        i.setAction("gift.dhamma.uposatha.WIDGET");
        i.putExtra("route", route);
        i.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        // The intents differ only in an extra, which PendingIntent ignores: the request code tells them apart.
        return PendingIntent.getActivity(ctx, widgetId * 64 + slot, i, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    private static PendingIntent cycle(Context ctx, int id, int dir) {
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
