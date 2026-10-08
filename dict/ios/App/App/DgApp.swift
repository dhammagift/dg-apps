import UIKit
import WebKit
import Capacitor

// Everything of the app that is not an npm plugin, in one file: the bridge view controller, the bundled page (with
// its own updater and site fallback) and the Home Screen quick actions ("recent words"). The same shape as
// Uposatha's DgApp.swift (uposatha/ios/App/App/DgApp.swift) and Android's DgSitePlugin/DgShortcutsPlugin.

// The page's own background (white by day, #111111 at night): what shows behind the first paint and at the overscroll edges.
// A dynamic colour, so the system's appearance switch re-tints it the way the page re-tints itself.
private let dgPageBackground = UIColor { traits in
    traits.userInterfaceStyle == .dark
        ? UIColor(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1)
        : UIColor.white
}

// The root: the page runs EDGE TO EDGE, as in Uposatha (uposatha/ios/App/App/DgApp.swift) and on Android - the WKWebView spans
// the whole screen under the transparent status bar and the home indicator, and the page keeps clear of them itself
// (viewport-fit=cover, env(safe-area-inset-*): src/dict-edge.js). It used to sit inside the safe area, and what was above
// and below it was this view's colour, not the page's.
final class DgRootViewController: UIViewController {
    private let bridgeController = DgBridgeViewController()

    // The status bar's icon colour is the page's decision: dict-edge.js calls SystemBars.setStyle on a theme change, which lands
    // on the bridge controller's preferredStatusBarStyle; UIKit asks the window's root (this one), so the query is forwarded.
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

    // Capacitor registers its asset handler for capacitor://localhost on the configuration this returns, after it
    // returns: the one moment the site's downloaded files (DgSite) can be put in front of the bundled ones.
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

    // The keyboard's height for the page (the Pali letters row, src/pali-bar.js, waits for it): how far the keyboard reaches into the
    // web view, in points (= css px). willChangeFrame also fires when the suggestion strip comes or goes, so the row follows the
    // keyboard's real top edge; the strip is part of the keyboard's frame.
    private func watchKeyboard() {
        let center = NotificationCenter.default
        center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
            guard let self = self, let webView = self.webView, let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let frame = webView.convert(webView.bounds, to: nil)
            let overlap = max(0, frame.maxY - end.minY)
            self.reportKeyboard(overlap)
        }
        center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reportKeyboard(0)
        }
    }

    // The strip with the arrows and the check mark that iOS puts above the keyboard for a web page's field: the letters row sat on
    // top of it with an empty gap between, and the strip does nothing the dictionary needs (one field). The web view's content
    // view is given a subclass whose inputAccessoryView is nil - the same way the Capacitor Keyboard plugin hides it.
    private func hideFormAccessoryBar() {
        guard let webView = webView else { return }
        for subview in webView.scrollView.subviews where String(describing: type(of: subview)).hasPrefix("WKContent") {
            let name = "\(type(of: subview))_NoInputAccessoryView"
            var target: AnyClass? = NSClassFromString(name)
            if target == nil, let base = object_getClass(subview), let created = objc_allocateClassPair(base, name, 0) {
                let selector = #selector(getter: UIResponder.inputAccessoryView)
                if let method = class_getInstanceMethod(UIView.self, selector) {
                    let block: @convention(block) (AnyObject) -> AnyObject? = { _ in nil }
                    class_addMethod(created, selector, imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self)), method_getTypeEncoding(method))
                }
                objc_registerClassPair(created)
                target = created
            }
            if let target = target { object_setClass(subview, target) }
        }
    }

    private func reportKeyboard(_ points: CGFloat) {
        webView?.evaluateJavaScript("window.__dgIme && window.__dgIme(\(Int(points.rounded())))", completionHandler: nil)
    }

    override func capacitorDidLoad() {
        webView?.allowsBackForwardNavigationGestures = true
        webView?.scrollView.showsVerticalScrollIndicator = false
        webView?.scrollView.showsHorizontalScrollIndicator = false

        // The bridge (www/dict-bridge.js, the same file Android injects) runs before the page's own scripts. The app's version
        // goes in front of it, as on Android (MainActivity), for the version row of the menu.
        if let url = Bundle.main.url(forResource: "dict-bridge", withExtension: "js", subdirectory: "public"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            let info = Bundle.main.infoDictionary
            let version = "\(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
            let quoted = (try? JSONSerialization.data(withJSONObject: [version]))
                .flatMap { String(data: $0, encoding: .utf8) }
                .map { String($0.dropFirst().dropLast()) } ?? "\"\""
            webView?.configuration.userContentController.addUserScript(
                WKUserScript(source: "window.__DG_APP_VERSION__=\(quoted);\n" + source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        watchKeyboard()
        hideFormAccessoryBar()

        bridge?.registerPluginInstance(DgShortcutsPlugin())
        bridge?.registerPluginInstance(DgSitePlugin())
        #if DEBUG
        // Debug builds only: the App Store screenshot tour (test/ios-sim/tour.js) needs one native call to say
        // which view is on screen; a release build's Capacitor.Plugins.DgSelfTest is undefined.
        bridge?.registerPluginInstance(DgSelfTestPlugin())
        #endif
    }
}

// MARK: - The bundled page and its updates

// Where the page comes from: the same site as SITE in dict-bridge.js / DgSitePlugin.java.
private let dgSite = "https://dict.dhamma.gift"

// Files of the page downloaded from the site (by the bridge's updater, through DgSite.put) live here and are
// answered in front of the bundled ones; nothing is ever deleted but by DgSite.clear.
enum DgSiteStore {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("site", isDirectory: true)
    }

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

// In order: the downloaded copy; a bundled directory's index.html ("/ru/" -> "/ru/index.html"); a bundled file at
// the literal path; anything else (a word's page, made by the site's server) is proxied from the site.
final class DgSiteRouter: NSObject, WKURLSchemeHandler {
    private let inner: WKURLSchemeHandler
    private var stopped = Set<ObjectIdentifier>()
    private let lock = NSLock()

    init(inner: WKURLSchemeHandler) { self.inner = inner }

    private static let types = [
        "html": "text/html; charset=utf-8", "js": "application/javascript; charset=utf-8", "mjs": "application/javascript; charset=utf-8",
        "css": "text/css; charset=utf-8", "json": "application/json; charset=utf-8", "svg": "image/svg+xml", "woff2": "font/woff2",
        "woff": "font/woff", "wasm": "application/wasm", "txt": "text/plain; charset=utf-8",
        "png": "image/png", "jpg": "image/jpeg", "webp": "image/webp", "mp3": "audio/mpeg", "ico": "image/x-icon"
    ]

    private static func typeOf(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        return types[ext] ?? "application/octet-stream"
    }

    private static func headers(_ type: String, length: Int) -> [String: String] {
        ["Content-Type": type, "Content-Length": String(length), "Access-Control-Allow-Origin": "*", "Cache-Control": "no-cache"]
    }

    private static func bundled(_ path: String) -> URL? {
        Bundle.main.url(forResource: "public" + path, withExtension: nil)
    }

    private static func answer(_ url: URL, from file: URL, task: WKURLSchemeTask) -> Bool {
        guard let data = try? Data(contentsOf: file) else { return false }
        // The TYPE from the FILE actually being served, not url.path: the root request ("capacitor://localhost",
        // no trailing slash at all) has an EMPTY path, and typeOf("") fell back to application/octet-stream —
        // which WebKit refuses to render as a page at all ("Frame load interrupted"), even though the bytes were
        // the real, correct index.html.
        let type = typeOf(file.lastPathComponent)
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers(type, length: data.count)) else { return false }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
        return true
    }

    private func isStopped(_ task: WKURLSchemeTask) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped.contains(ObjectIdentifier(task))
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, urlSchemeTask.request.httpMethod == "GET", url.host == "localhost" else {
            return inner.webView(webView, start: urlSchemeTask)
        }
        let path = url.path
        if path.hasPrefix("/_capacitor") || path == "/cordova.js" || path == "/favicon.ico" {
            return inner.webView(webView, start: urlSchemeTask)
        }
        // "/ru/" and "/ru" are a directory (the site's own convention: an extensionless path is one); Capacitor
        // itself only knows to answer "/" that way, so "/ru" needs the same help here.
        let last = (path as NSString).lastPathComponent
        let isDirectory = path.hasSuffix("/") || !last.contains(".")
        let indexPath = path.hasSuffix("/") ? path + "index.html" : path + "/index.html"
        let file = isDirectory ? indexPath : path

        if let downloaded = DgSiteStore.file(for: file), Self.answer(url, from: downloaded, task: urlSchemeTask) { return }
        if isDirectory, let bundle = Self.bundled(indexPath), Self.answer(url, from: bundle, task: urlSchemeTask) { return }
        if !isDirectory, let bundle = Self.bundled(path), Self.answer(url, from: bundle, task: urlSchemeTask) { return }
        proxy(url: url, task: urlSchemeTask, fallback: { self.inner.webView(webView, start: urlSchemeTask) })
    }

    // The site's answer for a word's page (made by the site's server, not in the bundle). Offline it is a plain
    // 404: the page copes with a missing extra file, and Capacitor's handler would only say the same.
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
                    task.didReceive(notFound); task.didReceive(Data()); task.didFinish()
                }
                return
            }
            let type = http.value(forHTTPHeaderField: "Content-Type") ?? Self.typeOf(url.path)
            if let answer = HTTPURLResponse(url: url, statusCode: http.statusCode, httpVersion: "HTTP/1.1", headerFields: Self.headers(type, length: data.count)) {
                task.didReceive(answer); task.didReceive(data); task.didFinish()
            }
        }.resume()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        lock.lock(); stopped.insert(ObjectIdentifier(urlSchemeTask)); lock.unlock()
        inner.webView(webView, stop: urlSchemeTask)
    }
}

// The bridge's updater hands the changed files of the page over here:
//     DgSite.put({ path, data })   DgSite.list()   DgSite.clear()
@objc(DgSitePlugin)
public class DgSitePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "DgSitePlugin"
    public let jsName = "DgSite"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "put", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "list", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clear", returnType: CAPPluginReturnPromise)
    ]

    private static let maxBytes = 8 * 1024 * 1024

    @objc func put(_ call: CAPPluginCall) {
        guard let path = call.getString("path"), let text = call.getString("data"),
              let file = DgSiteStore.file(for: path), let bytes = Data(base64Encoded: text) else {
            return call.reject("bad path or no data")
        }
        if bytes.isEmpty || bytes.count > Self.maxBytes { return call.reject("size out of range") }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
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

// MARK: - Quick actions ("recent words")

// The Home Screen's long-press menu: the page hands over its lookup history,
//     Capacitor.Plugins.DgShortcuts.set({ items: [{ id, label, route, icon, rank }] })
// and a tap arrives as the route: at a cold start it waits for launchRoute(), while the app runs it comes as a
// 'shortcut' event. Same contract as Uposatha's DgShortcutsPlugin.
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

    static func deliver(_ item: UIApplicationShortcutItem) {
        guard let route = item.userInfo?[routeKey] as? String, !route.isEmpty else { return }
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
            return UIApplicationShortcutItem(type: "dg.route", localizedTitle: label, localizedSubtitle: nil, icon: icon, userInfo: [Self.routeKey: route as NSString])
        }
        DispatchQueue.main.async {
            UIApplication.shared.shortcutItems = shortcuts
            call.resolve(["count": shortcuts.count])
        }
    }
}
