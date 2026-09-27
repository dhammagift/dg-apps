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
