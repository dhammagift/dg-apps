import XCTest

// The app downloads the real packs and answers offline (test/ios-sim/selftest-packs.js); this waits for its verdict line
// "DG-SELFTEST-DONE PASS|FAIL {json}" on the screen, taps through the system alerts on the way, and attaches screenshots.
final class PacksOnDeviceTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "gift.dhamma.mobile")
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let yes = ["Download", "Скачать", "Allow", "Разрешить", "OK", "ОК", "Continue", "Продолжить"]

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func answerAlerts() {
        for owner in [app, springboard] {
            let alert = owner.alerts.firstMatch
            guard alert.exists else { continue }
            for label in yes where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return
            }
        }
    }

    private func verdict() -> String? {
        let predicate = NSPredicate(format: "label BEGINSWITH 'DG-SELFTEST-DONE' OR value BEGINSWITH 'DG-SELFTEST-DONE'")
        let el = app.descendants(matching: .any).matching(predicate).firstMatch
        guard el.exists else { return nil }
        let text = el.label.isEmpty ? ((el.value as? String) ?? "") : el.label
        return text.isEmpty ? nil : text
    }

    func testPacksOffline() {
        continueAfterFailure = true
        app.launch()
        let deadline = Date().addingTimeInterval(38 * 60)
        var found: String?
        var tick = 0
        while Date() < deadline {
            answerAlerts()
            if let v = verdict() { found = v; break }
            if tick % 24 == 0 { shot("waiting-\(tick / 12)min") }
            tick += 1
            sleep(5)
        }
        shot("end")
        let text = found ?? "no verdict on the screen within 38 minutes"
        let a = XCTAttachment(string: text)
        a.name = "selftest-verdict"
        a.lifetime = .keepAlways
        add(a)
        print("DG-SELFTEST-VERDICT " + text)
        XCTAssertTrue(text.hasPrefix("DG-SELFTEST-DONE PASS"), text)
    }
}
