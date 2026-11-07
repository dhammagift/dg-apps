import Foundation
import Compression
import CryptoKit
import Capacitor

// The library download, moved off the WebView and onto the system's background transfer service.
//
// Why this exists: the offline layer downloads dg.db.gz (216 MB) with fetch() inside a Web Worker,
// and iOS suspends a WebView's JavaScript the moment the app leaves the foreground — so a reader who
// switches apps or locks the screen stops the transfer mid-way. Android answers that with a
// foreground service (DgDownloadService); iOS's answer is a background URLSession, which the system
// keeps running, and relaunches the app for when it finishes.
//
//   start({url, sha256}) -> {path} once dg.db is unpacked in the App Group container (DgSharedLibrary);
//                    "progress" events {loaded, total} while the archive downloads, "unpack"
//                    events {loaded, total} while it is being unpacked. sha256 (db-manifest.json's, of
//                    the unpacked database) is checked before the file replaces the library, as on Android.
//   existing()    -> {path} or {path: null} if no library is on disk
//   start({base, files}) -> {path} once every file is in DgLibrary.packsDirectory(): packs (owner 2026-11-07), files =
//                    JSON [{path, bytes, sha256}] relative to base (dg-node db-worker.js 'packs-plan'; sha256 is the
//                    archive's). All go to the background session at once, so the system carries them on while the app is
//                    away; each .db.gz is checked, unpacked into <id>.<build>.db and deleted. "progress" {loaded, total}
//                    over all of them.
//   cancel()      -> stops the transfer; the partial file is discarded and a waiting start() is refused
//                    (the caller can start again)
//
// The archive is unpacked here and deleted at once: the worker reads dg.db in place through
// /dg-sql (DgSharedLibrary.swift), so the file is the library — there is no import into OPFS and
// no second copy. An archive left by an earlier build in Application Support is unpacked too, so
// nobody downloads 216 MB again for the move.
//
// Deliberately no file size in any answer: FileManager's size/metadata reads are Apple's
// required-reason FileTimestamp APIs, and a plugin that does not use them needs no privacy manifest
// of its own. The byte counts the page shows come from the transfer's progress events.
//
// ponytail: one download at a time, no resume-data bookkeeping (a restart re-requests the file and
// the server's Range support does the rest), no notification and no Live Activity — progress is
// forwarded to the page, which already has a progress card and now also gets DgProgress's idle
// timer. Add resume data if a real network shows the server refusing Range.
@objc(DgDownloadPlugin)
public class DgDownloadPlugin: CAPPlugin, CAPBridgedPlugin, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    public let identifier = "DgDownloadPlugin"
    public let jsName = "DgDownload"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "existing", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "cancel", returnType: CAPPluginReturnPromise)
    ]

    static let sessionIdentifier = "gift.dhamma.mobile.library"
    // Set by AppDelegate when the system wakes the app to hand over a finished background transfer.
    static var backgroundCompletionHandler: (() -> Void)?

    private var session: URLSession!
    private var task: URLSessionDownloadTask?
    private var waiting: [CAPPluginCall] = []
    private var unpackError: Error?

    override public func load() {
        #if targetEnvironment(simulator)
        // The simulator's background transfer service often never starts a task (no request reached the server in two
        // runs of the packs self-test, 2026-11-07): an ordinary session there; devices keep the background one.
        let config = URLSessionConfiguration.default
        #else
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        // Not discretionary: a discretionary transfer waits for a good moment (charging, Wi-Fi) and
        // the reader is standing there watching a progress card.
        config.isDiscretionary = false
        // Relaunch the app when the transfer finishes, so the unpacking can run.
        config.sessionSendsLaunchEvents = true
        #endif
        // a transfer that is not finished in 6 hours fails instead of waiting the default 7 days
        config.timeoutIntervalForResource = 6 * 3600
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    @objc func existing(_ call: CAPPluginCall) {
        do {
            try unpackIfNeeded()
            call.resolve(["path": DgLibrary.singlePresent ? DgLibrary.dbURL.path : NSNull()])
        } catch {
            call.reject("could not unpack the downloaded archive: \(error.localizedDescription)")
        }
    }

    // The sha256 the unpacked database must have, kept across launches: the transfer may end while the app is not running,
    // and existing() unpacks the archive at the next launch. A file beside the archive, not UserDefaults: UserDefaults is
    // one of Apple's required-reason APIs, and this app declares none (build-app.yml's check).
    private static var expectedShaURL: URL { DgLibrary.archiveURL.appendingPathExtension("sha256") }

    @objc func start(_ call: CAPPluginCall) {
        if let files = call.getString("files"), let base = call.getString("base") {
            startPacks(call, base: base, files: files)
            return
        }
        guard let raw = call.getString("url"), let url = URL(string: raw) else {
            call.reject("no url")
            return
        }
        try? (call.getString("sha256") ?? "").write(to: Self.expectedShaURL, atomically: true, encoding: .utf8)
        // A second start while one is running joins the running transfer instead of racing it: the
        // page can be reloaded (or the app relaunched) mid-download. After a relaunch the plugin is new
        // (task == nil) while the system's background session may still be carrying the previous run's
        // transfer: that one is joined too, never a second 216 MB download beside it.
        if task != nil {
            waiting.append(call)
            return
        }
        session.getAllTasks { tasks in
            DispatchQueue.main.async {
                if self.task != nil {
                    self.waiting.append(call)
                    return
                }
                self.waiting = [call]
                self.unpackError = nil
                if let running = tasks.compactMap({ $0 as? URLSessionDownloadTask })
                    .first(where: { $0.state == .running || $0.state == .suspended }) {
                    self.task = running
                    running.resume()
                    return
                }
                let newTask = self.session.downloadTask(with: url)
                self.task = newTask
                newTask.resume()
            }
        }
    }

    @objc func cancel(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let calls = self.waiting + self.packWaiting
            self.waiting = []
            self.packWaiting = []
            self.packTasks = [:]
            self.packError = nil
            try? FileManager.default.removeItem(at: Self.packPlanURL)
            self.task = nil
            // Every transfer of the session, also one a previous run of the app started.
            self.session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
            calls.forEach { $0.reject("cancelled") }
            call.resolve()
        }
    }

    private func finish(error: Error?) {
        let calls = waiting
        waiting = []
        task = nil
        if let error = error ?? unpackError {
            calls.forEach { $0.reject("download failed: \(error.localizedDescription)") }
            return
        }
        guard DgLibrary.singlePresent else {
            calls.forEach { $0.reject("download failed: no library on disk afterwards") }
            return
        }
        calls.forEach { $0.resolve(["path": DgLibrary.dbURL.path]) }
    }

    // MARK: - Packs

    // One entry per file of the running set, by its URL; kept in a file beside the packs too, because the system may finish
    // the transfers while the app is not running and relaunch it with only the URLs.
    struct PackFile: Codable { let url: String; let name: String; let sha256: String; let bytes: Int64 }
    private var packTasks: [Int: PackFile] = [:]     // main thread: running task id -> its file
    private var packWritten: [Int: Int64] = [:]      // main thread: bytes so far, per task
    private var packTotal: Int64 = 0
    private var packWaiting: [CAPPluginCall] = []
    private var packError: Error?
    private var installing = 0                       // main thread: packs being checked and unpacked
    private static let installQueue = DispatchQueue(label: "gift.dhamma.mobile.packs.install")
    private static var packPlanURL: URL { DgLibrary.packsDirectory().appendingPathComponent("pending.json") }

    private static func savedPlan() -> [PackFile] {
        guard let data = try? Data(contentsOf: packPlanURL) else { return [] }
        return (try? JSONDecoder().decode([PackFile].self, from: data)) ?? []
    }

    private func startPacks(_ call: CAPPluginCall, base: String, files: String) {
        guard let data = files.data(using: .utf8),
              let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            call.reject("bad file list")
            return
        }
        let root = base.hasSuffix("/") ? base : base + "/"
        var plan: [PackFile] = []
        for f in list {
            guard let path = f["path"] as? String, let url = URL(string: path, relativeTo: URL(string: root)) else { continue }
            // root-ms.<build>.db.gz -> root-ms.<build>.db; the manifest keeps its name
            let file = (path as NSString).lastPathComponent
            let name = file.hasSuffix(".gz") ? String(file.dropLast(3)) : file
            guard DgLibrary.safeName(name) else { continue }
            plan.append(PackFile(url: url.absoluteString, name: name, sha256: f["sha256"] as? String ?? "",
                                 bytes: (f["bytes"] as? NSNumber)?.int64Value ?? 0))
        }
        let set = plan
        DispatchQueue.main.async {
            // A second start while a set is running - or still being set up: packTasks fills only in getAllTasks' callback
            // below - joins it (a reload, a relaunch, two presses: the page's own call and the consent sheet's Download
            // two seconds apart overwrote the first call, which then waited forever - simulator, 2026-11-07).
            if !self.packTasks.isEmpty || !self.packWaiting.isEmpty {
                self.packWaiting.append(call)
                return
            }
            self.packWaiting = [call]
            self.packError = nil
            self.packWritten = [:]
            self.packTotal = set.reduce(0) { $0 + $1.bytes }
            try? JSONEncoder().encode(set).write(to: Self.packPlanURL, options: .atomic)
            self.session.getAllTasks { tasks in
                DispatchQueue.main.async {
                    let running = tasks.compactMap { $0 as? URLSessionDownloadTask }
                        .filter { $0.state == .running || $0.state == .suspended }
                    // a transfer an earlier run left that this set does not need (another build, the single library)
                    for t in running where !set.contains(where: { $0.url == t.originalRequest?.url?.absoluteString }) { t.cancel() }
                    for entry in set {
                        if let t = running.first(where: { $0.originalRequest?.url?.absoluteString == entry.url }) {
                            self.packTasks[t.taskIdentifier] = entry
                            t.resume()
                        } else if let url = URL(string: entry.url) {
                            let t = self.session.downloadTask(with: url)
                            self.packTasks[t.taskIdentifier] = entry
                            t.resume()
                        }
                    }
                    if self.packTasks.isEmpty { self.finishPacks() } else { self.watch() }
                }
            }
        }
    }

    // No byte in 90 s: the transfer is not going to start (a stuck background service, no network). Better a clear
    // failure the page can retry than a progress card that waits forever.
    private var watchdog: DispatchWorkItem?
    private func watch() {
        watchdog?.cancel()
        let before = packWritten.values.reduce(0, +)
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, !self.packTasks.isEmpty else { return }
            if self.packWritten.values.reduce(0, +) > before { self.watch(); return }
            self.packError = self.packError ?? DgSqlError("no data arrived in 90 s")
            let ids = Set(self.packTasks.keys)
            self.session.getAllTasks { tasks in tasks.filter { ids.contains($0.taskIdentifier) }.forEach { $0.cancel() } }
        }
        watchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: item)
    }

    private func packEntry(for task: URLSessionTask) -> PackFile? {
        guard let url = task.originalRequest?.url?.absoluteString else { return nil }
        return Self.savedPlan().first(where: { $0.url == url })
    }

    // Called on the session's queue from didFinishDownloadingTo: the temporary file is gone once that returns.
    private func installPack(_ entry: PackFile, from location: URL) throws {
        let fm = FileManager.default
        let dir = DgLibrary.packsDirectory()
        if !entry.sha256.isEmpty {
            let actual = try Self.sha256(of: location)
            if actual.lowercased() != entry.sha256.lowercased() { throw DgSqlError("the downloaded pack \(entry.name) is damaged (checksum)") }
        }
        if !entry.name.hasSuffix(".db") {   // the manifest
            let target = dir.appendingPathComponent(entry.name)
            try? fm.removeItem(at: target)
            try fm.moveItem(at: location, to: target)
            return
        }
        let tmp = dir.appendingPathComponent(entry.name + ".tmp")
        try? fm.removeItem(at: tmp)
        try Self.gunzip(location, to: tmp, progress: { _ in }, output: { _ in })
        let target = dir.appendingPathComponent(entry.name)
        try? fm.removeItem(at: target)
        try fm.moveItem(at: tmp, to: target)
    }

    private static func sha256(of url: URL) throws -> String {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var hasher = SHA256()
        while true {
            let chunk = input.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // main thread
    private func finishPacks() {
        watchdog?.cancel()
        watchdog = nil
        let calls = packWaiting
        packWaiting = []
        packTasks = [:]
        try? FileManager.default.removeItem(at: Self.packPlanURL)
        if let error = packError {
            packError = nil
            calls.forEach { $0.reject("download failed: \(error.localizedDescription)") }
            return
        }
        calls.forEach { $0.resolve(["path": DgLibrary.packsDirectory().path]) }
    }

    // MARK: - Unpacking

    // An archive in the library directory, or one an earlier build left in Application Support,
    // becomes dg.db; the archive is deleted once the file is complete. Nothing to do when dg.db is
    // already there and no newer archive waits beside it.
    private func unpackIfNeeded() throws {
        let fm = FileManager.default
        let target = DgLibrary.archiveURL
        let legacy = DgLibrary.legacyDirectory().appendingPathComponent(DgLibrary.archiveName)
        if !fm.fileExists(atPath: target.path), legacy != target, fm.fileExists(atPath: legacy.path) {
            try fm.moveItem(at: legacy, to: target)
            try? fm.removeItem(at: DgLibrary.legacyDirectory())
        }
        guard fm.fileExists(atPath: target.path) else { return }
        try unpack(archive: target, expectedBytes: 0)
    }

    private func unpack(archive: URL, expectedBytes: Int64) throws {
        let fm = FileManager.default
        let tmp = DgLibrary.dbURL.appendingPathExtension("tmp")
        try? fm.removeItem(at: tmp)
        var hasher = SHA256()
        try Self.gunzip(archive, to: tmp, progress: { loaded in
            self.notifyListeners("unpack", data: ["loaded": loaded, "total": expectedBytes])
        }, output: { hasher.update(data: $0) })
        // The manifest's checksum, before anything replaces the working library (an archive an older build left has none).
        let expected = ((try? String(contentsOf: Self.expectedShaURL, encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !expected.isEmpty {
            let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            if actual.lowercased() != expected.lowercased() {
                try? fm.removeItem(at: tmp)
                try? fm.removeItem(at: archive)
                try? fm.removeItem(at: Self.expectedShaURL)
                throw DgSqlError("the downloaded library is damaged (checksum)")
            }
        }
        // Replace, not remove-then-move: a reader (or the extension) holding the old file keeps
        // reading it, and there is never a moment without a library.
        if fm.fileExists(atPath: DgLibrary.dbURL.path) {
            _ = try fm.replaceItemAt(DgLibrary.dbURL, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: DgLibrary.dbURL)
        }
        try? fm.removeItem(at: archive)
        try? fm.removeItem(at: Self.expectedShaURL)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = DgLibrary.dbURL
        try? mutable.setResourceValues(values)
    }

    // gzip = a 10-byte header (+ optional fields), a raw deflate stream, an 8-byte trailer. The
    // Compression framework decodes raw deflate (COMPRESSION_ZLIB); the header is skipped here
    // and the trailer is never reached — the stream ends at the deflate end marker.
    private static func gunzip(_ source: URL, to destination: URL, progress: (Int64) -> Void, output emit: (Data) -> Void) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let header = input.readData(ofLength: 10)
        guard header.count == 10, header[0] == 0x1f, header[1] == 0x8b, header[2] == 8 else {
            throw DgSqlError("not a gzip archive")
        }
        let flags = header[3]
        if flags & 0x04 != 0 {
            let extra = input.readData(ofLength: 2)
            guard extra.count == 2 else { throw DgSqlError("truncated gzip header") }
            _ = input.readData(ofLength: Int(extra[0]) | Int(extra[1]) << 8)
        }
        for bit in [UInt8(0x08), UInt8(0x10)] where flags & bit != 0 {
            while let byte = input.readData(ofLength: 1).first, byte != 0 {}
        }
        if flags & 0x02 != 0 { _ = input.readData(ofLength: 2) }

        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw DgSqlError("cannot create \(destination.lastPathComponent)")
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) != COMPRESSION_STATUS_ERROR else {
            throw DgSqlError("cannot start the decoder")
        }
        defer { compression_stream_destroy(stream) }

        let bufferSize = 1 << 20
        let out = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { out.deallocate() }
        var chunk = [UInt8]()
        var offset = 0
        var eof = false
        var consumed: Int64 = 10
        while true {
            if offset == chunk.count && !eof {
                chunk = [UInt8](input.readData(ofLength: bufferSize))
                offset = 0
                eof = chunk.isEmpty
            }
            let status: compression_status = chunk.withUnsafeBufferPointer { buffer in
                stream.pointee.src_ptr = (buffer.baseAddress ?? UnsafePointer(out)) + offset
                stream.pointee.src_size = chunk.count - offset
                stream.pointee.dst_ptr = out
                stream.pointee.dst_size = bufferSize
                let result = compression_stream_process(stream, eof ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)
                let used = chunk.count - offset - stream.pointee.src_size
                offset += used
                consumed += Int64(used)
                return result
            }
            let produced = bufferSize - stream.pointee.dst_size
            if produced > 0 {
                let piece = Data(bytesNoCopy: out, count: produced, deallocator: .none)
                output.write(piece)
                emit(piece)
            }
            progress(consumed)
            if status == COMPRESSION_STATUS_END { return }
            guard status == COMPRESSION_STATUS_OK else { throw DgSqlError("the archive is damaged") }
            if eof && produced == 0 && stream.pointee.src_size == 0 { throw DgSqlError("the archive ended early") }
        }
    }

    // MARK: - URLSessionDownloadDelegate

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                           didFinishDownloadingTo location: URL) {
        // A pack: checked, unpacked and in place before this returns (the temporary file goes then).
        if let entry = packEntry(for: downloadTask) {
            // Only the move happens here (the temporary file goes when this returns): the checksum of ~110 MB and the
            // unpacking to ~290 MB run on their own queue, and the set is done when they are (finishPacks waits).
            let held = DgLibrary.packsDirectory().appendingPathComponent(entry.name + ".download")
            do {
                if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
                    throw DgSqlError("HTTP \(http.statusCode) for \(entry.name)")
                }
                try? FileManager.default.removeItem(at: held)
                try FileManager.default.moveItem(at: location, to: held)
            } catch {
                DispatchQueue.main.async { self.packError = self.packError ?? error }
                return
            }
            DispatchQueue.main.async { self.installing += 1 }
            Self.installQueue.async {
                var failure: Error?
                do { try self.installPack(entry, from: held) } catch { failure = error }
                try? FileManager.default.removeItem(at: held)
                DispatchQueue.main.async {
                    if let failure = failure { self.packError = self.packError ?? failure }
                    self.installing -= 1
                    if self.packTasks.isEmpty && self.installing == 0 { self.finishPacks() }
                }
            }
            return
        }
        // Called before didCompleteWithError, and the temporary file is deleted the moment this
        // returns — so the move happens here, synchronously; and so does the unpacking, which the
        // system's background time for a finished transfer covers. If it does not, the archive is
        // still on disk and existing() unpacks it at the next launch.
        let archive = DgLibrary.archiveURL
        do {
            if FileManager.default.fileExists(atPath: archive.path) {
                try FileManager.default.removeItem(at: archive)
            }
            try FileManager.default.moveItem(at: location, to: archive)
            try unpack(archive: archive, expectedBytes: downloadTask.countOfBytesReceived)
            notifyListeners("done", data: ["path": DgLibrary.dbURL.path])
        } catch {
            unpackError = error
            notifyListeners("failed", data: ["error": error.localizedDescription])
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                           didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                           totalBytesExpectedToWrite: Int64) {
        let id = downloadTask.taskIdentifier
        DispatchQueue.main.async {
            if self.packTasks[id] != nil {
                // one bar over the whole set
                self.packWritten[id] = totalBytesWritten
                let loaded = self.packWritten.values.reduce(0, +)
                self.notifyListeners("progress", data: ["loaded": loaded, "total": max(self.packTotal, loaded)])
                return
            }
            self.notifyListeners("progress", data: [
                "loaded": totalBytesWritten,
                "total": totalBytesExpectedToWrite
            ])
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async {
            if self.packTasks.removeValue(forKey: task.taskIdentifier) != nil {
                if let error = error { self.packError = self.packError ?? error }
                if self.packTasks.isEmpty && self.installing == 0 { self.finishPacks() }
                return
            }
            // A cancelled transfer reports here after the next one may have started: it must not settle that one.
            if let current = self.task, current.taskIdentifier != task.taskIdentifier { return }
            self.finish(error: error)
        }
    }

    // The system's own "you may go back to sleep" signal for a background session, and the reason
    // AppDelegate has to park the handler this plugin is given: iOS relaunches the app for a
    // finished transfer, hands it a completion handler, and expects it called or the app is killed.
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let handler = Self.backgroundCompletionHandler else { return }
        Self.backgroundCompletionHandler = nil
        DispatchQueue.main.async { handler() }
    }
}
