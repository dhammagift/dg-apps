package gift.dhamma.pali;

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
 */
@CapacitorPlugin(name = "DgBars")
public class DgBarsPlugin extends Plugin {
    // null until the page has reported: the theme's navy and icons stay as they were.
    private static Integer top, rest;

    @PluginMethod
    public void set(PluginCall call) {
        try {
            top = Color.parseColor(call.getString("top"));
            rest = Color.parseColor(call.getString("bottom"));
        } catch (Exception e) {
            call.reject("bad colour");
            return;
        }
        getActivity().runOnUiThread(() -> {
            apply(getActivity());
            call.resolve();
        });
    }

    /**
     * Also called on resume, focus and configuration changes: SystemBars puts the theme's window
     * background back on the decor view there. False before the page has reported anything.
     */
    static boolean apply(Activity activity) {
        if (top == null) return false;
        final int t = top, r = rest;
        final View decor = activity.getWindow().getDecorView();
        decor.setBackground(new Drawable() {
            private final Paint paint = new Paint();

            @Override
            public void draw(Canvas canvas) {
                Rect b = getBounds();
                paint.setColor(r);
                canvas.drawRect(b, paint);
                // The status-bar strip is exactly the decor's top padding (SystemBars sets it to the inset).
                paint.setColor(t);
                canvas.drawRect(b.left, b.top, b.right, b.top + decor.getPaddingTop(), paint);
            }

            @Override
            public void setAlpha(int alpha) {}

            @Override
            public void setColorFilter(ColorFilter filter) {}

            @Override
            public int getOpacity() { return PixelFormat.OPAQUE; }
        });
        WindowInsetsControllerCompat icons = new WindowInsetsControllerCompat(activity.getWindow(), decor);
        icons.setAppearanceLightStatusBars(!isDark(t));
        icons.setAppearanceLightNavigationBars(!isDark(r));
        return true;
    }

    private static boolean isDark(int c) {
        return 0.299 * Color.red(c) + 0.587 * Color.green(c) + 0.114 * Color.blue(c) < 150;
    }
}
