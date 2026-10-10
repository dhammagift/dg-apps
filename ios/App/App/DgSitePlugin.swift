import Foundation
import WebKit
import Capacitor

// Files of the site downloaded after the app was built (scripts, styles, icons: www/site-manifest.json lists what may be),
// answered in front of the bundled ones. The page's updater (src/site-updater.js) hands them over:
//     DgSite.put({ path, data })   into the next round (site-next/)
//     DgSite.commit()              the round is complete: it serves from the next start of the app
//     DgSite.discard()             the round is dropped (a write failed)
//     DgSite.apply()               a committed round serves now (the "Update" bar, right before it reloads the page)
//     DgSite.list()   DgSite.clear() (both rounds)
// A round moves into site/ when the plugin loads (capacitorDidLoad, before the page), so a running page never gets new files
// next to the old ones it started with. Same as Android's DgSitePlugin.java. Only a downloaded file is answered here,
// everything else goes to Capacitor's asset handler (DgSchemeRouter).
enum DgSiteStore {
    private static var base: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
    static var root: URL { base.appendingPathComponent("site", isDirectory: true) }
    static var next: URL { base.appendingPathComponent("site-next", isDirectory: true) }
    static var ready: URL { next.appendingPathComponent(".ready") }

    static func file(for path: String, in dir: URL? = nil) -> URL? {
        guard path.hasPrefix("/"), !path.contains(".."), path.count < 300 else { return nil }
        return (dir ?? root).appendingPathComponent(String(path.dropFirst()))
    }

    /// A committed round takes over; an uncommitted one (the app stopped half-way through a check) is dropped.
    static func promote() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: next.path) else { return }
        if fm.fileExists(atPath: ready.path), let walker = fm.enumerator(at: next, includingPropertiesForKeys: nil) {
            // Listed first, moved after: the directory is not changed under its own enumerator.
            let basePath = next.resolvingSymlinksInPath().path
            let files = ((walker.allObjects as? [URL]) ?? []).filter { url -> Bool in
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue && url.lastPathComponent != ".ready"
            }
            for url in files {
                let full = url.resolvingSymlinksInPath().path
                guard full.hasPrefix(basePath + "/"), let dest = file(for: String(full.dropFirst(basePath.count))) else { continue }
                try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: dest.path) {
                    _ = try? fm.replaceItemAt(dest, withItemAt: url)
                } else {
                    try? fm.moveItem(at: url, to: dest)
                }
            }
        }
        try? fm.removeItem(at: next)
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
        CAPPluginMethod(name: "commit", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "discard", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "apply", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "list", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clear", returnType: CAPPluginReturnPromise)
    ]

    private static let maxBytes = 8 * 1024 * 1024

    override public func load() {
        DgSiteStore.promote()
    }

    @objc func put(_ call: CAPPluginCall) {
        guard let path = call.getString("path"), let text = call.getString("data"),
              let file = DgSiteStore.file(for: path, in: DgSiteStore.next), let bytes = Data(base64Encoded: text) else {
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

    @objc func commit(_ call: CAPPluginCall) {
        do {
            try FileManager.default.createDirectory(at: DgSiteStore.next, withIntermediateDirectories: true)
            try Data("1".utf8).write(to: DgSiteStore.ready, options: .atomic)
            call.resolve()
        } catch {
            call.reject("DgSite.commit failed: \(error.localizedDescription)")
        }
    }

    @objc func discard(_ call: CAPPluginCall) {
        try? FileManager.default.removeItem(at: DgSiteStore.next)
        call.resolve()
    }

    @objc func apply(_ call: CAPPluginCall) {
        DgSiteStore.promote()
        call.resolve()
    }

    @objc func clear(_ call: CAPPluginCall) {
        try? FileManager.default.removeItem(at: DgSiteStore.next)
        try? FileManager.default.removeItem(at: DgSiteStore.root)
        call.resolve()
    }
}
