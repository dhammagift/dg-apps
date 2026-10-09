package gift.dhamma.uposatha;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import org.json.JSONObject;

/**
 * DgWidget: the page hands the home-screen widget its data.
 *
 *   Capacitor.Plugins.DgWidget.put({ json: "<the object of window.__upoWidgetData() as a string>" })
 *
 * The string is kept as it is (SharedPreferences dg_widget / data, uposatha/widget/WIDGET.md) and every widget is redrawn
 * from it; the widget itself calculates nothing. Same call, same data on iOS (App Group).
 */
@CapacitorPlugin(name = "DgWidget")
public class DgWidgetPlugin extends Plugin {

    @PluginMethod
    public void put(PluginCall call) {
        String json = call.getString("json");
        if (json == null || json.isEmpty()) { call.reject("json is empty"); return; }
        try {
            new JSONObject(json);   // refuse what the widget could not read: the last good data stays
        } catch (Exception e) {
            call.reject("json is not valid: " + e.getMessage());
            return;
        }
        getContext().getSharedPreferences(WidgetProvider.PREFS, android.content.Context.MODE_PRIVATE)
                .edit().putString(WidgetProvider.KEY_DATA, json).apply();
        WidgetProvider.refreshAll(getContext());
        call.resolve(new JSObject());
    }
}
