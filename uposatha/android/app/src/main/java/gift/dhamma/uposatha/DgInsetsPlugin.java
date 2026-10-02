package gift.dhamma.uposatha;

import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

/**
 * The safe-area insets, for the page to ask for (dg-apps#41).
 *
 * Edge to edge means the page draws under the transparent status and navigation bars, so it has to
 * keep its own top bar, burger menu and side panels clear of them. The sources it could use are not
 * dependable: Capacitor's SystemBars injects --safe-area-inset-* only in its passthrough branch and
 * that injection has been failing in its own logs ("Error injecting safe area CSS: ... reading
 * 'style'"), and env(safe-area-inset-*) reads 0 in the CI emulator. The report from run 458 is
 * blunt: the page measured topInset 0 on a device whose status bar is 24dp tall, and the burger
 * menu opened under the clock (owner: "бургер меню открывается под часами").
 *
 * So the page asks here, the same call it makes on iOS (DgInsets, DgApp.swift): the real insets of
 * the window, divided by the density to be CSS pixels, exactly as Capacitor's own injection does.
 *     Capacitor.Plugins.DgInsets.get() -> { top, right, bottom, left }
 */
@CapacitorPlugin(name = "DgInsets")
public class DgInsetsPlugin extends Plugin {

    /**
     * The page's own theme, so the window and the WebView behind it stop showing the SYSTEM's
     * background. In dark theme on a light device that background was a white strip above the dark
     * page (owner's screenshots, dg-apps#41) — the bars are transparent, so whatever is behind the
     * WebView shows there whenever the platform pads it instead of passing the insets through.
     *     DgInsets.setTheme({ dark: true })
     */
    @PluginMethod
    public void setTheme(PluginCall call) {
        final boolean dark = call.getBoolean("dark", false);
        final int color = dark ? 0xFF111111 : 0xFFFFFFFF;
        getActivity().runOnUiThread(() -> {
            getActivity().getWindow().getDecorView().setBackgroundColor(color);
            if (getBridge() != null && getBridge().getWebView() != null) {
                getBridge().getWebView().setBackgroundColor(color);
            }
            call.resolve();
        });
    }

    @PluginMethod
    public void get(PluginCall call) {
        getActivity().runOnUiThread(() -> {
            // The STATUS bar for the top and the NAVIGATION bar for the bottom — not systemBars()
            // for everything: that union also carries the caption bar and the display cutout, and it
            // reported 52 CSS px on a device whose drawn status bar is 22 (owner: "отступ слишком
            // большой... на глаз?"). The cutout is asked for separately and only feeds the sides,
            // where it really matters (landscape).
            int top = 0, right = 0, bottom = 0, left = 0, cutL = 0, cutR = 0;
            try {
                WindowInsetsCompat insets = ViewCompat.getRootWindowInsets(getActivity().getWindow().getDecorView());
                if (insets != null) {
                    Insets status = insets.getInsets(WindowInsetsCompat.Type.statusBars());
                    Insets nav = insets.getInsets(WindowInsetsCompat.Type.navigationBars());
                    Insets cut = insets.getInsets(WindowInsetsCompat.Type.displayCutout());
                    top = status.top;
                    bottom = nav.bottom;
                    cutL = cut.left;
                    cutR = cut.right;
                    left = Math.max(status.left, cutL);
                    right = Math.max(status.right, cutR);
                }
            } catch (Exception e) {
                // No insets to report is not worth failing the page's layout over: it falls back to
                // env(), and to no padding at all if that is 0 too.
            }
            float density = getActivity().getResources().getDisplayMetrics().density;
            JSObject ret = new JSObject();
            ret.put("top", top / density);
            ret.put("right", right / density);
            ret.put("bottom", bottom / density);
            ret.put("left", left / density);
            // Diagnostics for the proof: the raw pixels and the density it divided by, so a wrong
            // number can be checked against the drawn status bar in the screenshot.
            ret.put("rawTop", top);
            ret.put("density", density);
            call.resolve(ret);
        });
    }
}
