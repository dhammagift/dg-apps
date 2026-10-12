import UIKit
import Capacitor

// "Recently read" in the Home Screen's long-press menu: the iOS half of Android's
// DgShortcutsPlugin, on the same contract — native code cannot read the page's history, so the page
// hands over a ready list and this turns it into quick actions:
//
//     Capacitor.Plugins.DgShortcuts.set({ items: [{ id, label, route, rank }] })
//
// Tapping one must open that route, and it does so by posting the app's own deep-link URL
// (dhammagift://route/<route>) through Capacitor's openURL notification. That is not a shortcut of
// its own: it is the path already covered by test/deep-link.test.js and by the simulator's deep-link
// check — the mapping, the SPA rewrite and the reload-loop guard all apply, and the app grows no
// second way to open a page.
//
// The same handler serves the STATIC quick action declared in the app's Info.plist, which until
// now did nothing at all on iOS: its userInfo carries the same "route" key.
//
// iOS shows at most FOUR quick actions, statics first. Info.plist declares one (Favorites & History),
// as Android does, so the three "recently read" texts fit; with four statics they never showed
// (owner, 2026-10-12).
@objc(DgShortcutsPlugin)
public class DgShortcutsPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "DgShortcutsPlugin"
    public let jsName = "DgShortcuts"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "set", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "get", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "open", returnType: CAPPluginReturnPromise)
    ]

    static let routeKey = "route"
    static let itemType = "dg.route"

    // A shortcut that launched the app: the bridge and its plugins do not exist yet, so the URL waits
    // for capacitorViewDidAppear — the same hook Capacitor's own SceneDelegateProxy uses for a
    // cold-start openURL.
    static var pendingLaunchShortcut: UIApplicationShortcutItem?

    private static var launchedObserver: NSObjectProtocol?

    override public func load() {
        guard let pending = Self.pendingLaunchShortcut else { return }
        Self.pendingLaunchShortcut = nil
        Self.launchedObserver = NotificationCenter.default.addObserver(
            forName: .capacitorViewDidAppear, object: nil, queue: .main
        ) { _ in
            if let token = Self.launchedObserver {
                NotificationCenter.default.removeObserver(token)
                Self.launchedObserver = nil
            }
            Self.perform(shortcutItem: pending)
        }
    }

    // MARK: - The page's list

    @objc func set(_ call: CAPPluginCall) {
        let items = (call.getArray("items", JSObject.self) ?? [])
        // Empty is a real instruction: it is what removes the shortcuts an earlier build left in the
        // menu, exactly as Android's setDynamicShortcuts() does.
        let shortcuts: [UIApplicationShortcutItem] = items.compactMap { item in
            // JSObject's values are JSValue (a marker protocol), so each is cast explicitly rather
            // than through the Optional — the compiler is happier and the intent is clearer.
            guard let rawRoute = item["route"], let route = rawRoute as? String, !route.isEmpty else {
                return nil
            }
            var label = route
            if let rawLabel = item["label"], let given = rawLabel as? String, !given.isEmpty {
                label = given
            }
            var iconName: String?
            if let rawIcon = item["icon"], let given = rawIcon as? String { iconName = given }
            return UIApplicationShortcutItem(
                type: Self.itemType,
                localizedTitle: Self.clamp(label),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(type: Self.icon(iconName)),
                // NSString, not String: the parameter wants NSSecureCoding, and String bridges to it
                // only through NSString.
                userInfo: [Self.routeKey: route as NSString]
            )
        }
        DispatchQueue.main.async {
            UIApplication.shared.shortcutItems = shortcuts
            call.resolve(["count": shortcuts.count])
        }
    }

    // The page names Android drawables (native-bridge.js PROGRAMMED); the same entries get the system
    // icons they had while they were static here. A recent text has none and gets the bookmark.
    static func icon(_ name: String?) -> UIApplicationShortcutIcon.IconType {
        switch name {
        case "shortcut_1": return .search    // Dictionary
        case "shortcut_3": return .compose   // Memo
        default: return .bookmark            // Table of Contents, recent texts
        }
    }

    @objc func get(_ call: CAPPluginCall) {
        let items = (UIApplication.shared.shortcutItems ?? []).map { item -> [String: Any] in
            [
                "type": item.type,
                "title": item.localizedTitle,
                "route": item.userInfo?[Self.routeKey] as? String ?? ""
            ]
        }
        call.resolve(["items": items])
    }

    // What a tap does, callable from the page: kept as a method rather than buried in the app
    // delegate because that is what makes it testable — the simulator run opens a route this way and
    // checks where the app ended up.
    @objc func open(_ call: CAPPluginCall) {
        guard let route = call.getString("route"), !route.isEmpty else {
            call.reject("no route")
            return
        }
        Self.perform(route: route)
        call.resolve()
    }

    // MARK: - Taps (static and dynamic items alike)

    static func perform(shortcutItem: UIApplicationShortcutItem) {
        guard let route = shortcutItem.userInfo?[routeKey] as? String else { return }
        perform(route: route)
    }

    static func perform(route: String) {
        guard let url = deepLink(route: route) else { return }
        // The same shape Capacitor's own SceneDelegateProxy posts (url plus options): the App plugin
        // casts the object to [String: Any?] and reads "url" out of it, and a bare dictionary is a
        // needless difference from the path that is known to work.
        NotificationCenter.default.post(name: .capacitorOpenURL, object: [
            "url": url,
            "options": [UIApplication.OpenURLOptionsKey: Any]()
        ])
    }

    // dhammagift://route/<route>, the form src/deep-link.js maps back to /?_nativeRoute=… . A route
    // can carry a segment (/dn22:2.2) or a fragment (/dn22#dn22:1.1) and both survive a URL path and
    // fragment as they are; anything a URL refuses falls back to a percent-encoded path.
    private static func deepLink(route: String) -> URL? {
        let path = route.hasPrefix("/") ? route : "/" + route
        if let url = URL(string: "dhammagift://route" + path) { return url }
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "dhammagift://route" + encoded)
    }

    // iOS truncates a long title itself, and does it less predictably than one place doing it.
    private static func clamp(_ label: String) -> String {
        label.count > 40 ? String(label.prefix(39)) + "…" : label
    }
}
