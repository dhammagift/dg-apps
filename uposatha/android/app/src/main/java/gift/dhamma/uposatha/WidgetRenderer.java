package gift.dhamma.uposatha;

import android.content.Context;
import android.content.res.Resources;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.BlurMaskFilter;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RadialGradient;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.text.Layout;
import android.text.StaticLayout;
import android.text.TextPaint;
import android.text.TextUtils;

import androidx.core.graphics.ColorUtils;
import androidx.core.graphics.PathParser;

import org.json.JSONObject;

import java.util.HashMap;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Draws one layer of the Uposatha widget (design/README.md: 1 Uposatha + kala, 2 Day and night, 3 Month)
 * into a Bitmap, at one of three sizes (small 2x2, medium 4x2, large 4x4), light or dark.
 * Everything is laid out in dp on a scaled canvas, with the designer's numbers (widget.html, README section 6).
 * The widget draws what WidgetModel took from the page: no moon, sun or Uposatha maths here, except the moon's
 * shadow, which is geometry of a given phase (dg-moon-site.js: litPath / shadePath), not astronomy.
 */
final class WidgetRenderer {
    static final int SMALL = 0, MEDIUM = 1, LARGE = 2;
    static final int LAYERS = 3;

    private WidgetRenderer() {}

    /** Size class from the widget's size in dp: 2x2 and anything narrow is small, wide and tall is large, the rest medium. */
    static int sizeClass(int widthDp, int heightDp) {
        if (widthDp < 280) return SMALL;
        return heightDp >= 240 ? LARGE : MEDIUM;
    }

    /** Pixels per dp of the bitmap: the screen's own, but not beyond what a RemoteViews bitmap can afford. */
    static float scaleFor(Context ctx, int widthDp, int heightDp) { return scaleFor(ctx, widthDp, heightDp, 1.4e6f); }

    /** The same with the picture's pixel budget given (a RemoteViews with several sizes shares what one may carry). */
    static float scaleFor(Context ctx, int widthDp, int heightDp, float budgetPx) {
        float s = Math.min(ctx.getResources().getDisplayMetrics().density, 2.6f);
        while (s > 1f && (widthDp * s) * (heightDp * s) > budgetPx) s -= 0.2f;
        return Math.max(1f, s);
    }

    /** One layer (0, 1, 2) as a bitmap of widthDp x heightDp. data == null, stale or not covering today: the placeholder. */
    static Bitmap render(Context ctx, JSONObject data, int layer, int widthDp, int heightDp, boolean dark, long nowMs) {
        return render(ctx, data, layer, widthDp, heightDp, dark, nowMs, scaleFor(ctx, widthDp, heightDp));
    }

    static Bitmap render(Context ctx, JSONObject data, int layer, int widthDp, int heightDp, boolean dark, long nowMs, float scale) {
        Bitmap bmp = Bitmap.createBitmap(Math.round(widthDp * scale), Math.round(heightDp * scale), Bitmap.Config.ARGB_8888);
        Canvas c = new Canvas(bmp);
        c.scale(scale, scale);
        Painter p = new Painter(ctx, c, widthDp, heightDp, scale, dark);
        WidgetModel m = WidgetModel.parse(data, nowMs);
        try {
            if (m == null) p.placeholder(data);
            else p.layer(m, ((layer % LAYERS) + LAYERS) % LAYERS);
        } catch (RuntimeException e) {
            // A drawing that fails must not take the home screen with it: start over with the placeholder.
            c.drawColor(Color.TRANSPARENT, android.graphics.PorterDuff.Mode.CLEAR);
            new Painter(ctx, c, widthDp, heightDp, scale, dark).placeholder(data);
        }
        return bmp;
    }

    // ------------------------------------------------------------------ colours, fonts, moon photo

    private static final class Theme {
        final int surface, text, text2, muted, accent, accentInk, border, borderStrong, navyInk, vik, shade, glow;
        Theme(boolean dark) {
            if (dark) {
                surface = 0xFF191919; text = 0xFFDDDDDD; text2 = 0xFFA8A8A8; muted = 0xFF7C7C7C; accent = 0xFF136857;
                accentInk = 0xFF09967A; border = 0xFF2C2C2C; borderStrong = 0xFF3B3B3B; navyInk = 0xFFA9C4DC; vik = 0xFFD8546B;
                shade = 0xFF131C26;   // --dg-navy (#1b2836) 70% + black
                glow = 0xFFE9E4DC;
            } else {
                surface = 0xFFFFFFFF; text = 0xFF1B1D19; text2 = 0xFF5C6058; muted = 0xFF6E716A; accent = 0xFF149C7C;
                accentInk = 0xFF0F7C63; border = 0xFFE7E5DE; borderStrong = 0xFFD7D4C9; navyInk = 0xFF2F4A63; vik = 0xFF9B1C31;
                shade = 0xFF192432;   // --dg-navy (#243448) 70% + black
                glow = 0xFFE9E4DC;
            }
        }
        int mix(int top, float amount) { return ColorUtils.blendARGB(surface, top, amount); }
    }

    private static Typeface f400, f600, f700;

    private static synchronized void fonts(Context ctx) {
        if (f400 != null) return;
        try {
            f400 = Typeface.createFromAsset(ctx.getAssets(), "widget/lato-400.ttf");
            f600 = Typeface.createFromAsset(ctx.getAssets(), "widget/lato-600.ttf");
            f700 = Typeface.createFromAsset(ctx.getAssets(), "widget/lato-700.ttf");
        } catch (RuntimeException e) {
            f400 = Typeface.DEFAULT; f600 = Typeface.DEFAULT_BOLD; f700 = Typeface.DEFAULT_BOLD;   // never block the widget on a font
        }
    }

    private static Bitmap moonPhoto;
    private static final Map<Integer, Bitmap> moonScaled = new HashMap<>();

    /** The NASA photo (res/drawable-nodpi/moon_nasa.png, 420 px) halved step by step down to about px: no shimmer when small. */
    private static synchronized Bitmap moonTexture(Context ctx, int px) {
        px = Math.max(8, px);
        Bitmap hit = moonScaled.get(px);
        if (hit != null) return hit;
        if (moonPhoto == null) {
            BitmapFactory.Options o = new BitmapFactory.Options();
            o.inScaled = false;
            moonPhoto = BitmapFactory.decodeResource(ctx.getResources(), R.drawable.moon_nasa, o);
        }
        Bitmap b = moonPhoto;
        if (b == null) return null;
        while (b.getWidth() / 2 >= px) b = Bitmap.createScaledBitmap(b, b.getWidth() / 2, b.getHeight() / 2, true);
        if (b.getWidth() != px) b = Bitmap.createScaledBitmap(b, px, px, true);
        moonScaled.put(px, b);
        return b;
    }

    // ------------------------------------------------------------------ the moon (shadow geometry of dg-moon-site.js)

    /**
     * The month grid on a medium / large widget, in dp: {left, top, right, head height, row height} for the given number of weeks.
     * Shared by the picture and the tap targets (WidgetProvider sets the overlay's padding from it), so a number and its target coincide.
     */
    static float[] monthGeo(Context ctx, int cls, int wDp, int hDp, int rows) {
        Resources r = ctx.getResources();
        float d = r.getDisplayMetrics().density;
        if (cls == LARGE) {
            float top = r.getDimension(R.dimen.w_l_grid_top) / d, head = r.getDimension(R.dimen.w_l_grid_head) / d, pitch = r.getDimension(R.dimen.w_l_grid_pitch) / d;
            float rowH = Math.min(Math.max(pitch, 46), (hDp - top - head - 54) / rows);   // 54: the "next Uposatha" line and the dots under the grid; a tall phone gets taller rows (up to 46 dp) instead of an empty bottom
            return new float[] { r.getDimension(R.dimen.w_l_grid_left) / d, top, r.getDimension(R.dimen.w_l_grid_right) / d, head, rowH };
        }
        float top = r.getDimension(R.dimen.w_m_grid_top) / d, head = r.getDimension(R.dimen.w_m_grid_head) / d;
        float reserve = hDp < 150 ? 14 : r.getDimension(R.dimen.w_m_grid_reserve) / d;
        return new float[] { r.getDimension(R.dimen.w_m_grid_left) / d, top, r.getDimension(R.dimen.w_m_grid_right) / d, head, (hDp - top - head - reserve) / rows };
    }

    private static String num(double v) { return String.format(Locale.US, "%.3f", v); }

    private static double norm(double f) { return ((f % 1) + 1) % 1; }

    /** The shaded part of the disc in a 100x100 box (centre 50, R 48): terminator ellipse + the big arc beyond the rim. */
    static String shadePath(double f) {
        f = norm(f);
        final int C = 50, R = 48, B = 62;
        double k = Math.cos(2 * Math.PI * f);
        String rx = num(Math.abs(k) * R);
        boolean gib = k < 0, wax = f < 0.5;
        int ts = wax ? (gib ? 0 : 1) : (gib ? 1 : 0), bs = wax ? 1 : 0;
        return "M" + C + " " + (C - R) + "A" + rx + " " + R + " 0 0 " + ts + " " + C + " " + (C + R)
                + "L" + C + " " + (C + B) + "A" + B + " " + B + " 0 0 " + bs + " " + C + " " + (C - B) + "Z";
    }

    static double illumination(double f) { return (1 - Math.cos(2 * Math.PI * norm(f))) / 2; }

    private static float blurRadius(float sigma) { return Math.max(0.1f, (sigma - 0.5f) / 0.57735f); }

    // ------------------------------------------------------------------ the painter

    private static final class Painter {
        final Context ctx; final Canvas c; final float W, H, scale; final boolean dark;
        final Theme th;
        final TextPaint tp = new TextPaint(Paint.ANTI_ALIAS_FLAG);
        final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
        final Resources res;
        final float density;
        WidgetText tx;
        int cls;

        Painter(Context ctx, Canvas c, int w, int h, float scale, boolean dark) {
            this.ctx = ctx; this.c = c; this.W = w; this.H = h; this.scale = scale; this.dark = dark;
            this.th = new Theme(dark);
            this.res = ctx.getResources();
            this.density = res.getDisplayMetrics().density;
            this.cls = sizeClass(w, h);
            fonts(ctx);
        }

        // ---- text

        private void setup(float size, Typeface f, int color, float ls, boolean tnum) {
            tp.setTextSize(size); tp.setTypeface(f); tp.setColor(color); tp.setLetterSpacing(ls);
            tp.setFontFeatureSettings(tnum ? "tnum" : "");
        }

        float w(String s, float size, Typeface f, float ls, boolean tnum) {
            setup(size, f, 0, ls, tnum);
            return tp.measureText(s);
        }

        /** Draws s inside a line box [top, top+lh) starting at x; returns the advance. */
        float t(String s, float x, float top, float lh, float size, Typeface f, int color, float ls, boolean tnum) {
            if (s == null || s.isEmpty()) return 0;
            setup(size, f, color, ls, tnum);
            Paint.FontMetrics fm = tp.getFontMetrics();
            float base = top + (lh - (fm.descent - fm.ascent)) / 2f - fm.ascent;
            c.drawText(s, x, base, tp);
            return tp.measureText(s);
        }

        float t(String s, float x, float top, float size, Typeface f, int color) {
            return t(s, x, top, size * 1.2f, size, f, color, 0, false);
        }

        /** Right-aligned: the text ends at xr. */
        float tr(String s, float xr, float top, float lh, float size, Typeface f, int color, float ls, boolean tnum) {
            float width = w(s, size, f, ls, tnum);
            t(s, xr - width, top, lh, size, f, color, ls, tnum);
            return width;
        }

        /** s cut with an ellipsis to fit maxW. */
        String fit(String s, float maxW, float size, Typeface f, float ls, boolean tnum) {
            setup(size, f, 0, ls, tnum);
            if (tp.measureText(s) <= maxW) return s;
            for (int n = s.length() - 1; n > 0; n--) {   // own loop: measured with the same paint the text is drawn with
                String cut = s.substring(0, n).trim() + "\u2026";
                if (tp.measureText(cut) <= maxW) return cut;
            }
            return "";
        }

        // ---- frame, dots, labels

        void card() {
            fill.setStyle(Paint.Style.FILL);
            fill.setColor(th.surface);
            c.drawRoundRect(0, 0, W, H, 22, 22, fill);
        }

        float padL() { return cls == LARGE ? 18 : cls == MEDIUM ? 16 : 14; }
        float padT() { return cls == LARGE ? 18 : cls == MEDIUM ? 14 : 13; }
        float padB() { return cls == LARGE ? 12 : cls == MEDIUM ? 10 : 9; }

        /** Centre line of the dots: at the usual spot, a little lower on a short 4x2 so the content has room. */
        float dotsCy() { return cls == MEDIUM && H < 150 ? H - 9 : H - padB() - 8; }

        /** The layer switch: three wide segments (the current one in accent) between two chevrons; the left half of the strip goes back, the right half forward. */
        void dots(int active) {
            float cy = dotsCy(), seg = 22, gap = 6, h = 6, total = 3 * seg + 2 * gap, x = W / 2 - total / 2;
            for (int i = 0; i < 3; i++) {
                fill.setColor(i == active ? th.accentInk : th.borderStrong);
                c.drawRoundRect(x, cy - h / 2, x + seg, cy + h / 2, h / 2, h / 2, fill);
                x += seg + gap;
            }
            Paint ch = new Paint(Paint.ANTI_ALIAS_FLAG);
            ch.setStyle(Paint.Style.STROKE);
            ch.setStrokeWidth(1.8f);
            ch.setStrokeCap(Paint.Cap.ROUND);
            ch.setStrokeJoin(Paint.Join.ROUND);
            ch.setColor(th.muted);
            float lx = W / 2 - total / 2 - 20, rx = W / 2 + total / 2 + 20;
            Path l = new Path(); l.moveTo(lx + 3, cy - 5); l.lineTo(lx - 2, cy); l.lineTo(lx + 3, cy + 5);
            Path r = new Path(); r.moveTo(rx - 3, cy - 5); r.lineTo(rx + 2, cy); r.lineTo(rx - 3, cy + 5);
            c.drawPath(l, ch);
            c.drawPath(r, ch);
        }

        float lbSize() { return cls == LARGE ? 12.5f : 11.5f; }
        float lbLine() { return cls == LARGE ? 16 : 14; }

        /** The caps label in accent; returns its width. */
        float label(String s, float x, float top) { return label(s, x, top, 1000); }

        float label(String s, float x, float top, float maxW) {
            String up = s.toUpperCase(tx.ru() ? new Locale("ru") : Locale.US);
            return t(fit(up, maxW, lbSize(), f600, 0.1f, false), x, top, lbLine(), lbSize(), f600, th.accentInk, 0.1f, false);
        }

        Typeface f4() { return f400; }
        Typeface f6() { return f600; }
        Typeface f7() { return f700; }

        // ---- the moon

        void moon(float x, float y, float d, double phase, boolean south) {
            Bitmap tex = moonTexture(ctx, Math.round(d * scale * 0.972f));
            final float C = 50, R = 48;
            c.save();
            c.translate(x, y);
            c.scale(d / 100f, d / 100f);
            if (south) c.rotate(180, C, C);
            double I = illumination(phase);
            if (dark) {   // a halo under EVERY moon on a dark background (a new moon on black would be lost), a bit stronger as the moon fills
                Paint g = new Paint(Paint.ANTI_ALIAS_FLAG);
                g.setColor(ColorUtils.setAlphaComponent(th.glow, (int) Math.round(255 * (0.26 + 0.22 * I))));
                g.setMaskFilter(new BlurMaskFilter(blurRadius((float) (3 + 3.5 * I)), BlurMaskFilter.Blur.NORMAL));
                c.drawCircle(C, C, R + 1f, g);
            }
            Path disc = new Path();
            disc.addCircle(C, C, R, Path.Direction.CW);
            c.save();
            c.clipPath(disc);
            Paint tpnt = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
            if (tex != null) c.drawBitmap(tex, null, new RectF(C - R - .6f, C - R - .6f, C + R + .6f, C + R + .6f), tpnt);
            else { fill.setColor(0xFF9A968E); c.drawCircle(C, C, R, fill); }
            // Edge darkening: transparent to 50 %, then a little, then 42 % black at the rim.
            Paint edge = new Paint(Paint.ANTI_ALIAS_FLAG);
            edge.setShader(new RadialGradient(C, C, R, new int[] { 0x00000000, 0x24000000, 0x6B000000 }, new float[] { .5f, .86f, 1f }, Shader.TileMode.CLAMP));
            c.drawCircle(C, C, R, edge);
            // The shade: a wide penumbra (blur 4.5, 50 %) under a sharp edge (blur 1.3, 80 %), navy 70 % + black.
            Path shade = PathParser.createPathFromPathData(shadePath(phase));
            if (shade != null) {
                Paint pen = new Paint(Paint.ANTI_ALIAS_FLAG);
                pen.setColor(ColorUtils.setAlphaComponent(th.shade, 128));
                pen.setMaskFilter(new BlurMaskFilter(blurRadius(4.5f), BlurMaskFilter.Blur.NORMAL));
                c.drawPath(shade, pen);
                Paint sha = new Paint(Paint.ANTI_ALIAS_FLAG);
                sha.setColor(ColorUtils.setAlphaComponent(th.shade, 204));
                sha.setMaskFilter(new BlurMaskFilter(blurRadius(1.3f), BlurMaskFilter.Blur.NORMAL));
                c.drawPath(shade, sha);
            }
            c.restore();
            // A thin rim keeps a full moon on a white card.
            Paint rim = new Paint(Paint.ANTI_ALIAS_FLAG);
            rim.setStyle(Paint.Style.STROKE);
            rim.setStrokeWidth(.8f);
            rim.setColor(dark ? ColorUtils.setAlphaComponent(th.glow, Math.round(255 * .45f)) : ColorUtils.setAlphaComponent(th.navyInk, Math.round(255 * .22f)));
            c.drawCircle(C, C, R - .4f, rim);
            c.restore();
        }

        // ---- texts of the data

        String wd(String ymd) {
            return tx.weekday(WidgetFormat.dow(WidgetFormat.year(ymd), WidgetFormat.month(ymd), WidgetFormat.day(ymd)));
        }

        /** "сб 10" */
        String dayLabel(String ymd) { return wd(ymd) + " " + WidgetFormat.day(ymd); }

        /** "вс 11 окт" */
        String dateLabel(String ymd) { return dayLabel(ymd) + " " + tx.monthShort(WidgetFormat.month(ymd)); }

        String ordinal(int n) { return tx.ru() ? n + "-й" : n + "th"; }

        String phase(WidgetModel.Upo u) { return tx.get("phase." + u.phaseName); }

        String counter(long rem) { return WidgetFormat.counter(rem, tx.get("unit.d"), tx.get("unit.h")); }

        /** "до 14:30" / "until 14:30" without a day. */
        String untilTime(String hm) { return tx.get("lite.until").replace("{endDay}, ", "").replace("{endTime}", hm); }

        /** Text on a given baseline, in the ink colour; returns the advance. */
        float tb(String s, float x, float base, float size, Typeface f, float ls, boolean tnum) {
            setup(size, f, th.text, ls, tnum);
            c.drawText(s, x, base, tp);
            return tp.measureText(s);
        }

        // ---- the large moon + counter block

        /** The big counter "1 д 7 ч": digits at size, units 16 / 500 with the designer's margins; drawn in a line box of height size. */
        float counterRow(String d, String h, long rem, float x, float top, float size) {
            float cx = x;
            setup(size, f600, th.text, -0.01f, true);
            Paint.FontMetrics fm = tp.getFontMetrics();
            float base = top + (size - (fm.descent - fm.ascent)) / 2f - fm.ascent;
            long days = rem / WidgetFormat.DAY, hours = (Math.max(rem, 0) % WidgetFormat.DAY) / WidgetFormat.HOUR;
            if (rem < 0) { days = 0; hours = 0; }
            if (days > 0) {
                cx += tb(String.valueOf(days), cx, base, size, f600, -0.01f, true) + 3;
                cx += tb(d, cx, base, 16, f400, 0, false) + 8;
            }
            cx += tb(String.valueOf(hours), cx, base, size, f600, -0.01f, true) + 3;
            cx += tb(h, cx, base, 16, f400, 0, false);
            return cx - x;
        }

        // ---- kala / vikala line

        /** "Kala until 12:41 · 1 h 34 min left"; left == null for none. Returns width; draws when draw is true. */
        float kalaLine(WidgetModel m, float x, float top, float size, float maxW, boolean withLeft, boolean draw) {
            boolean vik = m.kala == WidgetModel.VIKALA;
            int accent = vik ? th.vik : th.accentInk;
            String tpl = tx.get(vik ? "vikala" : "kala");
            int at = tpl.indexOf("{time}");
            String head = at >= 0 ? tpl.substring(0, at) : tpl;
            int sp = head.indexOf(' ');
            String word = sp > 0 ? head.substring(0, sp) : head, mid = sp > 0 ? head.substring(sp) : "";
            String time = m.kalaEndHm;
            String extra = "";
            if (!m.placeSet && !vik) extra = " · " + tx.get("byClock");
            else if (withLeft && !vik) extra = " · " + tx.fmt("kalaLeft", "left", WidgetFormat.left(m.kalaEndMs - m.now, tx.get("unit.h"), tx.unitMin()));
            float lh = size * 1.2f, cx = x;
            String[] parts = { word, mid, time, extra };
            Typeface[] tf = { f700, f400, f600, f400 };
            int[] col = { accent, th.text, accent, th.text2 };
            for (int i = 0; i < 4; i++) {
                if (parts[i].isEmpty()) continue;
                float rest = x + maxW - cx;
                String s = i == 3 ? fit(parts[i], rest, size, tf[i], 0, true) : parts[i];
                float width = w(s, size, tf[i], 0, i == 2 || i == 3);
                if (draw) t(s, cx, top, lh, size, tf[i], col[i], 0, i == 2 || i == 3);
                cx += width;
            }
            return cx - x;
        }

        // ---- layer switch

        void layer(WidgetModel m, int layer) {
            tx = new WidgetText(ctx, m.lang);
            card();
            if (layer == 0) layer1(m);
            else if (layer == 1) layer2(m);
            else layer3(m);
            dots(layer);
        }

        // ================================================================== layer 1: Uposatha + kala

        void layer1(WidgetModel m) {
            WidgetModel.Upo u = m.cur();
            long rem = m.counterTarget() - m.now;
            boolean kalaOn = m.showKala && m.kala != WidgetModel.NONE;
            String to = m.ongoing ? tx.fmt("toNow", "n", u.lunarDay) : tx.fmt("to", "n", u.lunarDay);
            String lbl = tx.get(m.ongoing ? "layer.uposathaNow" : "layer.uposatha");
            String l1, l2 = null;   // the detail lines
            String startDay = dayLabel(u.start.ymd), endDay = dayLabel(u.end.ymd);
            if (m.detail) {
                l1 = tx.fmt("detail.phase", "phase", phase(u), "n", u.lunarDay);
                if (!m.placeSet) l2 = tx.get("noPlace.assumed");
                else if (m.ongoing) {
                    l2 = tx.fmt("detail.endNow", "endDay", endDay, "endTime", u.end.hm);
                    if (WidgetFormat.minutes(u.end.hm) >= 12 * 60) l2 = l2.replace("рассвет ", "").replace("dawn ", "");   // the page's end is an evening here, not a dawn
                } else l2 = tx.fmt("detail.span", "startDay", startDay, "startTime", u.start.hm, "endDay", endDay, "endTime", u.end.hm);
            } else if (m.ongoing) {
                l1 = tx.fmt("lite.until", "endDay", endDay, "endTime", u.end.hm);
            } else {
                l1 = tx.fmt("lite.from", "startDay", startDay, "startTime", u.start.hm);
                if (!m.placeSet) l1 += " · " + tx.get("noPlace.short");
            }
            if (cls == SMALL) layer1Small(m, u, rem, kalaOn, to, lbl);
            else if (cls == MEDIUM) layer1Medium(m, u, rem, kalaOn, to, lbl, l1, l2);
            else layer1Large(m, u, rem, kalaOn, to, lbl, l1, l2);
        }

        void layer1Small(WidgetModel m, WidgetModel.Upo u, long rem, boolean kalaOn, String to, String lbl) {
            float x = padL(), maxW = W - 2 * padL(), y = padT();
            label(lbl, x, y + 4, maxW - 28);
            moon(W - padL() - 22, y, 22, u.nominal(), m.south);
            y += 22 + 6;
            t(fit(to, maxW, 12, f600, 0, false), x, y, 14, 12, f600, th.text2, 0, false);
            y += 14;
            float big = kalaOn ? 34 : 40;
            counterRow(tx.get("unit.d"), tx.get("unit.h"), rem, x, y, big);
            y += big + 3;
            String sub;
            String startWd = wd(u.start.ymd), endWd = wd(u.end.ymd);
            if (m.ongoing) {
                sub = m.detail ? phase(u) + " · " + untilTime(u.end.hm)
                        : tx.get("lite.until").replace("{endDay}", endWd).replace("{endTime}", u.end.hm).replace(", ", " ");
            } else {
                sub = m.detail ? phase(u) + " · " + startWd + " " + u.start.hm
                        : tx.get("lite.from").replace("{startDay}", startWd).replace("{startTime}", u.start.hm).replace(", ", " ");
            }
            t(fit(sub, maxW, 12.5f, f400, 0, false), x, y, 15, 12.5f, f400, th.text2, 0, false);
            if (kalaOn) kalaLine(m, x, y + 15 + 7, 12, maxW, false, true);
        }

        void layer1Medium(WidgetModel m, WidgetModel.Upo u, long rem, boolean kalaOn, String to, String lbl, String l1, String l2) {
            float x = padL(), top = padT(), bottom = dotsCy() - 8 - 2;
            float md = kalaOn ? 66 : 76, bigS = kalaOn ? 38 : 44, tx0 = x + md + 16, maxW = W - padL() - tx0;
            // A short widget (4x2 is often ~130 dp, the design has 170): drop the second detail line, then the first, before squeezing the counter.
            float fixed = 14 + 2 + 16 + (kalaOn ? 4 + 15.6f : 0), avail = bottom - top;
            boolean show2 = l2 != null, show1 = true;
            if (fixed + bigS + 2 + 15.6f + (show2 ? 17 : 0) > avail) show2 = false;
            if (fixed + bigS + 2 + 15.6f > avail) show1 = false;
            bigS = Math.min(bigS, avail - fixed - (show1 ? 17.6f : 0));
            float h = fixed + bigS + (show1 ? 17.6f : 0) + (show2 ? 17 : 0);
            float y = top + Math.max(0, (avail - h) / 2);
            moon(x, top + (avail - md) / 2, md, m.moonNow, m.south);   // the moon as it is now
            float lw = label(lbl, tx0, y);
            t(fit("· " + dateLabel(u.start.ymd), maxW - lw - 8, 12, f600, 0.04f, false), tx0 + lw + 8, y, 14, 12, f600, th.muted, 0.04f, false);
            y += 14 + 2;
            t(fit(to, maxW, 13, f600, 0, false), tx0, y, 16, 13, f600, th.text2, 0, false);
            y += 16;
            counterRow(tx.get("unit.d"), tx.get("unit.h"), rem, tx0, y, bigS);
            y += bigS;
            if (show1) { t(fit(l1, maxW, 13, f600, 0, false), tx0, y + 2, 15.6f, 13, f600, th.text, 0, false); y += 17.6f; }
            if (show2) { t(fit(l2, maxW, 12.5f, f400, 0, false), tx0, y + 2, 15, 12.5f, f400, th.text2, 0, false); y += 17; }
            if (kalaOn) kalaLine(m, tx0, y + 4, 13, maxW, true, true);
        }

        void layer1Large(WidgetModel m, WidgetModel.Upo u, long rem, boolean kalaOn, String to, String lbl, String l1, String l2) {
            float x = padL(), maxW = W - 2 * padL(), y = padT();
            boolean tight = H < 340;   // the design has 382 dp; a 4x4 can be a good deal less
            if (tight) l2 = null;
            label(lbl, x, y);
            String mode = tx.get(m.bySuttas ? "mode.bySuttas" : "mode.notBySuttas");
            tr(mode, W - padL(), y, 16, 13.5f, f600, th.muted, 0.04f, false);
            y += 16 + 8;
            float md = (kalaOn ? 90 : 100) * (tight ? .86f : 1), bigS = (kalaOn ? 54 : 58) - (tight ? 8 : 0), tx0 = x + md + 16, tw = W - padL() - tx0;
            float colH = 19 + bigS + 4 + 18 + (l2 != null ? 3 + 16 : 0);
            float heroH = Math.max(md, colH);
            moon(x, y + (heroH - md) / 2, md, m.moonNow, m.south);   // the moon as it is now
            float cy = y + (heroH - colH) / 2;
            t(fit(to, tw, 15, f600, 0, false), tx0, cy, 19, 15, f600, th.text2, 0, false);
            cy += 19;
            counterRow(tx.get("unit.d"), tx.get("unit.h"), rem, tx0, cy, bigS);
            cy += bigS + 4;
            t(fit(l1, tw, 15, f600, 0, false), tx0, cy, 18, 15, f600, th.text, 0, false);
            cy += 18;
            if (l2 != null) t(fit(l2, tw, 13.5f, f400, 0, false), tx0, cy + 3, 16, 13.5f, f400, th.text2, 0, false);
            y += heroH;
            if (kalaOn) { kalaLine(m, x, y + 10, 15, maxW, true, true); y += 10 + 18; }
            float gap = tight ? 8 : 12;
            y += gap;
            fill.setColor(th.border);
            c.drawRect(x, y, W - padL(), y + 1, fill);
            y += 1 + gap;
            t(tx.get("next").toUpperCase(tx.ru() ? new Locale("ru") : Locale.US), x, y, lbLine(), lbSize(), f600, th.muted, 0.1f, false);
            y += 16 + (tight ? 6 : 8);
            // as many of the next three as fit above the dots
            int rows = (int) Math.max(0, Math.min(cls == LARGE ? 6 : 3, (dotsCy() - 8 - y + 9) / 33));   // a tall widget lists more of the next ones
            List<WidgetModel.Upo> next = m.following(rows);
            float dw = 0;   // a table, not a line of words: the date, the day and the "in N d" each have a column of their own
            for (WidgetModel.Upo n : next) dw = Math.max(dw, w(dateLabel(n.start.ymd), 16, f600, 0, true));
            for (WidgetModel.Upo n : next) {
                float rx = W - padL();
                String in = inText(m, n);
                float rw = tr(in, rx, y, 24, 14, f400, th.muted, 0, true);
                moon(x, y, 24, n.nominal(), m.south);
                float cx = x + 24 + 8;
                String date = dateLabel(n.start.ymd);   // the date it BEGINS on (the evening), as the app's own lists say
                t(date, cx, y, 24, 16, f600, th.text, 0, true);
                cx += dw + 14;
                String em = ordinal(n.lunarDay) + (m.detail ? " " + (tx.ru() ? "день" : "day") : "");
                t(fit(em, rx - rw - 8 - cx, 16, f400, 0, false), cx, y, 24, 16, f400, th.text2, 0, false);
                y += 24 + 9;
            }
        }

        /** "через 8 д" / "in 8 d" for a later Uposatha. */
        String inText(WidgetModel m, WidgetModel.Upo n) {
            long rem = n.start.ms - m.now, days = rem / WidgetFormat.DAY;
            if (days >= 1) return tx.fmt("inDays", "n", days);
            String in = tx.get("inDays");
            return in.substring(0, in.indexOf("{n}")) + counter(rem);   // under a day: "через 2 ч", not "через 0 д"
        }

        // ================================================================== layer 2: day and night

        void layer2(WidgetModel m) {
            if (m.partIdx < 0 || m.kala == WidgetModel.NONE) { notice(m); return; }
            WidgetModel.Day d = m.days.get(m.partDay);
            int k = m.partIdx;
            String pn = tx.get("part." + d.partName[k]);
            int dot = pn.indexOf(" · ");
            String name = dot > 0 ? pn.substring(0, dot) : pn;
            String desc = dot > 0 ? pn.substring(dot + 3) : null;
            if (desc != null && tx.ru() && "majjhanhika".equals(d.partName[k])) desc += " дня";
            String sub = (desc != null ? desc + " · " : "") + untilTime(d.partTo[k]);
            long left = m.kalaEndMs - m.now;
            String leftTxt = WidgetFormat.left(left, tx.get("unit.h"), tx.unitMin());
            String leftLine = tx.fmt("kalaLeft", "left", leftTxt);
            float x = padL(), maxW = W - 2 * padL(), y = padT();
            String lbl = tx.get("layer.daynight");
            if (cls == SMALL) {
                label(lbl, x, y);
                y += 14 + 8;
                t(fit(name, maxW, 18, f600, 0, false), x, y, 19.8f, 18, f600, th.text, 0, false);
                y += 19.8f + 3;
                t(fit(untilTime(d.partTo[k]), maxW, 13, f400, 0, false), x, y, 16, 13, f400, th.text2, 0, false);
                y += 16 + 6;
                kalaLine2(m, x, y, 12.5f, maxW, true);
                y += 15 + 12;
                dayBar(m, d, k, x, y, maxW, 8);
                y += 8 + 5;
                ticks(d, x, y, maxW, 11.5f, false);
                return;
            }
            boolean big = cls == LARGE, tight = cls == MEDIUM && H < 150;
            label(lbl, x, y);
            tr(big ? dateLabel(m.today) : tx.get("now"), W - padL(), y, big ? 16 : 14, big ? 13.5f : 12, f600, th.muted, 0.04f, false);
            float ns = big ? 28 : 24, ss = big ? 14 : 13, ks = big ? 15 : 13, kss = big ? 13 : 12;
            float top2 = y + (big ? 16 : 14);
            // right column: kala / vikala with the time left under it
            float rw = Math.max(kalaLine2(m, 0, 0, ks, 1000, false), w(leftLine, kss, f400, 0, true));
            float rx = W - padL();
            float ky = top2 + 10;
            kalaLineRight(m, rx, ky, ks);
            tr(leftLine, rx, ky + ks * 1.2f + 2, kss * 1.2f, kss, f400, th.text2, 0, true);
            float lwid = maxW - rw - 12;
            float ny = top2 + (tight ? 4 : 8);
            float nsz = ns;
            while (nsz > 17 && w(name, nsz, f600, 0, false) > lwid) nsz -= 1;   // a long name first gets smaller, then cut
            t(fit(name, lwid, nsz, f600, 0, false), x, ny, ns * 1.1f, nsz, f600, th.text, 0, false);
            t(fit(sub, lwid, ss, f400, 0, false), x, ny + ns * 1.1f + 3, ss * 1.2f, ss, f400, th.text2, 0, false);
            float bottom = ny + ns * 1.1f + 3 + ss * 1.2f;
            bottom = Math.max(bottom, ky + ks * 1.2f + 2 + kss * 1.2f);
            float by = bottom + (tight ? 8 : 12);
            float bh = big ? 10 : tight ? 10 : 12;
            dayBar(m, d, k, x, by, maxW, bh);
            ticks(d, x, by + bh + (tight ? 4 : 5), maxW, 11.5f, true);
            if (big) partsList(m, d, k, x, by + bh + 5 + 14 + 10, maxW, dotsCy() - 8);
        }

        /** Kala line for layer 2 (always on): same runs as layer 1's, no "left" (it sits on its own line). Returns the width. */
        float kalaLine2(WidgetModel m, float x, float top, float size, float maxW, boolean draw) {
            boolean vik = m.kala == WidgetModel.VIKALA;
            int accent = vik ? th.vik : th.accentInk;
            String tpl = tx.get(vik ? "vikala" : "kala");
            int at = tpl.indexOf("{time}");
            String head = at >= 0 ? tpl.substring(0, at) : tpl;
            int sp = head.indexOf(' ');
            String word = sp > 0 ? head.substring(0, sp) : head, mid = sp > 0 ? head.substring(sp) : "";
            String[] parts = { word, mid, m.kalaEndHm };
            Typeface[] tf = { f700, f400, f600 };
            int[] col = { accent, th.text, accent };
            float cx = x;
            for (int i = 0; i < 3; i++) {
                if (parts[i].isEmpty()) continue;
                if (draw) t(parts[i], cx, top, size * 1.2f, size, tf[i], col[i], 0, i == 2);
                cx += w(parts[i], size, tf[i], 0, i == 2);
            }
            return cx - x;
        }

        void kalaLineRight(WidgetModel m, float xr, float top, float size) {
            float wd = kalaLine2(m, 0, 0, size, 1000, false);
            kalaLine2(m, xr - wd, top, size, 1000, true);
        }

        /** The day: six parts from sunrise to sunrise, three of day and three of night, the current one solid; a 2 px mark for now. */
        void dayBar(WidgetModel m, WidgetModel.Day d, int cur, float x, float y, float width, float h) {
            long t0 = d.partStart[0], t1 = d.partEnd[5];
            float usable = width - 5 * 2, cx = x;
            c.save();
            Path clip = new Path();
            clip.addRoundRect(new RectF(x, y, x + width, y + h), h / 2, h / 2, Path.Direction.CW);
            c.clipPath(clip);
            for (int k = 0; k < 6; k++) {
                float sw = usable * (d.partEnd[k] - d.partStart[k]) / (float) (t1 - t0);
                fill.setColor(k == cur ? th.accent : k < 3 ? th.mix(th.accent, .28f) : th.mix(th.navyInk, .30f));
                c.drawRect(cx, y, cx + sw, y + h, fill);
                cx += sw + 2;
            }
            c.restore();
            float f = Math.max(0, Math.min(1, (m.now - t0) / (float) (t1 - t0)));
            float mx = x + 1 + f * (width - 2);
            fill.setColor(th.text);
            c.drawRoundRect(mx - 1, y - 3, mx + 1, y + h + 3, 1, 1, fill);
        }

        void ticks(WidgetModel.Day d, float x, float y, float width, float size, boolean full) {
            String[] s;
            if (!full) s = new String[] { d.partFrom[0], d.sunset.hm };
            else s = new String[] { d.partFrom[0] + " " + tx.get("sunrise"), d.noon.hm + " " + tx.get("noon"), d.sunset.hm + " " + tx.get("sunset"), d.partTo[5] };
            float sum = 0;
            float[] ws = new float[s.length];
            for (int i = 0; i < s.length; i++) { ws[i] = w(s[i], size, f400, 0, true); sum += ws[i]; }
            float gap = s.length > 1 ? Math.max(4, (width - sum) / (s.length - 1)) : 0, cx = x;
            for (int i = 0; i < s.length; i++) {
                t(s[i], cx, y, size * 1.2f, size, f400, th.muted, 0, true);
                cx += ws[i] + gap;
            }
        }

        /** The six parts with their borders; when the widget is not tall enough, the three of the current half (day or night). */
        void partsList(WidgetModel m, WidgetModel.Day d, int cur, float x, float y, float width, float limit) {
            float rowH = 15 * 1.2f + 10;
            boolean all = y + 6 * rowH + 5 * 2 + 9 <= limit;
            if (all) { float spare = limit - (y + 6 * (rowH + 2) + 9); if (spare > 0) rowH += Math.min(14, spare / 6); }   // the spare height goes into taller rows
            int from = all ? 0 : cur < 3 ? 0 : 3, to = all ? 6 : from + 3;
            for (int k = from; k < to; k++) {
                String pn = tx.get("part." + d.partName[k]);
                if (k == cur) {
                    fill.setColor(th.mix(th.navyInk, .22f));
                    c.drawRoundRect(x, y, x + width, y + rowH, 10, 10, fill);
                }
                Typeface tf = k == cur ? f600 : f400;
                String times = d.partFrom[k] + "\u2013" + d.partTo[k];
                float tw = tr(times, x + width - 10, y + 5, 18, 15, tf, k == cur ? th.text : th.muted, 0, true);
                t(fit(pn, width - 20 - tw - 8, 15, tf, 0, false), x + 10, y + 5, 18, 15, tf, th.text, 0, false);
                y += rowH + 2;
                if (all && k == 2) {
                    fill.setColor(th.border);
                    c.drawRect(x + 10, y + 4, x + width - 10, y + 5, fill);
                    y += 9;
                }
            }
        }

        // ================================================================== layer 3: month

        void layer3(WidgetModel m) {
            int[] mo = WidgetModel.month(m.today, m.weekStart);   // year, month, offset, days, rows
            float x = padL(), y = padT();
            String monthName = tx.monthName(mo[1]);
            if (cls == SMALL) {
                label(monthName, x, y);
                y += 14 + 8;
                weekHeader(x, y, W - 2 * padL(), 10.5f, 14, m);
                y += 14 + 2;
                // two weeks: the one with today and the next, whatever month they fall in
                int off = WidgetModel.column(WidgetFormat.dow(WidgetFormat.year(m.today), WidgetFormat.month(m.today), WidgetFormat.day(m.today)), m.weekStart);
                long start = WidgetFormat.daysFromCivil(WidgetFormat.year(m.today), WidgetFormat.month(m.today), WidgetFormat.day(m.today)) - off;
                float colW = (W - 2 * padL()) / 7f;
                for (int r = 0; r < 2; r++) {
                    for (int cI = 0; cI < 7; cI++) {
                        String ymd = WidgetFormat.ymdFromDays(start + r * 7 + cI);
                        cell(m, ymd, x + cI * colW, y, colW, 17, 11.5f, 8.5f);
                    }
                    y += 19;
                }
                y += 6;
                WidgetModel.Upo u = m.cur();
                String line = wd(u.start.ymd) + " " + WidgetFormat.day(u.start.ymd) + " · " + ordinal(u.lunarDay) + " " + (tx.ru() ? "день" : "day");
                t(fit(line, W - 2 * padL(), 12.5f, f700, 0, false), x, y, 15, 12.5f, f700, th.text, 0, false);
                return;
            }
            boolean big = cls == LARGE;
            if (big) {
                label(monthName + " " + mo[0], x, y);
                int cnt = 0;
                for (WidgetModel.Upo u : m.upos) if (u.day.startsWith(String.format(Locale.US, "%04d-%02d", mo[0], mo[1]))) cnt++;
                tr(WidgetFormat.uposathas(tx.lang, cnt), W - padL(), y, 16, 13.5f, f600, th.muted, 0.04f, false);
            } else {
                label(monthName, x, y);
                float ly = y + 14 + 10;
                List<WidgetModel.Upo> ups = m.upos.subList(m.curIdx, Math.min(m.upos.size(), m.curIdx + 3));
                float dw2 = 0;
                for (WidgetModel.Upo n : ups) dw2 = Math.max(dw2, w(dayLabel(n.start.ymd), 14, f600, 0, true));
                for (WidgetModel.Upo n : ups) {
                    moon(x, ly, 20, n.nominal(), m.south);
                    float cx = x + 20 + 8;
                    t(dayLabel(n.start.ymd), cx, ly, 20, 14, f600, th.text, 0, true);
                    t(fit(ordinal(n.lunarDay), 132 - 20 - 8 - dw2 - 8, 14, f400, 0, false), cx + dw2 + 10, ly, 20, 14, f400, th.text2, 0, false);
                    ly += 20 + 8;
                }
            }
            float[] g = monthGeo(ctx, cls, (int) W, (int) H, mo[4]);   // left, top, right, head, row height
            float gl = g[0], gt = g[1], gh = g[3], rowH = g[4];
            float gw = W - gl - g[2], colW = gw / 7f;
            weekHeader(gl, gt, gw, big ? 11.5f : 10.5f, gh, m);
            float pill = big ? Math.min(36, rowH - 4) : Math.min(rowH - 2, 20);
            for (int r = 0; r < mo[4]; r++) {
                for (int cI = 0; cI < 7; cI++) {
                    int dd = r * 7 + cI - mo[2] + 1;
                    if (dd < 1 || dd > mo[3]) continue;
                    cell(m, WidgetModel.ymd(mo[0], mo[1], dd), gl + cI * colW, gt + gh + r * rowH + (rowH - pill) / 2, colW, pill, big ? (rowH > 40 ? 17 : 15) : 12, pill / 2);
                }
            }
            if (big) {
                // Under the grid, as far as the height goes: the Uposathas that are on and next, then today (sun, moon). The widget is the
                // biggest one: what the app shows on its home screen is here too, not an empty bottom.
                float ry = gt + gh + mo[4] * rowH + 8;
                float bottom = dotsCy() - 12;
                float rx = W - padL(), step = 28, todayH = 66;
                fill.setColor(th.border);
                c.drawRect(x, ry - 4, rx, ry - 3, fill);
                float room = bottom - ry;
                boolean today = room >= todayH + step + 8;
                int rowsN = (int) Math.max(1, Math.min(4, (room - (today ? todayH + 6 : 0)) / step));
                List<WidgetModel.Upo> list = new ArrayList<>();
                list.add(m.cur());
                list.addAll(m.following(rowsN - 1));
                float dw3 = 0;
                for (WidgetModel.Upo u : list) dw3 = Math.max(dw3, w(dateLabel(u.start.ymd), 15, f600, 0, true));
                for (int i = 0; i < list.size(); i++) {
                    WidgetModel.Upo u = list.get(i);
                    String right = i == 0 && m.ongoing ? tx.get("now") : inText(m, u);
                    float rw = tr(right, rx, ry, 24, 14, f400, th.muted, 0, true);
                    moon(x, ry + 1, 20, u.nominal(), m.south);
                    float cx = x + 20 + 8;
                    t(dateLabel(u.start.ymd), cx, ry, 24, 15, f600, th.text, 0, true);
                    String em = ordinal(u.lunarDay) + " \u00b7 " + phase(u);
                    t(fit(em, rx - rw - 8 - cx - dw3 - 12, 15, f400, 0, false), cx + dw3 + 12, ry, 24, 15, f400, th.text2, 0, false);
                    ry += step;
                }
                if (today) {
                    ry += 2;
                    WidgetModel.Day d = m.dayIdx >= 0 ? m.days.get(m.dayIdx) : null;
                    double lit = (1 - Math.cos(2 * Math.PI * m.moonNow)) / 2;
                    boolean waxing = m.moonNow < 0.5;
                    String ph = tx.ru() ? (waxing ? "растёт" : "убывает") : (waxing ? "waxing" : "waning");
                    String lt = tx.ru() ? "освещено" : "lit";
                    label(tx.ru() ? "СЕГОДНЯ" : "TODAY", x, ry);
                    ry += lbLine() + 4;
                    if (d != null) {
                        String sun = tx.get("sunrise") + " " + d.sunrise.hm + "  \u00b7  " + tx.get("noon") + " " + d.noon.hm + "  \u00b7  " + tx.get("sunset") + " " + d.sunset.hm;
                        t(fit(sun, rx - x, 14, f400, 0, true), x, ry, 20, 14, f400, th.text, 0, true);
                        ry += 22;
                    }
                    t(fit(ph + " \u00b7 " + Math.round(lit * 100) + "% " + lt, rx - x, 14, f400, 0, false), x, ry, 20, 14, f400, th.text2, 0, false);
                }
            }
        }

        void weekHeader(float x, float y, float width, float size, float h, WidgetModel m) {
            float colW = width / 7f;
            for (int i = 0; i < 7; i++) {
                String s = tx.weekday(m.weekStart == 0 ? (i + 6) % 7 : i);
                if (!tx.ru()) s = s.substring(0, 2);
                float sw = w(s, size, f600, 0, false);
                t(s, x + i * colW + (colW - sw) / 2, y, h, size, f600, th.muted, 0, false);
            }
        }

        /** One day cell of a grid. The Uposatha: its evening-before cell solid, its day a light band joined to it; today ringed. */
        void cell(WidgetModel m, String ymd, float x, float y, float colW, float h, float size, float rad) {
            int day = WidgetFormat.day(ymd);
            boolean today = ymd.equals(m.today), past = ymd.compareTo(m.today) < 0;
            WidgetModel.Upo startOf = m.startingOn(ymd), dayOf = m.uposathaOn(ymd);
            int col = WidgetModel.column(WidgetFormat.dow(WidgetFormat.year(ymd), WidgetFormat.month(ymd), day), m.weekStart);   // 0 = the week's first day
            int textColor = past ? th.muted : th.text;
            Typeface tf = f400;
            RectF r = new RectF(x, y, x + colW, y + h);
            float[] radii = null;
            // The strip: an evening-start cell (solid) and the day after it (light) are one band; a cell is square on the side that joins
            // the next one, unless the row ends there. A date that is the day of one Uposatha and the start of the next (14th, 15th) is
            // joined on both sides.
            boolean joinRight = startOf != null && col < 6 && WidgetFormat.daysBetween(ymd, startOf.day) == 1;
            boolean joinLeft = dayOf != null && !dayOf.start.ymd.equals(dayOf.day) && col > 0 && WidgetFormat.daysBetween(dayOf.start.ymd, ymd) == 1;
            if (startOf != null || dayOf != null) {
                float l = joinLeft ? 0 : rad, rr = joinRight ? 0 : rad;
                radii = new float[] { l, l, rr, rr, rr, rr, l, l };
                Path p = new Path(); p.addRoundRect(r, radii, Path.Direction.CW);
                if (startOf != null) { fill.setColor(th.accent); textColor = 0xFFFFFFFF; tf = f600; }
                else { fill.setColor(th.mix(th.accent, .30f)); textColor = th.accentInk; tf = f600; }
                c.drawPath(p, fill);
            }
            if (today) {
                Paint ring = new Paint(Paint.ANTI_ALIAS_FLAG);
                ring.setStyle(Paint.Style.STROKE);
                ring.setStrokeWidth(1.5f);
                ring.setColor(th.text);
                // The ring is inset and fully rounded: inside a strip it does not meet the straight joins of the band.
                float in = radii != null ? 2.2f : .75f;
                c.drawRoundRect(new RectF(x + in, y + in, x + colW - in, y + h - in), Math.max(2, rad - in + .75f), Math.max(2, rad - in + .75f), ring);
                tf = f700;
                if (startOf == null && dayOf == null) textColor = th.text;
            }
            String s = String.valueOf(day);
            float sw = w(s, size, tf, 0, true);
            t(s, x + (colW - sw) / 2, y, h, size, tf, textColor, 0, true);
        }

        // ================================================================== placeholder and notices

        void notice(WidgetModel m) {
            // Day & night needs the parts of the day, which the data does not cover right now (e.g. just before the first dawn).
            tx = new WidgetText(ctx, m.lang);
            placeholderBody(m.lang, true);
        }

        void placeholder(JSONObject data) {
            String lang = null;
            if (data != null) {
                JSONObject st = data.optJSONObject("settings");
                if (st != null) lang = st.optString("lang", null);
                if (lang == null) lang = "en";
            }
            if (lang == null) lang = Locale.getDefault().getLanguage();
            tx = new WidgetText(ctx, "ru".equals(lang) ? "ru" : "en");
            card();
            placeholderBody(tx.lang, data != null);
        }

        void placeholderBody(String lang, boolean stale) {
            boolean ru = "ru".equals(lang);
            String title = ru ? "Откройте Uposatha" : "Open Uposatha";
            String body = stale ? (ru ? "Данные устарели" : "The data is out of date") : (ru ? "Нужны данные для виджета" : "To set up the widget");
            float md = cls == LARGE ? 96 : cls == MEDIUM ? 64 : 40;
            float x = padL();
            if (cls == SMALL) {
                moon(x, padT(), md, 0.5, false);
                float y = padT() + md + 12;
                float tsz = 15;
                t(fit(title, W - 2 * x, tsz, f700, 0, false), x, y, 19, tsz, f700, th.text, 0, false);
                bodyText(body, x, y + 21, W - 2 * x, 12.5f);
            } else {
                float tx0 = x + md + 18, cy = H / 2;
                moon(x, cy - md / 2, md, 0.5, false);
                float tsz = cls == LARGE ? 22 : 18;
                float ty = cy - (tsz * 1.25f + 24) / 2;
                t(fit(title, W - tx0 - x, tsz, f700, 0, false), tx0, ty, tsz * 1.25f, tsz, f700, th.text, 0, false);
                bodyText(body, tx0, ty + tsz * 1.25f + 3, W - tx0 - x, 13.5f);
            }
        }

        void bodyText(String s, float x, float y, float width, float size) {
            tp.setTextSize(size); tp.setTypeface(f400); tp.setColor(th.text2); tp.setLetterSpacing(0); tp.setFontFeatureSettings("");
            StaticLayout sl = StaticLayout.Builder.obtain(s, 0, s.length(), tp, Math.max(1, Math.round(width)))
                    .setAlignment(Layout.Alignment.ALIGN_NORMAL).setMaxLines(2).setEllipsize(TextUtils.TruncateAt.END).build();
            c.save();
            c.translate(x, y);
            sl.draw(c);
            c.restore();
        }
    }
}
