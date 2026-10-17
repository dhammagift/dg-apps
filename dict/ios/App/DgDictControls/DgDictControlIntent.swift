import AppIntents
import Foundation

// The control's intent, compiled into BOTH the app and the DgDictControls extension: an intent with openAppWhenRun is run in
// the app's process, and when the app does not have it the tap opens nothing (owner, 2026-10-17: the control did nothing).
@available(iOS 18.0, *)
struct DgDictOpenControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Dict.Dhamma.Gift"
    static let description = IntentDescription("Opens the Dict.Dhamma.Gift dictionary.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        let url = URL(string: "dictdhammagift://") ?? URL(string: "dictdhammagift://open")!
        return .result(opensIntent: OpenURLIntent(url))
    }
}
