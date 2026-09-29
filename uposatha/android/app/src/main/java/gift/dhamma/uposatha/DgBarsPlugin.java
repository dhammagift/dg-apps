package gift.dhamma.uposatha;

import android.app.Activity;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ColorFilter;
import android.graphics.Paint;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.graphics.drawable.Drawable;
import android.view.View;

import androidx.core.view.WindowInsetsControllerCompat;

import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

/**
 * The strips around the page — behind the status bar, the gesture bar, and the camera cutout in
 * landscape — in the page's own colours (owner, dg-apps#40: "зачем борода? давай отключим").
 * They are the window background showing through the insets Capacitor's SystemBars pads the page
 * away from, so the fixed navy there (@color/dg_navbar) read as a frame round every screen. The
 * bridge script reports the colour at the page's top edge and of its body; this paints the
 * status-bar strip with the first, everything else with the second, and matches the icons.
 * Same file in all three apps (only the package differs).
 *
 * Quiet on purpose (380 made the page jump when it opened, owner): one drawable for the life of
 * the window whose colours change and which only repaints, never a new background (that re-lays
 * the whole window out), and the icon appearance is touched only when it actually flips.
 */
@CapacitorPlugin(name = "DgBars")
public class DgBarsPlugin extends Plugin {
    // null until the page has reported: the theme's colour and icons stay as they were.
    private static Integer top, rest;
    // How far down the page the top colour reaches (a navy header, in dp): the side strips of a
    // landscape cutout carry it that far too, so the header does not end in a white notch.
    private static float band;

    @PluginMethod
    public void set(PluginCall call) {
        final int t, r;
        final float b;
        try {
            t = Color.parseColor(call.getString("top"));
            r = Color.parseColor(call.getString("bottom"));
            b = call.getFloat("band", 0f);
        } catch (Exception e) {
            call.reject("bad colour");
            return;
        }
        if (top != null && top == t && rest == r && band == b) {
            call.resolve();
            return;
        }
        top = t;
        rest = r;
        band = b;
        getActivity().runOnUiThread(() -> {
            apply(getActivity());
            call.resolve();
        });
    }

    /**
     * Also called on resume, focus and configuration changes: SystemBars may have put the theme's
     * window background back on the decor view there. False before the page has reported anything.
     */
    static boolean apply(Activity activity) {
        if (top == null) return false;
        View decor = activity.getWindow().getDecorView();
        float density = activity.getResources().getDisplayMetrics().density;
        if (decor.getBackground() instanceof Strips) {
            ((Strips) decor.getBackground()).set(top, rest, band * density);   // repaint only
        } else {
            decor.setBackground(new Strips(decor, top, rest, band * density));
        }
        WindowInsetsControllerCompat icons = new WindowInsetsControllerCompat(activity.getWindow(), decor);
        boolean lightTop = !isDark(top), lightRest = !isDark(rest);
        if (icons.isAppearanceLightStatusBars() != lightTop) icons.setAppearanceLightStatusBars(lightTop);
        if (icons.isAppearanceLightNavigationBars() != lightRest) icons.setAppearanceLightNavigationBars(lightRest);
        return true;
    }

    private static boolean isDark(int c) {
        return 0.299 * Color.red(c) + 0.587 * Color.green(c) + 0.114 * Color.blue(c) < 150;
    }

    /** The decor's background: the status-bar strip (its top padding) in one colour, the rest in another. */
    private static final class Strips extends Drawable {
        private final View decor;
        private final Paint paint = new Paint();
        private int top, rest;
        private float bandPx;

        Strips(View decor, int top, int rest, float bandPx) {
            this.decor = decor;
            this.top = top;
            this.rest = rest;
            this.bandPx = bandPx;
        }

        void set(int top, int rest, float bandPx) {
            if (this.top == top && this.rest == rest && this.bandPx == bandPx) return;
            this.top = top;
            this.rest = rest;
            this.bandPx = bandPx;
            invalidateSelf();
        }

        @Override
        public void draw(Canvas canvas) {
            Rect b = getBounds();
            paint.setColor(rest);
            canvas.drawRect(b, paint);
            paint.setColor(top);
            int pt = decor.getPaddingTop();   // SystemBars sets it to the status-bar inset
            canvas.drawRect(b.left, b.top, b.right, b.top + pt, paint);
            if (bandPx > 0) {
                canvas.drawRect(b.left, b.top + pt, b.left + decor.getPaddingLeft(), b.top + pt + bandPx, paint);
                canvas.drawRect(b.right - decor.getPaddingRight(), b.top + pt, b.right, b.top + pt + bandPx, paint);
            }
        }

        @Override
        public void setAlpha(int alpha) {}

        @Override
        public void setColorFilter(ColorFilter filter) {}

        @Override
        public int getOpacity() { return PixelFormat.OPAQUE; }
    }
}
