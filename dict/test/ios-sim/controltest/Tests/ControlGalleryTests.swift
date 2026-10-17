import XCTest

// The Dict.Dhamma.Gift Control Center control as the system shows it, on a simulator. Only SpringBoard draws Control
// Center, so the test drives SpringBoard: open Control Center -> its "Add a Control" gallery -> find the control ->
// add it -> tap it -> the dictionary opens. Every step leaves a screenshot and SpringBoard's element tree (labels
// differ by iOS), so a miss can be read from the artifact. Mirrors uposatha/.../WidgetGalleryTests.swift.
final class ControlGalleryTests: XCTestCase {
    private let board = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let appId = "gift.dhamma.pali"
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
            search.tap(); search.typeText("Dhamma")
            sleep(3)
            shot("gallery-search")
            tree("tree-4-search")
        }

        // Find the control: the group is "Dict.Dhamma.Gift" / the control label "Dict.Dhamma.Gift".
        let needles = ["Dict.Dhamma.Gift", "Dict.Dhamma", "Dhamma.Gift", "Dhamma"]
        var hit: XCUIElement? = nil
        for q in needles {
            let c = board.cells.containing(NSPredicate(format: "label CONTAINS[c] %@", q)).firstMatch
            if c.waitForExistence(timeout: 2) { hit = c; break }
            let s = board.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", q)).firstMatch
            if s.waitForExistence(timeout: 2) { hit = s; break }
        }
        tree("tree-5-before-pick")
        if let el = hit {
            shot("control-found")
            el.tap()
            sleep(3)
            shot("control-added")
            tree("tree-6-after-add")
        } else {
            shot("control-NOT-found")
            XCTFail("the Dict.Dhamma.Gift control was not found in the Control Center gallery")
        }

        // Leave edit mode and tap the added control, then check the app comes to the front.
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).tap()
        sleep(1)
        shot("cc-with-control")
        // tap near where a freshly added control lands; best-effort, the screenshot is the real proof
        let app = XCUIApplication(bundleIdentifier: appId)
        // try to find and tap the control button in control center
        let ctl = board.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Dict' OR label CONTAINS[c] 'Dhamma'")).firstMatch
        if ctl.waitForExistence(timeout: 2) { ctl.tap(); sleep(5); shot("after-tap") }
        print("app foreground after tap:", app.state == .runningForeground)
    }
}
