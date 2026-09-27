import Foundation
import Capacitor

// Lets the App Store screenshot tour (test/ios-sim/tour.js) tell a simulator run which view is on screen, the same
// device the reader app uses for its own tour: one file, overwritten per stage, in Documents. A GitHub runner has no
// debugger to look at, so the page hands its progress out this one native call and the driver script screenshots on
// the signal instead of guessing at timings.
//
//     xcrun simctl get_app_container booted gift.dhamma.pali data
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
        do {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try name.write(to: dir.appendingPathComponent("stage.txt"), atomically: true, encoding: .utf8)
            call.resolve(["stage": name])
        } catch {
            call.reject("could not record the stage: \(error.localizedDescription)")
        }
    }
}
