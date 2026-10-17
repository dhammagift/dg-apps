import XCTest

// The Dict.Dhamma.Gift Control Center control as the system shows it, on a simulator. Only SpringBoard draws Control
// Center, so the test drives SpringBoard: open Control Center -> its "Add a Control" gallery -> find the control ->
// add it -> tap it -> the dictionary opens. Every step leaves a screenshot and SpringBoard's element tree (labels
// differ by iOS), so a miss can be read from the artifact. Mirrors uposatha/.../WidgetGalleryTests.swift.
final class ControlGalleryTests: XCTestCase {
    private let board = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    // Which app's control (control-gallery.sh passes them as TEST_RUNNER_CONTROL_*; the Dictionary's by default, Uposatha's
    // from uposatha-widget-ios.yml)
    private static let env = ProcessInfo.processInfo.environment
    private let appId = env["CONTROL_APP_ID"] ?? "gift.dhamma.pali"
    private let ctlId = env["CONTROL_KIND"] ?? "gift.dhamma.pali.DgDictControl"
    private let searchText = env["CONTROL_SEARCH"] ?? "Dhamma"
    private let out = URL(fileURLWithPath: "/tmp/dict-control-shots")
    private var n = 0

    private func shot(_ name: String) {
        n += 1
        let f = out.appendingPathComponent(String(format: "%02d-%@.png", n, name))
        do { try XCUIScreen.main.screenshot().pngRepresentation.write(to: f) } catch { print("shot \(name): \(error)") }
    }
    private func tree(_ name: String) {
        try? board.debugDescription.write(to: out.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
    }

    override func setUp() {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    }

    // Open Control Center: a press-and-drag from the very top-right corner down (the gesture on a Face ID iPhone).
    private func openControlCenter() {
        let top = board.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.0))
        let mid = board.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.55))
        top.press(forDuration: 0.1, thenDragTo: mid)
        sleep(2)
    }

    func testControlInGallery() {
        // Warm the app so its control extension is registered/awake, then go home.
        XCUIApplication(bundleIdentifier: appId).activate()
        sleep(8)
        XCUIDevice.shared.press(.home)
        sleep(2)
        shot("home")

        openControlCenter()
        shot("control-center")
        tree("tree-1-cc")

        // Edit mode: iOS 18 shows a "+" (Add a Control) in the top-left of Control Center, or a long-press enters edit.
        var add = board.buttons["Add a Control"].firstMatch
        if !add.waitForExistence(timeout: 3) {
            // long-press an empty area to enter edit mode, then look again
            board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.5)
            sleep(2)
            shot("cc-edit")
            tree("tree-2-cc-edit")
            add = board.buttons["Add a Control"].firstMatch
        }
        if !add.waitForExistence(timeout: 3) {
            // the "+" plus button in the corner
            let plus = board.buttons["Add"].firstMatch
            if plus.waitForExistence(timeout: 2) { plus.tap() }
        } else {
            add.tap()
        }
        sleep(3)
        shot("gallery")
        tree("tree-3-gallery")

        // Search the gallery for our control.
        let search = board.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap(); search.typeText(searchText)
            sleep(3)
            shot("gallery-search")
            tree("tree-4-search")
        }

        // Find and tap the control's preview button (identifier = the control's kind), which ADDS it to Control Center
        // and returns there. The group header is a StaticText with the same label — tapping that does nothing, which is
        // why an earlier run stayed in the gallery; the button carries the bundle id.
        tree("tree-5-before-pick")
        let preview = board.buttons[ctlId].firstMatch
        if !preview.waitForExistence(timeout: 6) {
            shot("control-NOT-found")
            XCTFail("the control \(ctlId) was not found in the Add-a-Control gallery")
            return
        }
        shot("control-found")
        preview.tap()
        sleep(3)
        shot("control-added")          // now Control Center shows the control with its rendered symbol
        tree("tree-6-after-add")

        // Tap the control in Control Center to open the app.
        let app = XCUIApplication(bundleIdentifier: appId)
        let inCC = board.buttons[ctlId].firstMatch
        if !inCC.waitForExistence(timeout: 4) {
            // Control Center is still in edit mode after the add (no button in the tree): a tap where the new control
            // landed only ends edit mode (Uposatha run 39000381785), so the control itself is looked for again after it
            board.coordinate(withNormalizedOffset: CGVector(dx: 0.16, dy: 0.18)).tap()
            sleep(3)
            shot("edit-mode-ended")
        }
        if inCC.waitForExistence(timeout: 4) {
            inCC.tap()
            sleep(6)
            shot("after-tap")
        } else {
            // fall back to a tap where a freshly added control lands (top-left of the grid)
            board.coordinate(withNormalizedOffset: CGVector(dx: 0.16, dy: 0.18)).tap()
            sleep(6)
            shot("after-tap-fallback")
        }
        let opened = app.state == .runningForeground
        print("app foreground after tap:", opened)
        tree("tree-7-after-tap")
        XCTAssertTrue(opened, "tapping the control did not bring \(appId) to the foreground")
    }
}
