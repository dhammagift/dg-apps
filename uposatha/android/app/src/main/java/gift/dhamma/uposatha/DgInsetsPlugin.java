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

    @PluginMethod
    public void get(PluginCall call) {
        getActivity().runOnUiThread(() -> {
            Insets bars = Insets.NONE;
            try {
                WindowInsetsCompat insets = ViewCompat.getRootWindowInsets(getActivity().getWindow().getDecorView());
                if (insets != null) {
                    bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.displayCutout());
                }
            } catch (Exception e) {
                // No insets to report is not worth failing the page's layout over: it falls back to
                // env(), and to no padding at all if that is 0 too.
            }
            float density = getActivity().getResources().getDisplayMetrics().density;
            JSObject ret = new JSObject();
            ret.put("top", bars.top / density);
            ret.put("right", bars.right / density);
            ret.put("bottom", bars.bottom / density);
            ret.put("left", bars.left / density);
            call.resolve(ret);
        });
    }
}
