package gift.dhamma.mobile;

import android.content.Context;
import android.content.Intent;
import android.os.Build;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.util.ArrayList;
import java.util.List;

/**
 * The offline library download, moved off the WebView (the Android twin of ios/.../DgDownloadPlugin.swift).
 *
 * A WebView's JavaScript and workers are frozen once the app is not on screen, so a transfer that runs in the page stops
 * in the background and goes on only when the reader comes back (owner, issue #62). The transfer here runs in
 * DgDownloadService, a real foreground service, into the app's files directory, and resumes after any break.
 *
 *   start({base}[, fresh]) -> {path}   the directory holding db-manifest.json and the archive (dg.db.gz), once both are in
 *                                      place; "progress" events {loaded, total} meanwhile. A second start joins the running
 *                                      transfer. `fresh` ignores an archive of the same build already on disk.
 *   existing()            -> {path} | {path: null}
 *   cancel()              -> stops it and drops the partial file
 *   clear()               -> deletes the archive (the manifest stays: it is only a few hundred bytes)
 *
 * The page then reads both files through Capacitor's file URL (dgPlatform.distBase), exactly as it reads them from the
 * site, and imports the archive into its own storage: nothing else in the offline layer changes.
 */
@CapacitorPlugin(name = "DgDownload")
public class DgDownloadPlugin extends Plugin {

    private final List<PluginCall> waiting = new ArrayList<>();

    private final DgDownloadService.Listener listener = new DgDownloadService.Listener() {
        @Override public void onProgress(long loaded, long total) {
            JSObject data = new JSObject();
            data.put("loaded", loaded);
            data.put("total", total);
            notifyListeners("progress", data);
        }
        @Override public void onFinished(String error) {
            List<PluginCall> calls;
            synchronized (waiting) { calls = new ArrayList<>(waiting); waiting.clear(); }
            for (PluginCall call : calls) {
                if (error == null) {
                    JSObject r = new JSObject();
                    r.put("path", DgDownloadService.libraryDir(getContext()).getAbsolutePath());
                    call.resolve(r);
                } else call.reject("download failed: " + error);
            }
            DgDownloadService.listeners.remove(this);
        }
    };

    @PluginMethod
    public void start(PluginCall call) {
        String base = call.getString("base");
        if (base == null || base.isEmpty()) { call.reject("no base"); return; }
        synchronized (waiting) { waiting.add(call); }
        if (!DgDownloadService.listeners.contains(listener)) DgDownloadService.listeners.add(listener);
        call.setKeepAlive(true);
        Context context = getContext();
        Intent intent = new Intent(context, DgDownloadService.class)
                .setAction(DgDownloadService.ACTION_DOWNLOAD)
                .putExtra(DgDownloadService.EXTRA_BASE, base)
                .putExtra(DgDownloadService.EXTRA_FRESH, Boolean.TRUE.equals(call.getBoolean("fresh", false)));
        try {
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent);
            else context.startService(intent);
        } catch (Exception e) {
            synchronized (waiting) { waiting.remove(call); }
            call.reject("could not start the download service: " + e.getMessage());
        }
    }

    @PluginMethod
    public void existing(PluginCall call) {
        JSObject r = new JSObject();
        File dir = DgDownloadService.libraryDir(getContext());
        File manifest = new File(dir, DgDownloadService.MANIFEST);
        try {
            if (manifest.isFile()) {
                StringBuilder sb = new StringBuilder();
                try (FileInputStream in = new FileInputStream(manifest)) {
                    byte[] buf = new byte[4096]; int n;
                    while ((n = in.read(buf)) > 0) sb.append(new String(buf, 0, n, "UTF-8"));
                }
                JSONObject m = new JSONObject(sb.toString());
                File archive = new File(dir, m.getString("file_gz"));
                if (archive.isFile() && archive.length() == m.getLong("bytes_gz")) {
                    r.put("path", dir.getAbsolutePath());
                    call.resolve(r);
                    return;
                }
            }
        } catch (Exception e) { /* unreadable: the same as absent */ }
        r.put("path", JSObject.NULL);
        call.resolve(r);
    }

    @PluginMethod
    public void cancel(PluginCall call) {
        DgDownloadService.cancelled = true;
        File dir = DgDownloadService.libraryDir(getContext());
        File[] parts = dir.listFiles();
        if (parts != null) for (File f : parts) if (f.getName().contains(".part")) f.delete();
        call.resolve();
    }

    @PluginMethod
    public void clear(PluginCall call) {
        File dir = DgDownloadService.libraryDir(getContext());
        File[] files = dir.listFiles();
        if (files != null) for (File f : files) if (!f.getName().equals(DgDownloadService.MANIFEST)) f.delete();
        call.resolve();
    }
}
