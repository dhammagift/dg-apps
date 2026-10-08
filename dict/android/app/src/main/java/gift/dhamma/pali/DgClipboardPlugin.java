package gift.dhamma.pali;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

/**
 * The clipboard's text for the Paste key above the keyboard (src/pali-bar.js). Android System WebView has no
 * navigator.clipboard.readText. Called only when the reader taps Paste: nothing here reads the clipboard on its own,
 * and Android itself shows its "pasted from clipboard" notice.
 *
 *   read()  ->  { text: "..." }   (empty when there is nothing, or nothing that is text)
 */
@CapacitorPlugin(name = "DgClipboard")
public class DgClipboardPlugin extends Plugin {

    @PluginMethod
    public void read(PluginCall call) {
        String text = "";
        ClipboardManager cm = (ClipboardManager) getContext().getSystemService(Context.CLIPBOARD_SERVICE);
        if (cm != null && cm.hasPrimaryClip()) {
            ClipData clip = cm.getPrimaryClip();
            if (clip != null && clip.getItemCount() > 0) {
                CharSequence c = clip.getItemAt(0).coerceToText(getContext());
                if (c != null) text = c.toString();
            }
        }
        JSObject result = new JSObject();
        result.put("text", text);
        call.resolve(result);
    }
}
