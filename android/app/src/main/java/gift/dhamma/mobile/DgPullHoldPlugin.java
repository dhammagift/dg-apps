package gift.dhamma.mobile;

import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Rect;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.view.PixelCopy;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;
import android.widget.FrameLayout;
import android.widget.ImageView;

import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout;

import com.getcapacitor.Plugin;
import com.getcapacitor.annotation.CapacitorPlugin;

/**
 * Pull to refresh, Android's own (src/pull-refresh.js). The same file in all three apps; only the package differs.
 *
 * Owner, 2026-10-11: the page should stay exactly as it is and the new content just appear. A bare reload painted
 * blank and jumped, a fade over it was "дорогое мелькание", a spinner the page drew over a held picture of itself
 * "дергается ... кошмарно дешево". So the gesture and the spinner are SwipeRefreshLayout's, the circle every Android
 * app pulls down. The WebView is put inside one (parent -> SwipeRefreshLayout -> FrameLayout -> [WebView, picture]).
 * When it fires, the WebView as it is on screen becomes a picture over it, the page reloads under the picture, and
 * release(), sent by the new page once it has loaded with its fonts, takes the picture and the circle away.
 *
 * The page decides whether a pull may refresh at all (setAllowed, on every touchstart): only one that starts on the
 * page itself, scrolled to the top. The window insets are the decor view's (Capacitor's SystemBars), so moving the
 * WebView one level down changes nothing there.
 */
@CapacitorPlugin(name = "DgPullHold")
public class DgPullHoldPlugin extends Plugin {
    // A page that never says it is ready (an error, a page without pull-refresh.js) is not held for ever.
    private static final long MAX_HOLD_MS = 8000;
    private static final int ACCENT = 0xFF149C7C;   // the pages' --dg-accent

    private final Handler ui = new Handler(Looper.getMainLooper());
    private SwipeRefreshLayout swipe;
    private ImageView shot;
    private volatile boolean allowed;
    private volatile String allowedOn = "";
    private int token;
    private int circleTop = -1;

    @Override
    public void load() {
        final WebView web = getBridge().getWebView();
        web.addJavascriptInterface(new Object() {
            @JavascriptInterface
            public void setAllowed(boolean yes, String href) { allowedOn = href == null ? "" : href; allowed = yes; }

            @JavascriptInterface
            public void release() { ui.post(DgPullHoldPlugin.this::release); }
        }, "DgPullHold");
        wrap(web);
    }

    private void wrap(final WebView web) {
        ViewGroup parent = (ViewGroup) web.getParent();
        if (parent == null) return;
        int index = parent.indexOfChild(web);
        ViewGroup.LayoutParams lp = web.getLayoutParams();
        parent.removeView(web);

        FrameLayout box = new FrameLayout(getContext());
        box.addView(web, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        shot = new ImageView(getContext());
        shot.setScaleType(ImageView.ScaleType.FIT_XY);
        shot.setVisibility(View.GONE);
        box.addView(shot, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        swipe = new SwipeRefreshLayout(getContext());
        swipe.addView(box, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        parent.addView(swipe, index, lp);

        // "The child can scroll up" = no refresh: the page is scrolled, or the pull did not start on the page itself,
        // or the answer came from a page that is no longer there (one without pull-refresh.js never answers).
        swipe.setOnChildScrollUpCallback((layout, child) -> web.getScrollY() > 0 || !allowed || !allowedOn.equals(web.getUrl()));
        swipe.setOnRefreshListener(() -> hold(web));
        swipe.setColorSchemeColors(ACCENT);
        boolean night = (getContext().getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK)
            == Configuration.UI_MODE_NIGHT_YES;
        swipe.setProgressBackgroundColorSchemeColor(night ? 0xFF2B2B2B : Color.WHITE);
        swipe.addOnLayoutChangeListener((v, l, t, r, b, ol, ot, or, ob) -> placeCircle());
    }

    // Edge to edge the page runs under the status bar: the circle comes down from below it, not from under the clock.
    private void placeCircle() {
        WindowInsetsCompat insets = ViewCompat.getRootWindowInsets(swipe);
        int bar = insets == null ? 0 : insets.getInsets(WindowInsetsCompat.Type.statusBars()).top;
        int[] at = new int[2];
        swipe.getLocationOnScreen(at);
        int top = Math.max(0, bar - at[1]);
        if (top == circleTop) return;
        circleTop = top;
        float d = getContext().getResources().getDisplayMetrics().density;
        swipe.setProgressViewOffset(false, top - Math.round(40 * d), top + Math.round(64 * d));
    }

    private void hold(final WebView web) {
        final int mine = ++token;
        final int w = web.getWidth(), h = web.getHeight();
        if (w == 0 || h == 0) { web.reload(); return; }
        final Bitmap picture = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
        Runnable then = () -> {
            if (mine != token) return;
            shot.setImageBitmap(picture);
            shot.setVisibility(View.VISIBLE);
            web.reload();
            ui.postDelayed(() -> { if (mine == token) release(); }, MAX_HOLD_MS);
        };
        // PixelCopy reads what is on the screen (the circle too: the live one is drawn over it, in the same place);
        // the WebView's own draw() is the fallback before Android 8 and if the copy fails.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            int[] at = new int[2];
            web.getLocationInWindow(at);
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

    private void release() {
        token++;
        if (shot != null && shot.getVisibility() == View.VISIBLE) {
            shot.setVisibility(View.GONE);
            shot.setImageDrawable(null);
        }
        if (swipe != null && swipe.isRefreshing()) swipe.setRefreshing(false);
    }
}
