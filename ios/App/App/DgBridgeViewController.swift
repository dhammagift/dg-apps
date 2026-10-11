import UIKit
import WebKit
import Capacitor

// The page's own background (white by day, #111111 at night): what shows behind the first paint and at the
// overscroll edges, the same pair as Android's dg_navbar (values/colors.xml, values-night) and Uposatha's.
private let dgPageBackground = UIColor { traits in
    traits.userInterfaceStyle == .dark
        ? UIColor(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1)
        : UIColor.white
}

// The root: the page runs EDGE TO EDGE, as on Android and in Uposatha and the dictionary on iOS (owner,
// 2026-10-11: the dark "борода" below the page "занимает драгоценные миллиметры"). The WKWebView spans the
// whole screen, under the transparent status bar and the home indicator. The page keeps clear of them
// itself, the way it already does on Android: its strip behind the clock (home.css, html.dg-app
// body::before, over every layer, the colour of what is under it), the drawer's and the sheets' padding
// (--dg-sat/--dg-sab), and on the pages the app carries as files a strip of their own (native-bridge.js,
// #dg-edge-strip). The bar heights come from the bridge below (--safe-area-inset-*), not from env() alone,
// which WKWebView does not report dependably in an app (Uposatha's runs 446-449) — the failure that put
// text under the clock before.
//
// What this replaces: the web view pinned to the safe area on a fixed navy background (issue #15/#51), so
// nothing could reach under the bars — at the price of a navy field above and below the page.
final class DgRootViewController: UIViewController {
    private let bridgeController = DgBridgeViewController()

    // The status bar's icon colour is the page's decision (native-bridge.js syncBarIcons -> SystemBars.setStyle,
    // light on the navy home bar and the dark theme, dark on the light theme), which lands on the bridge view
    // controller. UIKit asks the WINDOW'S root (this VC), so the question is forwarded.
    override var childForStatusBarStyle: UIViewController? { bridgeController }
    override var childForStatusBarHidden: UIViewController? { bridgeController }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = dgPageBackground
        addChild(bridgeController)
        bridgeController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bridgeController.view)
        NSLayoutConstraint.activate([
            bridgeController.view.topAnchor.constraint(equalTo: view.topAnchor),
            bridgeController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bridgeController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bridgeController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
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

    // The safe-area insets, handed to the page as --safe-area-inset-* (the page's CSS takes the larger of these
    // and env(); Android's SystemBars plugin writes the same variables). Written on every layout change, after
    // every page load (a reload, Memo, the sign-in page: a new document starts without them), and kept in
    // localStorage, which a document-start script reads, so a new page has them before its first paint.
    private var loadingObservation: NSKeyValueObservation?

    private func pushSafeAreaInsets() {
        guard let webView = webView else { return }
        let i = webView.safeAreaInsets
        guard i.top > 0 || i.bottom > 0 else { return }
        let js = "try{var v={top:\(i.top),right:\(i.right),bottom:\(i.bottom),left:\(i.left)};"
            + "localStorage.setItem('dgSafeArea',JSON.stringify(v));"
            + "var r=document.documentElement.style;for(var k in v)r.setProperty('--safe-area-inset-'+k,v[k]+'px')}catch(e){}"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func pushSafeAreaInsetsSoon() {
        pushSafeAreaInsets()
        for delay in [0.3, 1.0, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.pushSafeAreaInsets() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pushSafeAreaInsets()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        pushSafeAreaInsets()
    }

    override func capacitorDidLoad() {
        // Edge to edge (DgRootViewController): what shows through before the first paint and under
        // overscroll is the page's own background, not systemBackground.
        webView?.backgroundColor = dgPageBackground
        webView?.scrollView.backgroundColor = dgPageBackground
        webView?.configuration.userContentController.addUserScript(WKUserScript(
            source: "try{var v=JSON.parse(localStorage.getItem('dgSafeArea')||'null');if(v){var r=document.documentElement.style;"
                + "for(var k in v)r.setProperty('--safe-area-inset-'+k,v[k]+'px')}}catch(e){}",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        loadingObservation = webView?.observe(\.isLoading, options: [.new]) { [weak self] _, change in
            if change.newValue == false { DispatchQueue.main.async { self?.pushSafeAreaInsetsSoon() } }
        }
        pushSafeAreaInsetsSoon()

        // Edge swipe = browser Back. WKWebView leaves it off by default, and Android's system Back
        // already does this, so on iOS a reader who taps a link by accident had no way back to the
        // sutta (a tester's report). Uses the WebView's own history, so it only goes back when there
        // is somewhere to go.
        webView?.allowsBackForwardNavigationGestures = true

        // No scroll indicators: the page is the whole interface, and the indicator is drawn above the
        // launch splash as a strip (seen on Android, dropped here for the same reason).
        webView?.scrollView.showsVerticalScrollIndicator = false
        webView?.scrollView.showsHorizontalScrollIndicator = false
        // Pull to refresh holds the page on screen while it reloads (DgPullHold below, src/pull-refresh.js).
        webView?.configuration.userContentController.add(DgPullHold(webView), name: "dgPullHold")

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

// Pull to refresh with the page held on screen (src/pull-refresh.js; the same class in all three apps, as
// Android's DgPullHoldPlugin.java). Owner, 2026-10-11: the page should stay exactly as it is and the new
// content just appear; a bare reload painted blank and jumped, a fade over it was "дорогое мелькание".
// "hold" puts a picture of the web view over it, with the page's spinner cut out of the picture and turning,
// and reloads the page under it; "release", sent by the new page once it has loaded with its fonts, takes
// the picture away, so the next frame is the new page, whole.
final class DgPullHold: NSObject, WKScriptMessageHandler {
    private weak var web: WKWebView?
    private var shot: UIView?
    private var token = 0

    init(_ web: WKWebView?) { self.web = web }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body as? [String: Any] ?? [:]
        release()
        guard body["op"] as? String == "hold", let web = web else { return }
        let mine = token
        guard let parent = web.superview, let picture = web.snapshotView(afterScreenUpdates: false) else { web.reload(); return }
        picture.frame = web.frame
        parent.insertSubview(picture, aboveSubview: web)
        shot = picture
        // The spinner's square, in CSS px from the viewport's top left: points in the web view, past any inset.
        if let x = body["x"] as? Double, let y = body["y"] as? Double, let size = body["size"] as? Double, size > 0 {
            let inset = web.scrollView.adjustedContentInset
            let square = CGRect(x: x + inset.left, y: y + inset.top, width: size, height: size)
            if let ring = web.resizableSnapshotView(from: square, afterScreenUpdates: false, withCapInsets: .zero) {
                ring.frame = square
                ring.layer.cornerRadius = size / 2
                ring.clipsToBounds = true
                let turn = CABasicAnimation(keyPath: "transform.rotation.z")
                turn.fromValue = 0
                turn.toValue = Double.pi * 2
                turn.duration = 0.7
                turn.repeatCount = .infinity
                ring.layer.add(turn, forKey: "spin")
                picture.addSubview(ring)
            }
        }
        web.reload()
        // A page that never says it is ready (an error, a page without pull-refresh.js) is not held for ever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            if self?.token == mine { self?.release() }
        }
    }

    private func release() {
        token += 1
        shot?.removeFromSuperview()
        shot = nil
    }
}
