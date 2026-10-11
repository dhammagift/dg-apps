import XCTest

// Dhamma.Gift on an iOS simulator, toured the way a reader uses it while tour.sh records the screen: the home screen,
// a search, the results scrolled, the reader scrolled, a pull to refresh, Settings with a sideways swipe — in light,
// then (tour.sh switches the simulator's appearance between the two tests) the same places in dark. The video is the
// deliverable (owner, 2026-10-11: edge to edge on iOS, "сам посмотри и мне покажи видео"); every state also gets a
// screenshot, and each pauses long enough for a person to see it.
//
// Not a gate: the step that runs it never fails the job (build-app.yml), so a step here that cannot find its element
// takes the next way round (a dhammagift:// link instead of a tap) or moves on, rather than ending the tour.
final class DgTourTests: XCTestCase {

    private let app = XCUIApplication(bundleIdentifier: "gift.dhamma.mobile")
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() {
        continueAfterFailure = true
    }

    private var page: XCUIElement { app.webViews.firstMatch }

    // The search box: a type=search input is a search field to XCUI; a text field on older runtimes.
    private var box: XCUIElement {
        let s = page.searchFields.firstMatch
        return s.exists ? s : page.textFields.firstMatch
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    // A pause for the person watching the video, then the screenshot of what they saw.
    private func look(_ name: String, _ seconds: Double = 1.5) {
        Thread.sleep(forTimeInterval: seconds)
        shot(name)
    }

    // A dhammagift:// link from outside the app: iOS first asks «Open in "Dhamma.gift"?» (docs/DEEP_LINKS.md), which a
    // test can answer. Mapped by the app itself (src/deep-link.js), the same way a link from Safari is.
    private func openLink(_ link: String) {
        guard let url = URL(string: link) else { return }
        app.open(url)
        let open = springboard.buttons["Open"]
        if open.waitForExistence(timeout: 3) { open.tap() }
        Thread.sleep(forTimeInterval: 4)
    }

    private func toTop() {
        for _ in 0..<4 { page.swipeDown(velocity: .fast) }
    }

    // Away from both edges: an edge swipe is the web view's Back gesture (allowsBackForwardNavigationGestures).
    private func sideways(from: CGFloat, to: CGFloat) {
        let a = page.coordinate(withNormalizedOffset: CGVector(dx: from, dy: 0.5))
        let b = page.coordinate(withNormalizedOffset: CGVector(dx: to, dy: 0.5))
        a.press(forDuration: 0.1, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    // A pull from the top of the page, slow, past the point where a release reloads (src/pull-refresh.js).
    private func pullToRefresh() {
        toTop()
        Thread.sleep(forTimeInterval: 1)
        let from = page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let to = page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.4)
        Thread.sleep(forTimeInterval: 5)
    }

    private func readerScrolled(_ prefix: String) {
        for _ in 0..<3 { page.swipeUp(velocity: .slow) }
        look(prefix + "-reader-scrolled")
        toTop()
        look(prefix + "-reader-top")
        pullToRefresh()
        look(prefix + "-reader-refreshed")
    }

    // Every place is opened by a dhammagift:// link: in run 587 the self-test's quick window (/4as) held the search
    // box, typing never reached it, and the tour stopped there. A link also closes whatever is open on the way.
    func test1_Light() {
        app.launch()
        XCTAssertTrue(page.waitForExistence(timeout: 40), "no web view")
        // The self-test bundle sends the app to one quick action (/4as) on the first load of a session: let it settle.
        Thread.sleep(forTimeInterval: 8)
        look("tour-01-start")

        openLink("dhammagift://search?q=kacchapa")
        look("tour-02-results")
        page.swipeUp(velocity: .slow)
        look("tour-03-results-scrolled")
        toTop()
        look("tour-04-results-top")
        pullToRefresh()
        look("tour-05-results-refreshed")

        openLink("dhammagift://dn22")
        look("tour-06-reader")
        readerScrolled("tour-07")

        // The settings sheet over the results, as the burger opens it (home.js: #dg-settings opens it on load).
        openLink("dhammagift://route/?q=kacchapa#dg-settings")
        Thread.sleep(forTimeInterval: 3)
        look("tour-08-settings")
        sideways(from: 0.75, to: 0.25)
        look("tour-09-settings-swiped-left", 0.8)
        sideways(from: 0.25, to: 0.75)
        look("tour-10-settings-swiped-right", 0.8)
        page.swipeUp(velocity: .slow)
        look("tour-11-settings-scrolled")
    }

    // For ios-safari-probe.yml: opens each link of DG_LINKS (space-separated, passed as TEST_RUNNER_DG_LINKS), answers
    // iOS's «Open in "Dhamma.gift"?» and the first-start offer of the offline library, and leaves each page on screen
    // for the workflow's screenshot and the page's DgSelfTest report.
    func testOpenLinks() {
        let links = (ProcessInfo.processInfo.environment["DG_LINKS"] ?? "").split(separator: " ").map(String.init)
        // Launched by the test itself: an app that simctl started is not one XCUITest can attach to ("has not
        // loaded accessibility", the probe's first run). The first load of a session goes to /4as: let it settle.
        app.launch()
        _ = page.waitForExistence(timeout: 40)
        Thread.sleep(forTimeInterval: 8)
        for link in links {
            openLink(link)
            let notNow = app.buttons["Not now"]
            if notNow.waitForExistence(timeout: 3) { notNow.tap() }
            look("probe-" + String(link.suffix(24)).replacingOccurrences(of: "/", with: "_"), 10)
        }
    }

    func test2_Dark() {
        openLink("dhammagift://search?q=kacchapa")
        XCTAssertTrue(page.waitForExistence(timeout: 20), "no web view")
        look("tour-12-dark-results")
        openLink("dhammagift://dn22")
        look("tour-13-dark-reader")
        readerScrolled("tour-14-dark")
        openLink("dhammagift://route/?q=kacchapa#dg-settings")
        Thread.sleep(forTimeInterval: 3)
        look("tour-15-dark-settings")
        sideways(from: 0.75, to: 0.25)
        look("tour-16-dark-settings-swiped", 0.8)
    }
}
