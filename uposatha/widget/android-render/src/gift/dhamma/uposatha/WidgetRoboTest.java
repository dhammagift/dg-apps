package gift.dhamma.uposatha;

import android.app.Application;
import android.graphics.Bitmap;
import android.view.View;
import android.widget.RemoteViews;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;

import java.io.File;

/** Local render of the widget sheet (WidgetSheet.cases()) without a device: PNGs into -Dwidget.out. WIDGET_ONLY = a regex of case names; WIDGET_THEME = light | dark. */
@RunWith(RobolectricTestRunner.class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = 34, qualifiers = "w411dp-h891dp-xxhdpi")
public class WidgetRoboTest {
    @Test
    public void render() throws Exception {
        Application ctx = RuntimeEnvironment.getApplication();
        File out = new File(System.getProperty("widget.out", "/tmp/widget-out"));
        out.mkdirs();
        String only = System.getenv("WIDGET_ONLY") == null ? "" : System.getenv("WIDGET_ONLY"), theme = System.getenv("WIDGET_THEME");
        if ("1".equals(System.getenv("WIDGET_PREVIEW"))) {   // the picker previews, written straight into the resources
            File res = new File(System.getenv("WIDGET_RES"));
            for (Object[] p : WidgetSheet.PREVIEWS) WidgetSheet.save(WidgetSheet.preview(ctx, (Integer) p[1], (Integer) p[2], (Integer) p[3]), new File(res, "widget_preview_" + p[0] + ".png"));
            System.out.println("PREVIEWS " + WidgetSheet.PREVIEWS.length);
            return;
        }
        int n = 0;
        for (WidgetSheet.Case c : WidgetSheet.cases()) {
            if (!only.isEmpty() && !c.name.matches(only)) continue;
            for (int dark = 0; dark < 2; dark++) {
                if (theme != null && !theme.isEmpty() && !theme.equals(dark == 1 ? "dark" : "light")) continue;
                String name = c.name + (dark == 1 ? "-dark" : "-light");
                try {
                    RemoteViews rv = WidgetSheet.views(ctx, c);
                    View v = WidgetSheet.inflate(ctx, rv, c.w, c.h, dark == 1);
                    Bitmap b = WidgetSheet.draw(v, name);
                    WidgetSheet.save(b, new File(out, name + ".png"));
                    n++;
                } catch (Throwable t) {
                    System.out.println("FAILED " + name + ": " + t);
                    t.printStackTrace(System.out);
                }
            }
        }
        System.out.println("RENDERED " + n);
    }

    private static WidgetConfig cfg(java.util.function.Consumer<WidgetConfig> f) { WidgetConfig c = new WidgetConfig(); f.accept(c); return c; }

    private static int count(View v, int id) {
        int n = v.getId() == id ? 1 : 0;
        if (v instanceof android.view.ViewGroup) for (int i = 0; i < ((android.view.ViewGroup) v).getChildCount(); i++) n += count(((android.view.ViewGroup) v).getChildAt(i), id);
        return n;
    }

    /**
     * A launcher draws a new RemoteViews onto the views it already has when the layout is the same (reapply). The result must be what a
     * fresh widget shows: whatever one setting hides or colours, the other must set back. (Found on a device, 2026-10-10: the Moon's
     * percent stayed hidden after it was turned on; every redraw left one more copy of the slides' switch.)
     */
    @Test
    public void aRedrawOntoTheSameViewsEqualsAFreshDraw() throws Exception {
        if (System.getenv("WIDGET_REAPPLY") == null) return;
        Application ctx = RuntimeEnvironment.getApplication();
        File out = new File(System.getProperty("widget.out", "/tmp/widget-out"));
        WidgetConfig def = new WidgetConfig();
        Object[][] T = {   // kind, w, h, from (cfg, slide), to (cfg, slide)
                { "moon: percent on", 0, 78, 75, def, 0, cfg(c -> c.pct = true), 0 },
                { "moon: percent off", 0, 78, 75, cfg(c -> c.pct = true), 0, def, 0 },
                { "moon: dark to system", 0, 156, 151, cfg(c -> c.theme = WidgetConfig.DARK), 0, def, 0 },
                { "moon: light to system", 0, 156, 151, cfg(c -> c.theme = WidgetConfig.LIGHT), 0, def, 0 },
                { "moon: system to dark", 0, 156, 151, def, 0, cfg(c -> c.theme = WidgetConfig.DARK), 0 },
                { "moon: translucent to solid", 0, 156, 151, cfg(c -> c.opacity = 40), 0, def, 0 },
                { "moon+uposatha: light to system", 1, 156, 75, cfg(c -> c.theme = WidgetConfig.LIGHT), 0, def, 0 },
                { "2x2: kala off", 2, 156, 151, def, 0, cfg(c -> c.kala = WidgetConfig.OFF), 0 },
                { "2x2: kala on", 2, 156, 151, cfg(c -> c.kala = WidgetConfig.OFF), 0, def, 0 },
                { "2x2: details off", 2, 156, 151, def, 0, cfg(c -> c.details = WidgetConfig.OFF), 0 },
                { "2x2: details on", 2, 156, 151, cfg(c -> c.details = WidgetConfig.OFF), 0, def, 0 },
                { "strip: kala off", 3, 391, 75, def, 0, cfg(c -> c.kala = WidgetConfig.OFF), 0 },
                { "strip: kala on", 3, 391, 75, cfg(c -> c.kala = WidgetConfig.OFF), 0, def, 0 },
                { "strip 4x1: dark to system", 3, 298, 102, cfg(c -> c.theme = WidgetConfig.DARK), 0, def, 0 },
                { "4x2: the same again (the switch)", 4, 313, 151, def, 0, def, 0 },
                { "4x2: slides off", 4, 313, 151, def, 0, cfg(c -> c.slides = false), 0 },
                { "4x2: slides on", 4, 313, 151, cfg(c -> c.slides = false), 0, def, 0 },
                { "4x2: day slide, dark to system", 4, 313, 151, cfg(c -> c.theme = WidgetConfig.DARK), 1, def, 1 },
                { "4x2: calendar slide, moons off", 4, 391, 227, cfg(c -> c.moons = WidgetConfig.ON), 2, cfg(c -> c.moons = WidgetConfig.OFF), 2 },
                { "day: dark to system", 5, 156, 151, cfg(c -> c.theme = WidgetConfig.DARK), 0, def, 0 },
                { "day: translucent dark to system", 5, 313, 151, cfg(c -> { c.theme = WidgetConfig.DARK; c.opacity = 55; }), 0, def, 0 },
                { "calendar: the same again", 6, 391, 454, def, 2, def, 2 },
                { "calendar: no list of the next", 6, 391, 454, def, 2, cfg(c -> c.next = false), 2 },
                { "calendar: moons on", 6, 391, 454, def, 2, cfg(c -> c.moons = WidgetConfig.ON), 2 },
                { "calendar: moons off", 6, 391, 454, cfg(c -> c.moons = WidgetConfig.ON), 2, cfg(c -> c.moons = WidgetConfig.OFF), 2 },
                { "big, uposatha slide: no list of the next", 6, 391, 454, def, 0, cfg(c -> c.next = false), 0 },
                { "big, uposatha slide: list back", 6, 391, 454, cfg(c -> c.next = false), 0, def, 0 },
                { "big, uposatha slide: details off", 6, 391, 454, def, 0, cfg(c -> c.details = WidgetConfig.OFF), 0 },
                { "big, day slide: light to system", 6, 391, 454, cfg(c -> c.theme = WidgetConfig.LIGHT), 1, def, 1 },
        };
        java.util.List<String> bad = new java.util.ArrayList<>();
        int same = 0, skipped = 0;
        for (Object[] t : T) for (int sc : new int[] { 5, 0 }) for (int dark = 0; dark < 2; dark++) {
            String name = t[0] + (sc == 5 ? ", en" : ", ru") + (dark == 1 ? ", dark" : ", light");
            if (!System.getenv("WIDGET_REAPPLY").equals("1") && !name.matches(System.getenv("WIDGET_REAPPLY"))) continue;   // a regex of names instead of "1": only those
            WidgetSheet.Case a = new WidgetSheet.Case((Integer) t[1], (Integer) t[2], (Integer) t[3], sc, "", (WidgetConfig) t[4], 0);
            a.slide = (Integer) t[5];
            WidgetSheet.Case b = new WidgetSheet.Case((Integer) t[1], (Integer) t[2], (Integer) t[3], sc, "", (WidgetConfig) t[6], 0);
            b.slide = (Integer) t[7];
            RemoteViews ra = WidgetSheet.views(ctx, a), rb = WidgetSheet.views(ctx, b);
            if (ra.getLayoutId() != rb.getLayoutId()) { skipped++; continue; }   // another layout: the launcher inflates it anew
            android.view.ViewGroup back = (android.view.ViewGroup) WidgetSheet.inflate(ctx, ra, a.w, a.h, dark == 1);
            View v = back.getChildAt(0);
            rb.reapply(v.getContext(), v);
            WidgetSheet.views(ctx, b).reapply(v.getContext(), v);   // and a second redraw, as the clock does every quarter of an hour
            back.measure(View.MeasureSpec.makeMeasureSpec(back.getWidth(), View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(back.getHeight(), View.MeasureSpec.EXACTLY));
            back.layout(0, 0, back.getWidth(), back.getHeight());
            Bitmap redrawn = WidgetSheet.draw(back, "redrawn: " + name);
            View fresh = WidgetSheet.inflate(ctx, WidgetSheet.views(ctx, b), b.w, b.h, dark == 1);
            Bitmap want = WidgetSheet.draw(fresh, "redrawn: " + name);
            int switches = count(back, R.id.sw_next), wantSwitches = count(fresh, R.id.sw_next);
            if (!redrawn.sameAs(want) || switches != wantSwitches) {
                String f = "reapply-" + name.replaceAll("[^a-z0-9]+", "-");
                WidgetSheet.save(redrawn, new File(out, f + "-redrawn.png"));
                WidgetSheet.save(want, new File(out, f + "-fresh.png"));
                bad.add(name + (switches != wantSwitches ? " (" + switches + " switches, a fresh widget has " + wantSwitches + ")" : ""));
            } else same++;
        }
        System.out.println("REAPPLY same " + same + ", other layout " + skipped + ", DIFFERENT " + bad.size() + " " + bad);
        org.junit.Assert.assertTrue("a redraw differs from a fresh widget: " + bad, bad.isEmpty());
    }
}
