import AppIntents
import Foundation

// The Control Center control's intent (iOS 18+), compiled into BOTH the app and the widget extension: an intent with
// openAppWhenRun is run in the app's process, and when the app does not have it the tap opens nothing (the Dhamma.Gift and
// Dictionary controls, owner, 2026-10-17). It opens the app on its home tab by the widgets' own link (WLinks).
@available(iOS 18.0, *)
struct UposathaOpenControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Uposatha"
    static let description = IntentDescription("Opens the Uposatha calendar.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        let url = URL(string: "gift.dhamma.uposatha://open?tab=home") ?? URL(string: "gift.dhamma.uposatha://")!
        return .result(opensIntent: OpenURLIntent(url))
    }
}
