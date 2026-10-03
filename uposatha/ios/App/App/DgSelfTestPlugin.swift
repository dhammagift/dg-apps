import Foundation
import Capacitor

// Lets the App Store screenshot tour (test/ios-sim/tour.js) tell a simulator run which view is on screen, the same
// device Dhamma.Gift uses for its own tour: one file, overwritten per stage, in Documents. A GitHub runner has no
// debugger to look at, so the page hands its progress out this one native call and the driver script screenshots on
// the signal instead of guessing at timings.
//
//     xcrun simctl get_app_container booted gift.dhamma.uposatha data
//
// Registered only in DEBUG builds (see DgApp.swift) and never in a shipped app.
@objc(DgSelfTestPlugin)
public class DgSelfTestPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "DgSelfTestPlugin"
    public let jsName = "DgSelfTest"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "stage", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "report", returnType: CAPPluginReturnPromise)
    ]

    // The numbers the edge-to-edge proof judges (tools/ios-edgetoedge.sh): what the page's own
    // viewport/layout measured, so a screenshot's pixels do not have to be guessed at — the run 444
    // verdict was read off a screenshot and came out wrong twice (the system clock was taken for
    // the page's text, a card for the page's background).
    //
    //     DgSelfTest.report({ topInset: 59, viewportFit: true, barTop: 69, barBottom: 105, theme: 'light' })
    @objc func report(_ call: CAPPluginCall) {
        let body: [String: Any] = [
            "topInset": call.getDouble("topInset") ?? -1,
            "viewportFit": call.getBool("viewportFit") ?? false,
            "barTop": call.getDouble("barTop") ?? -1,
            "barBottom": call.getDouble("barBottom") ?? -1,
            "theme": call.getString("theme") ?? "",
            // Diagnostics for the iOS inset hunt: was the insets plugin there at all, and what did
            // it answer. The bridge sends them; without these two the report cannot say which of the
            // two a topInset of 0 came from.
            "insetsPlugin": call.getBool("insetsPlugin") ?? false,
            "insetsAnswer": call.getObject("insetsAnswer") ?? [:],
            "orientation": call.getString("orientation") ?? "",
            "at": Date().timeIntervalSince1970
        ]
        do {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let data = try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: dir.appendingPathComponent("dg-edgetoedge.json"), options: .atomic)
            call.resolve(body)
        } catch {
            call.reject("could not record the edge-to-edge numbers: \(error.localizedDescription)")
        }
    }

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
