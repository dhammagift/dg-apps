package gift.dhamma.uposatha;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.RemoteViews;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.File;

/**
 * DEBUG BUILDS ONLY (src/debug): every scenario x layer x size x light/dark of the REAL widget (WidgetViews.build -> RemoteViews.apply
 * into a frame of fixed dp size, WidgetSheet) in a scrolling list, so the layouts can be looked at - and any stretching, clipping or
 * overflow found - without a launcher. Each one is also saved as a PNG in getExternalFilesDir(null)/widget-previews (adb pull).
 *
 *   adb shell am start -n gift.dhamma.uposatha/.WidgetPreviewActivity
 *   optional extras: --ei w 360 --ei h 430 (one size)   --es theme light|dark   --ei layer 0|1|2   --ei scenario N
 */
public class WidgetPreviewActivity extends Activity {
    private static final String TAG = "DgWidgetPreview";

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        ScrollView sv = new ScrollView(this);
        final LinearLayout list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        list.setPadding(8, 8, 8, 8);
        sv.addView(list);
        setContentView(sv);
        getWindow().addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        final String theme = getIntent().getStringExtra("theme");
        final int layer = getIntent().getIntExtra("layer", -1), only = getIntent().getIntExtra("scenario", -1);
        final int ow = getIntent().getIntExtra("w", 0), oh = getIntent().getIntExtra("h", 0);
        list.post(() -> build(list, theme, layer, only, ow, oh));
    }

    private void build(LinearLayout list, String theme, int layer, int only, int ow, int oh) {
        File out = new File(getExternalFilesDir(null), "widget-previews");
        out.mkdirs();
        for (int si = 0; si < WidgetSheet.SCENARIOS.length; si++) {
            if (only >= 0 && only != si) continue;
            WidgetSheet.Scenario sc = WidgetSheet.SCENARIOS[si];
            list.addView(header("#" + si + "  " + sc.name));
            for (int[] sz : WidgetSheet.SIZES) {
                if (ow > 0 && (sz[0] != ow || sz[1] != oh)) continue;
                for (int dark = 0; dark < 2; dark++) {
                    if (theme != null && !theme.equals(dark == 1 ? "dark" : "light")) continue;
                    for (int ly = 0; ly < 3; ly++) {
                        if (layer >= 0 && layer != ly) continue;
                        if (sc.file == null && ly > 0) continue;   // the placeholders look the same in every layer
                        for (int variant = 0; variant < (sc.file == null ? 2 : 1); variant++) {
                            try {
                                RemoteViews rv = WidgetSheet.views(this, sc, variant, ly, sz[0], sz[1]);
                                View v = WidgetSheet.inflate(this, rv, sz[0], sz[1], dark == 1);
                                String cap = "#" + si + " L" + ly + " " + sz[0] + "x" + sz[1] + " dp " + (dark == 1 ? "dark" : "light");
                                Bitmap bm = WidgetSheet.draw(v, cap);
                                WidgetSheet.save(bm, new File(out, WidgetSheet.name(si, ly, sz[0], sz[1], dark == 1, variant) + ".png"));
                                list.addView(header(cap));
                                list.addView(v, new LinearLayout.LayoutParams(v.getWidth(), v.getHeight()));
                            } catch (Exception e) {
                                Log.e(TAG, "render failed", e);
                            }
                        }
                    }
                }
            }
        }
        Log.i(TAG, "done: " + out);
    }

    private TextView header(String s) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(13);
        t.setTextColor(Color.BLACK);
        t.setPadding(4, 14, 4, 4);
        return t;
    }
}
