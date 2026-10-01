import XCTest

// Simulator rotation for the Uposatha edge-to-edge proof (dg-apps#41). The shell side
// (tools/ios-edgetoedge.sh) can screenshot, record video and switch the appearance with plain
// `simctl`, but rotating needs a real UI-test run: it sets XCUIDevice's orientation — a system
// wide change SpringBoard keeps after the test exits — and does nothing else. AppleScript/System
// Events was the alternative and needs accessibility rights a CI runner does not grant; XCTest is
// the mechanism the sharetest job already relies on.
//
// tools/ios-edgetoedge.sh picks the method by name (-only-testing:RotateTests/RotateTests/testRotate<Landscape|Portrait>).
final class RotateTests: XCTestCase {

    func testRotateLandscape() {
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
    }

    func testRotatePortrait() {
        XCUIDevice.shared.orientation = .portrait
        sleep(3)
    }
}
