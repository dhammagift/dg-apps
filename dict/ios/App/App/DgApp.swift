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

    // The strip with the arrows and the check mark that iOS puts above the keyboard for a web page's field does nothing the
    // dictionary needs (one field). The web view's content view is given a subclass whose inputAccessoryView is the Pāli
    // letters row (DgPaliAccessory, below) - or nil when it is switched off in the menu: the row is part of the keyboard then,
    // drawn and moved by iOS with it. (It used to be a row of the page, placed by script from the keyboard's height: on an
    // iPhone it shook over the keyboard while the page scrolled, owner 2026-10-11 - "как трещотка трясется".)
    private func hideFormAccessoryBar() {
        guard let webView = webView else { return }
        for subview in webView.scrollView.subviews where String(describing: type(of: subview)).hasPrefix("WKContent") {
            let name = "\(type(of: subview))_NoInputAccessoryView"
            var target: AnyClass? = NSClassFromString(name)
            if target == nil, let base = object_getClass(subview), let created = objc_allocateClassPair(base, name, 0) {
                let selector = #selector(getter: UIResponder.inputAccessoryView)
                if let method = class_getInstanceMethod(UIView.self, selector) {
                    let block: @convention(block) (AnyObject) -> AnyObject? = { content in
                        guard DgPaliAccessory.enabled else { return nil }
                        let bar = DgPaliAccessory.shared
                        bar.target = content as? UIView
                        return bar
                    }
                    class_addMethod(created, selector, imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self)), method_getTypeEncoding(method))
                }
                objc_registerClassPair(created)
                target = created
            }
            if let target = target { object_setClass(subview, target) }
        }
    }

    // The status bar's and the home indicator's reach, written into the page as --safe-area-inset-* (dict-edge.js pads the page
    // and sizes its top strip by them). WKWebView's own env(safe-area-inset-top) is not dependable in an app (Uposatha's
    // DgApp.swift: 62 px in one run, 0 in the next): with 0 the strip had no height and a scrolled page ran under the clock
    // (owner, TestFlight 561). Written on every layout change; the page also asks DgInsets.get() when it starts, since a write
    // that lands before the document exists is lost.
    private func pushSafeAreaInsets() {
        guard let webView = webView else { return }
        let i = webView.safeAreaInsets
        let js = "try{var r=document.documentElement.style;r.setProperty('--safe-area-inset-top','\(i.top)px');r.setProperty('--safe-area-inset-right','\(i.right)px');r.setProperty('--safe-area-inset-bottom','\(i.bottom)px');r.setProperty('--safe-area-inset-left','\(i.left)px');}catch(e){}"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pushSafeAreaInsets()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        pushSafeAreaInsets()
    }

    private func reportKeyboard(_ points: CGFloat) {
        webView?.evaluateJavaScript("window.__dgIme && window.__dgIme(\(Int(points.rounded())))", completionHandler: nil)
    }

    override func capacitorDidLoad() {
        webView?.allowsBackForwardNavigationGestures = true
        webView?.scrollView.showsVerticalScrollIndicator = false
        webView?.scrollView.showsHorizontalScrollIndicator = false
        // Pull to refresh holds the page on screen while it reloads (DgPullHold below, src/pull-refresh.js).
        webView?.configuration.userContentController.add(DgPullHold(webView), name: "dgPullHold")

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
        webView?.configuration.userContentController.add(DgPaliSwitch(), name: "dgPaliBar")

        bridge?.registerPluginInstance(DgShortcutsPlugin())
        bridge?.registerPluginInstance(DgSitePlugin())
        bridge?.registerPluginInstance(DgInsetsPlugin())
        for delay in [0.5, 2.0, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.pushSafeAreaInsets() }
        }
        #if DEBUG
        // Debug builds only: the App Store screenshot tour (test/ios-sim/tour.js) needs one native call to say
        // which view is on screen; a release build's Capacitor.Plugins.DgSelfTest is undefined.
        bridge?.registerPluginInstance(DgSelfTestPlugin())
        #endif
    }
}

// MARK: - The Pāli letters row on the keyboard

// The letters row as part of the keyboard (inputAccessoryView of the web view's content view): the keyboard's own background
// (UIInputView .keyboard), keys drawn like the keyboard's, and a tap types the letter the way a key does - insertText on the
// content view, so the page gets the same input events as from the keyboard (Velthuis, suggestions). Paste reads the clipboard
// only when tapped. "…" opens the second row. The same letters as src/pali-bar.js, which draws the row on Android.
final class DgPaliAccessory: UIInputView {
    static var enabled = true
    static let shared = DgPaliAccessory()
    // The page's theme, from src/pali-bar.js: the row is drawn on the page's own background, solid - on iOS 26 the keyboard is
    // glass, and the row's .keyboard background came out see-through, letters on the bare page (owner, TestFlight 563).
    static var dark = false {
        didSet { if dark != oldValue { shared.paint() } }
    }
    weak var target: UIView?

    private static let main = ["ā", "ī", "ū", "ṁ", "ṅ", "ñ", "ṭ", "ḍ", "ṇ", "ḷ"]
    private static let more = ["ṃ", "ś", "ṣ", "ṛ", "ṝ", "ḹ", "ḥ"]
    private let stack = UIStackView()
    private let moreRow = UIStackView()
    private var height: NSLayoutConstraint!

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 50), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let row = UIStackView()
        row.spacing = 5
        row.distribution = .fill
        let paste = key(nil, symbol: "doc.on.clipboard")
        paste.accessibilityLabel = "Paste"
        paste.addAction(UIAction { [weak self] _ in
            guard let text = UIPasteboard.general.string else { return }
            self?.type(text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " "))
        }, for: .touchUpInside)
        paste.widthAnchor.constraint(equalToConstant: 44).isActive = true
        row.addArrangedSubview(paste)
        let letters = UIStackView()
        letters.spacing = 5
        letters.distribution = .fillEqually
        Self.main.forEach { letters.addArrangedSubview(letterKey($0)) }
        row.addArrangedSubview(letters)
        let dots = key("…", symbol: nil)
        dots.accessibilityLabel = "More letters"
        dots.widthAnchor.constraint(equalToConstant: 40).isActive = true
        dots.addAction(UIAction { [weak self] _ in self?.toggleMore() }, for: .touchUpInside)
        row.addArrangedSubview(dots)
        moreRow.spacing = 5
        moreRow.distribution = .fillEqually
        Self.more.forEach { moreRow.addArrangedSubview(letterKey($0)) }
        moreRow.isHidden = true
        stack.addArrangedSubview(row)
        stack.addArrangedSubview(moreRow)
        paint()
        height = heightAnchor.constraint(equalToConstant: 50)
        height.priority = .defaultHigh
        NSLayoutConstraint.activate([
            height,
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -4),
            row.heightAnchor.constraint(equalToConstant: 40),
            moreRow.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func paint() {
        let dark = Self.dark
        backgroundColor = dark ? UIColor(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1) : .white
        overrideUserInterfaceStyle = dark ? .dark : .light
        let keyColor = dark ? UIColor(white: 0.24, alpha: 1) : UIColor(white: 0.93, alpha: 1)
        func keys(_ v: UIView) -> [UIButton] { (v as? UIButton).map { [$0] } ?? v.subviews.flatMap(keys) }
        keys(stack).forEach { $0.backgroundColor = keyColor }
    }

    private func type(_ text: String) {
        guard !text.isEmpty else { return }
        UIDevice.current.playInputClick()
        (target as? UIKeyInput)?.insertText(text)
    }

    private func toggleMore() {
        moreRow.isHidden.toggle()
        height.constant = moreRow.isHidden ? 50 : 96
        target?.reloadInputViews()
    }

    private func letterKey(_ letter: String) -> UIButton {
        let b = key(letter, symbol: nil)
        // A sans-serif l with a dot under it reads as "!": these two are set in a serif face, as on Android.
        if letter == "ḷ" || letter == "ḹ" { b.titleLabel?.font = UIFont(name: "Georgia", size: 23) }
        b.addAction(UIAction { [weak self] _ in self?.type(letter) }, for: .touchUpInside)
        return b
    }

    // Drawn like the keyboard's own keys: white on the light keyboard, grey on the dark one, rounded, a hairline shadow below.
    private func key(_ title: String?, symbol: String?) -> UIButton {
        let b = UIButton(type: .system)
        if let title = title { b.setTitle(title, for: .normal) }
        if let symbol = symbol { b.setImage(UIImage(systemName: symbol), for: .normal) }
        b.titleLabel?.font = .systemFont(ofSize: 22)
        b.tintColor = .label
        b.setTitleColor(.label, for: .normal)
        b.layer.cornerRadius = 6
        b.layer.shadowColor = UIColor.black.cgColor
        b.layer.shadowOpacity = 0.3
        b.layer.shadowRadius = 0
        b.layer.shadowOffset = CGSize(width: 0, height: 1)
        return b
    }
}

extension DgPaliAccessory: UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

// The menu's switch ("Pāli letters above the keyboard", src/pali-bar.js posts 'on'/'off'): the row is there only when it is on.
final class DgPaliSwitch: NSObject, WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = (message.body as? String) ?? "on"
        DgPaliAccessory.dark = body.hasSuffix("dark")
        let on = !body.hasPrefix("off")
        if DgPaliAccessory.enabled == on { return }
        DgPaliAccessory.enabled = on
        DgPaliAccessory.shared.target?.reloadInputViews()
    }
}

// MARK: - The safe-area insets (the same plugin as Uposatha's)

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

// In order: the downloaded copy; a bundled directory's index.html ("/ru/" -> "/ru/index.html"); a word's page ("/dukkha",
// "/ru/dukkha": the language's bundled page, as the site answers it); a bundled file at the literal path; anything else is
// proxied from the site.
final class DgSiteRouter: NSObject, WKURLSchemeHandler {
    private let inner: WKURLSchemeHandler
    // Proxied tasks still waiting for the site. WebKit calls start/stop on the main thread and the answer is handed over there
    // too, so no lock: a task leaves this set exactly once, answered or stopped. While it is in here the request's closure
    // holds it, so its identity (an address) cannot be taken by a new task.
    private var waiting = Set<ObjectIdentifier>()

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

    // True for the first of "the site answered" and "WebKit stopped it" (main thread only).
    private func claim(_ task: WKURLSchemeTask) -> Bool {
        waiting.remove(ObjectIdentifier(task)) != nil
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, urlSchemeTask.request.httpMethod == "GET", url.host == "localhost" else {
            return inner.webView(webView, start: urlSchemeTask)
        }
        var path = url.path
        if path.hasPrefix("/_capacitor") || path == "/cordova.js" || path == "/favicon.ico" {
            return inner.webView(webView, start: urlSchemeTask)
        }
        // The ru page's static/ is a link to /static/ on the site: the bundle (and the updater) keep the one copy.
        if path.hasPrefix("/ru/static/") { path = String(path.dropFirst("/ru".count)) }
        // "/ru/" and "/ru" are a directory (the site's own convention: an extensionless path is one); Capacitor
        // itself only knows to answer "/" that way, so "/ru" needs the same help here.
        let last = (path as NSString).lastPathComponent
        let isDirectory = path.hasSuffix("/") || !last.contains(".")
        var indexPath = path.hasSuffix("/") ? path + "index.html" : path + "/index.html"
        // A word's page ("/dukkha", "/ru/dukkha") is the language's page itself on the site too (ddg-ui .htaccess), and the
        // page reads the word from the address: the bundled page answers it, with no network and with the bundle's own scripts.
        // Not "/dukkha/" (url.path drops the slash): there the page's relative static/ would point under /dukkha/.
        if isDirectory, !url.hasDirectoryPath, Self.bundled(indexPath) == nil {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            if parts.count == 2, !parts[1].isEmpty { indexPath = "/index.html" }
            else if parts.count == 3, parts[1] == "ru", !parts[2].isEmpty { indexPath = "/ru/index.html" }
        }
        let file = isDirectory ? indexPath : path

        if let downloaded = DgSiteStore.file(for: file), Self.answer(url, from: downloaded, task: urlSchemeTask) { return }
        if isDirectory, let bundle = Self.bundled(indexPath), Self.answer(url, from: bundle, task: urlSchemeTask) { return }
        if !isDirectory, let bundle = Self.bundled(path), Self.answer(url, from: bundle, task: urlSchemeTask) { return }
        proxy(url: url, task: urlSchemeTask, fallback: { self.inner.webView(webView, start: urlSchemeTask) })
    }

    // The site's answer for what the bundle does not have (a word's page is the bundled page, above). Offline it is a plain
    // 404: the page copes with a missing extra file, and Capacitor's handler would only say the same.
    private func proxy(url: URL, task: WKURLSchemeTask, fallback: @escaping () -> Void) {
        guard var parts = URLComponents(string: dgSite) else { return fallback() }
        parts.path = url.path
        parts.query = url.query
        guard let target = parts.url else { return fallback() }
        var request = URLRequest(url: target, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"
        waiting.insert(ObjectIdentifier(task))
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                // Stopped meanwhile (a new search, the page left): WebKit raises on an answer to a stopped task.
                guard self.claim(task) else { return }
                guard let http = response as? HTTPURLResponse, let data = data, error == nil else {
                    if let notFound = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Access-Control-Allow-Origin": "*"]) {
                        task.didReceive(notFound); task.didReceive(Data()); task.didFinish()
                    }
                    return
                }
                let type = http.value(forHTTPHeaderField: "Content-Type") ?? Self.typeOf(url.path)
                if let answer = HTTPURLResponse(url: url, statusCode: http.statusCode, httpVersion: "HTTP/1.1", headerFields: Self.headers(type, length: data.count)) {
                    task.didReceive(answer); task.didReceive(data); task.didFinish()
                } else {
                    task.didFailWithError(URLError(.badServerResponse))
                }
            }
        }.resume()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // A proxied task is ours alone (Capacitor's handler never saw it); anything else is Capacitor's to stop.
        if claim(urlSchemeTask) { return }
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
