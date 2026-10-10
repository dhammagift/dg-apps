import UIKit
import WebKit
import UserNotifications
import BackgroundTasks
import WidgetKit
import Capacitor

// Everything of the app that is not an npm plugin, in one file: the bridge view controller, the reminders (DgNotify) and
// the Home Screen quick actions (DgShortcuts). The same contract as Android's DgAlarm/DgSound and DgShortcuts plugins, as far as
// iOS has the same things: no notification channels or streams here, no launcher icon change.

// The page's own background (white by day, #111111 at night) — what shows behind the first paint and
// at the overscroll edges, matching Android's windowBackground pair (values/colors.xml and
// values-night). A dynamic colour, so the simulator's/simctl's appearance switch re-tints it the way
// the page re-tints itself.
private let dgPageBackground = UIColor { traits in
    traits.userInterfaceStyle == .dark
        ? UIColor(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1)
        : UIColor.white
}

// The root: the page runs EDGE TO EDGE (dg-apps#41) — the WKWebView spans the whole screen, under
// the transparent status bar and the home indicator, and the page's own CSS keeps its bar clear of
// both (viewport-fit=cover in the bundled page, env(safe-area-inset-*), the bridge's top-inset
// padding). What this replaces: the page sat inside the safe area and the fields above and below it
// were this view's own colour — the iOS half of the "борода" dg-apps#40/#41. The same change as
// Android's (a706f50, c019579).
final class DgRootViewController: UIViewController {
    private let bridgeController = DgBridgeViewController()

    // The status bar's icon colour is the page's decision, not ours: the bridge calls
    // SystemBars.setStyle when its theme changes, which lands on the bridge view controller's
    // preferredStatusBarStyle. UIKit asks the WINDOW'S root (this VC), so the query has to be
    // forwarded or this VC's implicit .default would win and the icons would stay dark on the
    // page's dark theme.
    // The names are Swift's, not the Objective-C ones: the Xcode 26 SDK no longer takes the older
    // `childViewControllerForStatusBarStyle`/`...Hidden` spellings (the iOS build failed on them,
    // dg-apps#41) — `childForStatusBarStyle`/`childForStatusBarHidden` is the same property.
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

class DgBridgeViewController: CAPBridgeViewController {

    // Capacitor registers its asset handler for capacitor://localhost on the configuration this returns, after it returns: the one
    // moment the site's downloaded files (DgSite) can be put in front of the bundled ones. So the configuration is a subclass that
    // wraps whatever handler is registered on it, and this method mirrors CAPBridgeViewController.webViewConfiguration(for:)
    // setting by setting, because super would hand back a plain WKWebViewConfiguration.
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

    // The safe-area insets, handed to the page the way Android's SystemBars plugin hands them over:
    // as --safe-area-inset-*, which the page's CSS reads first (var(--safe-area-inset-top,
    // env(safe-area-inset-top, 0px))). iOS needs this: WKWebView's own env(safe-area-inset-top) is
    // NOT reliable in an app — it came out 62px in one run and 0 in the next two, same build, same
    // simulator (runs 446/448/449), and a page whose top bar is padded by env() then sits under the
    // Dynamic Island. The web view's own safeAreaInsets are the value the system really reports.
    private func pushSafeAreaInsets() {
        guard let webView = webView else { return }
        let i = webView.safeAreaInsets
        let js = """
        try {
          var r = document.documentElement.style;
          r.setProperty('--safe-area-inset-top', '\(i.top)px');
          r.setProperty('--safe-area-inset-right', '\(i.right)px');
          r.setProperty('--safe-area-inset-bottom', '\(i.bottom)px');
          r.setProperty('--safe-area-inset-left', '\(i.left)px');
        } catch (e) {}
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // Called on every layout change (rotation, a split view, the keyboard): the values are written
    // again, which is what the page's resize handling expects. The async repeats cover the page
    // arriving after the first layout — the write is idempotent and cheap.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pushSafeAreaInsets()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        pushSafeAreaInsets()
    }

    private func pushSafeAreaInsetsSoon() {
        pushSafeAreaInsets()
        for delay in [0.5, 2.0, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.pushSafeAreaInsets()
            }
        }
    }

    override func capacitorDidLoad() {
        // Edge to edge (dg-apps#41): Capacitor would leave the web view on systemBackground; what
        // shows through before the first paint (and under overscroll) is the page's own background
        // instead — the same dynamic colour as the root view behind it.
        webView?.backgroundColor = dgPageBackground
        webView?.scrollView.backgroundColor = dgPageBackground
        pushSafeAreaInsetsSoon()

        // Edge swipe = browser Back (a WKWebView leaves it off), and there is no Back button on iOS.
        webView?.allowsBackForwardNavigationGestures = true
        // No scroll indicators: the page is the whole interface.
        webView?.scrollView.showsVerticalScrollIndicator = false
        webView?.scrollView.showsHorizontalScrollIndicator = false

        // The bridge (www/uposatha-bridge.js, the same file Android injects) runs before the page's own scripts. Added here and not
        // in webViewConfiguration(for:), because Capacitor replaces the user content controller after that call.
        // With it, the installed version as a global, as Android's MainActivity does ("1.0 (509)"): the page's "App version" row
        // showed "preview", its fallback for a page with no native shell, because only Android set it.
        let info = Bundle.main.infoDictionary ?? [:]
        let version = "\(info["CFBundleShortVersionString"] as? String ?? "") (\(info["CFBundleVersion"] as? String ?? ""))"
        let versionJS = "window.__DG_APP_VERSION__=\"\(version)\";\n"   // digits, dots, a space and brackets: nothing to escape
        if let url = Bundle.main.url(forResource: "uposatha-bridge", withExtension: "js", subdirectory: "public"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            webView?.configuration.userContentController.addUserScript(
                WKUserScript(source: versionJS + source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        bridge?.registerPluginInstance(DgNotifyPlugin())
        bridge?.registerPluginInstance(DgShortcutsPlugin())
        bridge?.registerPluginInstance(DgSitePlugin())
        bridge?.registerPluginInstance(DgInsetsPlugin())
        bridge?.registerPluginInstance(DgSharePlugin())
        bridge?.registerPluginInstance(DgWidgetPlugin())
        #if DEBUG
        // Debug builds only, for the same reason as Dhamma.Gift's DgSelfTestPlugin: the App Store screenshot
        // tour (test/ios-sim/tour.js) needs one native call to say which view is on screen; a release build's
        // Capacitor.Plugins.DgSelfTest is undefined.
        bridge?.registerPluginInstance(DgSelfTestPlugin())
        #endif
    }
}

// MARK: - The bundled page and its updates

// Where the page comes from: the same site as SITE_CONFIG in uposatha-bridge.js: the production site.
private let dgSite = "https://dhamma.gift"

// Files of the page downloaded from the site (by the bridge's updater, through DgSite.put) live here and are answered
// in front of the bundled ones; nothing is ever deleted but by DgSite.clear.
enum DgSiteStore {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("site", isDirectory: true)
    }

    // A request path inside the store, or nil for one that leaves it.
    static func file(for path: String) -> URL? {
        guard path.hasPrefix("/"), !path.contains("..") else { return nil }
        return root.appendingPathComponent(String(path.dropFirst()))
    }
}

final class DgWebViewConfiguration: WKWebViewConfiguration {
    override func setURLSchemeHandler(_ urlSchemeHandler: WKURLSchemeHandler?, forURLScheme urlScheme: String) {
        super.setURLSchemeHandler(urlSchemeHandler.map { DgSiteRouter(inner: $0) }, forURLScheme: urlScheme)
    }
}

// A downloaded file first; a file with an extension the bundle does not have is the site's (asked for there); everything else is Capacitor's.
final class DgSiteRouter: NSObject, WKURLSchemeHandler {
    private let inner: WKURLSchemeHandler
    private var stopped = Set<ObjectIdentifier>()
    private let lock = NSLock()

    init(inner: WKURLSchemeHandler) { self.inner = inner }

    private static let types = [
        "html": "text/html; charset=utf-8", "js": "application/javascript; charset=utf-8", "mjs": "application/javascript; charset=utf-8", "css": "text/css; charset=utf-8", "json": "application/json; charset=utf-8",
        "svg": "image/svg+xml", "woff2": "font/woff2", "woff": "font/woff", "wasm": "application/wasm", "txt": "text/plain; charset=utf-8",
        "png": "image/png", "jpg": "image/jpeg", "webp": "image/webp", "mp3": "audio/mpeg", "ico": "image/x-icon"
    ]

    private static func typeOf(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        return types[ext] ?? "application/octet-stream"
    }

    private static func headers(_ type: String, length: Int) -> [String: String] {
        ["Content-Type": type, "Content-Length": String(length), "Access-Control-Allow-Origin": "*", "Cache-Control": "no-cache"]
    }

    // Edge to edge (dg-apps#41): the page has to carry viewport-fit=cover or WKWebView reports
    // env(safe-area-inset-top) as 0 and the bridge's top-bar padding comes out 0 too — the run 444
    // screenshots show the page's own bar drawn under the Dynamic Island. build.js patches the
    // BUILD's index.html, but this router answers "/" with the site's own /uposatha-calendar.html
    // (both the bundled snapshot and, after an update, the copy DgSite downloaded), which is the
    // page as dhamma.gift serves it: the meta is added here, where every copy passes through.
    private static func withViewportCover(_ data: Data, type: String) -> Data {
        guard type.hasPrefix("text/html") else { return data }
        guard let html = String(data: data, encoding: .utf8), !html.contains("viewport-fit=cover") else { return data }
        let patched = html.replacingOccurrences(
            of: "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
            with: "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1, viewport-fit=cover\">")
        return patched == html ? data : (patched.data(using: .utf8) ?? data)
    }

    private func isStopped(_ task: WKURLSchemeTask) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped.contains(ObjectIdentifier(task))
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        // No host check: this handler only ever sees the app's own scheme, and the host is server.hostname
        // (uposatha.dhamma.gift since 538a62e). It was == "localhost", which silently stopped the downloaded page.
        guard let url = urlSchemeTask.request.url, urlSchemeTask.request.httpMethod == "GET" else {
            return inner.webView(webView, start: urlSchemeTask)
        }
        var path = url.path
        if path == "" || path == "/" || path == "/index.html" || path == "/uposatha-calendar" || path == "/uposatha-calendar/" {
            path = "/uposatha-calendar.html"
        }
        if let file = DgSiteStore.file(for: path), let data = try? Data(contentsOf: file), !data.isEmpty {
            let type = Self.typeOf(path)
            let body = Self.withViewportCover(data, type: type)
            if let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: Self.headers(type, length: body.count)) {
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(body)
                urlSchemeTask.didFinish()
                return
            }
        }
        // Bundled: read and serve it ourselves. `inner` (Capacitor's own handler) answers strictly by url.path, and path
        // is remapped above for "/" and friends — delegating a remapped lookup to it would serve THAT literal path
        // (index.html, the offline splash) instead of the calendar page every "/" request actually wants.
        if let bundle = Bundle.main.url(forResource: "public" + path, withExtension: nil), let data = try? Data(contentsOf: bundle) {
            let type = Self.typeOf(path)
            let body = Self.withViewportCover(data, type: type)
            if let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: Self.headers(type, length: body.count)) {
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(body)
                urlSchemeTask.didFinish()
                return
            }
        }
        let last = (path as NSString).lastPathComponent
        let hasExtension = (last as NSString).pathExtension.count > 0
        if hasExtension && !path.hasPrefix("/_capacitor") {
            return proxy(url: url, task: urlSchemeTask, fallback: { self.inner.webView(webView, start: urlSchemeTask) })
        }
        // No extension and not bundled: Capacitor's own SPA fallback (its internal /_capacitor paths, or a route with no
        // matching file) — the one case genuinely meant for the original, unmodified request.
        inner.webView(webView, start: urlSchemeTask)
    }

    // The site's answer to a file the bundle has never had (the page or a script asks for something the snapshot did not see).
    // Offline it is a plain 404: the page copes with a missing extra file, and Capacitor's handler would only say the same.
    private func proxy(url: URL, task: WKURLSchemeTask, fallback: @escaping () -> Void) {
        guard var parts = URLComponents(string: dgSite) else { return fallback() }
        parts.path = url.path
        parts.query = url.query
        guard let target = parts.url else { return fallback() }
        var request = URLRequest(url: target, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"
        URLSession.shared.dataTask(with: request) { data, response, error in
            if self.isStopped(task) { return }
            guard let http = response as? HTTPURLResponse, let data = data, error == nil else {
                if let notFound = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Access-Control-Allow-Origin": "*"]) {
                    task.didReceive(notFound)
                    task.didReceive(Data())
                    task.didFinish()
                }
                return
            }
            let type = http.value(forHTTPHeaderField: "Content-Type") ?? Self.typeOf(url.path)
            if let answer = HTTPURLResponse(url: url, statusCode: http.statusCode, httpVersion: "HTTP/1.1", headerFields: Self.headers(type, length: data.count)) {
                task.didReceive(answer)
                task.didReceive(data)
                task.didFinish()
            }
        }.resume()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        lock.lock(); stopped.insert(ObjectIdentifier(urlSchemeTask)); lock.unlock()
        inner.webView(webView, stop: urlSchemeTask)
    }
}

// The bridge's updater (src/site-updater.js) hands the changed files of the page over here:
//
//     DgSite.put({ path: '/assets/js/x.js', data: <base64> })   DgSite.list()   DgSite.clear()
@objc(DgSitePlugin)
public class DgSitePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "DgSitePlugin"
    public let jsName = "DgSite"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "put", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "list", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clear", returnType: CAPPluginReturnPromise)
    ]

    private static let maxBytes = 12 * 1024 * 1024

    @objc func put(_ call: CAPPluginCall) {
        guard let path = call.getString("path"), let text = call.getString("data"),
              let file = DgSiteStore.file(for: path), let bytes = Data(base64Encoded: text) else {
            return call.reject("bad path or no data")
        }
        if bytes.isEmpty || bytes.count > Self.maxBytes { return call.reject("size out of range") }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Written beside and moved into place: a request that arrives half-way sees the old file or the new one.
            try bytes.write(to: file, options: .atomic)
            call.resolve()
        } catch {
            call.reject("DgSite.put failed: \(error.localizedDescription)")
        }
    }

    @objc func list(_ call: CAPPluginCall) {
        var files: [String] = []
        let root = DgSiteStore.root
        if let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in walker where !url.hasDirectoryPath && !url.lastPathComponent.hasSuffix(".part") {
                files.append(String(url.path.dropFirst(root.path.count)))
            }
        }
        call.resolve(["files": files])
    }

    @objc func clear(_ call: CAPPluginCall) {
        try? FileManager.default.removeItem(at: DgSiteStore.root)
        call.resolve()
    }
}

// MARK: - The safe-area insets

// Edge to edge (dg-apps#41) needs the page to know how far the status bar (the Dynamic Island) and
// the home indicator reach into it. Android's SystemBars plugin injects --safe-area-inset-* by
// itself; iOS has no such thing, and WKWebView's own env(safe-area-inset-*) is not dependable in an
// app — it read 62px in one run and 0 in the next two, same build and simulator (runs 446/448/449),
// which left the page's top bar under the clock.
//
// So the page ASKS for them, at the moment it is ready (the bridge's applyTopInset): the answer is
// the web view's own safeAreaInsets, which is what the system really reports. Registering a push
// instead (writing the variables from the native side) loses the write when it lands before the
// page's document exists — which is what run 451 showed.
@objc(DgInsetsPlugin)
public class DgInsetsPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "DgInsetsPlugin"
    public let jsName = "DgInsets"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "get", returnType: CAPPluginReturnPromise)
    ]

    @objc func get(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let insets = self.bridge?.webView?.safeAreaInsets ?? .zero
            call.resolve([
                "top": Double(insets.top),
                "right": Double(insets.right),
                "bottom": Double(insets.bottom),
                "left": Double(insets.left)
            ])
        }
    }
}

// MARK: - Share

// The system share sheet (dg-apps#56), the same call as on Android (DgSharePlugin.java): uposatha-bridge.js puts it behind the
// page's navigator.share, so both Share buttons open the sheet with the docs page instead of relying on the WKWebView's own
// Web Share. On an iPad the sheet is a popover, anchored to the middle of the screen.
//     Capacitor.Plugins.DgShare.share({ title, url })
@objc(DgSharePlugin)
public class DgSharePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "DgSharePlugin"
    public let jsName = "DgShare"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "share", returnType: CAPPluginReturnPromise)
    ]

    @objc func share(_ call: CAPPluginCall) {
        guard let url = URL(string: call.getString("url") ?? "") else { call.reject("No url to share"); return }
        let title = call.getString("title") ?? ""
        DispatchQueue.main.async {
            guard let host = self.bridge?.viewController else { call.reject("No view to show the sheet on"); return }
            let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if !title.isEmpty { sheet.setValue(title, forKey: "subject") }
            if let pop = sheet.popoverPresentationController {
                pop.sourceView = host.view
                pop.sourceRect = CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY, width: 0, height: 0)
                pop.permittedArrowDirections = []
            }
            sheet.completionWithItemsHandler = { _, _, _, _ in call.resolve() }
            host.present(sheet, animated: true)
        }
    }
}

// MARK: - Reminders

// The reminders as Time Sensitive notifications (they get through a Focus and the notification summary), each with its sound.
// The page's calls arrive through the bridge's wrapper of LocalNotifications (src/uposatha-bridge.js, wrapIosNotifications):
//
//     Capacitor.Plugins.DgNotify.schedule({ items: [{ id, title, body, at (ms), sound ('gong', '' for the default) }], renew: { title, body } })
//
// Identifiers are "dg-uposatha-<id>": a schedule replaces the reminder with that id, others are left alone. iOS keeps only the
// 64 soonest pending notifications of an app, and the page hands over up to 200 (dg-apps U2: reminders must keep coming without
// the app being opened). So the whole list is kept here (UserDefaults) and only the next ones are set; the rest are topped up at
// every start, every return to the front and in background refresh (BGAppRefreshTask, when iOS grants it). A minute after the
// last one set comes the quiet "renew" notice (its text from the page): open the app, or the reminders end there.
@objc(DgNotifyPlugin)
public class DgNotifyPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "DgNotifyPlugin"
    public let jsName = "DgNotify"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "schedule", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "cancel", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getPending", returnType: CAPPluginReturnPromise)
    ]

    private static let prefix = "dg-uposatha-"
    private static let limit = 60   // set at once: the next 59 reminders and the renew notice
    private static let planKey = "dgNotifyPlan"
    private static let renewKey = "dgNotifyRenew"
    private static let renewId = prefix + "renew"
    // Also in Info.plist (BGTaskSchedulerPermittedIdentifiers).
    static let refreshTask = "gift.dhamma.uposatha.reminders"

    // The sounds ship inside the page bundle (public/ios-sounds/*.caf); a notification finds its sound in the app's
    // Library/Sounds, so they are copied there once.
    override public func load() {
        let fm = FileManager.default
        if let source = Bundle.main.url(forResource: "ios-sounds", withExtension: nil, subdirectory: "public"),
           let library = fm.urls(for: .libraryDirectory, in: .userDomainMask).first {
            let target = library.appendingPathComponent("Sounds", isDirectory: true)
            try? fm.createDirectory(at: target, withIntermediateDirectories: true)
            for name in (try? fm.contentsOfDirectory(atPath: source.path)) ?? [] where name.hasSuffix(".caf") {
                let destination = target.appendingPathComponent(name)
                try? fm.removeItem(at: destination)
                try? fm.copyItem(at: source.appendingPathComponent(name), to: destination)
            }
        }
        Self.refill()
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            DgNotifyPlugin.refill()
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            DgNotifyPlugin.scheduleRefresh()
        }
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }

    private static func plan() -> [[String: Any]] {
        (UserDefaults.standard.array(forKey: planKey) as? [[String: Any]]) ?? []
    }

    private static func save(_ items: [[String: Any]]) {
        UserDefaults.standard.set(items, forKey: planKey)
    }

    // An absolute instant (dg-apps U6): with the zone in the components the trigger does not follow a later change of the
    // phone's zone (without it, a reminder for 17:42 rang at 17:42 of wherever the phone was by then).
    private static func trigger(at date: Date) -> UNCalendarNotificationTrigger {
        let calendar = Calendar.current
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        parts.timeZone = calendar.timeZone
        return UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    }

    private static func request(for item: [String: Any]) -> UNNotificationRequest? {
        guard let id = number(item["id"]), let at = number(item["at"]) else { return nil }
        let content = UNMutableNotificationContent()
        content.title = (item["title"] as? String) ?? ""
        content.body = (item["body"] as? String) ?? ""
        content.threadIdentifier = "uposatha"
        if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
        if let sound = item["sound"] as? String, !sound.isEmpty {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: sound + ".caf"))
        } else {
            content.sound = .default
        }
        return UNNotificationRequest(identifier: prefix + String(Int(id)), content: content, trigger: trigger(at: Date(timeIntervalSince1970: at / 1000)))
    }

    // The next ones of the kept list as notifications, the renew notice after the last of them; what is set from the list
    // beyond them is taken back. A pending one the list does not hold (set by an older version) is left to the page's cancel.
    static func refill(_ done: ((Int) -> Void)? = nil) {
        let now = Date().timeIntervalSince1970 * 1000
        let items = plan().filter { (number($0["at"]) ?? 0) > now }.sorted { (number($0["at"]) ?? 0) < (number($1["at"]) ?? 0) }
        save(items)
        // The Uposatha reminders (first) are set however far ahead they are; the meal and parts ones fill the rest, the soonest first,
        // and where they stop is where the renew notice goes.
        let firsts = items.filter { ($0["first"] as? Bool) == true }.prefix(limit - 1)
        let others = items.filter { ($0["first"] as? Bool) != true }
        let rest = others.prefix(limit - 1 - firsts.count)
        let next = (Array(firsts) + Array(rest)).sorted { (number($0["at"]) ?? 0) < (number($1["at"]) ?? 0) }
        var requests = next.compactMap { request(for: $0) }
        let end = rest.count < others.count ? rest.last : next.last
        if let lastAt = end.flatMap({ number($0["at"]) }), let text = UserDefaults.standard.dictionary(forKey: renewKey) as? [String: String] {
            let content = UNMutableNotificationContent()
            content.title = text["title"] ?? ""
            content.body = text["body"] ?? ""
            content.threadIdentifier = "uposatha"   // no sound: news, not an alarm
            requests.append(UNNotificationRequest(identifier: renewId, content: content, trigger: trigger(at: Date(timeIntervalSince1970: lastAt / 1000 + 60))))
        }
        let planned = Set(items.compactMap { number($0["id"]).map { prefix + String(Int($0)) } })
        let toSet = requests
        let wanted = Set(toSet.map { $0.identifier })
        let renew = renewId
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let stale = pending.map { $0.identifier }.filter { ($0 == renew || planned.contains($0)) && !wanted.contains($0) }
            if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
            let group = DispatchGroup()
            for r in toSet {
                group.enter()
                center.add(r) { _ in group.leave() }
            }
            group.notify(queue: .main) { done?(toSet.count) }
        }
    }

    // Background refresh: iOS runs it when it sees fit (not at all once the app has been swiped away), never sooner than asked.
    // Registered by AppDelegate before the launch ends, as BGTaskScheduler requires.
    static func registerRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTask, using: nil) { task in
            DgNotifyPlugin.scheduleRefresh()
            task.expirationHandler = { task.setTaskCompleted(success: false) }
            DgNotifyPlugin.refill { _ in task.setTaskCompleted(success: true) }
        }
    }

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTask)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    @objc func schedule(_ call: CAPPluginCall) {
        let now = Date().timeIntervalSince1970 * 1000
        var byId: [Int: [String: Any]] = [:]
        for item in Self.plan() {
            if let id = Self.number(item["id"]) { byId[Int(id)] = item }
        }
        for item in call.getArray("items", JSObject.self) ?? [] {
            guard let id = Self.number(item["id"]), let at = Self.number(item["at"]), at > now else { continue }
            byId[Int(id)] = ["id": Int(id), "at": at, "title": (item["title"] as? String) ?? "", "body": (item["body"] as? String) ?? "", "sound": (item["sound"] as? String) ?? "",
                             "first": (item["first"] as? Bool) ?? false]
        }
        Self.save(Array(byId.values))
        if let renew = call.getObject("renew"), let title = renew["title"] as? String, let body = renew["body"] as? String {
            UserDefaults.standard.set(["title": title, "body": body], forKey: Self.renewKey)
        }
        Self.refill { count in call.resolve(["count": count]) }
    }

    @objc func cancel(_ call: CAPPluginCall) {
        let numbers = (call.getArray("ids") ?? []).compactMap { Self.number($0) }.map { Int($0) }
        let gone = Set(numbers)
        Self.save(Self.plan().filter { !gone.contains(Int(Self.number($0["id"]) ?? -1)) })
        let ids = numbers.map { Self.prefix + String($0) }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
        Self.refill { _ in call.resolve() }
    }

    // The whole kept list, not only what is set: the page cancels what it sees here before it sets the list again.
    @objc func getPending(_ call: CAPPluginCall) {
        let now = Date().timeIntervalSince1970 * 1000
        let kept = Self.plan().filter { (Self.number($0["at"]) ?? 0) > now }.compactMap { Self.number($0["id"]).map { Int($0) } }
        UNUserNotificationCenter.current().getPendingNotificationRequests { pending in
            var ids = Set(kept)
            for r in pending where r.identifier.hasPrefix(Self.prefix) {
                if let id = Int(r.identifier.dropFirst(Self.prefix.count)) { ids.insert(id) }
            }
            call.resolve(["notifications": ids.sorted().map { ["id": $0] }])
        }
    }
}

// MARK: - Quick actions

// The Home Screen's long-press menu (up to four): the page hands over Calendar and the next Uposatha days,
//
//     Capacitor.Plugins.DgShortcuts.set({ items: [{ id, label, route, icon, rank }] })
//
// and a tap arrives as the route: at a cold start it waits for launchRoute(), while the app runs it comes as a 'shortcut' event.
// The icon is the name of a template image in the asset catalog (shortcut_moon_N), drawn in one colour by the system.
@objc(DgShortcutsPlugin)
public class DgShortcutsPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "DgShortcutsPlugin"
    public let jsName = "DgShortcuts"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "set", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "launchRoute", returnType: CAPPluginReturnPromise)
    ]

    static let routeKey = "route"
    static var pendingRoute: String?
    private static weak var current: DgShortcutsPlugin?

    override public func load() { Self.current = self }

    // A tap on a quick action (SceneDelegate): the route waits for the page, and is told to it when the page is there.
    static func deliver(_ item: UIApplicationShortcutItem) {
        guard let route = item.userInfo?[routeKey] as? String, !route.isEmpty else { return }
        pendingRoute = route
        current?.notifyListeners("shortcut", data: ["route": route])
    }

    // A tap in a home-screen / lock-screen widget (SceneDelegate): gift.dhamma.uposatha://open?tab=home|parts|cal|list[&day=YYYY-MM-DD],
    // or gift.dhamma.uposatha://route?path=/uposatha-calendar... . It becomes the same route a quick action carries.
    static func deliver(url: URL) {
        guard url.scheme == "gift.dhamma.uposatha", let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = parts.queryItems ?? []
        func query(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }
        var route: String
        if let path = query("path"), path.hasPrefix("/uposatha-calendar") {
            route = path
        } else {
            let tab = ["home", "parts", "cal", "list"].contains(query("tab") ?? "") ? (query("tab") ?? "home") : "home"
            route = "/uposatha-calendar?app=1&tab=\(tab)"
            if let day = query("day"), day.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil {
                route += "&day=\(day)"
            }
        }
        // A changing tail, so the page's "same route as now: do nothing" check never swallows a tap that is meant to switch tabs.
        route += (route.contains("?") ? "&" : "?") + "w=\(Int(Date().timeIntervalSince1970))"
        pendingRoute = route
        current?.notifyListeners("shortcut", data: ["route": route])
    }

    @objc func launchRoute(_ call: CAPPluginCall) {
        let route = Self.pendingRoute
        Self.pendingRoute = nil
        call.resolve(["route": route ?? ""])
    }

    @objc func set(_ call: CAPPluginCall) {
        let items = call.getArray("items", JSObject.self) ?? []
        let shortcuts: [UIApplicationShortcutItem] = items.prefix(4).compactMap { item in
            guard let route = item["route"] as? String, !route.isEmpty, let label = item["label"] as? String, !label.isEmpty else { return nil }
            let icon: UIApplicationShortcutIcon? = (item["icon"] as? String).flatMap { $0.isEmpty ? nil : UIApplicationShortcutIcon(templateImageName: $0) }
            return UIApplicationShortcutItem(
                type: "dg.route",
                localizedTitle: label,
                localizedSubtitle: nil,
                icon: icon,
                userInfo: [Self.routeKey: route as NSString]
            )
        }
        DispatchQueue.main.async {
            UIApplication.shared.shortcutItems = shortcuts
            call.resolve(["count": shortcuts.count])
        }
    }
}

// MARK: - Widget

// The home-screen / lock-screen widget (the UposathaWidget extension) lays out the data the page builds (window.__upoWidgetData,
// uposatha/widget/WIDGET.md): the page hands it over after each paint,
//
//     Capacitor.Plugins.DgWidget.put({ json: "<the object as a string>" })
//
// and it is kept in the App Group the extension reads (UserDefaults key "data"). The widget calculates nothing itself.
@objc(DgWidgetPlugin)
public class DgWidgetPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "DgWidgetPlugin"
    public let jsName = "DgWidget"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "put", returnType: CAPPluginReturnPromise)
    ]

    static let appGroup = "group.gift.dhamma.uposatha"

    @objc func put(_ call: CAPPluginCall) {
        guard let json = call.getString("json"), !json.isEmpty else {
            call.reject("json is required")
            return
        }
        guard let defaults = UserDefaults(suiteName: Self.appGroup) else {
            call.reject("the App Group is not available")
            return
        }
        defaults.set(json, forKey: "data")
        WidgetCenter.shared.reloadAllTimelines()
        call.resolve()
    }
}
