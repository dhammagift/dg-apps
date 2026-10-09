import UIKit
import Capacitor

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = DgRootViewController()
        window?.makeKeyAndVisible()

        // The app was started by a quick action: its route waits until the page asks for it.
        if let item = connectionOptions.shortcutItem { DgShortcutsPlugin.deliver(item) }
        // ... or by a tap in a widget (a gift.dhamma.uposatha:// link).
        if let url = connectionOptions.urlContexts.first?.url { DgShortcutsPlugin.deliver(url: url) }

        SceneDelegateProxy.shared.scene(scene, willConnectTo: session, options: connectionOptions)
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        DgShortcutsPlugin.deliver(shortcutItem)
        completionHandler(true)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let url = URLContexts.first?.url { DgShortcutsPlugin.deliver(url: url) }
        SceneDelegateProxy.shared.scene(scene, openURLContexts: URLContexts)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        SceneDelegateProxy.shared.scene(scene, continue: userActivity)
    }
}
