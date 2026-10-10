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
 * halo, so a new moon does not vanish on black. The bitmap is SQUARE and the disc sits in the middle of it with a margin for the
 * halo, so an ImageView with scaleType fitCenter can show it at any size without squeezing it.
 */
final class WidgetMoon {
    private WidgetMoon() {}

    /** The share of the bitmap's side that the disc takes (the rest is the halo's room). */
    static final float DISC = 0.80f;

    private static final int GLOW = 0xFFE9E4DC;
    private static Bitmap photo;
    private static final Map<Integer, Bitmap> scaled = new HashMap<>();
    private static final Map<String, Bitmap> cache = new HashMap<>();

    /** A square moon for a view of about sizeDp (the picture has the screen's own pixel density, so it is never blown up). */
    static synchronized Bitmap render(Context ctx, int sizeDp, double phase, boolean south, boolean dark) {
        float density = Math.min(ctx.getResources().getDisplayMetrics().density, 2f);   // a widget picture is small; the launcher refuses an update that carries too many big ones
        int px = Math.max(16, Math.round(sizeDp * density));
        String key = px + "/" + Math.round(phase * 1000) + "/" + south + "/" + dark;
        Bitmap hit = cache.get(key);
        if (hit != null) return hit;
        if (cache.size() > 160) cache.clear();   // the grid of sizes shares these (one picture per size and phase); the RemoteViews hold their own references
        Bitmap b = draw(ctx, px, sizeDp < 50, phase, south, dark);
        cache.put(key, b);
        return b;
    }

    private static Bitmap draw(Context ctx, int px, boolean small, double phase, boolean south, boolean dark) {
        Bitmap bmp = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888);
        Canvas c = new Canvas(bmp);
        final float C = 50, R = 48;
        float k = px * DISC / (2 * R);   // pixels per unit of the 100 x 100 box the geometry is written in
        c.translate(px / 2f - C * k, px / 2f - C * k);
        c.scale(k, k);
        if (south) c.rotate(180, C, C);
        double I = illumination(phase);
        if (dark) {   // a halo under EVERY moon on a dark background (a new moon on black would be lost), a bit stronger as the moon fills
            Paint g = new Paint(Paint.ANTI_ALIAS_FLAG);
            g.setColor(ColorUtils.setAlphaComponent(GLOW, (int) Math.round(255 * (0.26 + 0.22 * I))));
            g.setMaskFilter(new BlurMaskFilter(blurRadius((float) (3 + 3.5 * I)), BlurMaskFilter.Blur.NORMAL));
            c.drawCircle(C, C, R + 1f, g);
        }
        Path disc = new Path();
        disc.addCircle(C, C, R, Path.Direction.CW);
        c.save();
        c.clipPath(disc);
        Bitmap tex = texture(ctx, Math.round(97.2f * k));
        Paint tpnt = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
        // The picture itself is warm (the NASA photo, sepia + saturation + brightness, variant B of the owner's choice, 2026-10-10);
        // at list sizes it is a little brighter still, so it does not read as one more row of text.
        if (small) tpnt.setColorFilter(new android.graphics.ColorMatrixColorFilter(new float[] { 1.12f, 0, 0, 0, 14, 0, 1.12f, 0, 0, 12, 0, 0, 1.12f, 0, 8, 0, 0, 0, 1, 0 }));
        if (tex != null) c.drawBitmap(tex, null, new RectF(C - R - .6f, C - R - .6f, C + R + .6f, C + R + .6f), tpnt);
        else { Paint f = new Paint(Paint.ANTI_ALIAS_FLAG); f.setColor(0xFF9A968E); c.drawCircle(C, C, R, f); }
        // Edge darkening: transparent to 50 %, then a little, then 42 % black at the rim (a small moon keeps its brightness to the rim).
        Paint edge = new Paint(Paint.ANTI_ALIAS_FLAG);
        edge.setShader(new RadialGradient(C, C, R, small ? new int[] { 0x00000000, 0x10000000, 0x30000000 } : new int[] { 0x00000000, 0x24000000, 0x6B000000 }, new float[] { .5f, .86f, 1f }, Shader.TileMode.CLAMP));
        c.drawCircle(C, C, R, edge);
        // The shade: a wide penumbra (blur 4.5, 50 %) under a sharp edge (blur 1.3, 80 %), navy 70 % + black.
        int shadeColor = dark ? 0xFF131C26 : 0xFF192432;
        Path shade = PathParser.createPathFromPathData(shadePath(phase));
        if (shade != null) {
            Paint pen = new Paint(Paint.ANTI_ALIAS_FLAG);
            pen.setColor(ColorUtils.setAlphaComponent(shadeColor, 128));
            pen.setMaskFilter(new BlurMaskFilter(blurRadius(4.5f), BlurMaskFilter.Blur.NORMAL));
            c.drawPath(shade, pen);
            Paint sha = new Paint(Paint.ANTI_ALIAS_FLAG);
            sha.setColor(ColorUtils.setAlphaComponent(shadeColor, 204));
            sha.setMaskFilter(new BlurMaskFilter(blurRadius(1.3f), BlurMaskFilter.Blur.NORMAL));
            c.drawPath(shade, sha);
        }
        c.restore();
        // A thin rim keeps a full moon on a white card.
        Paint rim = new Paint(Paint.ANTI_ALIAS_FLAG);
        rim.setStyle(Paint.Style.STROKE);
        rim.setStrokeWidth(.8f);
        rim.setColor(dark ? ColorUtils.setAlphaComponent(GLOW, Math.round(255 * .45f)) : ColorUtils.setAlphaComponent(0xFF2F4A63, Math.round(255 * .22f)));
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
    static double seen(double a) { return 1 - Math.pow(1 - Math.min(1, Math.max(0, a)), 0.6); }

    static double illumination(double f) { return (1 - Math.cos(2 * Math.PI * norm(f))) / 2; }

    private static float blurRadius(float sigma) { return Math.max(0.1f, (sigma - 0.5f) / 0.57735f); }
}
