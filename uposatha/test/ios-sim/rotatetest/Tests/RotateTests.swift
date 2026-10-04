import XCTest

// Simulator rotation for the Uposatha edge-to-edge proof (dg-apps#41). The shell side
// (tools/ios-edgetoedge.sh) can screenshot, record video and switch the appearance with plain
// `simctl`, but rotating needs a real UI-test run: it sets XCUIDevice's orientation — a system
// wide change SpringBoard keeps after the test exits — and does nothing else. AppleScript/System
// Events was the alternative and needs accessibility rights a CI runner does not grant; XCTest is
// the mechanism the sharetest job already relies on.
//
// The app has to be in front: an orientation change is applied to the app in front, and in run 444
// this test passed while the simulator never turned landscape (the runner app was in front, and it
// does not do landscape). `activate()` brings the app — already installed by the caller — back to
// the front, and the orientation then applies to it.
//
// tools/ios-edgetoedge.sh picks the method by name (-only-testing:RotateTests/RotateTests/testRotate<Landscape|Portrait>).
final class RotateTests: XCTestCase {

    private func frontmostApp() -> XCUIApplication {
        let bundle = ProcessInfo.processInfo.environment["DG_APP_BUNDLE"] ?? "gift.dhamma.uposatha"
        return XCUIApplication(bundleIdentifier: bundle)
    }

    // The sleep is the point: the caller (tools/ios-edgetoedge.sh) takes its screenshots WHILE the
    // orientation is held by this test, and stops the test afterwards. The simulator goes back to
    // portrait as soon as the session ends (run 445: the rotation took, the shots came out portrait).
    func testRotateLandscape() {
        frontmostApp().activate()
        sleep(2)
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(75)
    }

    func testRotatePortrait() {
        frontmostApp().activate()
        sleep(2)
        XCUIDevice.shared.orientation = .portrait
        sleep(20)
    }
}
