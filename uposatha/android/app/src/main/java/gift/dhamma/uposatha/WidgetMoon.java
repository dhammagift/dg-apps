package gift.dhamma.uposatha;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.BlurMaskFilter;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RadialGradient;
import android.graphics.RectF;
import android.graphics.Shader;

import androidx.core.graphics.ColorUtils;
import androidx.core.graphics.PathParser;

import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/**
 * The widget's moon, the ONE picture of an otherwise all-views widget: the NASA photo (res/drawable-nodpi/moon_nasa.png) with the
 * shade of the phase (geometry of dg-moon-site.js: litPath / shadePath), edge darkening and a thin rim; in the dark theme also a
 * halo, so a new moon does not vanish on a dark card. The bitmap is SQUARE, the disc in the middle of it with a margin for the
 * halo, and carries its own density: an ImageView with wrap_content shows it at the asked size on any screen.
 */
final class WidgetMoon {
    private WidgetMoon() {}

    /** The share of the bitmap's side that the disc takes (the rest is the halo's room; the halo ends exactly at the picture's edge). */
    static final float DISC = 0.88f;

    private static final int GLOW = 0xFFE9E4DC;
    private static Bitmap photo;
    private static final Map<Integer, Bitmap> scaled = new HashMap<>();
    private static final Map<String, Bitmap> cache = new HashMap<>();
    private static long cacheBytes;
    /** The most pixels a side of a moon gets. Lower while a widget is drawn for several sizes at once: RemoteViews has a ceiling on its pictures. */
    static volatile int maxPx = 640;
    /** Set while a widget is drawn for many sizes: the big moon is made in steps of a sixth, so views with moons of about one size carry ONE picture (WidgetViews.sized shows it at the view's own size). */
    static volatile boolean shared;

    /**
     * The big moon of a widget, for an ImageView with wrap_content: a square picture that is shown boxDp wide whatever the screen
     * (its own density says so), the disc DISC of it. The pixels are at most twice the dp: a widget picture is small, and the launcher
     * refuses an update that carries too many big ones.
     */
    static synchronized Bitmap render(Context ctx, float boxDp, double phase, boolean south, boolean dark) {
        if (shared) boxDp = (float) Math.pow(1.18, Math.ceil(Math.log(boxDp) / Math.log(1.18)));   // the next step up: 1.18^n dp
        return get(ctx, boxDp, phase, south, dark ? 1 : 0, DISC, 2f);
    }

    /** A moon of a list or of a calendar cell: ONE picture for the light and the dark card (a neutral rim, no halo), the disc fills it. */
    static synchronized Bitmap renderMini(Context ctx, float sizeDp, double phase, boolean south) {
        return get(ctx, sizeDp, phase, south, 2, 1f, 3f);
    }

    private static Bitmap get(Context ctx, float boxDp, double phase, boolean south, int look, float disc, float maxDensity) {
        float real = ctx.getResources().getDisplayMetrics().density, density = Math.min(real, maxDensity);
        int px = Math.max(12, Math.min(maxPx, Math.round(boxDp * density)));   // a moon over a whole big cell is stretched from 640 px: RemoteViews has a ceiling on its pictures
        String key = px + "/" + Math.round(boxDp * 4) + "/" + Math.round(phase * 500) + "/" + south + "/" + look;
        Bitmap hit = cache.get(key);
        if (hit != null) return hit;
        // the RemoteViews hold their own references. A ceiling in bytes: the phase moves on every 45 minutes, and an app open for hours
        // kept up to 20 MB of old moons beside its WebView
        if (cacheBytes > 12 << 20) { cache.clear(); cacheBytes = 0; }
        Bitmap b = draw(ctx, px, look == 2 || boxDp * disc < 50, phase, south, look, disc);
        b.setDensity(Math.max(1, Math.round(160f * px / boxDp)));   // an ImageView with wrap_content then shows it exactly boxDp wide
        cache.put(key, b);
        cacheBytes += b.getByteCount();
        return b;
    }

    /** look: 0 a light card, 1 a dark card (halo, light rim), 2 either (mini). */
    private static Bitmap draw(Context ctx, int px, boolean small, double phase, boolean south, int look, float discShare) {
        Bitmap bmp = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888);
        Canvas c = new Canvas(bmp);
        final float C = 50, R = 48;
        float k = px * discShare / (2 * R);   // pixels per unit of the 100 x 100 box the geometry is written in
        c.translate(px / 2f - C * k, px / 2f - C * k);
        c.scale(k, k);
        if (south) c.rotate(180, C, C);
        double I = illumination(phase);
        if (look == 1) {   // a halo under EVERY moon on a dark card, a bit stronger as the moon fills; it fades to nothing at the picture's edge
            float edge = R / discShare;
            Paint g = new Paint(Paint.ANTI_ALIAS_FLAG);
            int a = (int) Math.round(255 * (0.20 + 0.22 * I));
            g.setShader(new RadialGradient(C, C, edge, new int[] { ColorUtils.setAlphaComponent(GLOW, a), ColorUtils.setAlphaComponent(GLOW, a), ColorUtils.setAlphaComponent(GLOW, 0) },
                    new float[] { 0f, (R - 1) / edge, 1f }, Shader.TileMode.CLAMP));
            c.drawCircle(C, C, edge, g);
        }
        Path disc = new Path();
        disc.addCircle(C, C, R, Path.Direction.CW);
        c.save();
        c.clipPath(disc);
        Bitmap tex = texture(ctx, Math.round(97.2f * k));
        Paint tpnt = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
        // The picture itself is warm (the NASA photo, variant B of the owner's choice, 2026-10-10); at list sizes it is a little
        // brighter still, so it does not read as one more row of text.
        if (small) tpnt.setColorFilter(new android.graphics.ColorMatrixColorFilter(new float[] { 1.12f, 0, 0, 0, 14, 0, 1.12f, 0, 0, 12, 0, 0, 1.12f, 0, 8, 0, 0, 0, 1, 0 }));
        if (tex != null) c.drawBitmap(tex, null, new RectF(C - R - .6f, C - R - .6f, C + R + .6f, C + R + .6f), tpnt);
        else { Paint f = new Paint(Paint.ANTI_ALIAS_FLAG); f.setColor(0xFF9A968E); c.drawCircle(C, C, R, f); }
        // Edge darkening: transparent to 50 %, then a little, then 42 % black at the rim (a small moon keeps its brightness to the rim).
        Paint edge = new Paint(Paint.ANTI_ALIAS_FLAG);
        edge.setShader(new RadialGradient(C, C, R, small ? new int[] { 0x00000000, 0x10000000, 0x30000000 } : new int[] { 0x00000000, 0x24000000, 0x6B000000 }, new float[] { .5f, .86f, 1f }, Shader.TileMode.CLAMP));
        c.drawCircle(C, C, R, edge);
        // The shade is EARTHSHINE, not a black hole (owner, 2026-10-10: the new moon looked like a black spot): the night side is the same
        // moon, dim and blue-grey, its seas still readable. A wide penumbra (blur 4.5, 46 %) under a sharp edge (blur 1.3, 70 %; 60 % when small).
        int shadeColor = look == 1 ? 0xFF1B2535 : 0xFF1F2A3C;
        Path shade = PathParser.createPathFromPathData(shadePath(phase));
        if (shade != null) {
            Paint pen = new Paint(Paint.ANTI_ALIAS_FLAG);
            pen.setColor(ColorUtils.setAlphaComponent(shadeColor, 117));
            pen.setMaskFilter(new BlurMaskFilter(blurRadius(4.5f), BlurMaskFilter.Blur.NORMAL));
            c.drawPath(shade, pen);
            Paint sha = new Paint(Paint.ANTI_ALIAS_FLAG);
            sha.setColor(ColorUtils.setAlphaComponent(shadeColor, small ? 153 : 178));
            sha.setMaskFilter(new BlurMaskFilter(blurRadius(1.3f), BlurMaskFilter.Blur.NORMAL));
            c.drawPath(shade, sha);
        }
        c.restore();
        // The rim keeps a full moon on a light card and a new moon on a dark one.
        Paint rim = new Paint(Paint.ANTI_ALIAS_FLAG);
        rim.setStyle(Paint.Style.STROKE);
        rim.setStrokeWidth(small ? 1.6f : .9f);
        rim.setColor(look == 1 ? ColorUtils.setAlphaComponent(GLOW, Math.round(255 * (small ? .55f : .42f)))
                : look == 2 ? ColorUtils.setAlphaComponent(0xFF8A9096, Math.round(255 * .60f))
                : ColorUtils.setAlphaComponent(0xFF2F4A63, Math.round(255 * .30f)));
        c.drawCircle(C, C, R - .4f, rim);
        return bmp;
    }

    /** The NASA photo (420 px) halved step by step down to about px: no shimmer when small. */
    private static Bitmap texture(Context ctx, int px) {
        px = Math.max(8, px);
        Bitmap hit = scaled.get(px);
        if (hit != null) return hit;
        if (photo == null) {
            BitmapFactory.Options o = new BitmapFactory.Options();
            o.inScaled = false;
            photo = BitmapFactory.decodeResource(ctx.getResources(), R.drawable.moon_nasa, o);
        }
        Bitmap b = photo;
        if (b == null) return null;
        while (b.getWidth() / 2 >= px) b = Bitmap.createScaledBitmap(b, b.getWidth() / 2, b.getHeight() / 2, true);
        if (b.getWidth() != px) b = Bitmap.createScaledBitmap(b, px, px, true);
        scaled.put(px, b);
        return b;
    }

    private static String num(double v) { return String.format(Locale.US, "%.3f", v); }

    private static double norm(double f) { return ((f % 1) + 1) % 1; }

    /** The shaded part of the disc in a 100x100 box (centre 50, R 48): terminator ellipse + the big arc beyond the rim. */
    static String shadePath(double f) {
        f = norm(f);
        final int C = 50, R = 48, B = 62;
        double k = Math.cos(2 * Math.PI * f);
        String rx = num(seen(Math.abs(k)) * R);
        boolean gib = k < 0, wax = f < 0.5;
        int ts = wax ? (gib ? 0 : 1) : (gib ? 1 : 0), bs = wax ? 1 : 0;
        return "M" + C + " " + (C - R) + "A" + rx + " " + R + " 0 0 " + ts + " " + C + " " + (C + R)
                + "L" + C + " " + (C + B) + "A" + B + " " + B + " 0 0 " + bs + " " + C + " " + (C - B) + "Z";
    }

    /**
     * The terminator as it is DRAWN: a loader that is honest and still readable. The true crescent of the day after a new moon is two units
     * thick and looks like the new moon itself, and the 14th day looks like the full one; the thin part is made thicker (|k|: 0 at half, 1
     * at new and full; the thickness 1-|k| is raised to 0.6), the middle of the cycle hardly changes. Same function in dg-moon.js and MoonView.swift.
     */
    static double seen(double a) {
        double u = 1 - Math.min(1, Math.max(0, a));
        return 1 - (Math.pow(u, 0.6) + 0.07 * Math.exp(-u / 0.06) * (1 - Math.exp(-u / 0.0015)));   // + a bump for the first 5 %: not exact on purpose
    }

    static double illumination(double f) { return (1 - Math.cos(2 * Math.PI * norm(f))) / 2; }

    private static float blurRadius(float sigma) { return Math.max(0.1f, (sigma - 0.5f) / 0.57735f); }
}
