package gift.dhamma.mobile;

import android.app.Notification;
import android.app.Service;
import android.net.wifi.WifiManager;
import android.os.PowerManager;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;

import androidx.annotation.Nullable;
import androidx.core.app.NotificationManagerCompat;

import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;
import java.util.concurrent.CopyOnWriteArrayList;

/**
 * Keeps the process alive while the offline library is downloading, so the transfer the page
 * started actually finishes when the reader switches away or turns the screen off.
 *
 * Why a service and not just a notification: backgrounding the app is when Android starts treating
 * the WebView process as idle, and a 509MB download is minutes of work — the owner's report was
 * "свернута в нитку, там вообще нет процентов". A foreground service with an ongoing notification
 * is the platform's own answer to "this is still doing something the user asked for", and it is
 * exactly what the plan called for (docs/OFFLINE_PWA_PLAN.md: «уведомление о прогрессе» among the
 * five native items).
 *
 * The service owns no download logic and no timers: the page keeps transferring in its own worker
 * (WorkManager/DownloadManager cannot write to OPFS — see the plan), DgProgressPlugin pushes each
 * progress event in as an updated notification, and this class only holds the foreground slot.
 * Every failure to claim that slot is ignored on purpose: the download then simply runs with the
 * app in the background for as long as Android allows, which is what the app did before.
 */
public class DgDownloadService extends Service {

    static final String EXTRA_NOTIFICATION = "notification";
    static final int NOTIFICATION_ID = DgProgressPlugin.NOTIFICATION_ID;
    static final int DONE_NOTIFICATION_ID = NOTIFICATION_ID + 1;

    // The native download (owner: "загрузка в бекграунде замораживается ... это не настоящий foreground"). A WebView's
    // JavaScript and workers are frozen once the app is not visible, so the transfer itself runs HERE, on a service
    // thread, into the app's files directory; the page only imports the finished archive (db-worker.js, from the local
    // file URL) and shows progress from the events. Resumes by Range after any break, checks the sha256 the manifest
    // publishes. Statics, not a binder: the plugin and the service share one process and the page may come and go.
    static final String ACTION_DOWNLOAD = "gift.dhamma.mobile.DOWNLOAD";
    static final String EXTRA_BASE = "base";
    static final String EXTRA_FRESH = "fresh";
    static final String LIBRARY_DIR = "dg-library";
    static final String MANIFEST = "db-manifest.json";

    interface Listener {
        void onProgress(long loaded, long total);
        void onFinished(String error);   // null = the archive and its manifest are in place
    }
    static final CopyOnWriteArrayList<Listener> listeners = new CopyOnWriteArrayList<>();
    static volatile boolean running = false;
    static volatile boolean cancelled = false;
    static volatile long lastLoaded = 0, lastTotal = 0;
    static volatile boolean transferred = false;   // bytes really crossed the network in this run (not an archive already in place)

    static File libraryDir(android.content.Context context) {
        File dir = new File(context.getFilesDir(), LIBRARY_DIR);
        if (!dir.isDirectory()) dir.mkdirs();
        return dir;
    }

    private PowerManager.WakeLock wakeLock;
    private WifiManager.WifiLock wifiLock;

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && ACTION_DOWNLOAD.equals(intent.getAction())) {
            startDownload(intent.getStringExtra(EXTRA_BASE), intent.getBooleanExtra(EXTRA_FRESH, false));
            return START_NOT_STICKY;
        }
        Notification notification = null;
        if (intent != null && Build.VERSION.SDK_INT >= 33) {
            notification = intent.getParcelableExtra(EXTRA_NOTIFICATION, Notification.class);
        } else if (intent != null) {
            //noinspection deprecation — the typed overload only exists from API 33.
            notification = intent.getParcelableExtra(EXTRA_NOTIFICATION);
        }
        if (notification == null) {
            stopSelf();
            return START_NOT_STICKY;
        }
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC);
            } else {
                startForeground(NOTIFICATION_ID, notification);
            }
            // The foreground slot alone keeps the PROCESS alive, not the CPU: with the screen off the
            // device suspends and the transfer stops mid-file (owner: "качает и со свёрнутым, но как
            // только выключается экран — останавливается"). A partial wake lock is the platform's
            // answer for exactly this: screen may go off, the CPU and the network read loop stay up.
            acquireLocks();
        } catch (Exception e) {
            // Foreground services are refused in a few states (permission revoked, background
            // start restrictions after the app was killed). Not fatal: the download continues.
            stopSelf();
        }
        return START_NOT_STICKY;
    }


    private void startDownload(final String base, final boolean fresh) {
        final Notification first = DgProgressPlugin.buildNotification(this, "Dhamma.gift", "Downloading the offline library", -1);
        try {
            if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION_ID, first, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC);
            else startForeground(NOTIFICATION_ID, first);
            acquireLocks();
        } catch (Exception e) {
            finish("could not start the foreground service: " + e.getMessage());
            return;
        }
        if (running) return;   // a second start joins the running transfer
        running = true;
        cancelled = false;
        transferred = false;
        new Thread(new Runnable() {
            @Override public void run() {
                String error = null;
                try { download(base, fresh); }
                catch (Exception e) { error = String.valueOf(e.getMessage() != null ? e.getMessage() : e); }
                running = false;
                finish(error);
            }
        }, "dg-library-download").start();
    }

    private void finish(String error) {
        for (Listener l : listeners) l.onFinished(error);
        try {
            stopForeground(true);
            NotificationManagerCompat.from(this).cancel(NOTIFICATION_ID);
            if (error == null && transferred) {
                // The archive is on disk. The page unpacks it into the database when the app is open (JavaScript cannot run
                // in the background), so the reader is told to open it.
                Notification done = new androidx.core.app.NotificationCompat.Builder(this, "dg_download_v2")
                        .setSmallIcon(R.drawable.ic_tile)
                        .setContentTitle("Dhamma.gift")
                        .setContentText("The library is downloaded. Open the app to finish.")
                        .setContentIntent(android.app.PendingIntent.getActivity(this, 0,
                                new Intent(this, MainActivity.class).setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP),
                                android.app.PendingIntent.FLAG_UPDATE_CURRENT | android.app.PendingIntent.FLAG_IMMUTABLE))
                        .setAutoCancel(true).build();
                NotificationManagerCompat.from(this).notify(DONE_NOTIFICATION_ID, done);
            }
        } catch (Exception e) { /* no notification permission: the page still gets the result */ }
        stopSelf();
    }

    private static String readAll(InputStream in) throws Exception {
        java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
        byte[] buf = new byte[8192]; int n;
        while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
        return out.toString("UTF-8");
    }

    private void download(String base, boolean fresh) throws Exception {
        File dir = libraryDir(this);
        HttpURLConnection mc = (HttpURLConnection) new URL(base + "/" + MANIFEST).openConnection();
        mc.setConnectTimeout(20000); mc.setReadTimeout(30000); mc.setUseCaches(false);
        String manifestText = readAll(mc.getInputStream());
        JSONObject manifest = new JSONObject(manifestText);
        String file = manifest.getString("file_gz");
        long total = manifest.getLong("bytes_gz");
        String build = manifest.optString("build_id", "");
        String sha = manifest.optString("sha256", "");
        File archive = new File(dir, file);
        File part = new File(dir, file + ".part");
        File partBuild = new File(dir, file + ".part.build");
        File localManifest = new File(dir, MANIFEST);

        // Already here (the same build, complete): nothing to fetch.
        if (!fresh && archive.isFile() && archive.length() == total && localManifest.isFile()
                && manifestText.trim().equals(readAll(new FileInputStream(localManifest)).trim())) {
            lastLoaded = total; lastTotal = total;
            return;
        }
        archive.delete();
        // A partial file from another build is not continued.
        if (part.exists()) {
            String prev = partBuild.isFile() ? readAll(new FileInputStream(partBuild)).trim() : "";
            if (!prev.equals(build)) part.delete();
        }
        try (OutputStream os = new FileOutputStream(partBuild)) { os.write(build.getBytes("UTF-8")); }

        int attempt = 0;
        long lastNotify = 0;
        while (part.length() < total) {
            if (cancelled) { part.delete(); partBuild.delete(); throw new Exception("cancelled"); }
            long have = part.length();
            HttpURLConnection c = null;
            try {
                c = (HttpURLConnection) new URL(base + "/" + file).openConnection();
                c.setConnectTimeout(20000); c.setReadTimeout(30000); c.setUseCaches(false);
                if (have > 0) c.setRequestProperty("Range", "bytes=" + have + "-");
                int code = c.getResponseCode();
                if (code == 200 && have > 0) { part.delete(); have = 0; }          // the server ignored Range: from the start
                else if (code != 200 && code != 206) throw new java.io.IOException("HTTP " + code);
                try (InputStream in = c.getInputStream(); OutputStream out = new FileOutputStream(part, have > 0)) {
                    byte[] buf = new byte[65536]; int n; long loaded = have;
                    while ((n = in.read(buf)) > 0) {
                        if (cancelled) throw new Exception("cancelled");
                        out.write(buf, 0, n); loaded += n;
                        long now = System.currentTimeMillis();
                        if (now - lastNotify > 700) {
                            lastNotify = now;
                            lastLoaded = loaded; lastTotal = total;
                            int percent = (int) Math.min(100, loaded * 100 / total);
                            String text = "Downloading the offline library \u2014 " + percent + "% (" + (loaded / 1048576) + " of " + (total / 1048576) + " MB)";
                            try { NotificationManagerCompat.from(this).notify(NOTIFICATION_ID, DgProgressPlugin.buildNotification(this, "Dhamma.gift", text, percent)); } catch (Exception e) { /* no permission */ }
                            for (Listener l : listeners) l.onProgress(loaded, total);
                        }
                    }
                }
                attempt = 0;
            } catch (java.io.IOException e) {
                // A drop of the connection is not the end: wait and continue from where the file stops.
                if (++attempt > 40) throw e;
                try { Thread.sleep(Math.min(30000, 2000L * attempt)); } catch (InterruptedException ie) { throw new Exception("cancelled"); }
            } finally { if (c != null) c.disconnect(); }
        }
        if (part.length() != total) throw new Exception("the downloaded file has the wrong size");
        if (!sha.isEmpty()) {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            try (InputStream in = new FileInputStream(part)) { byte[] buf = new byte[65536]; int n; while ((n = in.read(buf)) > 0) md.update(buf, 0, n); }
            StringBuilder hex = new StringBuilder(); for (byte b : md.digest()) hex.append(String.format("%02x", b));
            if (!hex.toString().equalsIgnoreCase(sha)) { part.delete(); partBuild.delete(); throw new Exception("the downloaded file is damaged (checksum)"); }
        }
        if (!part.renameTo(archive)) throw new Exception("could not store the downloaded file");
        partBuild.delete();
        try (OutputStream os = new FileOutputStream(localManifest)) { os.write(manifestText.getBytes("UTF-8")); }
        transferred = true;
        lastLoaded = total; lastTotal = total;
        for (Listener l : listeners) l.onProgress(total, total);
    }

    private void acquireLocks() {
        if (wakeLock == null) {
            PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
            if (pm != null) {
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "dg:offline-download");
                // No timeout on purpose: the lock lives exactly as long as this service, and the
                // service is stopped by DgProgressPlugin.clear() when the download ends (finished,
                // cancelled, failed). A timed lock would silently expire under a slow connection.
                wakeLock.setReferenceCounted(false);
                wakeLock.acquire();
            }
        }
        if (wifiLock == null) {
            // Keeps the Wi-Fi radio out of power save while the screen is off; without it a large
            // transfer on some devices stalls until the next packet the radio wakes for.
            WifiManager wm = (WifiManager) getApplicationContext().getSystemService(WIFI_SERVICE);
            if (wm != null) {
                try {
                    wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "dg:offline-download");
                    wifiLock.setReferenceCounted(false);
                    wifiLock.acquire();
                } catch (Exception e) {
                    wifiLock = null; // not fatal: the download just runs on the normal radio policy
                }
            }
        }
    }

    private void releaseLocks() {
        try { if (wakeLock != null && wakeLock.isHeld()) wakeLock.release(); } catch (Exception e) { /* already gone */ }
        wakeLock = null;
        try { if (wifiLock != null && wifiLock.isHeld()) wifiLock.release(); } catch (Exception e) { /* already gone */ }
        wifiLock = null;
    }

    @Override
    public void onDestroy() {
        if (running) cancelled = true;   // stopped from outside (the page cancelled the download)
        releaseLocks();
        super.onDestroy();
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
