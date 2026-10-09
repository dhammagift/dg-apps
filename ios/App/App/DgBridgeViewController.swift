import UIKit
import WebKit
import Capacitor

// The root: the page sits inside the safe area (under the status bar and above the home indicator), on a
// fixed dark background — issue #15/#51's own words: the strip behind both bars is the site's own dark navbar
// band, ALWAYS, in both themes, not something that follows the page's current theme.
//
// This used to be done differently: capacitor.config.json's ios.contentInset:"always" (plus a matching
// ios.backgroundColor), which insets the WKWebView's SCROLL CONTENT but leaves its FRAME spanning the whole
// screen, status bar included — so the status bar is just the native OS chrome drawn transparently over
// whatever the page has scrolled to that instant. Capacitor's own contentInset handling doesn't touch
// position:fixed elements at all (they're laid out against the full, uninset viewport), so a fixed-position
// panel (dg-node's #dg-drawer, dg-node #51 "мультитул") or the page's own top content can end up rendered
// AT true screen y=0 — directly under/behind the status bar — independent of scroll position, which is
// exactly the reported "иконки мультитула наезжают на статус-бар" and the settings sheet's sideways drift
// (dg-node bc5a3e7 patched the drift's own symptom; this is that bug's actual native root cause).
//
// Uposatha and Dict hit no version of this bug because they never used contentInset — both already pin their
// bridge's view to safeAreaLayoutGuide (see their own DgApp.swift), so their WKWebView's FRAME itself never
// extends past the safe area: nothing in the page ever renders under either bar, fixed or not, scrolled or
// not. Same fix here.
final class DgRootViewController: UIViewController {
    private let bridgeController = DgBridgeViewController()

    // UIKit asks the WINDOW'S rootViewController for this — this VC, not its child bridgeController, now
    // that the child's own view no longer spans the full screen (it's confined to the safe area above). A
    // status-bar-style override left on DgBridgeViewController alone would simply never be consulted.
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0x2E / 255, green: 0x3E / 255, blue: 0x50 / 255, alpha: 1)
        addChild(bridgeController)
        bridgeController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bridgeController.view)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            bridgeController.view.topAnchor.constraint(equalTo: guide.topAnchor),
            bridgeController.view.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            bridgeController.view.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            bridgeController.view.trailingAnchor.constraint(equalTo: guide.trailingAnchor)
        ])
        bridgeController.didMove(toParent: self)
    }
}

// The app's own bridge view controller: CAPBridgeViewController plus the plugins that live in this
// target rather than in an npm package.
//
// Capacitor loads the npm plugins (App, Browser, Dialog, Network, Share) from the
// package list `cap sync` writes; anything written here has to be registered by hand, and it has to
// happen before the page loads. capacitorDidLoad() is Capacitor's own hook for exactly that: the
// bridge exists, the first navigation has not started.
//
// What is registered here, and why:
//   DgProgressPlugin  the idle timer that keeps the screen awake while the library downloads
//   DgTtsPlugin       the reader's voice (WKWebView's own speechSynthesis has no voices)
//   DgDownloadPlugin  the library download, on a background URLSession
//   DgShortcutsPlugin quick actions: the dynamic "recently read" list, and what a tap does
//   DgSelfTestPlugin  debug builds only: the CI simulator run's way of getting results out
//
// Note for the next plugin: Capacitor 8's iOS CAPPlugin has no handleOnDestroy (Android's has), so a
// cleanup hook has to be a deinit — an @objc override of it fails the build with "does not override
// any method from its superclass".
class DgBridgeViewController: CAPBridgeViewController {

    // Capacitor registers its asset handler for capacitor://localhost on the configuration this
    // returns, after it returns — the one moment /dg-sql can be put on the same origin, which is
    // what lets the worker reach it with a plain same-origin XMLHttpRequest. So the configuration is
    // a subclass that wraps whatever handler is registered on it (DgSchemeRouter), and this method
    // mirrors CAPBridgeViewController.webViewConfiguration(for:) setting by setting, because super
    // would hand back a plain WKWebViewConfiguration.
    override func webViewConfiguration(for instanceConfiguration: InstanceConfiguration) -> WKWebViewConfiguration {
        let configuration = DgWebViewConfiguration()
        configuration.websiteDataStore.httpCookieStore.add(CapacitorWKCookieObserver())
        configuration.allowsInlineMediaPlayback = true
        configuration.suppressesIncrementalRendering = false
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.limitsNavigationsToAppBoundDomains = instanceConfiguration.limitsNavigationsToAppBoundDomains
        if #available(iOS 15.4, *) {
            configuration.preferences.isElementFullscreenEnabled = true
        }
        if let appendUserAgent = instanceConfiguration.appendedUserAgentString {
            if let appName = configuration.applicationNameForUserAgent {
                configuration.applicationNameForUserAgent = "\(appName) \(appendUserAgent)"
            } else {
                configuration.applicationNameForUserAgent = appendUserAgent
            }
        }
        if let preferredContentMode = instanceConfiguration.preferredContentMode {
            var mode = WKWebpagePreferences.ContentMode.recommended
            if preferredContentMode == "mobile" {
                mode = .mobile
            } else if preferredContentMode == "desktop" {
                mode = .desktop
            }
            configuration.defaultWebpagePreferences.preferredContentMode = mode
        }
        return configuration
    }

    override func capacitorDidLoad() {
        // Edge swipe = browser Back. WKWebView leaves it off by default, and Android's system Back
        // already does this, so on iOS a reader who taps a link by accident had no way back to the
        // sutta (a tester's report). Uses the WebView's own history, so it only goes back when there
        // is somewhere to go.
        webView?.allowsBackForwardNavigationGestures = true

        // No scroll indicators: the page is the whole interface, and the indicator is drawn above the
        // launch splash as a strip (seen on Android, dropped here for the same reason).
        webView?.scrollView.showsVerticalScrollIndicator = false
        webView?.scrollView.showsHorizontalScrollIndicator = false

        // The page learns that SQL runs natively (DgSharedLibrary.swift). Added here and not in
        // webViewConfiguration(for:), because Capacitor replaces the user content controller after
        // that call.
        webView?.configuration.userContentController.addUserScript(DgLibrary.userScript(shareSheet: false))

        // Ships in the app: it keeps the screen awake while the offline library downloads
        // (DgProgressPlugin.swift), which is what stops iOS suspending the transfer mid-way.
        bridge?.registerPluginInstance(DgProgressPlugin())
        // Also shipped: the WebView's own speechSynthesis has no voices (see DgTtsPlugin.swift), and
        // the reader's voice player is part of the reader.
        bridge?.registerPluginInstance(DgTtsPlugin())
        // The library download on the system's background transfer service (DgDownloadPlugin.swift):
        // the WebView's own fetch dies when the app leaves the foreground, and this is the iOS
        // answer to Android's foreground service.
        bridge?.registerPluginInstance(DgDownloadPlugin())
        // The Home Screen's long-press menu: the dynamic "recently read" items the page hands over,
        // and the handler that makes a tap open its route (DgShortcutsPlugin.swift).
        bridge?.registerPluginInstance(DgShortcutsPlugin())
        // Native sign-in (DgSignInPlugin.swift): Apple's own sheet, and Google's in the system sign-in
        // sheet — instead of a browser page that never came back on iOS (dg-apps#43).
        bridge?.registerPluginInstance(DgSignInPlugin())
        // Files of the site downloaded after the build, answered in front of the bundled ones (DgSitePlugin.swift).
        bridge?.registerPluginInstance(DgSitePlugin())

        #if DEBUG
        // Debug builds only, and deliberately so: this plugin lets the page write a file into the
        // app's Documents directory, which no shipped build may be able to do on a web page's
        // behalf. A release build's `Capacitor.Plugins.DgSelfTest` is therefore undefined.
        bridge?.registerPluginInstance(DgSelfTestPlugin())
        #endif
    }
}

final class DgWebViewConfiguration: WKWebViewConfiguration {
    override func setURLSchemeHandler(_ urlSchemeHandler: WKURLSchemeHandler?, forURLScheme urlScheme: String) {
        super.setURLSchemeHandler(urlSchemeHandler.map { DgSchemeRouter(inner: $0) }, forURLScheme: urlScheme)
    }
}

// /dg-sql/* goes to the SQL handler, everything else to Capacitor's asset handler.
final class DgSchemeRouter: NSObject, WKURLSchemeHandler {
    private let inner: WKURLSchemeHandler
    private let sql = DgSqlSchemeHandler()

    init(inner: WKURLSchemeHandler) {
        self.inner = inner
    }

    private func isSql(_ task: WKURLSchemeTask) -> Bool {
        return task.request.url?.path.hasPrefix(DgLibrary.endpointPath + "/") == true
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        if !isSql(urlSchemeTask), DgSiteStore.answer(urlSchemeTask) { return }
        (isSql(urlSchemeTask) ? sql : inner).webView(webView, start: urlSchemeTask)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        (isSql(urlSchemeTask) ? sql : inner).webView(webView, stop: urlSchemeTask)
    }
}
