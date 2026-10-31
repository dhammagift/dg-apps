import XCTest

// The test reminder of the settings, driven the way a reader does it, and the notification looked for where iOS shows it
// (SpringBoard's banner): first "now" with the app open (the app has to let iOS show it in front), then "in 1 min" with the
// app sent Home. The page is English on the simulator: Settings (the gear), Test reminders, now, in 1 min, Test; the title "Uposatha (test)".
// Pictures go to /tmp/upo-notify-shots (notify.sh collects them).
final class NotifyTests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "gift.dhamma.uposatha")
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let shots = "/tmp/upo-notify-shots"

    private func shot(_ name: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
    }

    // The system's permission alerts belong to SpringBoard: location at the start, notifications at the first test.
    private func allowAlerts() {
        for label in ["Allow", "Allow While Using App", "Allow Once"] {
            let b = springboard.alerts.buttons[label]
            if b.waitForExistence(timeout: 1) { b.tap(); sleep(1) }
        }
    }

    // An element of the page by its accessible label (any case: the group titles are uppercased by CSS), scrolled to by
    // dragging the open menu upwards when it is below the fold - the menu is a scroller of its own, so not swipeUp on the page.
    private func tapWeb(_ label: String, scrolls: Int = 12) -> Bool {
        let el = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
        for i in 0...scrolls {
            if el.exists && el.isHittable { el.tap(); return true }
            if i == 0 { _ = el.waitForExistence(timeout: 3); continue }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.35)))
            sleep(1)
        }
        return false
    }

    private func banner(_ timeout: TimeInterval) -> Bool {
        let p = NSPredicate(format: "label CONTAINS[c] %@", "Uposatha (test)")
        return springboard.descendants(matching: .any).matching(p).firstMatch.waitForExistence(timeout: timeout)
    }

    func testReminders() {
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        app.activate()
        sleep(12)
        allowAlerts()
        shot("01-start")
        // In the app the menu opens from the top bar's gear (Settings); the site's burger (Menu) is hidden there.
        XCTAssertTrue(tapWeb("Settings") || tapWeb("Menu", scrolls: 0), "no Settings / Menu button on the page")
        sleep(2)
        XCTAssertTrue(tapWeb("Test reminders"), "no 'Test reminders' group in the menu")
        sleep(2)
        shot("02-tests-group")
        // "now" is the default
        XCTAssertTrue(tapWeb("Test"), "no Test button")
        sleep(3)
        allowAlerts()      // the notification permission, asked at the first test
        shot("03-after-test")
        let inFront = banner(25)
        shot("04-with-the-app-open")
        XCTAssertTrue(inFront, "the test reminder 'now' showed no banner with the app open")

        sleep(6)           // the banner goes away
        XCTAssertTrue(tapWeb("in 1 min"), "no 'in 1 min' choice")
        XCTAssertTrue(tapWeb("Test"), "no Test button (second time)")
        sleep(3)
        // what the page answered under the button ("Will arrive at …" / not allowed / cannot)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.75))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.55)))
        sleep(1)
        shot("05-set-in-1-min")
        XCUIDevice.shared.press(.home)
        let behind = banner(110)
        shot("06-app-in-the-background")
        XCTAssertTrue(behind, "the test reminder 'in 1 min' showed no banner with the app in the background")
    }
}
