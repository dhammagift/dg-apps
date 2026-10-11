package gift.dhamma.uposatha;

import android.app.Activity;
import android.appwidget.AppWidgetManager;
import android.content.Intent;
import android.content.res.Configuration;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.TextView;

import org.json.JSONObject;

import java.util.List;
import java.util.Locale;

/**
 * The settings of one widget (the launcher's gear / "edit" on a long press; on Android 11 and older also when the widget is added):
 * the theme, the transparency of the card, and how much the widget says. The widget itself is shown on top and changes with every
 * choice (the real RemoteViews, applied here the way a launcher does it). A choice is saved and drawn on the home screen at once,
 * there is nothing to confirm (owner, 2026-10-10: he changed a setting, went back, and nothing had changed). Nothing here is
 * mirrored into the app's own settings.
 */
public class WidgetConfigActivity extends Activity {
    private int id = AppWidgetManager.INVALID_APPWIDGET_ID, kind, wDp, hDp;
    private WidgetConfig cfg;
    private WidgetText tx;
    private JSONObject data;
    private FrameLayout preview;
    private TextView saved;
    private final Runnable apply = this::apply;
    private boolean night;
    private float d;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        Intent in = getIntent();
        if (in != null && in.getExtras() != null) id = in.getExtras().getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID);
        if (id == AppWidgetManager.INVALID_APPWIDGET_ID) { setResult(RESULT_CANCELED); finish(); return; }
        setResult(RESULT_OK, new Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id));   // every choice is already applied, so going back keeps the widget too
        AppWidgetManager mgr = AppWidgetManager.getInstance(this);
        kind = WidgetProvider.kindOf(mgr, id);
        List<int[]> sizes = WidgetProvider.sizesDp(this, mgr, id);
        wDp = sizes.get(0)[0]; hDp = sizes.get(0)[1];
        cfg = WidgetConfig.load(this, id);
        data = WidgetProvider.readData(this);
        JSONObject st = data == null ? null : data.optJSONObject("settings");
        tx = new WidgetText(this, st != null ? st.optString("lang", "en") : Locale.getDefault().getLanguage());
        night = (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES;
        d = getResources().getDisplayMetrics().density;
        setTitle(tx.get("cfg.title"));
        setContentView(build());
        redraw();
    }

    private int px(float dp) { return Math.round(dp * d); }
    private int ink() { return night ? 0xFFE2E2E2 : 0xFF1B1D19; }
    private int soft() { return night ? 0xFFB0B0B0 : 0xFF5C6058; }
    private int line() { return night ? 0xFF3B4543 : 0xFFD7DDD9; }
    private static final int ACCENT = 0xFF149C7C;

    private View build() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(night ? 0xFF121615 : 0xFFF4F6F5);
        root.setFitsSystemWindows(true);
        // the widget itself, on something like a wallpaper
        preview = new FrameLayout(this);
        GradientDrawable wall = new GradientDrawable(GradientDrawable.Orientation.TL_BR, night ? new int[] { 0xFF141C2B, 0xFF27324A, 0xFF101522 } : new int[] { 0xFF8A6A2F, 0xFFC9A85A, 0xFF3D4A55 });
        preview.setBackground(wall);
        preview.setClipChildren(false);   // the widget is laid out at its real size and scaled down, its box may be bigger than the strip
        root.setClipChildren(true);
        root.addView(preview, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, px(Math.round(hDp * previewFit()) + 32)));
        ScrollView scroll = new ScrollView(this);
        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setPadding(px(18), px(4), px(18), px(18));
        scroll.addView(col);
        root.addView(scroll, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));

        col.addView(label(tx.get("cfg.theme")));
        col.addView(seg(new String[] { tx.get("cfg.system"), tx.get("cfg.light"), tx.get("cfg.dark") }, cfg.theme, v -> cfg.theme = v));
        final TextView tl = label("");
        col.addView(tl);
        SeekBar bar = new SeekBar(this);
        bar.setMax(20);
        bar.setProgress((100 - cfg.opacity) / 5);
        tl.setText(tx.get("cfg.transparency") + ": " + (100 - cfg.opacity) + "%");
        bar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar s, int p, boolean user) { cfg.opacity = 100 - p * 5; tl.setText(tx.get("cfg.transparency") + ": " + (100 - cfg.opacity) + "%"); redraw(); later(); }
            @Override public void onStartTrackingTouch(SeekBar s) { }
            @Override public void onStopTrackingTouch(SeekBar s) { }
        });
        col.addView(bar);
        String[] app3 = { tx.get("cfg.app"), tx.get("cfg.on"), tx.get("cfg.off") };
        if (kind == WidgetPlan.UPO || kind == WidgetPlan.UPO_M || kind == WidgetPlan.CAL) {
            col.addView(label(tx.get("cfg.details")));
            col.addView(seg(app3, cfg.details, v -> cfg.details = v));
        }
        if (kind == WidgetPlan.UPO || kind == WidgetPlan.UPO_M || kind == WidgetPlan.STRIP || kind == WidgetPlan.CAL) {
            col.addView(label(tx.get("cfg.kala")));
            col.addView(seg(new String[] { tx.get("cfg.app"), tx.get("cfg.show"), tx.get("cfg.hide") }, cfg.kala, v -> cfg.kala = v));
        }
        if (kind == WidgetPlan.MOON) {
            col.addView(label(tx.get("cfg.pct")));
            col.addView(seg(new String[] { tx.get("cfg.on"), tx.get("cfg.off") }, cfg.pct ? 0 : 1, v -> cfg.pct = v == 0));
        }
        if (kind == WidgetPlan.UPO_M || kind == WidgetPlan.CAL) {
            col.addView(label(tx.get("cfg.slides")));
            col.addView(seg(new String[] { tx.get("cfg.on"), tx.get("cfg.off") }, cfg.slides ? 0 : 1, v -> cfg.slides = v == 0));
        }
        if (kind == WidgetPlan.CAL || kind == WidgetPlan.UPO_M) {
            col.addView(label(tx.get("cfg.moons")));
            col.addView(seg(app3, cfg.moons, v -> cfg.moons = v));
            col.addView(label(tx.get("cfg.next")));
            col.addView(seg(new String[] { tx.get("cfg.on"), tx.get("cfg.off") }, cfg.next ? 0 : 1, v -> cfg.next = v == 0));
        }
        // What the launcher says about this widget's size. The design is scaled to these numbers, so when a widget comes out small
        // or stretched on some launcher, this line in a screenshot tells why (owner's phone, 2026-10-10).
        android.os.Bundle o = AppWidgetManager.getInstance(this).getAppWidgetOptions(id);
        StringBuilder dbg = new StringBuilder("size ").append(wDp).append('x').append(hDp)
                .append(" · min ").append(o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)).append('x').append(o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT))
                .append(" · max ").append(o.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH)).append('x').append(o.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT));
        if (android.os.Build.VERSION.SDK_INT >= 31) {
            java.util.ArrayList<android.util.SizeF> list = o.getParcelableArrayList(AppWidgetManager.OPTION_APPWIDGET_SIZES);
            if (list != null) for (android.util.SizeF f : list) dbg.append(" · ").append(Math.round(f.getWidth())).append('x').append(Math.round(f.getHeight()));
        }
        android.content.res.Configuration cf = getResources().getConfiguration();
        dbg.append(" · screen ").append(cf.screenWidthDp).append('x').append(cf.screenHeightDp)
                .append(" · density ").append(getResources().getDisplayMetrics().density).append(" · font ").append(cf.fontScale);
        TextView info = label(dbg.toString());
        info.setTextSize(TypedValue.COMPLEX_UNIT_SP, 10);
        col.addView(info);
        TextView done = new TextView(this);
        done.setText(tx.get("cfg.done"));
        done.setTextColor(0xFFFFFFFF);
        done.setTypeface(Typeface.DEFAULT_BOLD);
        done.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        done.setGravity(Gravity.CENTER);
        done.setBackground(round(ACCENT, 12, 0));
        done.setPadding(0, px(13), 0, px(13));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.setMargins(px(18), px(10), px(18), px(14));
        saved = label("\u2713 " + tx.get("cfg.saved"));
        saved.setTextColor(ACCENT);
        saved.setGravity(Gravity.CENTER);
        saved.setPadding(0, px(6), 0, 0);
        saved.setVisibility(View.INVISIBLE);   // it has its room from the start, so nothing jumps when it appears
        root.addView(saved);
        root.addView(done, lp);   // under the list, always on the screen
        done.setOnClickListener(v -> finish());
        return root;
    }

    /** A choice was made: it is saved and the widget on the home screen is drawn with it. */
    private void apply() {
        preview.removeCallbacks(apply);
        cfg.save(this, id);
        WidgetProvider.update(this, AppWidgetManager.getInstance(this), id);
        WidgetProvider.schedule(this);
        saved.setVisibility(View.VISIBLE);
        saved.setAlpha(0f);
        saved.animate().alpha(1f).setDuration(200);
    }

    /** The slider moves many times a second: applied when it rests. */
    private void later() { preview.removeCallbacks(apply); preview.postDelayed(apply, 250); }

    @Override
    protected void onPause() {
        super.onPause();
        if (preview != null && cfg != null) { preview.removeCallbacks(apply); cfg.save(this, id); WidgetProvider.update(this, AppWidgetManager.getInstance(this), id); }   // a slider still waiting
    }

    private GradientDrawable round(int fill, float radiusDp, int stroke) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(fill);
        g.setCornerRadius(px(radiusDp));
        if (stroke != 0) g.setStroke(px(1), stroke);
        return g;
    }

    private TextView label(String s) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextColor(soft());
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setPadding(0, px(16), 0, px(7));
        return t;
    }

    private interface Pick { void pick(int v); }

    /** A row of two or three choices, one of them on. */
    private View seg(String[] names, int on, Pick pick) {
        LinearLayout row = new LinearLayout(this);
        row.setBackground(round(night ? 0xFF1A211F : 0xFFFFFFFF, 10, line()));
        row.setPadding(px(1), px(1), px(1), px(1));
        TextView[] cells = new TextView[names.length];
        for (int i = 0; i < names.length; i++) {
            final int idx = i;
            TextView t = new TextView(this);
            t.setText(names[i]);
            t.setGravity(Gravity.CENTER);
            t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
            t.setPadding(px(4), px(11), px(4), px(11));
            t.setMinHeight(px(48));
            cells[i] = t;
            row.addView(t, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
            t.setOnClickListener(v -> { pick.pick(idx); paint(cells, idx); redraw(); apply(); });
        }
        paint(cells, on);
        return row;
    }

    private void paint(TextView[] cells, int on) {
        for (int i = 0; i < cells.length; i++) {
            cells[i].setBackground(i == on ? round(ACCENT, 9, 0) : null);
            cells[i].setTextColor(i == on ? 0xFFFFFFFF : ink());
            cells[i].setTypeface(i == on ? Typeface.DEFAULT_BOLD : Typeface.DEFAULT);
        }
    }

    /** How much smaller than life the widget is shown on this screen: at most 230 dp high and as wide as the screen. */
    private float previewFit() {
        return Math.min(1f, Math.min((getResources().getDisplayMetrics().widthPixels / d - 32) / wDp, 230f / hDp));
    }

    /** The real widget with the choices of now, inflated the way a launcher does it. */
    private void redraw() {
        if (preview == null) return;
        try {
            // the widget at its real size (its design is scaled for that size), then the whole picture is shown smaller when it is big
            float fit = previewFit();
            View v = WidgetViews.build(this, id, kind, wDp, hDp, data, System.currentTimeMillis(), cfg, 0, WidgetProvider.slideOf(this, AppWidgetManager.getInstance(this), id)).apply(getApplicationContext(), preview);
            v.setScaleX(fit); v.setScaleY(fit);
            preview.removeAllViews();
            preview.addView(v, new FrameLayout.LayoutParams(px(wDp), px(hDp), Gravity.CENTER));
        } catch (RuntimeException e) {
            android.util.Log.w("DgWidget", "settings preview failed: " + e);
        }
    }
}
