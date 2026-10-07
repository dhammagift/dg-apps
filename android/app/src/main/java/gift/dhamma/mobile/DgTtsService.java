package gift.dhamma.mobile;

import android.app.Notification;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;

import androidx.annotation.Nullable;

/**
 * Keeps Dhamma.Gift alive while it reads aloud, the way a browser playing speech is kept alive.
 *
 * The player's notification alone is not enough: a notification is only a picture, and a few minutes
 * after the app leaves the screen Android freezes its process. The WebView then runs no script and
 * makes no request, the voice runs out of lines, and on return the page showed "the server isn't
 * responding" (owner, 2026-10-04: "a browser keeps going in the background, our own app does not").
 * A foreground service of type mediaPlayback is the platform's guarantee against that: the process
 * is not frozen and keeps its network. Like DgDownloadService it owns no logic, only the slot;
 * DgTtsPlugin starts it with the player notification while reading and stops it on pause or stop.
 * A refused start (a background start Android does not allow) is not fatal: the reading then runs
 * as it did before, for as long as Android lets it.
 */
public class DgTtsService extends Service {

    static final String EXTRA_NOTIFICATION = "notification";
    static final String EXTRA_ID = "id";

    // The plugin asks these instead of tracking the service itself: it can stop on its own (the pause timeout).
    static volatile boolean running;
    private static DgTtsService instance;
    // A pause keeps the service (and so the process, and the one notification) for this long, then lets go.
    private static final long PAUSE_HOLD_MS = 30L * 60 * 1000;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable giveUp = () -> {
        // The notification stays as an ordinary one: the reader still sees what was read and can press Play.
        if (Build.VERSION.SDK_INT >= 24) stopForeground(Service.STOP_FOREGROUND_DETACH);
        stopSelf();
    };

    private PowerManager.WakeLock wakeLock;
    private WifiManager.WifiLock wifiLock;

    /**
     * Playing: the locks are held and the pause timer is off. Paused: the service stays a foreground one (the
     * notification is the same one, only redrawn, and Play from it reaches a live page), the locks go back.
     */
    static void setPlaying(boolean playing) {
        DgTtsService s = instance;
        if (s == null) return;
        s.handler.removeCallbacks(s.giveUp);
        if (playing) {
            s.acquireLocks();
        } else {
            s.releaseLocks();
            s.handler.postDelayed(s.giveUp, PAUSE_HOLD_MS);
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Notification notification = null;
        if (intent != null && Build.VERSION.SDK_INT >= 33) {
            notification = intent.getParcelableExtra(EXTRA_NOTIFICATION, Notification.class);
        } else if (intent != null) {
            //noinspection deprecation — the typed overload only exists from API 33.
            notification = intent.getParcelableExtra(EXTRA_NOTIFICATION);
        }
        int id = intent != null ? intent.getIntExtra(EXTRA_ID, 0) : 0;
        if (notification == null || id == 0) {
            stopSelf();
            return START_NOT_STICKY;
        }
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(id, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK);
            } else {
                startForeground(id, notification);
            }
            instance = this;
            running = true;
            acquireLocks();
        } catch (Exception e) {
            stopSelf();
        }
        return START_NOT_STICKY;
    }

    // Screen off: the slot keeps the process, these keep the CPU and the radio for the next lines.
    private void acquireLocks() {
        if (wakeLock == null) {
            PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
            if (pm != null) {
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "dg:read-aloud");
                wakeLock.setReferenceCounted(false);
                wakeLock.acquire();
            }
        }
        if (wifiLock == null) {
            WifiManager wm = (WifiManager) getApplicationContext().getSystemService(WIFI_SERVICE);
            if (wm != null) {
                try {
                    wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "dg:read-aloud");
                    wifiLock.setReferenceCounted(false);
                    wifiLock.acquire();
                } catch (Exception e) {
                    wifiLock = null;
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
        handler.removeCallbacks(giveUp);
        running = false;
        if (instance == this) instance = null;
        releaseLocks();
        super.onDestroy();
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
