import AppIntents
import SwiftUI
import WidgetKit

// Control Center (iOS 18+): a control that opens the Dhamma.gift library, added in
// Settings → Control Center or from the + button in Control Center itself.
//
// It is a widget extension because that is the only place a ControlWidget can be declared: the
// system discovers controls in extension binaries carrying the NSExtensionPointIdentifier
// com.apple.widgetkit-extension, never in the app target.
//
// The extension process has no Capacitor and no running WebView, so there is no DgShortcutsPlugin
// to post to. Instead the control's intent returns .result(opensIntent: OpenURLIntent(...)) — the
// documented iOS 18 way for a control to open its app — handing over the same dhammagift://route
// URL every other launch path uses (src/deep-link.js maps it; SceneDelegate → Capacitor's App
// plugin → the page). An in-app copy of the open intent (DgAppIntents.swift) exists so the phrase
// also works from Siri and the Shortcuts app in the app's own process.
//
// iOS 26 introduced a ControlWidgetButton initializer taking an OpenURLIntent directly; the
// AppIntent form is used here because it is the one iOS 18.0 also has — the deployment target of
// this extension is 18.0, and the button must build against both.
@available(iOS 18.0, *)
struct DgLibraryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "gift.dhamma.mobile.DgLibraryControl") {
            ControlWidgetButton(action: DgOpenLibraryControlIntent()) {
                // A control draws only a symbol (SF Symbol or a custom .symbolset): a plain image (the brand mark it had, a loose
                // imageset outside an asset catalog) came out as "?" in Control Center (owner, 2026-10-17).
                Label("Dhamma.gift", systemImage: "books.vertical")
            }
        }
        .displayName("Dhamma.gift")
        .description("Opens the offline Pāli canon library.")
    }
}

// The extension's entry point, and the reason the control above is reachable at all: WidgetKit
// discovers widgets and controls through the @main WidgetBundle of the extension, never by scanning
// the binary for ControlWidget conformances. A control that is defined but not listed here builds
// fine and stays invisible in Control Center (WWDC24 10157, "add the Control to your existing Widget
// Bundle").
//
// No #available guard: this target's deployment target is 18.0 (project.pbxproj), so the type it
// lists exists on every OS this extension can run on. Nothing else is in the bundle — Home Screen
// widgets, if any ever appear, belong here next to the control.
@main
struct DgControlsBundle: WidgetBundle {
    var body: some Widget {
        DgLibraryControl()
    }
}
