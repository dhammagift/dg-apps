package gift.dhamma.mobile;

import android.content.Context;
import android.net.Uri;
import android.util.Base64;
import android.webkit.MimeTypeMap;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.util.HashMap;
import java.util.Map;

/**
 * Files of the site that were downloaded after the app was built, served in place of the bundled copy.
 *
 * The page's updater (native-bridge.js, updateSite) fetches the files of the site that are verbatim copies in the bundle
 * (scripts, styles, icons: the list is www/site-manifest.json) and hands the ones that changed over:
 *
 *     Capacitor.Plugins.DgSite.put({ path: "/read/js/voice.js", data: "<base64>" })
 *     Capacitor.Plugins.DgSite.list()   ->  { files: [ ... ] }
 *     Capacitor.Plugins.DgSite.clear()
 *
 * They are written under files/site/ and answered by {@link #serve} (MainActivity's WebViewClient) for the next request.
 * Nothing else is served from here: a path that was not downloaded goes to Capacitor and the bundle, as it always did.
 *
 * Same idea as the dictionary's plugin (dict/android/.../DgSitePlugin.java), without its proxy to the site.
 */
@CapacitorPlugin(name = "DgSite")
public class DgSitePlugin extends Plugin {

    private static final long MAX_BYTES = 8L * 1024 * 1024;

    static File root(Context context) {
        return new File(context.getFilesDir(), "site");
    }

    /** A request path inside files/site/, or null when it would leave it. */
    static File resolve(Context context, String path) {
        if (path == null || !path.startsWith("/") || path.length() > 300 || path.indexOf('\0') >= 0) return null;
        try {
            File base = root(context).getCanonicalFile();
            File file = new File(base, path).getCanonicalFile();
            return file.getPath().startsWith(base.getPath() + File.separator) ? file : null;
        } catch (Exception e) {
            return null;
        }
    }

    @PluginMethod
    public void put(PluginCall call) {
        String path = call.getString("path");
        String data = call.getString("data");
        File file = resolve(getContext(), path);
        if (file == null || data == null) {
            call.reject("bad path or no data");
            return;
        }
        try {
            byte[] bytes = Base64.decode(data, Base64.DEFAULT);
            if (bytes.length == 0 || bytes.length > MAX_BYTES) {
                call.reject("size out of range");
                return;
            }
            File dir = file.getParentFile();
            if (dir != null && !dir.isDirectory() && !dir.mkdirs()) {
                call.reject("could not create the directory");
                return;
            }
            // Written beside and renamed: a request that arrives half-way sees the old file or the new one, never half.
            File temp = new File(dir, file.getName() + ".part");
            try (FileOutputStream out = new FileOutputStream(temp)) {
                out.write(bytes);
            }
            if (!temp.renameTo(file)) {
                //noinspection ResultOfMethodCallIgnored
                temp.delete();
                call.reject("could not store the file");
                return;
            }
            call.resolve();
        } catch (Exception e) {
            call.reject("DgSite.put failed: " + e.getMessage());
        }
    }

    @PluginMethod
    public void list(PluginCall call) {
        JSArray files = new JSArray();
        collect(root(getContext()), "", files);
        JSObject out = new JSObject();
        out.put("files", files);
        call.resolve(out);
    }

    @PluginMethod
    public void clear(PluginCall call) {
        deleteTree(root(getContext()));
        call.resolve();
    }

    private static void collect(File dir, String prefix, JSArray out) {
        File[] entries = dir.listFiles();
        if (entries == null) return;
        for (File f : entries) {
            if (f.isDirectory()) collect(f, prefix + "/" + f.getName(), out);
            else if (!f.getName().endsWith(".part")) out.put(prefix + "/" + f.getName());
        }
    }

    private static void deleteTree(File file) {
        File[] entries = file.listFiles();
        if (entries != null) for (File f : entries) deleteTree(f);
        //noinspection ResultOfMethodCallIgnored
        file.delete();
    }

    // ---- serving ------------------------------------------------------------------------------

    private static final Map<String, String> TYPES = new HashMap<>();
    static {
        TYPES.put("js", "application/javascript");
        TYPES.put("mjs", "application/javascript");
        TYPES.put("css", "text/css");
        TYPES.put("json", "application/json");
        TYPES.put("svg", "image/svg+xml");
        TYPES.put("woff2", "font/woff2");
        TYPES.put("woff", "font/woff");
        TYPES.put("webp", "image/webp");
        TYPES.put("png", "image/png");
    }

    private static String typeOf(String path) {
        int dot = path.lastIndexOf('.');
        String ext = dot < 0 ? "" : path.substring(dot + 1).toLowerCase();
        String known = TYPES.get(ext);
        if (known != null) return known;
        String guessed = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext);
        return guessed == null ? "application/octet-stream" : guessed;
    }

    /** The downloaded copy of a file the app's own origin is asked for, or null to let Capacitor serve the bundled one. */
    static WebResourceResponse serve(Context context, WebResourceRequest request) {
        if (!"GET".equals(request.getMethod())) return null;
        Uri uri = request.getUrl();
        if (!"localhost".equals(uri.getHost())) return null;
        String path = uri.getPath();
        if (path == null || path.endsWith("/") || path.startsWith("/_capacitor")) return null;
        try {
            File downloaded = resolve(context, path);
            if (downloaded == null || !downloaded.isFile()) return null;
            Map<String, String> headers = new HashMap<>();
            headers.put("Access-Control-Allow-Origin", "*");
            headers.put("Cache-Control", "no-cache");
            return new WebResourceResponse(typeOf(path), "UTF-8", 200, "OK", headers, new FileInputStream(downloaded));
        } catch (Exception e) {
            return null;
        }
    }
}
