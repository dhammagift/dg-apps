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

    // An element of the page by its accessible label; scrolled into reach when it is below the fold.
    private func tapWeb(_ label: String, timeout: TimeInterval = 15) -> Bool {
        let el = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        guard el.waitForExistence(timeout: timeout) else { return false }
        for _ in 0..<6 where !el.isHittable { app.webViews.firstMatch.swipeUp(); sleep(1) }
        guard el.isHittable else { return false }
        el.tap()
        return true
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
        XCTAssertTrue(tapWeb("Settings") || tapWeb("Menu", timeout: 3), "no Settings / Menu button on the page")
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
        sleep(2)
        shot("05-set-in-1-min")
        XCUIDevice.shared.press(.home)
        let behind = banner(110)
        shot("06-app-in-the-background")
        XCTAssertTrue(behind, "the test reminder 'in 1 min' showed no banner with the app in the background")
    }
}
