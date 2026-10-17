import AppIntents
import SwiftUI
import WidgetKit

// Control Center (iOS 18+): a control that opens the Dict.Dhamma.Gift dictionary, added in
// Settings → Control Center or from the + button in Control Center itself. It mirrors the
// Dhamma.gift library control (the DG app's DgControls target) and the Android Quick Settings tile
// (DgDictTileService.java), which opens the dictionary's start page with no launcher, browser tab
// or share chooser in between.
//
// A ControlWidget can only be declared in a widget extension (the system discovers controls in a
// binary carrying NSExtensionPointIdentifier com.apple.widgetkit-extension, never in the app
// target). The extension process has no Capacitor and no WebView, so the control opens the app with
// OpenURLIntent(dictdhammagift://) — the documented iOS 18 way for a control to open its app. The
// app declares that scheme in Info.plist; the dictionary is its only page, so coming to the
// foreground is "open the dictionary", the same as the Android tile's route "/".
//
// The AppIntent form of the button (not the iOS 26 OpenURLIntent initializer) is used because it is
// the one iOS 18.0 — this extension's deployment target — also has.
@available(iOS 18.0, *)
struct DgDictControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "gift.dhamma.pali.DgDictControl") {
            ControlWidgetButton(action: DgDictOpenControlIntent()) {
                // A control draws only a symbol (SF Symbol or a custom .symbolset): a plain image (the brand mark it had, a loose
                // imageset outside an asset catalog) came out as "?" in Control Center (owner, 2026-10-17).
                Label("Dict.Dhamma.Gift", image: "DictMark")
            }
        }
        .displayName("Dict.Dhamma.Gift")
        .description("Opens the Pāli and Sanskrit dictionary.")
    }
}

// WidgetKit finds controls through the @main WidgetBundle of the extension, never by scanning for
// ControlWidget conformances — a control not listed here builds but stays invisible in Control
// Center. The deployment target is 18.0, so no #available guard is needed around the type.
@main
struct DgDictControlsBundle: WidgetBundle {
    var body: some Widget {
        DgDictControl()
    }
}
