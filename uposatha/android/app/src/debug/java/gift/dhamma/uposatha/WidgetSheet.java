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
 * the moon pair resolve exactly as the launcher's night mode would). Shared by WidgetPreviewActivity (on screen) and the androidTest
 * WidgetSheetTest (PNGs for Test Lab). Any stretching, clipping or overflow of the layouts shows here.
 */
final class WidgetSheet {
    private WidgetSheet() {}

    /** Sizes (dp) to try: the usual 2x2 / 4x2 / 4x4, tall and narrow ones, and a deliberately odd one. */
    static final int[][] SIZES = { { 160, 160 }, { 130, 110 }, { 170, 340 }, { 250, 110 }, { 360, 150 }, { 360, 300 }, { 300, 430 }, { 360, 430 }, { 360, 520 }, { 170, 170 }, { 364, 170 }, { 364, 382 }, { 290, 430 }, { 364, 430 } };   // the last five: the designer's three sizes, and the two sizes of a 4x4 resized narrow and wide on a phone

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

    /** The widget of a scenario at a size: layer 0..2; placeholders are the last scenario (no data, then stale). */
    static RemoteViews views(Context ctx, Scenario sc, int variant, int layer, int w, int h) throws Exception {
        if (sc.file == null) {
            JSONObject d = variant == 0 ? null : sample(ctx, "widget-sample.json");
            long n = variant == 0 ? System.currentTimeMillis() : now(SCENARIOS[0], d) + 30L * 24 * H;
            return WidgetViews.build(ctx, 1, w, h, d, n, 0);
        }
        JSONObject d = data(ctx, sc);
        return WidgetViews.build(ctx, 1, w, h, d, now(sc, d), layer);
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

    static void save(Bitmap b, File f) throws Exception {
        try (FileOutputStream fo = new FileOutputStream(f)) { b.compress(Bitmap.CompressFormat.PNG, 100, fo); }
    }

    static String name(int scenario, int layer, int w, int h, boolean dark, int variant) {
        return "sheet-s" + scenario + (scenario == SCENARIOS.length - 1 ? "v" + variant : "") + "-L" + layer + "-" + w + "x" + h + "-" + (dark ? "dark" : "light");
    }
}
