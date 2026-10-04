package gift.dhamma.uposatha;

import android.content.res.Configuration;
import android.graphics.Color;
import android.view.Window;

import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsControllerCompat;

import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

/**
 * The system bars follow the page's theme (dg-apps#54): the bar icons and the window behind the
 * WebView, in one call, so they cannot disagree.
 *     DgInsets.setTheme({ dark: true, color: "#111111" })
 *
 * Not Capacitor's SystemBars.setStyle: it ends by repainting the window in the SYSTEM's background
 * (windowBackground of the phone's own light/dark mode). On a light phone a dark page then had
 * white strips above and below it, on a dark phone a light page black ones (owner's screenshots).
 * SystemBars still owns the insets (viewport-fit=cover: it passes them through to the page), and it
 * calls setStyle again on every configuration change (rotation, the phone's own theme), so the
 * page's choice is put back right after it.
 *
 * The insets themselves are the page's (SystemBars' --safe-area-inset-* and env()); the iOS plugin
 * of the same name still answers get(), Android has no second source any more.
 */
@CapacitorPlugin(name = "DgInsets")
public class DgInsetsPlugin extends Plugin {

    private Boolean dark;
    private int color;

    @PluginMethod
    public void setTheme(PluginCall call) {
        final boolean isDark = call.getBoolean("dark", false);
        int c = isDark ? 0xFF111111 : 0xFFFFFFFF;
        try {
            c = Color.parseColor(call.getString("color", ""));
        } catch (IllegalArgumentException e) {
            // no colour or not a #rrggbb one: the page's plain light/dark background
        }
        final int pageColor = c;
        getActivity().runOnUiThread(() -> {
            dark = isDark;
            color = pageColor;
            apply();
            call.resolve();
        });
    }

    private void apply() {
        if (dark == null) return;
        Window window = getActivity().getWindow();
        window.getDecorView().setBackgroundColor(color);
        if (getBridge() != null && getBridge().getWebView() != null) {
            getBridge().getWebView().setBackgroundColor(color);
        }
        WindowInsetsControllerCompat bars = WindowCompat.getInsetsController(window, window.getDecorView());
        bars.setAppearanceLightStatusBars(!dark);
        bars.setAppearanceLightNavigationBars(!dark);
    }

    @Override
    protected void handleOnConfigurationChanged(Configuration newConfig) {
        super.handleOnConfigurationChanged(newConfig);
        // After SystemBars has had its turn (it repaints the window in the system's colour).
        getActivity().getWindow().getDecorView().post(this::apply);
    }
}
