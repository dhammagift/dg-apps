package gift.dhamma.uposatha;

import android.app.Activity;
import android.app.ActivityOptions;
import android.content.Intent;
import android.os.Build;
import android.os.Bundle;

/**
 * A tap on a widget opens the app the way its icon does, and says where to go on the side.
 *
 * The widget used to start MainActivity itself with the route as an extra. Android then refuses to bring a running app
 * forward with its own picture (ActivityRecord.allowTaskSnapshot: only the launcher's own intent, or one with no extras,
 * may use the snapshot) and puts a splash screen over it instead: a white screen with the mark over the open, dark
 * page at every tap (owner, 2026-10-10). So the tap lands here, on a screen that shows nothing; the route is left for
 * MainActivity (the same process) and the app is started with the launcher's own intent.
 */
public class WidgetOpenActivity extends Activity {
    private static volatile String pending;

    /** The route a widget asked for, once. */
    static String take() {
        String r = pending;
        pending = null;
        return r;
    }

    static boolean waiting() { return pending != null; }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        String route = getIntent() == null ? null : getIntent().getStringExtra("route");
        if (route != null && !route.isEmpty()) pending = route;
        Intent main = getPackageManager().getLaunchIntentForPackage(getPackageName());
        if (main != null) {
            main.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            // A cold start: only the launcher's icon gets the splash with the mark by itself; from Android 13 the one who
            // starts the app may ask for it.
            Bundle options = Build.VERSION.SDK_INT >= 33
                    ? ActivityOptions.makeBasic().setSplashScreenStyle(android.window.SplashScreen.SPLASH_SCREEN_STYLE_ICON).toBundle() : null;
            startActivity(main, options);
        }
        finish();   // Theme.NoDisplay: finished before it is shown
    }
}
