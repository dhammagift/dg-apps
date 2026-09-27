import UIKit
import WebKit
import UserNotifications
import Capacitor

// Everything of the app that is not an npm plugin, in one file: the bridge view controller, the reminders (DgNotify) and
// the Home Screen quick actions (DgShortcuts). The same contract as Android's DgAlarm/DgSound and DgShortcuts plugins, as far as
// iOS has the same things: no notification channels or streams here, no launcher icon change.

// The root: the page sits inside the safe area (under the status bar and above the home indicator) on the page's own colour, so
// nothing of it is hidden by the Dynamic Island or the home bar.
final class DgRootViewController: UIViewController {
    private let bridgeController = DgBridgeViewController()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
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

    override func capacitorDidLoad() {
        // Edge swipe = browser Back (a WKWebView leaves it off), and there is no Back button on iOS.
        webView?.allowsBackForwardNavigationGestures = true
        // No scroll indicators: the page is the whole interface.
        webView?.scrollView.showsVerticalScrollIndicator = false
        webView?.scrollView.showsHorizontalScrollIndicator = false

        // The bridge (www/uposatha-bridge.js, the same file Android injects) runs before the page's own scripts. Added here and not
        // in webViewConfiguration(for:), because Capacitor replaces the user content controller after that call.
        if let url = Bundle.main.url(forResource: "uposatha-bridge", withExtension: "js", subdirectory: "public"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            webView?.configuration.userContentController.addUserScript(
                WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        bridge?.registerPluginInstance(DgNotifyPlugin())
        bridge?.registerPluginInstance(DgShortcutsPlugin())
        bridge?.registerPluginInstance(DgSitePlugin())
        #if DEBUG
        // Debug builds only, for the same reason as the reader app's DgSelfTestPlugin: the App Store screenshot
        // tour (test/ios-sim/tour.js) needs one native call to say which view is on screen; a release build's
        // Capacitor.Plugins.DgSelfTest is undefined.
        bridge?.registerPluginInstance(DgSelfTestPlugin())
        #endif
    }
}

// MARK: - The bundled page and its updates

// Where the page comes from: the same site as SITE_CONFIG in uposatha-bridge.js (test for now, dhamma.gift later).
private let dgSite = "https://test.dhamma.gift"

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

    private func isStopped(_ task: WKURLSchemeTask) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped.contains(ObjectIdentifier(task))
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, urlSchemeTask.request.httpMethod == "GET", url.host == "localhost" else {
            return inner.webView(webView, start: urlSchemeTask)
        }
        var path = url.path
        if path == "" || path == "/" || path == "/index.html" || path == "/uposatha-calendar" || path == "/uposatha-calendar/" {
            path = "/uposatha-calendar.html"
        }
        if let file = DgSiteStore.file(for: path), let data = try? Data(contentsOf: file), !data.isEmpty {
            let type = Self.typeOf(path)
            if let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: Self.headers(type, length: data.count)) {
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
                return
            }
        }
        // Bundled: read and serve it ourselves. `inner` (Capacitor's own handler) answers strictly by url.path, and path
        // is remapped above for "/" and friends — delegating a remapped lookup to it would serve THAT literal path
        // (index.html, the offline splash) instead of the calendar page every "/" request actually wants.
        if let bundle = Bundle.main.url(forResource: "public" + path, withExtension: nil), let data = try? Data(contentsOf: bundle) {
            let type = Self.typeOf(path)
            if let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: Self.headers(type, length: data.count)) {
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
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

// MARK: - Reminders

// The reminders as Time Sensitive notifications (they get through a Focus and the notification summary), each with its sound.
// The page's calls arrive through the bridge's wrapper of LocalNotifications (src/uposatha-bridge.js, wrapIosNotifications):
//
//     Capacitor.Plugins.DgNotify.schedule({ items: [{ id, title, body, at (ms), sound ('gong', '' for the default) }] })
//
// Identifiers are "dg-uposatha-<id>": a schedule replaces the reminder with that id, others are left alone. iOS keeps only the
// 64 soonest pending notifications of an app, so the ones further away are not set (the page sets them again at its next start).
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
    private static let limit = 60

    // The sounds ship inside the page bundle (public/ios-sounds/*.caf); a notification finds its sound in the app's
    // Library/Sounds, so they are copied there once.
    override public func load() {
        let fm = FileManager.default
        guard let source = Bundle.main.url(forResource: "ios-sounds", withExtension: nil, subdirectory: "public"),
              let library = fm.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        let target = library.appendingPathComponent("Sounds", isDirectory: true)
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        for name in (try? fm.contentsOfDirectory(atPath: source.path)) ?? [] where name.hasSuffix(".caf") {
            let destination = target.appendingPathComponent(name)
            try? fm.removeItem(at: destination)
            try? fm.copyItem(at: source.appendingPathComponent(name), to: destination)
        }
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }

    @objc func schedule(_ call: CAPPluginCall) {
        let items = call.getArray("items", JSObject.self) ?? []
        let center = UNUserNotificationCenter.current()
        var requests: [UNNotificationRequest] = []
        for item in items {
            guard let id = Self.number(item["id"]), let at = Self.number(item["at"]), at > 0 else { continue }
            let date = Date(timeIntervalSince1970: at / 1000)
            if date <= Date() { continue }
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
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            requests.append(UNNotificationRequest(identifier: Self.prefix + String(Int(id)), content: content, trigger: trigger))
        }
        center.getPendingNotificationRequests { pending in
            // Ours that stay + the new ones, the soonest first, cut to the limit.
            let replaced = Set(requests.map { $0.identifier })
            let kept = pending.filter { $0.identifier.hasPrefix(Self.prefix) && !replaced.contains($0.identifier) }
            func when(_ r: UNNotificationRequest) -> Date {
                (r.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? Date.distantFuture
            }
            let all = (kept + requests).sorted { when($0) < when($1) }
            let dropped = all.dropFirst(Self.limit).map { $0.identifier }
            let keep = Set(all.prefix(Self.limit).map { $0.identifier })
            if !dropped.isEmpty { center.removePendingNotificationRequests(withIdentifiers: dropped) }
            let group = DispatchGroup()
            for r in requests where keep.contains(r.identifier) {
                group.enter()
                center.add(r) { _ in group.leave() }
            }
            group.notify(queue: .main) { call.resolve(["count": keep.count]) }
        }
    }

    @objc func cancel(_ call: CAPPluginCall) {
        let ids = (call.getArray("ids") ?? []).compactMap { Self.number($0) }.map { Self.prefix + String(Int($0)) }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
        call.resolve()
    }

    @objc func getPending(_ call: CAPPluginCall) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { pending in
            let list: [[String: Any]] = pending.compactMap { r in
                guard r.identifier.hasPrefix(Self.prefix), let id = Int(r.identifier.dropFirst(Self.prefix.count)) else { return nil }
                return ["id": id]
            }
            call.resolve(["notifications": list])
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
