import AppIntents
import Foundation

// The control's intent, compiled into BOTH the app and the DgControls extension: an intent with openAppWhenRun is run in the
// app's process, and when the app does not have it the tap opens nothing (owner, 2026-10-17: the control did nothing).
@available(iOS 18.0, *)
struct DgOpenLibraryControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Dhamma.gift"
    static let description = IntentDescription("Opens the Dhamma.gift library.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        let route = URL(string: "dhammagift://route/")
            ?? URL(string: "dhammagift://")!
        return .result(opensIntent: OpenURLIntent(route))
    }
}
