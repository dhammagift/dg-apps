import Foundation
import Capacitor

// Lets the App Store screenshot tour (test/ios-sim/tour.js) tell a simulator run which view is on screen, the same
// device the reader app uses for its own tour: one file, overwritten per stage, in Documents. A GitHub runner has no
// debugger to look at, so the page hands its progress out this one native call and the driver script screenshots on
// the signal instead of guessing at timings.
//
//     xcrun simctl get_app_container booted gift.dhamma.pali data
//
// This call BLOCKS until the driver acks (Documents/stage.ack) that it has actually screenshotted this stage. A CI
// runner's `xcrun simctl io screenshot` can be slow enough that a second, later stage overwrites stage.txt before
// the driver's poll ever reads the first one — two real stages (autocomplete, settings) went missing this way
// under load, with no error anywhere, because the page just moved on and nothing was left to prove it hadn't.
// 15s cap: a stuck or crashed driver must not hang the tour forever.
//
// Registered only in DEBUG builds (see DgApp.swift) and never in a shipped app.
@objc(DgSelfTestPlugin)
public class DgSelfTestPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "DgSelfTestPlugin"
    public let jsName = "DgSelfTest"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "stage", returnType: CAPPluginReturnPromise)
    ]

    @objc func stage(_ call: CAPPluginCall) {
        let name = call.getString("name") ?? ""
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let ackURL = dir.appendingPathComponent("stage.ack")
        do {
            try? FileManager.default.removeItem(at: ackURL)
            try name.write(to: dir.appendingPathComponent("stage.txt"), atomically: true, encoding: .utf8)
        } catch {
            call.reject("could not record the stage: \(error.localizedDescription)")
            return
        }
        let deadline = Date().addingTimeInterval(15)
        while !FileManager.default.fileExists(atPath: ackURL.path) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        call.resolve(["stage": name])
    }
}
