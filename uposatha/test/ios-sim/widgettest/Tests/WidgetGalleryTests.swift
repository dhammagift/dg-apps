import XCTest

// The Uposatha widgets as the system shows them (owner, 2026-10-11: on a real iPhone every preview in the gallery and the widget
// on the Home Screen were black). Nothing but SpringBoard draws a widget, so the test drives SpringBoard: Home Screen -> edit mode
// -> Add Widget -> search "Uposatha" -> every page of the previews -> Add Widget -> the Home Screen with it.
// A widget the system refuses to draw is a pure black card (what the owner saw): the previews of the real widgets and the widget
// on the Home Screen must not be one. The shell side (widget-gallery.sh) collects the extension's log and crash reports. Every
// step leaves a screenshot, and SpringBoard's element tree where a step can miss (the labels differ by iOS).
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

    // The share of pure black in a box of the screen (centre and size as shares of the screen)
    private func black(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Double {
        guard let full = XCUIScreen.main.screenshot().image.cgImage else { return 0 }
        let W = CGFloat(full.width), H = CGFloat(full.height)
        let box = CGRect(x: (cx - w / 2) * W, y: (cy - h / 2) * H, width: w * W, height: h * H).integral
        guard let part = full.cropping(to: box) else { return 0 }
        let pw = part.width, ph = part.height
        var px = [UInt8](repeating: 0, count: pw * ph * 4)
        guard let ctx = CGContext(data: &px, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.draw(part, in: CGRect(x: 0, y: 0, width: pw, height: ph))
        var dark = 0
        for i in stride(from: 0, to: px.count, by: 4) where px[i] < 6 && px[i + 1] < 6 && px[i + 2] < 6 { dark += 1 }
        return Double(dark) / Double(pw * ph)
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

        // every preview: the Uposatha in three sizes, the Moon, Day & night, then the probes of a debug build
        // (UposathaWidget.swift); a swipe past the last page changes nothing
        let pages = 13
        for page in 1...pages {
            shot("preview-\(page)")
            // the five real widgets: the middle of the preview (every size covers it) is the card, not a black hole
            if page <= 5 {
                let share = black(0.5, 0.61, 0.16, 0.06)   // measured on the black run: 1.00 for all five, 0.00 for a drawn card
                XCTAssertLessThan(share, 0.9, "preview \(page) is a black card: the system did not draw the widget")
            }
            if page < pages {
                board.swipeLeft()
                sleep(2)
            }
        }
        // back to the first one (the small Uposatha): that is the one put on the Home Screen
        for _ in 1..<pages {
            board.swipeRight()
            sleep(1)
        }
        sleep(1)
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
        // the new widget takes the first place of the page: its middle
        XCTAssertLessThan(black(0.29, 0.21, 0.20, 0.06), 0.9, "the widget on the Home Screen is a black card")
    }
}
