import XCTest

// The Dictionary on an iOS simulator, driven the way a reader does it: real taps, typing, swipes. Each test is one case of
// test/ios-sim/feature-tour.sh, which records the simulator's video around it and judges the screenshots it keeps
// (XCTAttachment, exported from the result bundle). The checks here are the ones an XCUI query can make: what is on screen,
// what a field holds, where the letters row sits. What only a picture shows (the strip under the clock, a blank frame during a
// refresh) is measured by the script from the screenshots and the video.
//
// The tests share one app session in order (the words typed early are the history the quick actions show later), so the
// script runs them one by one, in the order of their names.
final class DictFeatureTests: XCTestCase {

    private let app = XCUIApplication(bundleIdentifier: "gift.dhamma.pali")

    override func setUp() {
        continueAfterFailure = false
        app.activate()
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private var page: XCUIElement { app.webViews.firstMatch }

    // The search box: a type=search input is a search field to XCUI; a text field on older runtimes.
    private var box: XCUIElement {
        let s = page.searchFields.firstMatch
        return s.exists ? s : page.textFields.firstMatch
    }

    private func value(_ e: XCUIElement) -> String { (e.value as? String) ?? "" }

    // The keyboard's one-time "slide to type" card (a fresh simulator shows it on the first keyboard) hides the page.
    private func dismissKeyboardTips() {
        let go = app.buttons["Continue"]
        if go.waitForExistence(timeout: 1) { go.tap(); sleep(1) }
    }

    private func clearAndFocus() {
        XCTAssertTrue(box.waitForExistence(timeout: 30), "no search box on the page")
        box.tap()
        dismissKeyboardTips()
        let current = value(box)
        if !current.isEmpty && !current.hasPrefix("kacchapā, kacchapaa") {
            box.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        }
    }

    func test01_StartScreen() {
        XCTAssertTrue(page.waitForExistence(timeout: 40), "no web view")
        XCTAssertTrue(box.waitForExistence(timeout: 30), "the start page did not come up")
        shot("01-start")
    }

    func test02_TypeVelthuis() {
        clearAndFocus()
        box.typeText("kacchapaa")
        sleep(1)
        XCTAssertEqual(value(box), "kacchapā", "Velthuis typing did not turn aa into ā")
        shot("02-typed")
        box.typeText("\n")
        XCTAssertTrue(page.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "kacchap")).firstMatch.waitForExistence(timeout: 20),
                      "the word page did not open")
        shot("02-word")
    }

    // The letters row is the keyboard's own accessory: it must be there with the keyboard, stay exactly where it is while the
    // page scrolls under it, and type into the box.
    func test03_LettersRowOnTheKeyboard() {
        clearAndFocus()
        let a = app.buttons["ā"]
        XCTAssertTrue(a.waitForExistence(timeout: 10), "no letters row above the keyboard")
        let y0 = a.frame.minY
        shot("03-row")
        var ys: [CGFloat] = []
        for _ in 0..<3 {
            page.swipeUp(velocity: .slow)
            ys.append(a.frame.minY)
            page.swipeDown(velocity: .slow)
            ys.append(a.frame.minY)
        }
        // 0 = not on screen (a swipe down can put the keyboard away); where it is on screen it must be exactly where it was.
        let drift = ys.filter { $0 > 0 }.map { abs($0 - y0) }.max() ?? 0
        XCTAssertLessThanOrEqual(drift, 1, "the letters row moved while the page scrolled: \(y0) -> \(ys)")
        if !box.exists || !box.isHittable { box.tap() }
        box.typeText("kacchap")
        a.tap()
        XCTAssertTrue(value(box).hasSuffix("ā"), "tapping ā did not type it (box: \(value(box)))")
        let more = app.buttons["More letters"]
        if more.exists {
            more.tap()
            XCTAssertTrue(app.buttons["ś"].waitForExistence(timeout: 3), "the second row did not open")
            shot("03-more")
            more.tap()
        }
        box.typeText("\n")
    }

    // Scrolled down, the page must not run under the clock: the screenshot's top strip is judged by the script.
    func test04_ScrolledUnderTheClock() {
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        for _ in 0..<3 { page.swipeUp(velocity: .fast) }
        sleep(1)
        shot("04-scrolled")
    }

    // Pull to refresh from the top: the script looks for blank frames in this case's video.
    func test05_PullToRefresh() {
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        for _ in 0..<4 { page.swipeDown(velocity: .fast) }
        sleep(1)
        shot("05-before")
        let from = page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let to = page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(6)
        XCTAssertTrue(page.exists, "the page is gone after a refresh")
        shot("05-after")
    }

    // The owner's case (TestFlight 563): the box has the focus, the page is scrolled down and back up - the caret must still be
    // inside the box. The box's frame goes along as text; the script finds the blue caret in the screenshots and checks it.
    func test06_CaretAfterScrollingDownAndUp() {
        clearAndFocus()
        for _ in 0..<3 { page.swipeUp(velocity: .slow) }
        sleep(1)
        for _ in 0..<4 { page.swipeDown(velocity: .slow) }
        sleep(1)
        box.tap(); sleep(1)   // the place the reader taps to type again; the caret must land inside the box
        let f = box.frame
        let note = XCTAttachment(string: "\(f.minX) \(f.minY) \(f.maxX) \(f.maxY)")
        note.name = "06-box-frame"
        note.lifetime = .keepAlways
        add(note)
        for i in 1...4 { shot("06-caret-\(i)"); usleep(280_000) }
    }

    // The Home Screen quick actions: long press on the icon, the menu, a word from it opens its page.
    func test07_QuickActions() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCUIDevice.shared.press(.home)
        sleep(2)
        let icon = springboard.icons["Dict.Dhamma.Gift"]
        var tries = 0
        while !icon.isHittable && tries < 4 { springboard.swipeLeft(); sleep(1); tries += 1 }
        XCTAssertTrue(icon.waitForExistence(timeout: 10), "no app icon on the Home Screen")
        icon.press(forDuration: 1.6)
        sleep(1)
        shot("07-menu")
        let word = springboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "kacchap")).firstMatch
        if word.waitForExistence(timeout: 5) {
            word.tap()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "the quick action did not open the app")
            sleep(3)
            shot("07-opened")
        } else {
            XCTFail("no recent word in the quick actions menu")
        }
    }
}
