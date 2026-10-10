import AppIntents
import WidgetKit

// The dots of the widget are buttons: a tap turns to the previous / next layer (the left / right half of the strip) and does not open the app (iOS 17+ App Intents).
// The layer is kept per widget SIZE (family key), because iOS gives a widget no identity of its own without a configuration:
// two widgets of one size show the same layer. The intent lives in the widget extension, so it runs there.
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
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
