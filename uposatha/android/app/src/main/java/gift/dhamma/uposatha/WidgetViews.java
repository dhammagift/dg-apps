package gift.dhamma.uposatha;

import android.app.PendingIntent;
import android.content.Context;
import android.graphics.Bitmap;
import android.os.Build;
import android.util.TypedValue;
import android.view.View;
import android.widget.RemoteViews;

import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Builds the Uposatha widget as REAL views: one layout per layer x size class (res/layout/w_l{1,2,3}_{s,m,l}.xml), TextViews,
 * LinearLayout weights, ProgressBars for the day bar, the moon the only picture. The launcher reflows all of it to any size by itself;
 * nothing is a picture of text, so nothing is stretched or squeezed while a resize waits for the next update.
 *
 * What is decided here is only WHAT is shown for the height the launcher reports (which lines and rows exist, the counter's size); the
 * geometry is weights. Colours are resources (values-night): the launcher's theme switch recolours the widget without a redraw
 * (API 31+: RemoteViews.setColor with a resource; older: the colour of the moment, until the next update).
 * Nothing here computes the moon, the sun or an Uposatha: WidgetModel lays out what the page handed over.
 */
final class WidgetViews {
    static final int SMALL = WidgetPlan.SMALL, MEDIUM = WidgetPlan.MEDIUM, LARGE = WidgetPlan.LARGE, LAYERS = WidgetPlan.LAYERS;

    private static final int[][] LAYOUT = {
            { R.layout.w_l1_s, R.layout.w_l1_m, R.layout.w_l1_l },
            { R.layout.w_l2_s, R.layout.w_l2_m, R.layout.w_l2_l },
            { R.layout.w_l3_s, R.layout.w_l3_m, R.layout.w_l3_l } };
    private static final String[] TAB = { "home", "parts", "cal" };
    private static final int[] BAR = { R.id.bar0, R.id.bar1, R.id.bar2, R.id.bar3, R.id.bar4, R.id.bar5 };
    private static final int[] BARC = { R.id.barc0, R.id.barc1, R.id.barc2, R.id.barc3, R.id.barc4, R.id.barc5 };
    private static final int[] DOT = { R.id.w_dot0, R.id.w_dot1, R.id.w_dot2 };
    private static final int[] WD = { R.id.wd0, R.id.wd1, R.id.wd2, R.id.wd3, R.id.wd4, R.id.wd5, R.id.wd6 };
    private static final int[] TK = { R.id.tk0, R.id.tk1, R.id.tk2, R.id.tk3 };
    private static final int[] CELL = { R.id.c0, R.id.c1, R.id.c2, R.id.c3, R.id.c4, R.id.c5, R.id.c6 };
    private static final int[] CT = { R.id.t0, R.id.t1, R.id.t2, R.id.t3, R.id.t4, R.id.t5, R.id.t6 };
    private static final int[] CB = { R.id.b0, R.id.b1, R.id.b2, R.id.b3, R.id.b4, R.id.b5, R.id.b6 };

    /** Bytes of the moon pictures handed to RemoteViews since the counter was last read (the launcher refuses an update that carries too much). */
    static long bitmapBytes;

    private final Context ctx;
    private final RemoteViews rv;
    private final int widgetId, cls, wDp, hDp, layer;
    private WidgetModel m;
    private WidgetText tx;

    private WidgetViews(Context ctx, RemoteViews rv, int widgetId, int wDp, int hDp, int layer) {
        this.ctx = ctx; this.rv = rv; this.widgetId = widgetId; this.wDp = wDp; this.hDp = hDp; this.layer = layer;
        this.cls = WidgetPlan.sizeClass(wDp, hDp);
    }

    /** The widget for one size and layer; data == null, stale or not covering today: the placeholder. A failure falls back to the placeholder too. */
    static RemoteViews build(Context ctx, int widgetId, int wDp, int hDp, JSONObject data, long now, int layer) {
        layer = ((layer % LAYERS) + LAYERS) % LAYERS;
        WidgetModel model = WidgetModel.parse(data, now);
        int cls = WidgetPlan.sizeClass(wDp, hDp);
        if (model != null) {
            try {
                WidgetViews v = new WidgetViews(ctx, new RemoteViews(ctx.getPackageName(), LAYOUT[layer][cls]), widgetId, wDp, hDp, layer);
                v.m = model;
                v.tx = new WidgetText(ctx, model.lang);
                if (v.fill()) return v.rv;
            } catch (RuntimeException e) {
                android.util.Log.w("DgWidget", "layout failed, placeholder instead: " + e);
            }
        }
        WidgetViews v = new WidgetViews(ctx, new RemoteViews(ctx.getPackageName(), cls == SMALL ? R.layout.w_ph_s : R.layout.w_ph_h), widgetId, wDp, hDp, 0);
        v.placeholder(data);
        return v.rv;
    }

    // ------------------------------------------------------------------ small helpers

    private void text(int id, CharSequence s) { rv.setTextViewText(id, s); }
    private void show(int id, boolean on) { rv.setViewVisibility(id, on ? View.VISIBLE : View.GONE); }
    private void size(int id, float dp) { size(rv, id, dp); }
    private static void size(RemoteViews r, int id, float dp) { r.setTextViewTextSize(id, TypedValue.COMPLEX_UNIT_DIP, dp); }

    /** A text colour from a resource: from API 31 the launcher resolves it itself (so the theme switch recolours it), before that it is the colour of now. */
    private static void color(Context ctx, RemoteViews r, int id, int colorRes) {
        if (Build.VERSION.SDK_INT >= 31) r.setColor(id, "setTextColor", colorRes);
        else r.setTextColor(id, ctx.getColor(colorRes));
    }
    private void color(int id, int colorRes) { color(ctx, rv, id, colorRes); }

    private int px(float dp) { return Math.round(dp * ctx.getResources().getDisplayMetrics().density); }

    /** A moon in both themes into the pair of ImageViews id_l / id_d (the layout shows the one that fits the theme). */
    private void moon(RemoteViews r, int idL, int idD, int sizeDp, double phase, boolean south) {
        Bitmap l = WidgetMoon.render(ctx, sizeDp, phase, south, false), d = WidgetMoon.render(ctx, sizeDp, phase, south, true);
        bitmapBytes += l.getByteCount() + d.getByteCount();
        r.setImageViewBitmap(idL, l);
        r.setImageViewBitmap(idD, d);
    }

    private boolean shortMedium() { return cls == MEDIUM && hDp < 150; }
    /** A short card (a low 2x2 or 4x2): the strip sits lower and the content gets the room. */
    private boolean lowDots() { return shortMedium() || (cls == SMALL && hDp < 130); }
    /** The height the content has: the card without its paddings and the strip. */
    private float avail() { return hDp - (cls == LARGE ? 18 : cls == MEDIUM ? 14 : 13) - (lowDots() ? 17 : cls == LARGE ? 30 : 26); }

    // ------------------------------------------------------------------ texts of the data (the words of the design)

    private String wd(String ymd) { return tx.weekday(WidgetFormat.dow(WidgetFormat.year(ymd), WidgetFormat.month(ymd), WidgetFormat.day(ymd))); }
    private String dayLabel(String ymd) { return wd(ymd) + " " + WidgetFormat.day(ymd); }
    private String dateLabel(String ymd) { return dayLabel(ymd) + " " + tx.monthShort(WidgetFormat.month(ymd)); }
    private String ordinal(int n) { return tx.ru() ? n + "-й" : n + "th"; }
    private String phase(WidgetModel.Upo u) { return tx.get("phase." + u.phaseName); }
    private String untilTime(String hm) { return tx.get("lite.until").replace("{endDay}, ", "").replace("{endTime}", hm); }
    private String caps(String s) { return s.toUpperCase(tx.ru() ? new Locale("ru") : Locale.US); }
    private String dayWord() { return tx.ru() ? "день" : "day"; }

    /** "через 8 д" / "in 8 d" for a later Uposatha. */
    private String inText(WidgetModel.Upo n) {
        long rem = n.start.ms - m.now, days = rem / WidgetFormat.DAY;
        if (days >= 1) return tx.fmt("inDays", "n", days);
        String in = tx.get("inDays");
        return in.substring(0, in.indexOf("{n}")) + WidgetFormat.counter(rem, tx.get("unit.d"), tx.get("unit.h"));   // under a day: "через 2 ч", not "через 0 д"
    }

    // ------------------------------------------------------------------ the frame: taps, dots

    private boolean fill() {
        rv.setContentDescription(R.id.w_root, ctx.getString(R.string.widget_cd));
        rv.setOnClickPendingIntent(R.id.w_root, WidgetProvider.openApp(ctx, widgetId, 0, WidgetProvider.route(layer, null)));
        rv.setOnClickPendingIntent(R.id.w_dots_prev, WidgetProvider.cycle(ctx, widgetId, -1));
        rv.setOnClickPendingIntent(R.id.w_dots_next, WidgetProvider.cycle(ctx, widgetId, 1));
        for (int i = 0; i < 3; i++) rv.setInt(DOT[i], "setBackgroundResource", i == layer ? R.drawable.w_dot_on : R.drawable.w_dot_off);
        rv.setViewPadding(R.id.w_dots_vis, 0, 0, 0, px(cls == LARGE ? 13 : lowDots() ? 2 : cls == MEDIUM ? 11 : 10));
        if (lowDots()) rv.setViewPadding(R.id.w_content, px(cls == MEDIUM ? 16 : 14), px(cls == MEDIUM ? 14 : 13), px(cls == MEDIUM ? 16 : 14), px(17));
        if (layer == 0) { layer1(); return true; }
        if (layer == 1) return layer2();
        layer3();
        return true;
    }

    // ------------------------------------------------------------------ kala line, counter

    /** "Kala until 12:41 · 1 h 34 min left": the word and the time in the accent (green; vikala red), the rest in the text colours. */
    private void kalaLine(float sizeDp, String extra) {
        boolean vik = m.kala == WidgetModel.VIKALA;
        String tpl = tx.get(vik ? "vikala" : "kala");
        int at = tpl.indexOf("{time}");
        String head = at >= 0 ? tpl.substring(0, at) : tpl;
        int sp = head.indexOf(' ');
        String word = sp > 0 ? head.substring(0, sp) : head, mid = sp > 0 ? head.substring(sp) : "";
        int accent = vik ? R.color.w_vik : R.color.w_accent_ink;
        text(R.id.k_word, word); text(R.id.k_mid, mid); text(R.id.k_time, m.kalaEndHm); text(R.id.k_extra, extra);
        color(R.id.k_word, accent); color(R.id.k_time, accent);
        for (int id : new int[] { R.id.k_word, R.id.k_mid, R.id.k_time, R.id.k_extra }) size(id, sizeDp);
        show(R.id.k_extra, !extra.isEmpty());
        show(R.id.kala, true);
    }

    private String kalaExtra(boolean withLeft) {
        boolean vik = m.kala == WidgetModel.VIKALA;
        if (!m.placeSet && !vik) return " · " + tx.get("byClock");
        if (withLeft && !vik) return " · " + tx.fmt("kalaLeft", "left", WidgetFormat.left(m.kalaEndMs - m.now, tx.get("unit.h"), tx.unitMin()));
        return "";
    }

    private void counter(long rem, float bigDp) {
        long[] dh = WidgetPlan.counter(rem);
        text(R.id.c_dn, String.valueOf(dh[0])); text(R.id.c_du, tx.get("unit.d"));
        text(R.id.c_hn, String.valueOf(dh[1])); text(R.id.c_hu, tx.get("unit.h"));
        size(R.id.c_dn, bigDp); size(R.id.c_hn, bigDp);
        show(R.id.c_dn, dh[0] > 0); show(R.id.c_du, dh[0] > 0);
    }

    // ================================================================== layer 1: Uposatha + kala

    private void layer1() {
        WidgetModel.Upo u = m.cur();
        long rem = m.counterTarget() - m.now;
        boolean kalaOn = m.showKala && m.kala != WidgetModel.NONE;
        String to = m.ongoing ? tx.fmt("toNow", "n", u.lunarDay) : tx.fmt("to", "n", u.lunarDay);
        String lbl = tx.get(m.ongoing ? "layer.uposathaNow" : "layer.uposatha");
        String l1, l2 = null;   // the detail lines
        String startDay = dayLabel(u.start.ymd), endDay = dayLabel(u.end.ymd);
        if (m.detail) {
            l1 = tx.fmt("detail.phase", "phase", phase(u), "n", u.lunarDay);
            if (!m.placeSet) l2 = tx.get("noPlace.assumed");
            else if (m.ongoing) {
                l2 = tx.fmt("detail.endNow", "endDay", endDay, "endTime", u.end.hm);
                if (WidgetFormat.minutes(u.end.hm) >= 12 * 60) l2 = l2.replace("рассвет ", "").replace("dawn ", "");   // the page's end is an evening here, not a dawn
            } else l2 = tx.fmt("detail.span", "startDay", startDay, "startTime", u.start.hm, "endDay", endDay, "endTime", u.end.hm);
        } else if (m.ongoing) {
            l1 = tx.fmt("lite.until", "endDay", endDay, "endTime", u.end.hm);
        } else {
            l1 = tx.fmt("lite.from", "startDay", startDay, "startTime", u.start.hm);
            if (!m.placeSet) l1 += " · " + tx.get("noPlace.short");
        }
        text(R.id.lbl, caps(lbl));
        text(R.id.to, to);
        show(R.id.kala, false);
        if (cls == SMALL) {
            String sub;
            String startWd = wd(u.start.ymd), endWd = wd(u.end.ymd);
            if (m.ongoing) {
                sub = m.detail ? phase(u) + " · " + untilTime(u.end.hm)
                        : tx.get("lite.until").replace("{endDay}", endWd).replace("{endTime}", u.end.hm).replace(", ", " ");
            } else {
                sub = m.detail ? phase(u) + " · " + startWd + " " + u.start.hm
                        : tx.get("lite.from").replace("{startDay}", startWd).replace("{startTime}", u.start.hm).replace(", ", " ");
            }
            // A low 2x2 (the launcher's own cell is ~110 dp): lines go in this order - kala, the second line, "to the Nth day" - before the counter shrinks.
            float av = avail(), big = hDp >= 240 ? (kalaOn ? 46 : 52) : kalaOn ? 34 : 40;   // a tall narrow widget gets a bigger counter
            boolean kalaShow = kalaOn, subShow = true, toShow = true;
            if (28 + 15 + 15 + 1.2f * big + (kalaShow ? 22 : 0) > av) kalaShow = false;
            if (28 + 15 + 15 + 1.2f * big + (kalaShow ? 22 : 0) > av) subShow = false;
            if (28 + 15 + 1.2f * big > av) toShow = false;
            big = Math.max(24, Math.min(big, (av - 28 - (toShow ? 15 : 0)) / 1.2f));
            text(R.id.sub, sub); show(R.id.sub, subShow);
            show(R.id.to, toShow);
            counter(rem, big);
            if (kalaShow) kalaLine(12, "");
            moon(rv, R.id.moon_l, R.id.moon_d, 28, u.nominal(), m.south);
            return;
        }
        if (cls == MEDIUM) {
            text(R.id.dateh, "· " + dateLabel(u.start.ymd));
            // A short widget (4x2 is often ~130 dp, the design has 170): drop the second detail line, then the first, then "to the Nth day"
            // and the kala line, before the counter shrinks below 24.
            float av = avail(), big = kalaOn ? 38 : 44;
            boolean show2 = l2 != null, show1 = true, showTo = true, showKala = kalaOn;
            if (14 + 18 + 1.2f * big + 17.6f + 16 + (showKala ? 19.6f : 0) > av) show2 = false;
            if (14 + 18 + 1.2f * big + 17.6f + (showKala ? 19.6f : 0) > av) show1 = false;
            if (14 + 18 + 1.2f * Math.min(big, 30) + (showKala ? 19.6f : 0) > av) showTo = false;
            if (14 + 1.2f * Math.min(big, 30) + (showKala ? 19.6f : 0) > av) showKala = false;
            big = Math.max(24, Math.min(big, (av - 14 - (showTo ? 18 : 0) - (show1 ? 17.6f : 0) - (showKala ? 19.6f : 0)) / 1.2f));
            counter(rem, big);
            show(R.id.to, showTo);
            text(R.id.l1, l1); show(R.id.l1, show1);
            text(R.id.l2, l2 == null ? "" : l2); show(R.id.l2, show2);
            if (showKala) kalaLine(13, kalaExtra(true));
            moon(rv, R.id.moon_l, R.id.moon_d, 96, m.moonNow, m.south);   // the moon as it is now
            return;
        }
        // large
        boolean tight = hDp < 340;   // the design has 382 dp; a 4x4 can be a good deal less
        if (tight) l2 = null;
        text(R.id.mode, tx.get(m.bySuttas ? "mode.bySuttas" : "mode.notBySuttas"));
        float big = (kalaOn ? 54 : 58) - (tight ? 8 : 0);
        counter(rem, big);
        text(R.id.l1, l1);
        text(R.id.l2, l2 == null ? "" : l2); show(R.id.l2, l2 != null);
        if (kalaOn) kalaLine(15, kalaExtra(true));
        moon(rv, R.id.moon_l, R.id.moon_d, 112, m.moonNow, m.south);   // the moon as it is now
        text(R.id.next, caps(tx.get("next")));
        float colH = 19 + 1.2f * big + 4 + 18 + (l2 != null ? 3 + 16 : 0);
        float used = 18 + 16 + 8 + Math.max(colH, 100) + (kalaOn ? 10 + 18 : 0) + 2 * (tight ? 8 : 12) + 1 + 16 + 8 + 30;
        int rows = WidgetPlan.rowsThatFit(hDp - used, 33, 6);   // a tall widget lists more of the next ones
        boolean any = rows > 0;
        show(R.id.next, any); show(R.id.list, any); show(R.id.div, any);
        rv.removeAllViews(R.id.list);
        for (WidgetModel.Upo n : m.following(rows)) {
            RemoteViews row = new RemoteViews(ctx.getPackageName(), R.layout.w_row_next);
            moon(row, R.id.r_moon_l, R.id.r_moon_d, 32, n.nominal(), m.south);
            row.setTextViewText(R.id.r_date, dateLabel(n.start.ymd));   // the date it BEGINS on (the evening), as the app's own lists say
            row.setTextViewText(R.id.r_day, ordinal(n.lunarDay) + (m.detail && wDp >= 340 ? " " + dayWord() : ""));
            row.setTextViewText(R.id.r_in, inText(n));
            rv.addView(R.id.list, row);
        }
    }

    // ================================================================== layer 2: day and night

    private boolean layer2() {
        if (m.partIdx < 0 || m.kala == WidgetModel.NONE) return false;   // the parts are not known right now (just before the first dawn): the placeholder
        WidgetModel.Day d = m.days.get(m.partDay);
        int k = m.partIdx;
        String pn = tx.get("part." + d.partName[k]);
        int dot = pn.indexOf(" · ");
        String name = dot > 0 ? pn.substring(0, dot) : pn;
        String desc = dot > 0 ? pn.substring(dot + 3) : null;
        if (desc != null && tx.ru() && "majjhanhika".equals(d.partName[k])) desc += " дня";
        String sub = (desc != null ? desc + " · " : "") + untilTime(d.partTo[k]);
        String leftLine = tx.fmt("kalaLeft", "left", WidgetFormat.left(m.kalaEndMs - m.now, tx.get("unit.h"), tx.unitMin()));
        text(R.id.lbl, caps(tx.get("layer.daynight")));
        text(R.id.name, name);
        boolean ticks = true, subShow = true;
        if (cls == SMALL) {
            float av = avail();   // a low 2x2: the ticks go first, then the second line
            ticks = av >= 112; subShow = av >= 98;
            text(R.id.sub, untilTime(d.partTo[k])); show(R.id.sub, subShow);
            kalaLine(12.5f, "");
        } else {
            float av = avail();
            ticks = av >= 88 || cls == LARGE;
            show(R.id.sub, av >= 73);
            text(R.id.sub, sub);
            text(R.id.date, cls == LARGE ? dateLabel(m.today) : tx.get("now"));
            text(R.id.left, leftLine);
            kalaLine(cls == LARGE ? 15 : 13, "");
        }
        // the bar
        int[] ends = WidgetPlan.barEnds(d.partStart, d.partEnd);
        for (int i = 0; i < 6; i++) {
            rv.setProgressBar(BAR[i], 1000, ends[i], false);
            rv.setProgressBar(BARC[i], 1000, ends[i], false);
            show(BAR[i], i != k); show(BARC[i], i == k);
        }
        rv.setProgressBar(R.id.bar_now, 1000, WidgetPlan.nowMark(m.now, d.partStart[0], d.partEnd[5]), false);
        show(R.id.tk0, ticks); show(R.id.tk1, ticks);
        if (cls != SMALL) { show(R.id.tk2, ticks); show(R.id.tk3, ticks); }
        if (cls == SMALL) {
            text(TK[0], d.partFrom[0]); text(TK[1], d.sunset.hm);
        } else {
            boolean words = wDp >= 330;   // a narrower widget keeps the times only
            text(TK[0], d.partFrom[0] + (words ? " " + tx.get("sunrise") : "")); text(TK[1], d.noon.hm + (words ? " " + tx.get("noon") : ""));
            text(TK[2], d.sunset.hm + (words ? " " + tx.get("sunset") : "")); text(TK[3], d.partTo[5]);
        }
        if (cls == LARGE) partsList(d, k);
        return true;
    }

    /** The six parts with their borders; when the widget is not tall enough, the three of the current half (day or night). */
    private void partsList(WidgetModel.Day d, int cur) {
        float used = 18 + 16 + 8 + 61 + 10 + 16 + 16 + 10 + 30;
        float avail = hDp - used;
        boolean all = avail >= 6 * 28 + 9;
        int n = all ? 6 : Math.max(1, WidgetPlan.rowsThatFit(avail, 26, 3));
        int from = all ? 0 : cur < 3 ? 0 : 3;
        if (!all && cur >= from + n) from = cur - n + 1;   // the current one is always among the rows
        rv.removeAllViews(R.id.list);
        for (int k = from; k < from + n; k++) {
            RemoteViews row = new RemoteViews(ctx.getPackageName(), k == cur ? R.layout.w_row_part_cur : R.layout.w_row_part);
            row.setTextViewText(R.id.p_name, tx.get("part." + d.partName[k]));
            row.setTextViewText(R.id.p_times, d.partFrom[k] + "–" + d.partTo[k]);
            rv.addView(R.id.list, row);
            if (all && k == 2) rv.addView(R.id.list, new RemoteViews(ctx.getPackageName(), R.layout.w_row_div));
        }
    }

    // ================================================================== layer 3: month

    private void layer3() {
        int[] mo = WidgetModel.month(m.today, m.weekStart);   // year, month, offset, days, rows
        String monthName = tx.monthName(mo[1]);
        for (int i = 0; i < 7; i++) {
            String s = tx.weekday(m.weekStart == 0 ? (i + 6) % 7 : i);
            text(WD[i], tx.ru() ? s : s.substring(0, 2));
        }
        rv.removeAllViews(R.id.grid);
        if (cls == SMALL) {
            text(R.id.lbl, caps(monthName));
            float av = avail();
            boolean tall = hDp >= 200;
            if (tall) {   // a tall narrow widget: the whole month, taller rows
                for (String[] w : monthWeeks(mo)) rv.addView(R.id.grid, monthRow(R.layout.w_row_month_st, w, true, 0));
            } else {
                // two weeks (one, when low): the one with today and the next, whatever month they fall in
                int off = WidgetModel.column(WidgetFormat.dow(WidgetFormat.year(m.today), WidgetFormat.month(m.today), WidgetFormat.day(m.today)), m.weekStart);
                long start = WidgetFormat.daysFromCivil(WidgetFormat.year(m.today), WidgetFormat.month(m.today), WidgetFormat.day(m.today)) - off;
                for (int r = 0; r < (av >= 74 ? 2 : 1); r++) {
                    String[] week = new String[7];
                    for (int c = 0; c < 7; c++) week[c] = WidgetFormat.ymdFromDays(start + r * 7 + c);
                    rv.addView(R.id.grid, monthRow(R.layout.w_row_month_s, week, false, 0));
                }
            }
            WidgetModel.Upo u = m.cur();
            text(R.id.sline, wd(u.start.ymd) + " " + WidgetFormat.day(u.start.ymd) + " · " + ordinal(u.lunarDay) + " " + dayWord());
            show(R.id.sline, tall || av >= 93);
            return;
        }
        String[][] weeks = monthWeeks(mo);
        boolean big = cls == LARGE;
        rv.removeAllViews(R.id.list);
        if (!big) {
            text(R.id.lbl, caps(monthName));
            float avail = hDp - 14 - (shortMedium() ? 17 : 26) - 24;
            int n = Math.max(1, WidgetPlan.rowsThatFit(avail, 26, 3));
            for (WidgetModel.Upo u : m.upos.subList(m.curIdx, Math.min(m.upos.size(), m.curIdx + n))) {
                RemoteViews row = new RemoteViews(ctx.getPackageName(), R.layout.w_row_upo_s);
                moon(row, R.id.r_moon_l, R.id.r_moon_d, 28, u.nominal(), m.south);
                row.setTextViewText(R.id.r_date, dayLabel(u.start.ymd));
                row.setTextViewText(R.id.r_day, ordinal(u.lunarDay));
                rv.addView(R.id.list, row);
            }
            // a low 4x2 (6 weeks in ~70 dp): the numbers get smaller before the rows overlap
            float rowH = (avail() - 12) / mo[4];
            float tdp = rowH < 17 ? Math.max(9.5f, rowH * 0.75f) : 0;
            for (String[] w : weeks) rv.addView(R.id.grid, monthRow(R.layout.w_row_month_m, w, true, tdp));
            return;
        }
        text(R.id.lbl, caps(monthName + " " + mo[0]));
        int cnt = 0;
        for (WidgetModel.Upo u : m.upos) if (u.day.startsWith(String.format(Locale.US, "%04d-%02d", mo[0], mo[1]))) cnt++;
        text(R.id.count, WidgetFormat.uposathas(tx.lang, cnt));
        for (String[] w : weeks) rv.addView(R.id.grid, monthRow(R.layout.w_row_month_l, w, true, 0));
        // Under the grid, as far as the height goes: the Uposathas that are on and next, then today (sun, moon). The grid keeps 30 dp a week.
        float lowerAvail = hDp - (18 + 16 + 24 + 30) - mo[4] * 30;
        float room = lowerAvail - 9;
        boolean lower = room >= 28;
        boolean today = room >= 118;
        show(R.id.lower, lower);
        show(R.id.today, today);
        if (!lower) return;
        int rowsN = (int) Math.max(1, Math.min(4, (room - (today ? 72 : 0)) / 28));
        List<WidgetModel.Upo> list = new ArrayList<>();
        list.add(m.cur());
        list.addAll(m.following(rowsN - 1));
        for (int i = 0; i < list.size(); i++) {
            WidgetModel.Upo u = list.get(i);
            RemoteViews row = new RemoteViews(ctx.getPackageName(), R.layout.w_row_upo);
            moon(row, R.id.r_moon_l, R.id.r_moon_d, 28, u.nominal(), m.south);
            row.setTextViewText(R.id.r_date, dateLabel(u.start.ymd));
            row.setTextViewText(R.id.r_em, ordinal(u.lunarDay) + (wDp >= 340 ? " · " + phase(u) : ""));
            row.setTextViewText(R.id.r_in, i == 0 && m.ongoing ? tx.get("now") : inText(u));
            rv.addView(R.id.list, row);
        }
        if (today) {
            WidgetModel.Day d = m.dayIdx >= 0 ? m.days.get(m.dayIdx) : null;
            double lit = (1 - Math.cos(2 * Math.PI * m.moonNow)) / 2;
            boolean waxing = m.moonNow < 0.5;
            String ph = tx.ru() ? (waxing ? "растёт" : "убывает") : (waxing ? "waxing" : "waning");
            String lt = tx.ru() ? "освещено" : "lit";
            text(R.id.tlbl, tx.ru() ? "СЕГОДНЯ" : "TODAY");
            if (d != null) text(R.id.tsun, tx.get("sunrise") + " " + d.sunrise.hm + "  ·  " + tx.get("noon") + " " + d.noon.hm + "  ·  " + tx.get("sunset") + " " + d.sunset.hm);
            show(R.id.tsun, d != null);
            text(R.id.tmoon, ph + " · " + Math.round(lit * 100) + "% " + lt);
        }
    }

    /** The weeks of the month as rows of 7 dates (null = a day of the neighbouring month). */
    private static String[][] monthWeeks(int[] mo) {
        String[][] weeks = new String[mo[4]][7];
        for (int r = 0; r < mo[4]; r++)
            for (int c = 0; c < 7; c++) {
                int dd = r * 7 + c - mo[2] + 1;
                weeks[r][c] = dd < 1 || dd > mo[3] ? null : WidgetModel.ymd(mo[0], mo[1], dd);
            }
        return weeks;
    }

    /** One week of the grid as its own RemoteViews (added to R.id.grid): the numbers, each a tap target to the calendar on that day. A null date is an empty cell. */
    private RemoteViews monthRow(int layout, String[] week, boolean clickable, float textDp) {
        RemoteViews row = new RemoteViews(ctx.getPackageName(), layout);
        for (int c = 0; c < 7; c++) {
            String ymd = week[c];
            if (ymd == null) { row.setViewVisibility(CT[c], View.GONE); row.setViewVisibility(CB[c], View.GONE); continue; }
            int day = WidgetFormat.day(ymd);
            boolean today = ymd.equals(m.today), past = ymd.compareTo(m.today) < 0;
            WidgetModel.Upo startOf = m.startingOn(ymd), dayOf = m.uposathaOn(ymd);
            int col = WidgetModel.column(WidgetFormat.dow(WidgetFormat.year(ymd), WidgetFormat.month(ymd), day), m.weekStart);   // 0 = the week's first day
            // The strip: an evening-start cell (solid) and the day after it (light) are one band; a cell is square on the side that joins
            // the next one, unless the row ends there. A date that is the day of one Uposatha and the start of the next (14th, 15th) is
            // joined on both sides.
            boolean joinRight = startOf != null && col < 6 && WidgetFormat.daysBetween(ymd, startOf.day) == 1;
            boolean joinLeft = dayOf != null && !dayOf.start.ymd.equals(dayOf.day) && col > 0 && WidgetFormat.daysBetween(dayOf.start.ymd, ymd) == 1;
            String fill = startOf != null ? "solid" : dayOf != null ? "band" : null;
            int textColor = fill == null ? (past ? R.color.w_muted : R.color.w_text) : startOf != null ? R.color.w_on_accent : R.color.w_accent_ink;
            int shown = fill != null || today ? CB[c] : CT[c], hidden = shown == CB[c] ? CT[c] : CB[c];
            row.setViewVisibility(hidden, View.GONE);
            row.setViewVisibility(shown, View.VISIBLE);
            row.setTextViewText(shown, String.valueOf(day));
            if (textDp > 0) size(row, shown, textDp);
            color(ctx, row, shown, textColor);
            int bg = cellRes(WidgetPlan.cellDrawable(fill, joinLeft, joinRight, today));
            if (bg != 0) row.setInt(shown, "setBackgroundResource", bg);
            if (clickable) row.setOnClickPendingIntent(CELL[c], WidgetProvider.openApp(ctx, widgetId, 3 + day, WidgetProvider.route(2, ymd)));
        }
        return row;
    }

    /** The drawable of a cell by name (explicit, so the resource shrinker of the release build sees every one of them used). */
    static int cellRes(String name) {
        if (name == null) return 0;
        switch (name) {
            case "w_cell_t": return R.drawable.w_cell_t;
            case "w_cell_solid_r": return R.drawable.w_cell_solid_r;
            case "w_cell_solid_sr": return R.drawable.w_cell_solid_sr;
            case "w_cell_solid_sl": return R.drawable.w_cell_solid_sl;
            case "w_cell_solid_s": return R.drawable.w_cell_solid_s;
            case "w_cell_band_r": return R.drawable.w_cell_band_r;
            case "w_cell_band_sl": return R.drawable.w_cell_band_sl;
            case "w_cell_solid_r_t": return R.drawable.w_cell_solid_r_t;
            case "w_cell_solid_sr_t": return R.drawable.w_cell_solid_sr_t;
            case "w_cell_solid_sl_t": return R.drawable.w_cell_solid_sl_t;
            case "w_cell_solid_s_t": return R.drawable.w_cell_solid_s_t;
            case "w_cell_band_r_t": return R.drawable.w_cell_band_r_t;
            case "w_cell_band_sl_t": return R.drawable.w_cell_band_sl_t;
            default: return 0;
        }
    }

    // ================================================================== placeholder

    private void placeholder(JSONObject data) {
        String lang = null;
        if (data != null) {
            JSONObject st = data.optJSONObject("settings");
            if (st != null) lang = st.optString("lang", null);
            if (lang == null) lang = "en";
        }
        if (lang == null) lang = Locale.getDefault().getLanguage();
        boolean ru = "ru".equals(lang);
        String title = ru ? "Откройте Uposatha" : "Open Uposatha";
        String body = data != null ? (ru ? "Данные устарели" : "The data is out of date") : (ru ? "Нужны данные для виджета" : "To set up the widget");
        rv.setContentDescription(R.id.w_root, ctx.getString(R.string.widget_cd));
        text(R.id.title, title);
        text(R.id.body, body);
        moon(rv, R.id.moon_l, R.id.moon_d, cls == SMALL ? 56 : 96, 0.5, false);
        rv.setOnClickPendingIntent(R.id.w_root, WidgetProvider.openApp(ctx, widgetId, 0, WidgetProvider.route(0, null)));
    }
}
