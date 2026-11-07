import Foundation
import WebKit
import DgSQLite

// One dg.db in the App Group container, read by the app and by the share extension.
//
// The offline layer (dg-node's public/offline) keeps the library in OPFS, which belongs to the
// process that created it: the share extension, a separate process, could never see the app's
// copy, so sharing text to Dhamma.gift needed the network. A plain file in the group container is
// visible to both, and it also ends the double storage iOS had — the 206 MB archive that nothing
// deleted next to the 584 MB OPFS copy. Here the archive is unpacked into dg.db and removed.
//
// The search core talks to SQLite through one prepare().all() adapter (db-worker.js), and it calls
// it synchronously. So the worker asks this process with a synchronous XMLHttpRequest to
// /dg-sql/... on the page's own origin, and DgSqlSchemeHandler answers with rows as JSON:
//   /dg-sql/status            {present, single, packs}   — also closes the connection, so a replaced file reopens
//   /dg-sql/query?s=<json>    {cols, rows} for {sql, params}
//   /dg-sql/open?s=<json>     {main, attach: [{id, name}], views}: packs, the main one opened, the others ATTACHed, then the
//                             worker's TEMP VIEWs over them (kept, so a reopen after status has them again)
//   /dg-sql/remove?s=<json>   {keep: [names]}: every other pack, and the single dg.db, removed
//   /dg-sql/manifest          the packs-manifest.json saved with the packs
//   /dg-sql/delete            removes dg.db and the packs (Settings → delete the offline library)
// Packs (owner 2026-11-07): the library as segments - the main pack and the chosen translations and editions, each a plain
// <id>.<build>.db in packs/ beside the old single dg.db, which only builds before packs downloaded. db-worker.js decides
// which to open (openNativePacks); this side only opens, lists and removes files.
// This file is compiled into both targets; the download and unpacking live in DgDownloadPlugin
// (app only), the extension only reads.
enum DgLibrary {
    static let groupId = "group.gift.dhamma.mobile"
    static let endpointPath = "/dg-sql"
    static let dbName = "dg.db"
    static let archiveName = "dg.db.gz"

    // The group container, or — for a build whose App ID has no App Group yet — the app's own
    // Application Support (the same directory builds 170–215 downloaded into). The app works
    // either way; only the extension needs the group.
    static func directory() -> URL {
        let fm = FileManager.default
        let dir = fm.containerURL(forSecurityApplicationGroupIdentifier: groupId)?
            .appendingPathComponent("dg-library", isDirectory: true) ?? legacyDirectory()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func legacyDirectory() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("dg-library", isDirectory: true)
    }

    static var dbURL: URL { directory().appendingPathComponent(dbName) }
    static var archiveURL: URL { directory().appendingPathComponent(archiveName) }
    // The old single library (builds before packs).
    static var singlePresent: Bool { FileManager.default.fileExists(atPath: dbURL.path) }
    static var isPresent: Bool { singlePresent || !packFiles().isEmpty }

    static func packsDirectory() -> URL {
        let dir = directory().appendingPathComponent("packs", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutable = dir
            try? mutable.setResourceValues(values)
        }
        return dir
    }
    static var packsManifestURL: URL { packsDirectory().appendingPathComponent("packs-manifest.json") }
    // The unpacked packs, <id>.<build>.db; an archive or a half-written .tmp is not one.
    static func packFiles() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: packsDirectory().path)) ?? []
        return names.filter { $0.hasSuffix(".db") }.sorted()
    }
    // A pack's file name or id from the page goes into a path and into SQL: letters, digits, '-', '_' and '.' only.
    static func safeName(_ name: String) -> Bool {
        return !name.isEmpty && !name.hasPrefix(".") && name.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil
    }

    // Tells src/platform.js (and through it the worker) that SQL runs natively at endpointPath.
    // The site and Android never define it and keep their OPFS path. In the share sheet the page
    // also gets the offline layer's own "a library exists here" flag, because the sheet's WebView
    // has a fresh localStorage and the layer starts its worker only for a reason.
    static func userScript(shareSheet: Bool) -> WKUserScript {
        // DG_NATIVE_PACKS: this shell downloads and opens the library in packs (dg-node offline/app.js PACKS_ON).
        var js = "window.DG_NATIVE_SQL = '\(endpointPath)'; window.DG_NATIVE_PACKS = true;"
        if shareSheet {
            js += "window.DG_SHARE_SHEET = true;"
            if isPresent { js += "try { localStorage.setItem('dg.offline.libraryExists', '1'); } catch (e) {}" }
        }
        return WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }
}

struct DgSqlError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// The regex the core registers as regexp_test (core-bundle.js, registerRegexpTest): a JS RegExp
// with the 'i' flag over a JS callback, which a native SQLite cannot call — so the same function
// is defined here with NSRegularExpression. A C callback cannot capture, hence the static cache.
// ponytail: ICU regex, not JS regex — identical for the words and alternations people search
// for; a pattern that only JS accepts fails here with "invalid regular expression".
private var regexCache: (pattern: String, regex: NSRegularExpression?) = ("", nil)

private func regexpTest(_ ctx: OpaquePointer?, _ argc: Int32, _ argv: UnsafeMutablePointer<OpaquePointer?>?) {
    guard let argv = argv, let p = sqlite3_value_text(argv[0]), let t = sqlite3_value_text(argv[1]) else {
        sqlite3_result_int(ctx, 0)
        return
    }
    let pattern = String(cString: p)
    if regexCache.pattern != pattern {
        regexCache = (pattern, try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))
    }
    guard let regex = regexCache.regex else {
        sqlite3_result_error(ctx, "invalid regular expression", -1)
        return
    }
    let text = String(cString: t)
    let hit = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil
    sqlite3_result_int(ctx, hit ? 1 : 0)
}

final class DgSqlSchemeHandler: NSObject, WKURLSchemeHandler {
    private let queue = DispatchQueue(label: "gift.dhamma.mobile.sql")
    private var db: OpaquePointer?               // touched on `queue` only
    // The packs the worker last opened ("open"): "status" closes the connection, and the next query reopens these, not the
    // single dg.db (the worker asks for status again while a library is open: the update check, Settings).
    private var lastPacks: (main: String, attach: [(String, String)], views: [String])?   // `queue` only
    private var live = Set<ObjectIdentifier>()   // main thread only: tasks not yet stopped

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let id = ObjectIdentifier(task as AnyObject)
        live.insert(id)
        let op = url.lastPathComponent
        let payload = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "s" })?.value
        queue.async {
            let (status, body) = self.handle(op: op, payload: payload)
            DispatchQueue.main.async {
                // A task that was stopped must not be touched again — WebKit throws.
                guard self.live.remove(id) != nil else { return }
                let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [
                    "Content-Type": "application/json",
                    "Content-Length": String(body.count),
                    "Cache-Control": "no-store"
                ])!
                task.didReceive(response)
                task.didReceive(body)
                task.didFinish()
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        live.remove(ObjectIdentifier(task as AnyObject))
    }

    private func handle(op: String, payload: String?) -> (Int, Data) {
        do {
            switch op {
            case "status":
                close()
                return (200, try json(["present": DgLibrary.isPresent, "single": DgLibrary.singlePresent, "packs": DgLibrary.packFiles()]))
            case "open":
                let request = try body(payload)
                guard let main = request["main"] as? String else { return (400, try json(["error": "bad request"])) }
                let attach = (request["attach"] as? [[String: Any]] ?? []).compactMap { a -> (String, String)? in
                    guard let id = a["id"] as? String, let name = a["name"] as? String else { return nil }
                    return (id, name)
                }
                let views = request["views"] as? [String] ?? []
                try openPacks(main: main, attach: attach, views: views)
                lastPacks = (main, attach, views)
                return (200, try json(["open": true]))
            case "remove":
                let keep = Set(try body(payload)["keep"] as? [String] ?? [])
                let dir = DgLibrary.packsDirectory()
                for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
                where !keep.contains(name) && name != DgLibrary.packsManifestURL.lastPathComponent {
                    try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
                }
                // The packs replace the single library: once they open, it goes.
                if !keep.isEmpty {
                    try? FileManager.default.removeItem(at: DgLibrary.dbURL)
                    try? FileManager.default.removeItem(at: DgLibrary.archiveURL)
                }
                return (200, try json(["removed": true]))
            case "manifest":
                guard let data = try? Data(contentsOf: DgLibrary.packsManifestURL) else { return (404, try json(["error": "no saved manifest"])) }
                return (200, data)
            case "query":
                guard let request = try? body(payload), let sql = request["sql"] as? String else {
                    return (400, try json(["error": "bad request"]))
                }
                return (200, try json(try run(sql: sql, params: request["params"] as? [Any] ?? [])))
            case "delete":
                close()
                lastPacks = nil
                try? FileManager.default.removeItem(at: DgLibrary.dbURL)
                try? FileManager.default.removeItem(at: DgLibrary.archiveURL)
                try? FileManager.default.removeItem(at: DgLibrary.packsDirectory())
                return (200, try json(["deleted": true]))
            default:
                return (404, try json(["error": "unknown op \(op)"]))
            }
        } catch {
            return (500, (try? json(["error": error.localizedDescription])) ?? Data())
        }
    }

    private func body(_ payload: String?) throws -> [String: Any] {
        guard let payload = payload, let data = payload.data(using: .utf8),
              let request = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DgSqlError("bad request")
        }
        return request
    }

    private func json(_ object: Any) throws -> Data {
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func close() {
        if let db = db { sqlite3_close(db) }
        db = nil
    }

    // Read-only and immutable: SQLite then never creates -journal/-wal/-shm next to a file that
    // another process is reading, and never takes a lock on it. The single dg.db when nothing was
    // opened explicitly (builds before packs); packs are opened by "open" first.
    private func open() throws -> OpaquePointer {
        if let db = db { return db }
        if let packs = lastPacks {
            try openPacks(main: packs.main, attach: packs.attach, views: packs.views)
            if let db = db { return db }
        }
        guard DgLibrary.singlePresent else { throw DgSqlError("the offline library is not downloaded") }
        let opened = try openFile(DgLibrary.dbURL)
        db = opened
        return opened
    }

    private static func uri(_ url: URL) -> String {
        let path = url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.path
        return "file:\(path)?immutable=1"
    }

    private func openFile(_ url: URL) throws -> OpaquePointer {
        guard FileManager.default.fileExists(atPath: url.path) else { throw DgSqlError("the offline library is not downloaded") }
        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(Self.uri(url), &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX, nil)
        guard rc == SQLITE_OK, let opened = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open the database"
            if let handle = handle { sqlite3_close(handle) }
            throw DgSqlError(message)
        }
        sqlite3_create_function_v2(opened, "regexp_test", 2, SQLITE_UTF8 | SQLITE_DETERMINISTIC, nil, regexpTest, nil, nil, nil)
        return opened
    }

    // The main pack, then each other one ATTACHed under its id (db-worker.js names the schemas in its SQL). The TEMP VIEWs
    // over them are the worker's, through "query": a read-only connection still has its own temp schema.
    private func openPacks(main: String, attach: [(String, String)], views: [String]) throws {
        guard DgLibrary.safeName(main), attach.allSatisfy({ DgLibrary.safeName($0.0) && DgLibrary.safeName($0.1) }) else {
            throw DgSqlError("bad pack name")
        }
        close()
        let dir = DgLibrary.packsDirectory()
        let opened = try openFile(dir.appendingPathComponent(main))
        for (id, name) in attach {
            let url = dir.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else {
                sqlite3_close(opened)
                throw DgSqlError("the offline pack \(id) is not downloaded")
            }
            let sql = "ATTACH '\(Self.uri(url).replacingOccurrences(of: "'", with: "''"))' AS \"\(id)\""
            guard sqlite3_exec(opened, sql, nil, nil, nil) == SQLITE_OK else {
                let message = String(cString: sqlite3_errmsg(opened))
                sqlite3_close(opened)
                throw DgSqlError(message)
            }
        }
        // temp_store=memory: the views' temp schema needs no file next to the read-only packs
        for sql in ["PRAGMA temp_store = memory"] + views where sqlite3_exec(opened, sql, nil, nil, nil) != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(opened))
            sqlite3_close(opened)
            throw DgSqlError(message)
        }
        db = opened
    }

    // Column-major on purpose: {cols, rows} is a fraction of the JSON of one object per row, and
    // the worker rebuilds objects in a few lines. A search can return tens of thousands of rows.
    private func run(sql: String, params: [Any]) throws -> [String: Any] {
        let db = try open()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let stmt = statement else {
            throw DgSqlError(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, param) in params.enumerated() {
            let index = Int32(i + 1)
            switch param {
            case let text as String:
                sqlite3_bind_text(stmt, index, text, -1, transient)
            case let number as NSNumber:
                if CFNumberIsFloatType(number) { sqlite3_bind_double(stmt, index, number.doubleValue) }
                else { sqlite3_bind_int64(stmt, index, number.int64Value) }
            default:
                sqlite3_bind_null(stmt, index)
            }
        }
        let count = Int(sqlite3_column_count(stmt))
        let cols = (0..<count).map { String(cString: sqlite3_column_name(stmt, Int32($0))!) }
        var rows: [[Any]] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw DgSqlError(String(cString: sqlite3_errmsg(db))) }
            var row: [Any] = []
            row.reserveCapacity(count)
            for c in 0..<count {
                let column = Int32(c)
                switch sqlite3_column_type(stmt, column) {
                case SQLITE_INTEGER: row.append(sqlite3_column_int64(stmt, column))
                case SQLITE_FLOAT: row.append(sqlite3_column_double(stmt, column))
                case SQLITE_TEXT: row.append(String(cString: sqlite3_column_text(stmt, column)!))
                default: row.append(NSNull())
                }
            }
            rows.append(row)
        }
        return ["cols": cols, "rows": rows]
    }
}
