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
        // The right edge goes Back too, as on Android, where Back works from either edge (owner, 2026-10-16: «не работает свайп
        // от правого экрана — назад»). WebKit's own right-edge swipe is Forward, which a reader almost never has; it now waits
        // for this one to fail, so a swipe from the right never jumps forward instead.
        if let webView = webView {
            let rightBack = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(rightEdgeBack(_:)))
            rightBack.edges = .right
            webView.addGestureRecognizer(rightBack)
            for gr in webView.gestureRecognizers ?? [] where gr !== rightBack {
                if let edge = gr as? UIScreenEdgePanGestureRecognizer, edge.edges.contains(.right) { edge.require(toFail: rightBack) }
            }
        }

        // No scroll indicators: the page is the whole interface, and the indicator is drawn above the
        // launch splash as a strip (seen on Android, dropped here for the same reason).
        webView?.scrollView.showsVerticalScrollIndicator = false
        webView?.scrollView.showsHorizontalScrollIndicator = false
        // Pull to refresh: a Chrome-style circle over the page, the page held on screen while it reloads (DgPullHold below, src/pull-refresh.js).
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

    // Back once the finger has travelled a third of the way in from the right edge, only if there is somewhere to go back to.
    @objc private func rightEdgeBack(_ gr: UIScreenEdgePanGestureRecognizer) {
        guard gr.state == .ended, let webView = webView, webView.canGoBack else { return }
        if -gr.translation(in: webView).x > webView.bounds.width / 3 || -gr.velocity(in: webView).x > 600 { webView.goBack() }
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

// Pull to refresh with Chrome's look (src/pull-refresh.js; the same classes in all three apps; Android gets the same look
// from SwipeRefreshLayout, DgPullHoldPlugin.java). Owner, 2026-10-11: UIRefreshControl turned behind the page's fixed
// header, «какую-то полосу сверху вместо аккуратного лоадера как в хроме». So the circle is a view of our own ABOVE
// the web view, above every layer of the page: the content stays where it is (no bounce) and only the circle comes
// down from under the status bar, its arc growing with the pull and the arrowhead showing once a release would
// refresh. On release the page as it is becomes a picture under the turning circle and reloads beneath it; "release",
// sent by the new page once it has loaded with its fonts, takes the picture away and sends the circle back up.
// Whether a pull may refresh is the page's word for the touch ({op:'allowed'} on touchstart): only one that starts on
// the page itself, scrolled to the top, not in a sheet, a popup, a field or a scrolled box.
final class DgPullHold: NSObject, WKScriptMessageHandler, UIGestureRecognizerDelegate {
    private weak var web: WKWebView?
    private let circle = DgPullCircle()
    private var shot: UIView?
    private var token = 0
    private var allowed = false
    private var armed = false
    private var refreshing = false
    private var travel: CGFloat = 0
    private let threshold: CGFloat = 72   // how far the circle comes down before a release refreshes
    private let maxTravel: CGFloat = 110

    init(_ web: WKWebView?) {
        self.web = web
        super.init()
        guard let web = web else { return }
        // The content stays put under a pull, as in Chrome (Capacitor's own setting; a bounce dragged the page under its
        // fixed header). The pull is read by a recognizer of our own, alongside the scroll view's, so it also works on
        // a page too short to scroll.
        web.scrollView.bounces = false
        web.scrollView.alwaysBounceVertical = false
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        web.addGestureRecognizer(pan)
    }

    private func atTop(_ web: WKWebView) -> Bool {
        web.scrollView.contentOffset.y <= -web.scrollView.adjustedContentInset.top + 1
    }

    // The circle's centre: hidden just above the top inset (under the status bar), down by `travel` from there.
    private func place(_ travel: CGFloat) {
        guard let web = web else { return }
        circle.center = CGPoint(x: web.frame.midX,
                                y: web.frame.minY + web.safeAreaInsets.top - DgPullCircle.size / 2 - 4 + travel)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let web = web, !refreshing else { return false }
        let v = pan.velocity(in: web)
        return v.y > 0 && v.y > abs(v.x) && atTop(web)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        guard let web = web, !refreshing else { return }
        switch pan.state {
        case .began:
            armed = true
            travel = 0
        case .changed:
            // The page's answer can land a moment after the drag starts; until it says yes nothing shows.
            guard armed, allowed, atTop(web), let parent = web.superview else {
                if armed && !atTop(web) { armed = false; circle.hide() }
                return
            }
            if circle.superview !== parent { parent.addSubview(circle); circle.reset() }
            parent.bringSubviewToFront(circle)
            travel = min(max(pan.translation(in: web).y, 0) * 0.55, maxTravel)
            place(travel)
            circle.pulled(travel / threshold)
        case .ended, .cancelled, .failed:
            guard armed else { return }
            armed = false
            if pan.state == .ended && allowed && travel >= threshold { refresh() } else { circle.hide() }
        default:
            break
        }
    }

    private func refresh() {
        guard let web = web, let parent = web.superview else { return circle.hide() }
        refreshing = true
        token += 1
        let mine = token
        UIView.animate(withDuration: 0.15) { self.place(self.threshold) }
        circle.spin()
        if let picture = web.snapshotView(afterScreenUpdates: false) {
            picture.frame = web.frame
            parent.insertSubview(picture, belowSubview: circle)
            shot = picture
        }
        web.reload()
        // A page that never says it is ready (an error, a page without pull-refresh.js) is not held for ever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            if self?.token == mine { self?.release() }
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        switch body["op"] as? String {
        case "allowed": allowed = body["value"] as? Bool ?? false
        case "release": release()
        default: break
        }
    }

    // Every page says it once it is ready; with no refresh under way there is nothing to let go of.
    private func release() {
        guard refreshing else { return }
        refreshing = false
        token += 1
        if let picture = shot {
            shot = nil
            UIView.animate(withDuration: 0.15, animations: { picture.alpha = 0 }, completion: { _ in picture.removeFromSuperview() })
        }
        circle.hide()
    }
}

// The circle itself: Chrome's/Material's pull-to-refresh disc. White (#2a2a2a in the dark), a shadow, the apps' teal
// arc that grows to 4/5 of a turn with the pull, an arrowhead at its end once a release would refresh, and the arc
// turning while the page reloads.
final class DgPullCircle: UIView {
    static let size: CGFloat = 40
    private let arc = CAShapeLayer()
    private let head = CAShapeLayer()

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: DgPullCircle.size, height: DgPullCircle.size))
        isUserInteractionEnabled = false
        backgroundColor = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 0x2A / 255, green: 0x2A / 255, blue: 0x2A / 255, alpha: 1) : .white }
        layer.cornerRadius = DgPullCircle.size / 2
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)
        let teal = UIColor(red: 0x1A / 255, green: 0x9B / 255, blue: 0x7B / 255, alpha: 1).cgColor
        let c = CGPoint(x: DgPullCircle.size / 2, y: DgPullCircle.size / 2), r: CGFloat = 9
        for l in [arc, head] { l.frame = bounds; layer.addSublayer(l) }
        arc.path = UIBezierPath(arcCenter: c, radius: r, startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: true).cgPath
        arc.fillColor = nil
        arc.strokeColor = teal
        arc.lineWidth = 2.5
        arc.lineCap = .round
        arc.strokeEnd = 0
        // The arrowhead where the arc ends at 4/5 of a turn, pointing along it (clockwise).
        let a = -CGFloat.pi / 2 + 0.8 * 2 * .pi
        let tip = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
        let t = CGPoint(x: -sin(a), y: cos(a)), n = CGPoint(x: cos(a), y: sin(a))
        let p = UIBezierPath()
        p.move(to: CGPoint(x: tip.x + t.x * 4, y: tip.y + t.y * 4))
        p.addLine(to: CGPoint(x: tip.x - t.x + n.x * 3.5, y: tip.y - t.y + n.y * 3.5))
        p.addLine(to: CGPoint(x: tip.x - t.x - n.x * 3.5, y: tip.y - t.y - n.y * 3.5))
        p.close()
        head.path = p.cgPath
        head.fillColor = teal
        head.opacity = 0
        alpha = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func reset() {
        layer.removeAllAnimations()
        arc.removeAnimation(forKey: "spin")
        transform = .identity
        alpha = 0
    }

    // 0 = just started, 1 = a release refreshes.
    func pulled(_ progress: CGFloat) {
        let p = min(max(progress, 0), 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arc.strokeEnd = 0.8 * p
        head.opacity = p >= 1 ? 1 : 0
        CATransaction.commit()
        transform = CGAffineTransform(rotationAngle: p * .pi)
        alpha = min(1, 0.3 + p)
    }

    func spin() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        head.opacity = 0
        arc.strokeEnd = 0.8
        CATransaction.commit()
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = 2 * Double.pi
        turn.duration = 0.8
        turn.repeatCount = .infinity
        arc.add(turn, forKey: "spin")
    }

    func hide() {
        guard superview != nil else { return }
        UIView.animate(withDuration: 0.2, animations: {
            self.alpha = 0
            self.transform = self.transform.scaledBy(x: 0.6, y: 0.6)
        }, completion: { _ in
            self.reset()
            self.removeFromSuperview()
        })
    }
}
