import XCTest

// The Uposatha widgets as the system shows them (owner, 2026-10-11: on a real iPhone every preview in the gallery and the widget
// on the Home Screen were black). Nothing but SpringBoard draws a widget, so the test drives SpringBoard: Home Screen -> edit mode
// -> Add Widget -> search "Uposatha" -> every page of the previews -> Add Widget -> the Home Screen with it.
// It asserts nothing about the pictures: the shell side (widget-gallery.sh) measures them and collects the extension's log and
// crash reports. Every step leaves a screenshot, and SpringBoard's element tree where a step can miss (the labels differ by iOS).
final class WidgetGalleryTests: XCTestCase {
    private let board = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    // The simulator's processes see the Mac's file system: the shell reads the pictures from here
    private let out = URL(fileURLWithPath: "/tmp/upo-widget-shots")
    private var n = 0

    private func shot(_ name: String) {
        n += 1
        let file = out.appendingPathComponent(String(format: "%02d-%@.png", n, name))
        do { try XCUIScreen.main.screenshot().pngRepresentation.write(to: file) } catch { print("shot \(name): \(error)") }
    }

    private func tree(_ name: String) {
        try? board.debugDescription.write(to: out.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
    }

    override func setUp() {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    }

    func testGalleryAndHomeScreen() {
        // the app first: it hands its data over to the widgets
        XCUIApplication(bundleIdentifier: "gift.dhamma.uposatha").activate()
        sleep(15)
        XCUIDevice.shared.press(.home)
        sleep(2)
        shot("home")

        // edit mode: a long press on the wallpaper
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).press(forDuration: 2.5)
        sleep(2)
        shot("edit-mode")
        tree("tree-1-edit-mode")

        // iOS 17: a "+" named Add Widget; iOS 18 and later: Edit -> Add Widget
        let add = board.buttons["Add Widget"].firstMatch
        if !add.waitForExistence(timeout: 3) {
            let edit = board.buttons["Edit"].firstMatch
            XCTAssertTrue(edit.waitForExistence(timeout: 5), "no Edit button in edit mode")
            edit.tap()
            sleep(1)
            shot("edit-menu")
            tree("tree-2-edit-menu")
        }
        XCTAssertTrue(add.waitForExistence(timeout: 5), "no Add Widget")
        add.tap()
        sleep(3)
        shot("gallery")
        tree("tree-3-gallery")

        let search = board.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8), "no search field in the gallery")
        search.tap()
        search.typeText("Uposatha")
        sleep(3)
        shot("search")
        tree("tree-4-search")

        // the app's row in the results (not the text typed into the field)
        var row = board.cells.containing(NSPredicate(format: "label CONTAINS[c] 'Uposatha'")).firstMatch
        if !row.waitForExistence(timeout: 3) { row = board.cells.staticTexts["Uposatha"].firstMatch }
        if !row.waitForExistence(timeout: 3) { row = board.staticTexts["Uposatha"].firstMatch }
        XCTAssertTrue(row.waitForExistence(timeout: 3), "Uposatha is not in the gallery")
        row.tap()
        sleep(4)
        tree("tree-5-previews")

        // every preview: the Uposatha in three sizes, the Moon, Day & night
        for page in 1...5 {
            shot("preview-\(page)")
            if page < 5 {
                board.swipeLeft()
                sleep(2)
            }
        }
        board.swipeRight()
        sleep(2)
        shot("preview-to-add")

        let put = board.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Add Widget'")).firstMatch
        XCTAssertTrue(put.waitForExistence(timeout: 5), "no Add Widget under the preview")
        put.tap()
        sleep(4)
        shot("home-with-widget-editing")
        XCUIDevice.shared.press(.home)
        sleep(6)
        shot("home-with-widget")
        tree("tree-6-home")
    }
}
