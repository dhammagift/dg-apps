package gift.dhamma.uposatha;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.os.Bundle;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;

/**
 * DEBUG BUILDS ONLY (src/debug): every layer x size x light/dark of the widget, drawn by WidgetRenderer from the sample data
 * (assets/widget-sample.json and widget-sample-en.json) into a scrolling list, so the pictures can be looked at without a launcher.
 * Each picture is also saved as a PNG in getExternalFilesDir(null)/widget-previews (adb pull).
 *
 *   adb shell am start -n gift.dhamma.uposatha/.WidgetPreviewActivity
 *   optional extras: --es size s|m|l   --es theme light|dark   --ei layer 0|1|2   --ei scenario N
 */
public class WidgetPreviewActivity extends Activity {
    private static final String TAG = "DgWidgetPreview";
    // widths/heights in dp: the usual phone sizes of 2x2, 4x2 and 4x4 (the width is cut to the screen)
    private static final int[][] SIZES = { { 160, 160 }, { 360, 130 }, { 360, 300 } };
    private static final String[] SIZE_NAME = { "s", "m", "l" };

    private static final class Scenario {
        final String name, file; final long nowOffset; final String nowFrom;
        final boolean detail, showKala, placeSet, bySuttas, south; final String lang;
        Scenario(String name, String file, String lang, String nowFrom, long nowOffset, boolean detail, boolean showKala, boolean placeSet, boolean bySuttas, boolean south) {
            this.name = name; this.file = file; this.lang = lang; this.nowFrom = nowFrom; this.nowOffset = nowOffset;
            this.detail = detail; this.showKala = showKala; this.placeSet = placeSet; this.bySuttas = bySuttas; this.south = south;
        }
    }

    private static final long H = 3600000L;
    private static final Scenario[] SCENARIOS = {
            new Scenario("ru, as the page gave it (no place, lite), vikala", "widget-sample.json", "ru", "gen", 0, false, true, false, true, false),
            new Scenario("ru, kala in the morning, detail, place set", "widget-sample.json", "ru", "sunrise", 3 * H, true, true, true, true, false),
            new Scenario("ru, Uposatha is on, detail", "widget-sample.json", "ru", "upoStart", 5 * H, true, true, true, false, false),
            new Scenario("en, kala off, lite", "widget-sample-en.json", "en", "sunrise", 3 * H, false, false, true, true, false),
            new Scenario("en, detail, vikala, south", "widget-sample-en.json", "en", "gen", 0, true, true, true, true, true),
            new Scenario("placeholders: no data (system language), stale (ru)", null, "ru", "gen", 0, false, true, true, true, false),
    };

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        final String size = getIntent().getStringExtra("size"), theme = getIntent().getStringExtra("theme");
        final int layer = getIntent().getIntExtra("layer", -1), only = getIntent().getIntExtra("scenario", -1);
        ScrollView sv = new ScrollView(this);
        final LinearLayout list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        list.setPadding(dp(8), dp(8), dp(8), dp(8));
        sv.addView(list);
        setContentView(sv);
        getWindow().addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        new Thread(() -> build(list, size, theme, layer, only)).start();
    }

    private int dp(float v) { return Math.round(v * getResources().getDisplayMetrics().density); }

    private void build(LinearLayout list, String size, String theme, int layer, int only) {
        File out = new File(getExternalFilesDir(null), "widget-previews");
        out.mkdirs();
        DisplayMetrics dm = getResources().getDisplayMetrics();
        int screenDp = Math.round(dm.widthPixels / dm.density) - 16 - 16 - 8;
        for (int si = 0; si < SCENARIOS.length; si++) {
            if (only >= 0 && only != si) continue;
            final Scenario sc = SCENARIOS[si];
            post(list, header("#" + si + "  " + sc.name));
            for (int z = 0; z < 3; z++) {
                if (size != null && !size.equals(SIZE_NAME[z])) continue;
                int w = Math.min(SIZES[z][0], screenDp), h = SIZES[z][1];
                for (int dark = 0; dark < 2; dark++) {
                    if (theme != null && !theme.equals(dark == 1 ? "dark" : "light")) continue;
                    for (int ly = 0; ly < 3; ly++) {
                        if (layer >= 0 && layer != ly) continue;
                        if (sc.file == null && ly > 0) continue;   // the placeholders look the same in every layer
                        try {
                            JSONObject data = data(sc);
                            long now = now(sc, data);
                            if (sc.file == null && si == SCENARIOS.length - 1) {
                                // first the no-data picture, then a stale one (generated 30 days before the clock)
                                for (int k = 0; k < 2; k++) {
                                    JSONObject d = k == 0 ? null : sample("widget-sample.json");
                                    long n = k == 0 ? System.currentTimeMillis() : now + 30L * 24 * H;
                                    Bitmap bm = WidgetRenderer.render(this, d, ly, w, h, dark == 1, n, 1.75f);
                                    show(list, bm, dark == 1, si + "-" + SIZE_NAME[z] + "-ph" + k + "-" + (dark == 1 ? "dark" : "light"), out, w, h);
                                }
                                continue;
                            }
                            Bitmap bm = WidgetRenderer.render(this, data, ly, w, h, dark == 1, now, 1.75f);
                            show(list, bm, dark == 1, si + "-" + SIZE_NAME[z] + "-l" + ly + "-" + (dark == 1 ? "dark" : "light"), out, w, h);
                        } catch (Exception e) {
                            Log.e(TAG, "render failed", e);
                        }
                    }
                }
            }
        }
        Log.i(TAG, "done: " + out);
    }

    private JSONObject sample(String file) throws Exception {
        try (InputStream in = getAssets().open(file)) {
            ByteArrayOutputStream bo = new ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) bo.write(buf, 0, n);
            return new JSONObject(bo.toString("UTF-8"));
        }
    }

    private JSONObject data(Scenario sc) throws Exception {
        JSONObject d = sample(sc.file != null ? sc.file : "widget-sample.json");
        JSONObject st = d.getJSONObject("settings");
        st.put("lang", sc.lang).put("detail", sc.detail).put("showKala", sc.showKala).put("placeSet", sc.placeSet)
                .put("bySuttas", sc.bySuttas).put("south", sc.south);
        return d;
    }

    private long now(Scenario sc, JSONObject d) throws Exception {
        long base;
        switch (sc.nowFrom) {
            case "sunrise": base = d.getJSONArray("days").getJSONObject(0).getJSONObject("sunrise").getLong("ms"); break;
            case "upoStart": base = d.getJSONArray("uposathas").getJSONObject(1).getJSONObject("start").getLong("ms"); break;
            default: base = WidgetModel.parseIso(d.getString("generatedAt"));
        }
        return base + sc.nowOffset;
    }

    private TextView header(String s) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(13);
        t.setTextColor(Color.BLACK);
        t.setPadding(dp(4), dp(14), dp(4), dp(4));
        return t;
    }

    private void show(LinearLayout list, Bitmap bm, boolean dark, String name, File out, int wDp, int hDp) {
        try (FileOutputStream fo = new FileOutputStream(new File(out, name + ".png"))) {
            bm.compress(Bitmap.CompressFormat.PNG, 100, fo);
        } catch (Exception e) { Log.w(TAG, "save failed: " + e); }
        FrameLayout panel = new FrameLayout(this);
        panel.setBackgroundColor(dark ? Color.BLACK : 0xFFDFE3E6);
        panel.setPadding(dp(8), dp(8), dp(8), dp(8));
        ImageView iv = new ImageView(this);
        iv.setImageBitmap(bm);
        iv.setScaleType(ImageView.ScaleType.FIT_XY);
        panel.addView(iv, new FrameLayout.LayoutParams(dp(wDp), dp(hDp), Gravity.CENTER_HORIZONTAL));
        post(list, panel);
    }

    private void post(final LinearLayout list, final android.view.View v) {
        runOnUiThread(() -> list.addView(v, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)));
    }
}
