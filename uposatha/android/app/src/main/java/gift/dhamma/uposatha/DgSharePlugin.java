package gift.dhamma.uposatha;

import android.content.Intent;

import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

/**
 * The system share sheet (dg-apps#56). Android's WebView has no navigator.share, so both Share
 * buttons only copied a link; uposatha-bridge.js puts this behind navigator.share.
 *     DgShare.share({ title, url })
 */
@CapacitorPlugin(name = "DgShare")
public class DgSharePlugin extends Plugin {

    @PluginMethod
    public void share(PluginCall call) {
        String url = call.getString("url", "");
        String title = call.getString("title", "");
        Intent send = new Intent(Intent.ACTION_SEND);
        send.setType("text/plain");
        send.putExtra(Intent.EXTRA_TEXT, url);
        if (!title.isEmpty()) send.putExtra(Intent.EXTRA_SUBJECT, title);
        try {
            getActivity().startActivity(Intent.createChooser(send, title.isEmpty() ? null : title));
            call.resolve();
        } catch (Exception e) {
            call.reject("No app to share with", e);
        }
    }
}
