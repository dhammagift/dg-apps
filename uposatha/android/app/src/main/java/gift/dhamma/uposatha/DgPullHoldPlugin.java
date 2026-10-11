package gift.dhamma.uposatha;

import android.animation.ObjectAnimator;
import android.animation.ValueAnimator;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Outline;
import android.graphics.Rect;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.view.PixelCopy;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewOutlineProvider;
import android.view.animation.LinearInterpolator;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;
import android.widget.FrameLayout;
import android.widget.ImageView;

import com.getcapacitor.Plugin;
import com.getcapacitor.annotation.CapacitorPlugin;

/**
 * Pull to refresh with the page held on screen (src/pull-refresh.js). The same file in all three apps;
 * only the package differs.
 *
 * Owner, 2026-10-11: the page should stay exactly as it is and the new content just appear. A bare reload
 * painted blank, then the page in fallback fonts, then jumped; a fade over it was "дорогое мелькание".
 * hold() turns the WebView as it is on screen into a picture over it, with the page's spinner cut out of
 * that picture and turning, and reloads the page under it. release(), called by the new page once it has
 * loaded with its fonts, takes the picture away, so the next frame is the new page, whole.
 *
 * A JavaScript interface, not a plugin method: load() runs before the bridge loads the first page (an
 * interface added later only shows up after the next load), and the call is synchronous, so nothing on the
 * page moves between the pull and the picture.
 */
@CapacitorPlugin(name = "DgPullHold")
public class DgPullHoldPlugin extends Plugin {
    // A page that never says it is ready (an error, a page without pull-refresh.js) is not held for ever.
    private static final long MAX_HOLD_MS = 8000;

    private final Handler ui = new Handler(Looper.getMainLooper());
    private View shot, ring;
    private ObjectAnimator spin;
    private int token;

    @Override
    public void load() {
        getBridge().getWebView().addJavascriptInterface(new Object() {
            @JavascriptInterface
            public void hold(float x, float y, float size) { ui.post(() -> DgPullHoldPlugin.this.hold(x, y, size)); }

            @JavascriptInterface
            public void release() { ui.post(DgPullHoldPlugin.this::release); }
        }, "DgPullHold");
    }

    /** x, y, size: the spinner's square in CSS px, from the viewport's top left. */
    private void hold(float x, float y, float size) {
        final WebView web = getBridge().getWebView();
        release();
        final int mine = ++token;
        final int w = web.getWidth(), h = web.getHeight();
        if (w == 0 || h == 0) { web.reload(); return; }
        final int[] at = new int[2];
        web.getLocationInWindow(at);
        final Bitmap picture = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
        Runnable then = () -> {
            if (mine != token) return;
            cover(web, picture, at, x, y, size);
            web.reload();
            ui.postDelayed(() -> { if (mine == token) release(); }, MAX_HOLD_MS);
        };
        // PixelCopy reads what is on the screen; the WebView's own draw() is the fallback before Android 8
        // (and if the copy fails).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PixelCopy.request(getActivity().getWindow(), new Rect(at[0], at[1], at[0] + w, at[1] + h), picture, result -> {
                if (result != PixelCopy.SUCCESS) drawInto(web, picture);
                then.run();
            }, ui);
        } else {
            drawInto(web, picture);
            then.run();
        }
    }

    private static void drawInto(WebView web, Bitmap picture) {
        Canvas canvas = new Canvas(picture);
        canvas.translate(-web.getScrollX(), -web.getScrollY());
        web.draw(canvas);
    }

    private void cover(WebView web, Bitmap picture, int[] at, float x, float y, float size) {
        FrameLayout root = getActivity().findViewById(android.R.id.content);
        int[] rootAt = new int[2];
        root.getLocationInWindow(rootAt);
        int left = at[0] - rootAt[0], top = at[1] - rootAt[1];

        ImageView whole = new ImageView(getContext());
        whole.setScaleType(ImageView.ScaleType.FIT_XY);
        whole.setImageBitmap(picture);
        FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(picture.getWidth(), picture.getHeight());
        lp.leftMargin = left;
        lp.topMargin = top;
        root.addView(whole, lp);
        shot = whole;

        // CSS px to the screen's: the page is laid out at the device width, so one CSS px is one density unit.
        float d = web.getResources().getDisplayMetrics().density;
        int s = Math.round(size * d), rx = Math.round(x * d), ry = Math.round(y * d);
        if (s <= 0 || rx < 0 || ry < 0 || rx + s > picture.getWidth() || ry + s > picture.getHeight()) return;
        ImageView piece = new ImageView(getContext());
        piece.setImageBitmap(Bitmap.createBitmap(picture, rx, ry, s, s));
        piece.setOutlineProvider(new ViewOutlineProvider() {
            @Override
            public void getOutline(View v, Outline outline) { outline.setOval(0, 0, v.getWidth(), v.getHeight()); }
        });
        piece.setClipToOutline(true);
        FrameLayout.LayoutParams plp = new FrameLayout.LayoutParams(s, s);
        plp.leftMargin = left + rx;
        plp.topMargin = top + ry;
        root.addView(piece, plp);
        ring = piece;
        spin = ObjectAnimator.ofFloat(piece, View.ROTATION, 0f, 360f);
        spin.setDuration(700);
        spin.setRepeatCount(ValueAnimator.INFINITE);
        spin.setInterpolator(new LinearInterpolator());
        spin.start();
    }

    private void release() {
        token++;
        if (spin != null) spin.cancel();
        spin = null;
        for (View v : new View[] { ring, shot }) {
            if (v != null && v.getParent() instanceof ViewGroup) ((ViewGroup) v.getParent()).removeView(v);
        }
        ring = null;
        shot = null;
    }
}
