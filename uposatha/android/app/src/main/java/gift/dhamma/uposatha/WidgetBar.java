package gift.dhamma.uposatha;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;

/**
 * The day bar of the "Day & night" widget as a picture: six parts from dawn to dawn, each as wide as it lasts, the current one in the
 * accent, a mark at "now". A picture (like the moon) because the parts' widths are the data's, and a widget's views cannot be given
 * proportional widths at run time; the gaps between the parts are transparent, so the bar is right on a translucent card too.
 */
final class WidgetBar {
    private WidgetBar() {}

    /** The bar's own height in the picture, and the picture's height (the "now" mark sticks out above and below), in base dp. */
    static final float BAR = 9, HEIGHT = 13;

    /** parts: WidgetPlan.barParts (start, end as shares 0..1); cur: the part that is on (-1 none); now: 0..1. The picture is wDp wide on any screen. */
    static Bitmap render(Context ctx, float wDp, float scale, float[] parts, int cur, float now, int dayColor, int nightColor, int curColor, int markColor) {
        float density = Math.min(ctx.getResources().getDisplayMetrics().density, 2f);
        float hDp = HEIGHT * scale;
        int w = Math.max(8, Math.round(wDp * density)), h = Math.max(4, Math.round(hDp * density));
        Bitmap bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
        Canvas c = new Canvas(bmp);
        float u = density * scale, top = (HEIGHT - BAR) / 2 * u, bottom = top + BAR * u, gap = 2 * u, rOut = BAR / 2 * u, rIn = 2 * u;
        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        int n = parts.length / 2;
        for (int k = 0; k < n; k++) {
            float x0 = parts[2 * k] * w + (k == 0 ? 0 : gap / 2), x1 = parts[2 * k + 1] * w - (k == n - 1 ? 0 : gap / 2);
            if (x1 <= x0) continue;
            p.setColor(k == cur ? curColor : k < n / 2 ? dayColor : nightColor);
            float l = k == 0 ? rOut : rIn, r = k == n - 1 ? rOut : rIn;
            Path path = new Path();
            path.addRoundRect(new RectF(x0, top, x1, bottom), new float[] { l, l, r, r, r, r, l, l }, Path.Direction.CW);
            c.drawPath(path, p);
        }
        p.setColor(markColor);
        float mx = Math.max(u, Math.min(w - u, now * w));
        c.drawRoundRect(new RectF(mx - u, 0, mx + u, h), u, u, p);
        bmp.setDensity(Math.max(1, Math.round(160f * w / wDp)));
        return bmp;
    }
}
