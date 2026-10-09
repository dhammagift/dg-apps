import Foundation
import WebKit
import Capacitor

// Files of the site downloaded after the app was built (scripts, styles, icons: www/site-manifest.json lists what may be),
// answered in front of the bundled ones. The page's updater (native-bridge.js) hands them over:
//     DgSite.put({ path, data })   DgSite.list()   DgSite.clear()
// Same as the dictionary's (dict/ios/App/App/DgApp.swift), without its proxy: only a downloaded file is answered here,
// everything else goes to Capacitor's asset handler (DgSchemeRouter).
enum DgSiteStore {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("site", isDirectory: true)
    }

    static func file(for path: String) -> URL? {
        guard path.hasPrefix("/"), !path.contains(".."), path.count < 300 else { return nil }
        return root.appendingPathComponent(String(path.dropFirst()))
    }

    private static let types = [
        "js": "application/javascript; charset=utf-8", "mjs": "application/javascript; charset=utf-8", "css": "text/css; charset=utf-8",
        "json": "application/json; charset=utf-8", "svg": "image/svg+xml", "woff2": "font/woff2", "woff": "font/woff",
        "png": "image/png", "webp": "image/webp"
    ]

    /// A downloaded file for a request to the app's own origin, answered; false = not ours, let Capacitor serve it.
    static func answer(_ task: WKURLSchemeTask) -> Bool {
        guard let url = task.request.url, task.request.httpMethod == "GET", url.host == "localhost",
              !url.path.hasSuffix("/"), !url.path.hasPrefix("/_capacitor"),
              let file = file(for: url.path), FileManager.default.fileExists(atPath: file.path),
              let data = try? Data(contentsOf: file) else { return false }
        let type = types[file.pathExtension.lowercased()] ?? "application/octet-stream"
        let headers = ["Content-Type": type, "Content-Length": String(data.count), "Access-Control-Allow-Origin": "*", "Cache-Control": "no-cache"]
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) else { return false }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
        return true
    }
}

@objc(DgSitePlugin)
public class DgSitePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "DgSitePlugin"
    public let jsName = "DgSite"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "put", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "list", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clear", returnType: CAPPluginReturnPromise)
    ]

    private static let maxBytes = 8 * 1024 * 1024

    @objc func put(_ call: CAPPluginCall) {
        guard let path = call.getString("path"), let text = call.getString("data"),
              let file = DgSiteStore.file(for: path), let bytes = Data(base64Encoded: text) else {
            return call.reject("bad path or no data")
        }
        if bytes.isEmpty || bytes.count > Self.maxBytes { return call.reject("size out of range") }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: file, options: .atomic)
            call.resolve()
        } catch {
            call.reject("DgSite.put failed: \(error.localizedDescription)")
        }
    }

    @objc func list(_ call: CAPPluginCall) {
        var files: [String] = []
        let root = DgSiteStore.root
        if let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in walker where !url.hasDirectoryPath {
                files.append(String(url.path.dropFirst(root.path.count)))
            }
        }
        call.resolve(["files": files])
    }

    @objc func clear(_ call: CAPPluginCall) {
        try? FileManager.default.removeItem(at: DgSiteStore.root)
        call.resolve()
    }
}
