package gift.dhamma.pali;

import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.View;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;

import androidx.core.splashscreen.SplashScreen;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsAnimationCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.webkit.WebViewCompat;
import androidx.webkit.WebViewFeature;

import com.getcapacitor.Bridge;
import com.getcapacitor.BridgeActivity;
import com.getcapacitor.BridgeWebViewClient;
import com.getcapacitor.WebViewListener;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * The dictionary as a Capacitor app.
 *
 * The interface is the dictionary site's own page, bundled in the APK so the app opens with no network
 * (uposatha-style: dict/tools/bundle-from-repo.js lays it out from ddg-ui at build time, DgSitePlugin keeps it up to
 * date and answers for the site). It replaces the Trusted Web Activity, whose container was the problem.
 * What changed is the container. A TWA runs inside Chrome's Custom Tab, which is why the owner's
 * two reports existed at all — "не работает стандалон" (a Custom Tab still shows Chrome's own
 * chrome and follows Chrome's display-mode, not the app's) and the burger panel "улетает" (the
 * bottom sheet is positioned against a viewport Chrome resizes as its URL bar hides and shows).
 * A WebView this app owns has neither problem.
 *
 * Everything this file adds is the part a web manifest cannot do: the bridge that puts app-only
 * rows into the site's burger menu (www/dict-bridge.js, injected below), and the launch routes
 * (App Shortcuts, shared text, selected text) that used to live in the TWA's LauncherActivity.
 */
public class MainActivity extends BridgeActivity {

    // The app's own origin: the dictionary's page is bundled in the APK (www/, a snapshot of the site's page taken
    // at build time) and served from here; a word's page is fetched from the site by DgSitePlugin under this
    // address. The injected bridge runs here, and routes (shortcuts, shared text) are loaded from here.
    private static final String SITE_ORIGIN = "https://localhost";
    private static final String SITE_ROOT = SITE_ORIGIN + "/";
    // Where `cap sync` puts the committed src/dict-bridge.js (see dict/build.js).
    private static final String BRIDGE_ASSET = "public/dict-bridge.js";

    // Guards against handling the same launch twice: BridgeActivity.load() — called from its
    // onCreate — ends with this.onNewIntent(getIntent()), so the launch intent already arrives
    // through the override below and no explicit call belongs in onCreate.
    private Intent handledIntent;

    // How long the animated splash mark is held on screen: nearly its own length (the motion decelerates and
    // is ~95% done by then), so a warm start is not made to wait for the last few frames.
    private static final long SPLASH_HOLD_MS = 750;

    @Override
    public void onCreate(Bundle savedInstanceState) {
        // Before super.onCreate(): Capacitor collects registered plugins while the bridge is being
        // created. DgShortcuts pushes the lookup history into the launcher's long-press menu.
        registerPlugin(DgShortcutsPlugin.class);
        registerPlugin(DgSitePlugin.class);
        // Paste for the Pali letters row (src/pali-bar.js): reads the clipboard only when the key is tapped.
        registerPlugin(DgClipboardPlugin.class);
        // The launch splash is the animated mark (res/drawable/dg_splash_icon.xml, 900 ms). The system takes the
        // splash down the moment the first frame is ready, which on a warm start is before the mark has drawn;
        // holding it for the length of the animation is what lets it play, and costs a cold start nothing it
        // was not going to spend loading anyway.
        SplashScreen splash = SplashScreen.installSplashScreen(this);
        final long shownAt = SystemClock.uptimeMillis();
        splash.setKeepOnScreenCondition(() -> SystemClock.uptimeMillis() - shownAt < SPLASH_HOLD_MS);
        super.onCreate(savedInstanceState);

        serveTheBundle();
        injectBridge();
        // What the WebView shows before the site's first paint is the launch screen's own colour
        // (light/dark by the system theme), so native splash -> web splash has no gap.
        if (getBridge() != null && getBridge().getWebView() != null) {
            getBridge().getWebView().setBackgroundColor(getColor(R.color.dg_splash_bg));
            // No scrollbars, no overscroll glow: the WebView draws its own scroll indicator ABOVE the page
            // (and above the splash), which showed as a strip down the launch screen. The page is the app's
            // whole interface here, and a phone app has no scrollbars on it.
            WebView bare = getBridge().getWebView();
            bare.setVerticalScrollBarEnabled(false);
            bare.setHorizontalScrollBarEnabled(false);
            bare.setOverScrollMode(View.OVER_SCROLL_NEVER);
        }
        // Deliberately no handleIntent(getIntent()) here — see handledIntent above.
        reportKeyboardHeight();
    }

    /**
     * The keyboard's height, in css px, to the page: window.__dgIme(px) (src/pali-bar.js lifts its row of Pāli letters by it). The
     * insets animation callback is a second listener on the window and leaves SystemBars' own insets handling alone.
     */
    private void reportKeyboardHeight() {
        if (getBridge() == null || getBridge().getWebView() == null) return;
        final View decor = getWindow().getDecorView();
        final WebView web = getBridge().getWebView();
        final float density = getResources().getDisplayMetrics().density;
        ViewCompat.setWindowInsetsAnimationCallback(decor, new WindowInsetsAnimationCompat.Callback(
                WindowInsetsAnimationCompat.Callback.DISPATCH_MODE_CONTINUE_ON_SUBTREE) {
            @Override
            public WindowInsetsCompat onProgress(WindowInsetsCompat insets, List<WindowInsetsAnimationCompat> running) {
                return insets;
            }

            @Override
            public void onEnd(WindowInsetsAnimationCompat animation) {
                WindowInsetsCompat now = ViewCompat.getRootWindowInsets(decor);
                if (now == null) return;
                int px = now.isVisible(WindowInsetsCompat.Type.ime()) ? now.getInsets(WindowInsetsCompat.Type.ime()).bottom : 0;
                final int css = Math.round(px / density);
                web.post(() -> web.evaluateJavascript("window.__dgIme&&window.__dgIme(" + css + ")", null));
            }
        });
    }

    @Override
    public void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        // Identity check, not equals(): two separate taps on the same shortcut produce
        // equal-but-distinct Intents and both must work.
        if (intent == handledIntent) return;
        handledIntent = intent;
        handleIntent(intent);
    }

    /**
     * The page is bundled in the APK; DgSitePlugin serves the files downloaded since, the bundle's directory
     * pages (/ru/), and the site's own answers (a word's page) in place of Capacitor's asset server.
     */
    private void serveTheBundle() {
        final Bridge bridge = getBridge();
        if (bridge == null) return;
        bridge.setWebViewClient(new BridgeWebViewClient(bridge) {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                WebResourceResponse answer = DgSitePlugin.serve(MainActivity.this, bridge, request);
                return answer != null ? answer : super.shouldInterceptRequest(view, request);
            }
        });
    }

    /**
     * Injects www/dict-bridge.js into the loaded site, plus the installed version as a global so
     * the "App version" row never has to ask the site (or the bridge) for something only the
     * package manager knows.
     *
     * Document-start injection is the supported path and runs before the page's own scripts, so
     * the rows are already in the burger panel the first time it opens. It needs a WebView with
     * DOCUMENT_START_SCRIPT (Chrome 105+); on anything older the listener below re-injects on every
     * page load instead, which is a little later but the same rows.
     */
    private void injectBridge() {
        if (getBridge() == null || getBridge().getWebView() == null) return;
        final String script = "window.__DG_APP_VERSION__=" + JSONObject.quote(versionString()) + ";\n"
                + readAsset(BRIDGE_ASSET);
        WebView webView = getBridge().getWebView();
        if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            try {
                WebViewCompat.addDocumentStartJavaScript(webView, script, Collections.singleton(SITE_ORIGIN));
                return;
            } catch (IllegalArgumentException e) {
                // Falls through to the listener: an injection that cannot be registered must not
                // cost the reader the rows.
            }
        }
        getBridge().addWebViewListener(new WebViewListener() {
            @Override
            public void onPageLoaded(WebView view) {
                view.evaluateJavascript(script, null);
            }
        });
    }

    /** versionName (versionCode), the same string the site's own "App version" style uses. */
    private String versionString() {
        try {
            android.content.pm.PackageInfo info = getPackageManager().getPackageInfo(getPackageName(), 0);
            long code = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P ? info.getLongVersionCode() : info.versionCode;
            return info.versionName + " (" + code + ")";
        } catch (Exception e) {
            return "";
        }
    }

    private String readAsset(String path) {
        StringBuilder out = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(getAssets().open(path), "UTF-8"))) {
            String line;
            while ((line = reader.readLine()) != null) out.append(line).append('\n');
        } catch (Exception e) {
            // An unreadable bridge is not worth failing the launch over; the page simply gets the
            // version global and no extra rows.
            return "";
        }
        return out.toString();
    }

    /**
     * The three ways this activity can be launched with extra data, turned into a URL: a static or
     * dynamic App Shortcut's "route" extra (res/xml/shortcuts.xml, DgShortcutsPlugin), a shared
     * text (AndroidManifest.xml's ACTION_SEND filter) or a selected text (its PROCESS_TEXT filter).
     *
     * The text is handed over RAW as the site's ?q=, exactly as the TWA's LauncherActivity did and
     * as dg-app-full does: the site owns the cleaning, and a second copy of it in a wrapper is how
     * the two drift apart.
     */
    private void handleIntent(Intent intent) {
        if (intent == null) return;
        String url = null;
        String route = intent.getStringExtra("route");
        if (route != null && !route.isEmpty()) {
            url = routeUrl(route);
        } else if (Intent.ACTION_SEND.equals(intent.getAction())) {
            String shared = intent.getStringExtra(Intent.EXTRA_TEXT);
            if (shared != null && !shared.isEmpty()) url = SITE_ROOT + "?q=" + Uri.encode(shared);
        } else if (Intent.ACTION_PROCESS_TEXT.equals(intent.getAction())) {
            // getCharSequenceExtra, not getStringExtra: a selection arrives as a Spannable.
            CharSequence selected = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT);
            if (selected != null && selected.length() > 0) url = SITE_ROOT + "?q=" + Uri.encode(selected.toString());
        }
        if (url == null) return;

        final String finalUrl = url;
        final WebView webView = getBridge() != null ? getBridge().getWebView() : null;
        if (webView != null) webView.post(() -> webView.loadUrl(finalUrl));
    }

    // The sites a shortcut may name that are not the app's: dhamma.gift opens in the app (server.allowNavigation, the
    // static shortcut and Table of Contents), the two outside tools in the system browser. The activity is exported, so
    // the route can come from any app: nothing else is loaded.
    private static final Set<String> BROWSER_HOSTS = new HashSet<>(Arrays.asList(
            "dharmamitra.org", "www.dharmamitra.org", "aksharamukha.com", "www.aksharamukha.com"));

    /** A shortcut's route as the URL to load in the WebView, or null (handed to the browser, or refused). */
    private String routeUrl(String route) {
        if (route.startsWith("/")) {
            // A path of the app's own origin, parsed rather than prefix-checked: "//host/..." or "/\host" must not leave it.
            Uri own = Uri.parse(SITE_ORIGIN + route);
            boolean ok = !route.startsWith("//") && route.indexOf('\\') < 0 && "https".equals(own.getScheme())
                    && "localhost".equals(own.getHost()) && own.getPort() == -1 && own.getUserInfo() == null;
            return ok ? own.toString() : null;
        }
        Uri site = Uri.parse(route);
        String host = site.getHost() == null ? "" : site.getHost().toLowerCase();
        if (!"https".equals(site.getScheme()) || site.getUserInfo() != null || site.getPort() != -1) return null;
        if (host.equals("dhamma.gift") || host.endsWith(".dhamma.gift")) return site.toString();
        if (BROWSER_HOSTS.contains(host)) {
            // webView.loadUrl() would open it inside the dictionary (no shouldOverrideUrlLoading for a load the app starts).
            try {
                startActivity(new Intent(Intent.ACTION_VIEW, site).addCategory(Intent.CATEGORY_BROWSABLE));
            } catch (ActivityNotFoundException e) {
                // No browser on the device: nothing to open it with.
            }
        }
        return null;
    }
}
