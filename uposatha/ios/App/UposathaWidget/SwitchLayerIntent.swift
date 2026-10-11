import AppIntents
import WidgetKit

// The switch of the big widgets is two buttons: a tap turns to the previous / next slide (the left / right half of the strip) and does not open the app (iOS 17+ App Intents).
// The slide is kept per widget SIZE (family key "medium" / "large"), because iOS gives a widget no identity of its own without a configuration:
// two widgets of one size show the same slide. The calendar's arrows use the same intent with the key "month" (0..2 months ahead).
// The intent lives in the widget extension, so it runs there.
@available(iOS 17.0, *)
struct SwitchLayerIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch widget layer"

    @Parameter(title: "Widget size")
    var family: String

    @Parameter(title: "Layers")
    var count: Int

    @Parameter(title: "Step")
    var step: Int

    init() {}

    init(family: String, count: Int, step: Int = 1) {
        self.family = family
        self.count = count
        self.step = step
    }

    func perform() async throws -> some IntentResult {
        let n = max(1, count)
        let next = ((WStore.layer(family) + step) % n + n) % n   // step is -1 (left half) or +1 (right half)
        WStore.setLayer(family, next)
        WStore.defaults?.set(Date().timeIntervalSince1970, forKey: "at." + family)   // when it was chosen (WStore.monthOffset forgets a month chosen on another day)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
