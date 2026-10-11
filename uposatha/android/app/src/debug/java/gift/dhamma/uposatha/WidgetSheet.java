package gift.dhamma.uposatha;

import android.content.Context;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.RemoteViews;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;

/**
 * DEBUG BUILDS ONLY: the REAL widget (WidgetViews.build -> RemoteViews) inflated with RemoteViews.apply into fixed-size frames, the
 * way a launcher does it, at any dp size and in the light or the dark theme (a configuration context, so the colours, drawables and
 * the moon pair resolve exactly as the launcher's night mode would). Shared by WidgetPreviewActivity (on screen), the androidTest
 * WidgetSheetTest (PNGs for Test Lab) and the local Robolectric render (widget/android-render). Any clipping or overflow shows here.
 */
final class WidgetSheet {
    private WidgetSheet() {}

    /** One picture of the sheet: a widget (WidgetPlan.MOON .. CAL) at a size in dp, a scenario, the widget's own settings. */
    static final class Case {
        final String name; final int kind, w, h, scenario, variant; final WidgetConfig cfg; int slide;
        Case(int kind, int w, int h, int scenario, String tag, WidgetConfig cfg, int variant) {
            this.kind = kind; this.w = w; this.h = h; this.scenario = scenario; this.cfg = cfg; this.variant = variant;
            this.slide = kind == WidgetPlan.CAL ? 2 : 0;   // where a big widget opens
            this.name = KIND[kind] + "-" + w + "x" + h + "-s" + scenario + (tag.isEmpty() ? "" : "-" + tag);
        }
    }

    static final String[] KIND = { "moon", "moonupo", "upo", "strip", "upom", "day", "cal" };
    /** Real cells (dp): a 5-column phone like the owner's (a cell 66 x 102), a Pixel (57 x 102 a cell), a Samsung (lower cells), and stretched ones. */
    private static final int[][][] SIZES = {
            { { 66, 102 }, { 57, 102 }, { 145, 215 } },
            { { 145, 102 }, { 130, 102 }, { 224, 215 } },
            { { 200, 200 }, { 180, 190 }, { 145, 215 }, { 155, 165 }, { 130, 220 }, { 224, 328 }, { 110, 110 } },
            { { 298, 102 }, { 276, 102 }, { 376, 102 } },
            { { 298, 215 }, { 376, 215 }, { 330, 150 }, { 276, 220 }, { 376, 328 } },
            { { 298, 215 }, { 376, 215 }, { 145, 215 }, { 180, 190 }, { 298, 441 } },
            { { 298, 441 }, { 376, 441 }, { 376, 556 }, { 298, 328 }, { 276, 456 } } };

    private static WidgetConfig cfg(int theme, int opacity, int details, int kala, int moons, boolean next) {
        WidgetConfig c = new WidgetConfig();
        c.theme = theme; c.opacity = opacity; c.details = details; c.kala = kala; c.moons = moons; c.next = next;
        return c;
    }

    private static WidgetConfig noSlides() { WidgetConfig c = new WidgetConfig(); c.slides = false; return c; }

    /** The whole sheet: every widget at its sizes in a few scenarios, then the widget's own settings (a forced theme, a translucent card, lines on and off). */
    static java.util.List<Case> cases() {
        java.util.List<Case> out = new java.util.ArrayList<>();
        WidgetConfig def = new WidgetConfig();
        for (int kind = 0; kind < SIZES.length; kind++) {
            for (int i = 0; i < SIZES[kind].length; i++) {
                int[] sz = SIZES[kind][i];
                int[] scs = i == 0 ? new int[] { 7, 5, 4, 2, 0, 6, 3 } : new int[] { 7, 4, 2 };   // the first size in every scenario, the rest in three
                for (int sc : scs) out.add(new Case(kind, sz[0], sz[1], sc, "", def, 0));
            }
            int[] sz = SIZES[kind][0];
            out.add(new Case(kind, sz[0], sz[1], 5, "dark55", cfg(WidgetConfig.DARK, 55, 0, 0, 0, true), 0));
            out.add(new Case(kind, sz[0], sz[1], 5, "light", cfg(WidgetConfig.LIGHT, 100, 0, 0, 0, true), 0));
            out.add(new Case(kind, sz[0], sz[1], 5, "nokala-nodet", cfg(0, 100, WidgetConfig.OFF, WidgetConfig.OFF, 0, true), 0));
            out.add(new Case(kind, sz[0], sz[1], 8, "nodata", def, 0));
            out.add(new Case(kind, sz[0], sz[1], 8, "stale", def, 1));
        }
        int[] c = SIZES[WidgetPlan.CAL][1];
        out.add(new Case(WidgetPlan.CAL, c[0], c[1], 5, "allmoons", cfg(0, 100, 0, 0, WidgetConfig.ON, true), 0));
        out.add(new Case(WidgetPlan.CAL, c[0], c[1], 5, "nonext", cfg(0, 100, 0, 0, 0, false), 0));
        for (int[] sz : new int[][] { { 298, 215 }, { 376, 215 }, { 376, 328 }, { 145, 215 } })   // the 4x2's other two slides
            for (int sl = 1; sl < 3; sl++) { Case x = new Case(WidgetPlan.UPO_M, sz[0], sz[1], sl == 1 ? 7 : 5, "slide" + sl, def, 0); x.slide = sl; out.add(x); }
        for (int sl = 0; sl < 3; sl++) { Case x = new Case(WidgetPlan.CAL, 362, 646, 5, "tall-slide" + sl, def, 0); x.slide = sl; out.add(x); }   // the owner's phone: 5 x 6 cells
        for (int[] sz : new int[][] { { 298, 441 }, { 376, 441 }, { 376, 556 } })   // the 4x4's other two slides
            for (int sl = 0; sl < 2; sl++) { Case x = new Case(WidgetPlan.CAL, sz[0], sz[1], sl == 1 ? 7 : sz[1] > 500 ? 2 : 5, "slide" + sl, def, 0); x.slide = sl; out.add(x); }
        // The owner's launcher by its own numbers (the size line of the settings screen, 2026-10-10): a cell is 78 x 75 dp, five columns on a
        // 408 dp screen - a row is far lower than the 102 dp of a Pixel, so every one-row widget is a low wide one there.
        int[][] own = { { 0, 78, 75 }, { 0, 78, 151 }, { 0, 156, 151 }, { 0, 313, 302 }, { 1, 156, 75 }, { 1, 235, 75 }, { 2, 156, 151 }, { 2, 235, 151 }, { 2, 156, 227 },
                { 3, 313, 75 }, { 3, 391, 75 }, { 3, 235, 75 }, { 4, 313, 151 }, { 4, 391, 151 }, { 4, 391, 227 }, { 5, 156, 151 }, { 5, 313, 151 }, { 5, 391, 151 },
                { 6, 313, 302 }, { 6, 391, 302 }, { 6, 391, 378 }, { 6, 391, 454 }, { 6, 391, 438 } };
        for (int[] o : own) for (int sc : new int[] { 5, 0 }) out.add(new Case(o[0], o[1], o[2], sc, "own", def, 0));
        // ... and what those cells may really be: a Motorola razr reports the cells of its other screen, the real ones are about 1.7 times
        // taller (WidgetPlan.TALLER; a 1 x 1 "82 x 68" was 82 x 115 on a razr plus 2024). The launcher takes one of these.
        int[][] real = { { 0, 78, 132 }, { 1, 156, 132 }, { 2, 156, 266 }, { 3, 313, 132 }, { 3, 391, 118 }, { 3, 391, 132 }, { 4, 313, 266 }, { 4, 391, 266 }, { 5, 156, 266 },
                { 6, 313, 532 }, { 6, 391, 713 }, { 6, 391, 799 } };
        for (int[] o : real) for (int sc : new int[] { 5, 0 }) out.add(new Case(o[0], o[1], o[2], sc, "real", def, 0));
        for (int[] o : new int[][] { { 0, 78, 75 }, { 0, 78, 151 }, { 0, 313, 302 } }) { WidgetConfig p = new WidgetConfig(); p.pct = true; out.add(new Case(o[0], o[1], o[2], 5, "own-pct", p, 0)); }
        for (int sl = 1; sl < 3; sl++) { Case x = new Case(WidgetPlan.CAL, 391, 454, 5, "own-slide" + sl, def, 0); x.slide = sl; out.add(x); }
        WidgetConfig pct = new WidgetConfig(); pct.pct = true;   // the Moon with its percent (a setting; just the moon is the default)
        for (int[] sz : SIZES[WidgetPlan.MOON]) out.add(new Case(WidgetPlan.MOON, sz[0], sz[1], 5, "pct", pct, 0));
        out.add(new Case(WidgetPlan.UPO_M, 298, 215, 5, "noslides", noSlides(), 0));
        out.add(new Case(WidgetPlan.CAL, 298, 441, 5, "noslides", noSlides(), 0));
        out.add(new Case(WidgetPlan.CAL, c[0], c[1], 5, "allmoons-dark", cfg(WidgetConfig.DARK, 100, WidgetConfig.ON, 0, WidgetConfig.ON, true), 0));
        return out;
    }

    static final class Scenario {
        final String name, file, lang, nowFrom; final long nowOffset;
        final boolean detail, showKala, placeSet, bySuttas, south;
        Scenario(String name, String file, String lang, String nowFrom, long nowOffset, boolean detail, boolean showKala, boolean placeSet, boolean bySuttas, boolean south) {
            this.name = name; this.file = file; this.lang = lang; this.nowFrom = nowFrom; this.nowOffset = nowOffset;
            this.detail = detail; this.showKala = showKala; this.placeSet = placeSet; this.bySuttas = bySuttas; this.south = south;
        }
    }

    private static final long H = 3600000L;
    static final Scenario[] SCENARIOS = {
            new Scenario("ru, as the page gave it (no place, lite), vikala", "widget-sample.json", "ru", "gen", 0, false, true, false, true, false),
            new Scenario("ru, kala in the morning, detail, place set", "widget-sample.json", "ru", "sunrise", 3 * H, true, true, true, true, false),
            new Scenario("ru, Uposatha is on, detail", "widget-sample.json", "ru", "upoStart", 5 * H, true, true, true, false, false),
            new Scenario("en, kala off, lite", "widget-sample-en.json", "en", "sunrise", 3 * H, false, false, true, true, false),
            new Scenario("en, detail, vikala, south", "widget-sample-en.json", "en", "gen", 0, true, true, true, true, true),
            new Scenario("en, kala in the morning, detail, place set (the designer's mockup)", "widget-sample-en.json", "en", "sunrise", 3 * H, true, true, true, true, false),
            new Scenario("the picker previews: a full moon, the 15th day on, in 28 d", "widget-preview-sample.json", "en", "sunrise", 51 * H, true, true, true, true, false),
            new Scenario("en, kala in the morning, lite (the 2x2 without details)", "widget-sample-en.json", "en", "sunrise", 3 * H, false, true, true, true, false),
            new Scenario("placeholders: no data, stale", null, "ru", "gen", 0, false, true, true, true, false),
    };

    static JSONObject sample(Context ctx, String file) throws Exception {
        try (InputStream in = ctx.getAssets().open(file)) {
            ByteArrayOutputStream bo = new ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) bo.write(buf, 0, n);
            return new JSONObject(bo.toString("UTF-8"));
        }
    }

    static JSONObject data(Context ctx, Scenario sc) throws Exception {
        JSONObject d = sample(ctx, sc.file != null ? sc.file : "widget-sample.json");
        d.getJSONObject("settings").put("lang", sc.lang).put("detail", sc.detail).put("showKala", sc.showKala).put("placeSet", sc.placeSet)
                .put("bySuttas", sc.bySuttas).put("south", sc.south);
        return d;
    }

    static long now(Scenario sc, JSONObject d) throws Exception {
        long base;
        switch (sc.nowFrom) {
            case "sunrise": base = d.getJSONArray("days").getJSONObject(0).getJSONObject("sunrise").getLong("ms"); break;
            case "upoStart": base = d.getJSONArray("uposathas").getJSONObject(1).getJSONObject("start").getLong("ms"); break;
            default: base = WidgetModel.parseIso(d.getString("generatedAt"));
        }
        return base + sc.nowOffset;
    }

    /** The widget of a case; the placeholders are the last scenario (variant 0: no data, 1: stale). */
    static RemoteViews views(Context ctx, Case c) throws Exception {
        Scenario sc = SCENARIOS[c.scenario];
        if (sc.file == null) {
            JSONObject d = c.variant == 0 ? null : sample(ctx, "widget-sample.json");
            long n = c.variant == 0 ? System.currentTimeMillis() : now(SCENARIOS[0], d) + 30L * 24 * H;
            return WidgetViews.build(ctx, 1, c.kind, c.w, c.h, d, n, c.cfg, 0, c.slide);
        }
        JSONObject d = data(ctx, sc);
        return WidgetViews.build(ctx, 1, c.kind, c.w, c.h, d, now(sc, d), c.cfg, 0, c.slide);
    }

    /** rv applied into a wDp x hDp frame in the given theme, laid out; call on the main thread. */
    static View inflate(Context ctx, RemoteViews rv, int wDp, int hDp, boolean dark) {
        Configuration cfg = new Configuration(ctx.getResources().getConfiguration());
        cfg.uiMode = (cfg.uiMode & ~Configuration.UI_MODE_NIGHT_MASK) | (dark ? Configuration.UI_MODE_NIGHT_YES : Configuration.UI_MODE_NIGHT_NO);
        Context c = ctx.createConfigurationContext(cfg);
        float d = c.getResources().getDisplayMetrics().density;
        int wPx = Math.round(wDp * d), hPx = Math.round(hDp * d), pad = Math.round(8 * d);
        FrameLayout back = new FrameLayout(c);
        back.setBackgroundColor(dark ? 0xFF0B0F14 : 0xFFC9D2DA);
        View v = rv.apply(c, back);
        back.addView(v, new FrameLayout.LayoutParams(wPx, hPx, android.view.Gravity.CENTER));
        int tw = wPx + 2 * pad, th = hPx + 2 * pad;
        back.measure(View.MeasureSpec.makeMeasureSpec(tw, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(th, View.MeasureSpec.EXACTLY));
        back.layout(0, 0, tw, th);
        return back;
    }

    static Bitmap draw(View v, String caption) {
        int extra = Math.round(16 * v.getResources().getDisplayMetrics().density);
        Bitmap b = Bitmap.createBitmap(v.getWidth(), v.getHeight() + extra, Bitmap.Config.ARGB_8888);
        Canvas c = new Canvas(b);
        c.drawColor(Color.WHITE);
        v.draw(c);
        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        p.setColor(Color.BLACK);
        p.setTextSize(extra * 0.75f);
        c.drawText(caption, 6, v.getHeight() + extra * 0.8f, p);
        return b;
    }

    /** The picker previews (res/drawable-nodpi/widget_preview_*.png): each widget at its own cells, the preview sample (a full moon, the 15th day on), light. */
    static final Object[][] PREVIEWS = { { "moon", 0, 66, 102 }, { "moonupo", 1, 145, 102 }, { "s", 2, 160, 200 }, { "strip", 3, 298, 102 }, { "m", 4, 298, 215 }, { "day", 5, 160, 200 }, { "l", 6, 298, 441 } };

    /** A widget alone on a transparent picture, as the picker shows it. */
    static Bitmap preview(Context ctx, int kind, int w, int h) throws Exception {
        Case c = new Case(kind, w, h, 6, "", new WidgetConfig(), 0);
        Configuration cfg = new Configuration(ctx.getResources().getConfiguration());
        cfg.uiMode = (cfg.uiMode & ~Configuration.UI_MODE_NIGHT_MASK) | Configuration.UI_MODE_NIGHT_NO;
        Context lc = ctx.createConfigurationContext(cfg);
        float d = lc.getResources().getDisplayMetrics().density;
        int wPx = Math.round(w * d), hPx = Math.round(h * d);
        FrameLayout back = new FrameLayout(lc);
        View v = views(lc, c).apply(lc, back);
        back.addView(v, new FrameLayout.LayoutParams(wPx, hPx));
        back.measure(View.MeasureSpec.makeMeasureSpec(wPx, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(hPx, View.MeasureSpec.EXACTLY));
        back.layout(0, 0, wPx, hPx);
        Bitmap b = Bitmap.createBitmap(wPx, hPx, Bitmap.Config.ARGB_8888);
        back.draw(new Canvas(b));
        return b;
    }

    static void save(Bitmap b, File f) throws Exception {
        try (FileOutputStream fo = new FileOutputStream(f)) { b.compress(Bitmap.CompressFormat.PNG, 100, fo); }
    }
}
