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
 * DEBUG BUILDS ONLY (src/debug): every case of WidgetSheet.cases() (widget x size x scenario x settings) in light and dark, the REAL
 * widget (WidgetViews.build -> RemoteViews.apply into a frame of fixed dp size) in a scrolling list, so the layouts can be looked at -
 * and any clipping or overflow found - without a launcher. Each one is also saved as a PNG in getExternalFilesDir(null)/widget-previews.
 *
 *   adb shell am start -n gift.dhamma.uposatha/.WidgetPreviewActivity
 *   optional extras: --es only <regex of case names, e.g. "cal-.*">   --es theme light|dark
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
        final String theme = getIntent().getStringExtra("theme"), only = getIntent().getStringExtra("only");
        list.post(() -> build(list, theme, only));
    }

    private void build(LinearLayout list, String theme, String only) {
        File out = new File(getExternalFilesDir(null), "widget-previews");
        out.mkdirs();
        for (WidgetSheet.Case c : WidgetSheet.cases()) {
            if (only != null && !c.name.matches(only)) continue;
            for (int dark = 0; dark < 2; dark++) {
                if (theme != null && !theme.equals(dark == 1 ? "dark" : "light")) continue;
                try {
                    RemoteViews rv = WidgetSheet.views(this, c);
                    View v = WidgetSheet.inflate(this, rv, c.w, c.h, dark == 1);
                    String cap = c.name + (dark == 1 ? " dark" : " light");
                    Bitmap bm = WidgetSheet.draw(v, cap);
                    WidgetSheet.save(bm, new File(out, c.name + (dark == 1 ? "-dark" : "-light") + ".png"));
                    list.addView(header(cap));
                    list.addView(v, new LinearLayout.LayoutParams(v.getWidth(), v.getHeight()));
                } catch (Exception e) {
                    Log.e(TAG, "render failed", e);
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
