import Foundation

// The widget lays out data the app's page has built (uposatha/widget/WIDGET.md) and counts time forward from it.
// It never works out the moon, the sun or the Uposatha itself. Every moment is { ms, ymd, hm } of the place's time zone;
// `hm` is shown as it is. The only arithmetic here: durations, "which part is it now", and a calendar of the month.

// MARK: - The data (the contract)

struct WMoment: Codable {
    let ms: Double
    let ymd: String
    let hm: String
    var date: Date { Date(timeIntervalSince1970: ms / 1000) }
}

struct WSettings: Codable {
    var lang: String?
    let bySuttas: Bool?
    let detail: Bool?
    let allMoons: Bool?      // the calendar shows the moon of every day, not only of the Uposatha days
    let showKala: Bool?
    let placeSet: Bool?
    let tzAuto: Bool?        // the page follows the phone's time zone (none was chosen there)
    let south: Bool?
    let weekStart: Int?      // 0 = the week starts on Sunday, 1 = Monday
}

struct WToday: Codable {
    let ymd: String?
    let moon: Double?
}

// The moon of every day at midday (phase 0..1), from the date `from` on: the page's own numbers.
// The lit percent of the moon as the page shows it (its own numbers, every 3 hours for 30 days)
struct WLit: Codable {
    let from: Double         // epoch ms of the first point
    let step: Double         // ms between two points
    let pct: [Double]
}

struct WMoons: Codable {
    let from: String
    let phase: [Double]
    let lit: WLit?
}

struct WUposatha: Codable {
    let start: WMoment
    let day: String
    let end: WMoment
    let lunarDay: Int
    let phaseName: String
    let phase: Double
}

struct WDay: Codable {
    let date: String
    let sunrise: WMoment
    let noon: WMoment
    let sunset: WMoment
    let aruna: WMoment?
    let parts: [[String]]
    // kala starts at aruna (the dawn glow), or at sunrise when the data has no aruna
    var kalaStart: Date { (aruna ?? sunrise).date }
    var kalaStartHm: String { (aruna ?? sunrise).hm }
}

struct WData: Decodable {
    let generatedAt: String?
    let tz: String?
    var settings: WSettings?
    let today: WToday?
    let uposathas: [WUposatha]
    let days: [WDay]
    let moons: WMoons?

    private enum CodingKeys: String, CodingKey { case generatedAt, tz, settings, today, uposathas, days, moons }

    // One Uposatha the page could not date (a null start / end, a NaN phase) is dropped; it must not blank the whole widget.
    private struct LossyUposatha: Decodable {
        let value: WUposatha?
        init(from decoder: Decoder) throws { value = try? WUposatha(from: decoder) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try? c.decodeIfPresent(String.self, forKey: .generatedAt)
        tz = try? c.decodeIfPresent(String.self, forKey: .tz)
        settings = try? c.decodeIfPresent(WSettings.self, forKey: .settings)
        today = try? c.decodeIfPresent(WToday.self, forKey: .today)
        uposathas = ((try? c.decode([LossyUposatha].self, forKey: .uposathas)) ?? []).compactMap { $0.value }
        days = try c.decode([WDay].self, forKey: .days)
        moons = try? c.decodeIfPresent(WMoons.self, forKey: .moons)
    }
}

// MARK: - Where the data lives

enum WStore {
    static let group = "group.gift.dhamma.uposatha"
    static var defaults: UserDefaults? { UserDefaults(suiteName: group) }

    // What the app wrote (DgWidget.put): nil when nothing is there or it does not parse.
    static func load() -> WData? {
        guard let json = defaults?.string(forKey: "data"), let raw = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WData.self, from: raw)
    }

    // The bundled sample, for the widget gallery and the placeholder: in the device's language.
    static func sample() -> WData? {
        guard let url = Bundle.main.url(forResource: "widget-sample", withExtension: "json"),
              let raw = try? Data(contentsOf: url) else { return nil }
        var data = try? JSONDecoder().decode(WData.self, from: raw)
        data?.settings?.lang = Loc.deviceLang()
        return data
    }

    // The slide shown, per widget SIZE (iOS gives a widget no identity of its own without a configuration, so two widgets of the same size
    // show the same slide). Nothing stored: the medium opens on the Uposatha (0), the large on the calendar (2).
    static func layer(_ key: String) -> Int {
        if let v = defaults?.object(forKey: "layer." + key) as? Int { return v }
        return key == "large" ? 2 : 0
    }
    static func setLayer(_ key: String, _ value: Int) { defaults?.set(value, forKey: "layer." + key) }

    // The month the calendar shows at a moment: 0 = today's, up to 2 ahead (the arrows, key "layer.month"). A choice made on another
    // day of the place is forgotten, as on Android. SwitchLayerIntent stamps the choice ("at.month").
    static func monthOffset(_ data: WData, at t: Date) -> Int {
        let v = defaults?.integer(forKey: "layer.month") ?? 0
        if v <= 0 { return 0 }
        let at = defaults?.double(forKey: "at.month") ?? 0
        if data.localYmd(at: Date(timeIntervalSince1970: at)) != data.localYmd(at: t) { return 0 }
        return min(v, 2)
    }
}

// MARK: - Calendar arithmetic (no time zone database: the data carries its own offset)

enum WTime {
    // Days since 1970-01-01 of a civil date (proleptic Gregorian).
    static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (m + 9) % 12
        let doy = (153 * mp + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    static func civilFromDays(_ z0: Int) -> (y: Int, m: Int, d: Int) {
        let z = z0 + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }

    static func parseYmd(_ s: String) -> (y: Int, m: Int, d: Int)? {
        let p = s.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]), m >= 1, m <= 12, d >= 1, d <= 31 else { return nil }
        return (y, m, d)
    }

    static func ymdString(fromDays z: Int) -> String {
        let c = civilFromDays(z)
        return String(format: "%04d-%02d-%02d", c.y, c.m, c.d)
    }

    static func dayNumber(_ ymd: String) -> Int? {
        guard let c = parseYmd(ymd) else { return nil }
        return daysFromCivil(c.y, c.m, c.d)
    }

    // 0 = Monday ... 6 = Sunday (1970-01-01 was a Thursday)
    static func weekdayIndex(fromDays z: Int) -> Int { (((z + 3) % 7) + 7) % 7 }

    static func minutes(_ hm: String) -> Int? {
        let p = hm.split(separator: ":")
        guard p.count >= 2, let h = Int(p[0]), let m = Int(p[1]), h >= 0, h < 48, m >= 0, m < 60 else { return nil }
        return h * 60 + m
    }

    // The wall-clock date and time read as if they were UTC, in seconds. Minus the real moment it is the place's UTC offset.
    static func localSeconds(_ ymd: String, _ hm: String) -> Double? {
        guard let dn = dayNumber(ymd), let mm = minutes(hm) else { return nil }
        return Double(dn) * 86400 + Double(mm) * 60
    }

    static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

// MARK: - Texts

struct Loc {
    let lang: String

    static func deviceLang() -> String {
        (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("ru") ? "ru" : "en"
    }

    func s(_ key: String, _ vars: [String: String] = [:]) -> String {
        var out = WidgetStrings.text[lang]?[key] ?? WidgetStrings.text["en"]?[key] ?? key
        for (k, v) in vars { out = out.replacingOccurrences(of: "{" + k + "}", with: v) }
        return out
    }

    func list(_ key: String) -> [String] { WidgetStrings.lists[lang]?[key] ?? WidgetStrings.lists["en"]?[key] ?? [] }

    func months(long: Bool) -> [String] {
        (WidgetStrings.text[lang]?[long ? "monthsLong" : "monthsShort"] ?? "").components(separatedBy: "|")
    }

    func weekday(_ ymd: String) -> String {
        guard let dn = WTime.dayNumber(ymd) else { return "" }
        let names = list("weekdays")
        let i = WTime.weekdayIndex(fromDays: dn)
        return i < names.count ? names[i] : ""
    }

    func dayOfMonth(_ ymd: String) -> String {
        guard let c = WTime.parseYmd(ymd) else { return "" }
        return String(c.d)
    }

    func monthShort(_ ymd: String) -> String {
        guard let c = WTime.parseYmd(ymd) else { return "" }
        let names = months(long: false)
        return c.m - 1 < names.count ? names[c.m - 1] : ""
    }

    // "сб 10"
    func dayShort(_ ymd: String) -> String { weekday(ymd) + " " + dayOfMonth(ymd) }

    // "вс 11 окт"
    func dateShort(_ ymd: String) -> String { dayShort(ymd) + " " + monthShort(ymd) }

    func monthTitle(_ month: Int) -> String {
        let names = months(long: true)
        return month - 1 >= 0 && month - 1 < names.count ? names[month - 1] : ""
    }

    // One of the eight names of the moon's phase (WPlan.phaseIndex)
    func phaseName(_ index: Int) -> String { s("w.ph" + String(index)) }

    // "Saturday" / "Суббота"
    func weekdayLong(_ ymd: String) -> String {
        guard let dn = WTime.dayNumber(ymd) else { return "" }
        let names = list("w.weekdaysLong")
        let i = WTime.weekdayIndex(fromDays: dn)
        return i < names.count ? names[i] : ""
    }

    // "October" / "октября" (after a day number)
    func monthOf(_ ymd: String) -> String {
        guard let c = WTime.parseYmd(ymd) else { return "" }
        let names = list("w.monthsOf")
        return c.m - 1 < names.count ? names[c.m - 1] : ""
    }

    // Time left as "1 h 34 min" / "34 min": rounded up, so "0 min" is never shown while time is left.
    func left(_ seconds: TimeInterval) -> String {
        let total = max(0, seconds)
        var mins = Int((total / 60).rounded(.up))
        if mins < 1 && total > 0 { mins = 1 }
        let h = mins / 60
        let m = mins % 60
        let unit: String = " " + s("unit.min")
        if h == 0 { return String(m) + unit }
        let mm: String = m < 10 ? "0" + String(m) : String(m)
        let hours: String = String(h) + " " + s("unit.h")
        return hours + " " + mm + unit
    }

    // "in 8 d" for a later Uposatha; under a day "in 2 h"
    func inText(_ seconds: TimeInterval) -> String {
        let rem = max(0, seconds)
        let days = Int(rem / 86400)
        if days >= 1 { return s("inDays", ["n": String(days)]) }
        let head = s("inDays").components(separatedBy: "{n}").first ?? ""
        return head + String(Int(rem / 3600)) + " " + s("unit.h")
    }

    // A part's name split into the title and the rest: "Majjhanhika · midday" -> ("Majjhanhika", "midday")
    func partName(_ key: String) -> (String, String) {
        let full = s("part." + key)
        let bits = full.components(separatedBy: " · ")
        return (bits.first ?? full, bits.count > 1 ? bits[1] : "")
    }
}

// MARK: - What the data says at a moment

struct WKala {
    let isKala: Bool
    let until: Date
    let untilHm: String
    let from: Date
}

struct WPart {
    let key: String
    let from: Date
    let to: Date
    let fromHm: String
    let toHm: String
    let isDay: Bool
}

// One day-and-night: from sunrise to the next sunrise, in six parts.
struct WCycle {
    let day: WDay
    let next: WDay
    let parts: [WPart]
    var start: Date { parts.first?.from ?? day.sunrise.date }
    var end: Date { parts.last?.to ?? next.sunrise.date }

    // The index of the part that is on (the last one that has begun)
    func currentIndex(at t: Date) -> Int {
        var idx = 0
        for (i, p) in parts.enumerated() where p.from <= t { idx = i }
        return idx
    }

    func fraction(_ t: Date) -> Double {
        let a = start.timeIntervalSince1970, b = end.timeIntervalSince1970
        guard b > a else { return 0 }
        return min(1, max(0, (t.timeIntervalSince1970 - a) / (b - a)))
    }
}

extension WUposatha {
    // The moon of a LIST row or a calendar cell: the plain phase of that day (new, 50 %, full; the 14th a crescent or a gibbous),
    // not the exact fraction. Same rule as Android's WidgetModel.Upo.nominal().
    var nominal: Double {
        let wax = phase > 0 && phase < 0.5
        if lunarDay == 8 {
            if phaseName == "firstQuarter" { return 0.25 }
            if phaseName == "lastQuarter" { return 0.75 }
            return wax ? 0.25 : 0.75
        }
        if lunarDay == 14 { return wax ? 0.375 : 0.875 }
        if lunarDay == 15 {
            if phaseName == "full" { return 0.5 }
            if phaseName == "new" { return 0 }
            return wax ? 0.5 : 0
        }
        return phase
    }
}

struct WCell {
    let ymd: String
    let day: Int
    let inMonth: Bool
}

extension WData {
    var sortedUposathas: [WUposatha] { uposathas.sorted { $0.start.ms < $1.start.ms } }

    var lang: String {
        let l = (settings?.lang ?? "").lowercased()
        if l.hasPrefix("ru") { return "ru" }
        if l.hasPrefix("en") { return "en" }
        return Loc.deviceLang()
    }

    var showKala: Bool { settings?.showKala ?? true }
    var detail: Bool { settings?.detail ?? false }
    var allMoons: Bool { settings?.allMoons ?? false }
    var south: Bool { settings?.south ?? false }

    // The week's first day: the app's own setting; absent -> Monday for Russian, Sunday for English.
    var weekStart: Int { settings?.weekStart ?? (lang == "ru" ? 1 : 0) }
    // columns to shift a Monday-first weekday index by (Sunday-first: Sunday is column 0)
    var weekShift: Int { weekStart == 0 ? 1 : 0 }

    func weekColumn(ofDays z: Int) -> Int { (WTime.weekdayIndex(fromDays: z) + weekShift) % 7 }

    // The weekday names for the header, in the order of the columns.
    func weekdayNames(_ loc: Loc) -> [String] {
        let names = loc.list("weekdays")
        guard names.count == 7, weekShift == 1 else { return names }
        return [names[6]] + Array(names[0..<6])
    }

    // Whether the data can say what is true at `t`: not older than 30 days (the page gives 31 days of sun), and `t` falls inside the days it covers.
    // Outside that the widget shows "Open Uposatha" and no times: it never shows a wrong one.
    func isUsable(at t: Date) -> Bool {
        guard days.count >= 2, let first = days.first, let last = days.last else { return false }
        if let g = generatedAt.flatMap({ WTime.parseISO($0) }), t.timeIntervalSince(g) > 30 * 86400 { return false }
        // The page followed the phone's zone and the phone is in another one now (a flight): the dawn and "today" are the old place's.
        if settings?.tzAuto == true, let z = tz.flatMap({ TimeZone(identifier: $0) }), z.secondsFromGMT(for: t) != TimeZone.current.secondsFromGMT(for: t) { return false }
        return t >= first.sunrise.date && t < last.kalaStart
    }

    var coverageEnd: Date? { days.last?.kalaStart }

    // The place's UTC offset around a moment, from the data itself (rounded to a quarter of an hour).
    func offset(of m: WMoment) -> Double {
        guard let l = WTime.localSeconds(m.ymd, m.hm) else { return 0 }
        return ((m.ms / 1000 - l) / 900).rounded() * 900
    }

    // The place's wall clock at a moment, read as if it were UTC, in seconds
    func localSeconds(at t: Date) -> Double {
        var anchor = days.first?.sunrise
        for d in days where d.sunrise.date <= t { anchor = d.sunrise }
        let off = anchor.map { offset(of: $0) } ?? 0
        return t.timeIntervalSince1970 + off
    }

    func localYmd(at t: Date) -> String {
        WTime.ymdString(fromDays: Int((localSeconds(at: t) / 86400).rounded(.down)))
    }

    // The Uposatha whose own day is the given date
    func uposathaOn(_ ymd: String) -> WUposatha? { uposathas.first(where: { $0.day == ymd }) }

    // The Uposatha that begins on the evening of the given date, the day before its own day (by the suttas)
    func startingOn(_ ymd: String) -> WUposatha? { uposathas.first(where: { $0.start.ymd == ymd && $0.start.ymd != $0.day }) }

    // Kala runs from aruna to noon of a day, vikala from noon to the next day's aruna.
    func kala(at t: Date) -> WKala? {
        var idx = -1
        for (i, d) in days.enumerated() where d.kalaStart <= t { idx = i }
        guard idx >= 0 else { return nil }
        let d = days[idx]
        if t < d.noon.date {
            return WKala(isKala: true, until: d.noon.date, untilHm: d.noon.hm, from: d.kalaStart)
        }
        guard idx + 1 < days.count else { return nil }
        let n = days[idx + 1]
        return WKala(isKala: false, until: n.kalaStart, untilHm: n.kalaStartHm, from: d.noon.date)
    }

    func cycle(at t: Date) -> WCycle? {
        var idx = -1
        for (i, d) in days.enumerated() where d.sunrise.date <= t { idx = i }
        guard idx >= 0, idx + 1 < days.count else { return nil }
        let d = days[idx]
        guard let base = WTime.localSeconds(d.sunrise.ymd, "00:00"), d.parts.count == 6 else { return nil }
        let off = offset(of: d.sunrise)
        var parts: [WPart] = []
        var cursor: Double = 0
        for (i, p) in d.parts.enumerated() {
            guard p.count >= 3, let a = WTime.minutes(p[1]), let b = WTime.minutes(p[2]) else { return nil }
            if i == 0 { cursor = base + Double(a) * 60 - off }
            var dur = (b - a) % 1440
            if dur <= 0 { dur += 1440 }
            let from = cursor
            cursor += Double(dur) * 60
            parts.append(WPart(key: p[0],
                               from: Date(timeIntervalSince1970: from),
                               to: Date(timeIntervalSince1970: cursor),
                               fromHm: p[1], toHm: p[2], isDay: i < 3))
        }
        return WCycle(day: d, next: days[idx + 1], parts: parts)
    }

    // The current Uposatha is chosen by TIME (the list starts on the 1st of the month, so never by index): the first whose end is
    // still ahead. It is on when it has begun.
    func current(at t: Date) -> WUposatha? { sortedUposathas.first(where: { $0.end.date > t }) }

    // What the big counter counts to: the end of the Uposatha that is on, else the start of the next one.
    func counterTarget(at t: Date) -> Date? {
        guard let c = current(at: t) else { return nil }
        return c.start.date <= t ? c.end.date : c.start.date
    }

    // The days of a calendar, Monday first: `rows` weeks starting at day number `first` (a Monday).
    func cells(from first: Int, rows: Int, month: Int?) -> [[WCell]] {
        var out: [[WCell]] = []
        for r in 0..<rows {
            var row: [WCell] = []
            for c in 0..<7 {
                let dn = first + r * 7 + c
                let civil = WTime.civilFromDays(dn)
                row.append(WCell(ymd: WTime.ymdString(fromDays: dn), day: civil.d, inMonth: month == nil || civil.m == month))
            }
            out.append(row)
        }
        return out
    }

    // The moments the widget has to change at, within `hours` from `now`, for the timeline.
    func timelineDates(from now: Date, hours: Double = 24) -> [Date] {
        let horizon = now.addingTimeInterval(hours * 3600)
        var stamps: [Double] = [now.timeIntervalSince1970]
        func add(_ d: Date) {
            if d > now && d <= horizon { stamps.append(d.timeIntervalSince1970) }
        }
        for d in days {
            add(d.sunrise.date); add(d.noon.date); add(d.sunset.date); add(d.kalaStart)
        }
        for d in days where d.sunrise.date >= now.addingTimeInterval(-2 * 86400) && d.sunrise.date <= horizon {
            if let c = cycle(at: d.sunrise.date) {
                for p in c.parts { add(p.from); add(p.to) }
            }
        }
        for u in uposathas { add(u.start.date); add(u.end.date) }
        if let end = coverageEnd { add(end) }
        // a mark every quarter of an hour (as on Android): the "now" tick of the day bar and "N min left" move with it
        var g = (floor(now.timeIntervalSince1970 / 900) + 1) * 900
        while g <= horizon.timeIntervalSince1970 { stamps.append(g); g += 900 }
        // the counter ("1 д 7 ч") changes on the hour counted back from the moment it counts to
        var cursor = now
        for _ in 0..<4 {
            guard let target = counterTarget(at: cursor) else { break }
            let toGo = target.timeIntervalSince(cursor)
            var k = Int(toGo / 3600)
            while k >= 1 {
                let p = target.addingTimeInterval(-Double(k) * 3600)
                if p > horizon { break }
                if p > cursor { stamps.append(p.timeIntervalSince1970) }
                k -= 1
            }
            if target > horizon { break }
            cursor = target.addingTimeInterval(1)
        }
        stamps.sort()
        var out: [Date] = []
        var lastStamp = -1.0e18
        for s in stamps {
            if s - lastStamp >= 60 || out.isEmpty {
                out.append(Date(timeIntervalSince1970: s))
                lastStamp = s
            }
        }
        return Array(out.prefix(160))
    }
}

// MARK: - A moment's view of the data (what the designs print)

struct WSnap {
    let data: WData
    let t: Date
    let loc: Loc
    let upo: WUposatha?          // the Uposatha that is on, else the next one
    let active: Bool
    let target: Date?            // what the counter counts to
    let kala: WKala?
    let cycle: WCycle?
    let today: String            // the place's date now, YYYY-MM-DD
    let rest: [WUposatha]        // the ones after `upo`
    let moonNow: Double          // the real phase of the moon now, 0 new .. 0.5 full

    init(data: WData, t: Date) {
        self.data = data
        self.t = t
        self.loc = Loc(lang: data.lang)
        let list = data.sortedUposathas
        let chosen = list.first(where: { $0.end.date > t })
        let on = chosen.map { $0.start.date <= t } ?? false
        self.upo = chosen
        self.active = on
        self.target = chosen.map { on ? $0.end.date : $0.start.date }
        self.kala = data.kala(at: t)
        self.cycle = data.cycle(at: t)
        self.today = data.localYmd(at: t)
        if let c = chosen {
            self.rest = list.filter { $0.start.ms > c.start.ms }
        } else {
            self.rest = []
        }
        // the page's today.moon (at generatedAt) carried on by the clock (a lunation is 29.530588853 days)
        let base = data.today?.moon ?? chosen?.phase ?? 0.5
        var gone = 0.0
        if let g = data.generatedAt.flatMap({ WTime.parseISO($0) }) { gone = t.timeIntervalSince(g) / (29.530588853 * 86400) }
        self.moonNow = WPlan.norm(base + gone)
    }

    var south: Bool { data.south }
    var secondsToTarget: TimeInterval { (target ?? t).timeIntervalSince(t) }

    // The day (dawn glow to the next dawn glow) that contains now: its sunrise, noon and sunset are "the sun of today"
    var dayNow: WDay? {
        var found: WDay? = nil
        for d in data.days where d.kalaStart <= t { found = d }
        return found
    }

    // The moon of a day (its phase at midday): the page's own number when it sent one, else today's moon carried to that date at the
    // mean speed of the moon (a few percent off at most, on a picture of a dozen points).
    func phaseOn(_ ymd: String) -> Double {
        guard let dn = WTime.dayNumber(ymd) else { return moonNow }
        if let m = data.moons, let from = WTime.dayNumber(m.from) {
            let i = dn - from
            if i >= 0 && i < m.phase.count { return m.phase[i] }
        }
        guard let td = WTime.dayNumber(today) else { return moonNow }
        let secs = data.localSeconds(at: t)
        let dayShare = (secs - (secs / 86400).rounded(.down) * 86400) / 86400
        let days = Double(dn - td) + 0.5 - dayShare
        return WPlan.norm(moonNow + days / 29.530588853)
    }
}

// MARK: - The words: one table for every widget and size (keys w.* of strings.json)

extension WSnap {
    // "Sat 17 Oct" / "сб 17 окт"
    func dateLabel(_ ymd: String) -> String { loc.dateShort(ymd) }
    func dayN(_ u: WUposatha) -> String { loc.s("w.dayN", ["n": String(u.lunarDay)]) }
    var stateWord: String { loc.s(active ? "now" : "w.coming") }
    // "15th day · coming" / "15th day · now": the title of every Uposatha widget
    func status(_ u: WUposatha) -> String { dayN(u) + " · " + stateWord }
    // The date the counter runs to: the evening the Uposatha begins on, or, when it is on, the day it ends
    func whenDate(_ u: WUposatha) -> String { dateLabel(active ? u.end.ymd : u.start.ymd) }
    func whenTime(_ u: WUposatha) -> String {
        active ? loc.s("w.until", ["time": u.end.hm]) : loc.s("w.from", ["time": u.start.hm])
    }

    // The lit percent now as the page shows it: between two points of its table, with two decimals (at a new moon it is 0.1, not 0:
    // the moon passes above or below the sun). No table (older data) or past its end: the phase's cosine.
    var litNow: Double {
        if let l = data.moons?.lit, l.step > 0 {
            let x = (t.timeIntervalSince1970 * 1000 - l.from) / l.step
            let i = Int(x.rounded(.down))
            if x >= 0, i + 1 < l.pct.count { return l.pct[i] + (l.pct[i + 1] - l.pct[i]) * (x - Double(i)) }
        }
        return (1 - cos(2 * Double.pi * WPlan.norm(moonNow))) / 2 * 100
    }
    var lit: String {
        let s = String(format: "%.2f", litNow)
        return data.lang == "ru" ? s.replacingOccurrences(of: ".", with: ",") : s
    }
    var phaseWord: String { loc.phaseName(WPlan.phaseIndex(moonNow)) }
    // "waxing crescent · 30%": the moon as it is NOW (not the phase of the Uposatha the counter runs to)
    var moonLine: String { phaseWord + " · " + lit + "%" }
    var litText: String { lit + "%" }
    // The same in the small circle of the lock screen: tenths while they matter (under 10 %), whole percents above
    var litShort: String {
        let s = litNow < 10 ? String(format: "%.1f", litNow) : String(Int(litNow.rounded()))
        return (data.lang == "ru" ? s.replacingOccurrences(of: ".", with: ",") : s) + "%"
    }
    var growing: Bool { moonNow < 0.5 }

    // With details: what comes after: the end of an Uposatha that is coming, or the next one when one is on
    func detailLine(_ u: WUposatha) -> String {
        if !active { return loc.s("w.ends", ["day": dateLabel(u.end.ymd), "time": u.end.hm]) }
        guard let n = rest.first else { return "" }
        let ord = loc.s("w.ord", ["n": String(n.lunarDay)])
        return loc.s("w.next", ["n": ord, "day": dateLabel(n.start.ymd)])
    }

    // The kala line follows the app's setting
    var kalaOn: Bool { kala != nil && data.showKala }
    func kalaWord(_ k: WKala) -> String { loc.s(k.isKala ? "w.kala" : "w.vikala") }
    // "Kala until 12:41" as one plain string (the lock screen)
    func kalaText(_ k: WKala) -> String { kalaWord(k) + loc.s("w.untilMid") + k.untilHm }
    // "1 h 34 min left"
    func kalaLeft(_ k: WKala) -> String { loc.s("kalaLeft", ["left": loc.left(k.until.timeIntervalSince(t))]) }

    // "1d 7h" as one plain string (the lock screen)
    var counterText: String {
        let c = WPlan.counter(secondsToTarget)
        let hours = String(c.h) + loc.s("unit.h")
        return c.d > 0 ? String(c.d) + loc.s("unit.d") + " " + hours : hours
    }

    // "in 8 d" for a later Uposatha
    func inText(_ u: WUposatha) -> String { loc.inText(u.start.date.timeIntervalSince(t)) }
}

// MARK: - The pure decisions behind the designs (a port of Android's WidgetPlan.java)

struct WCalPlan {
    let rows: Int        // rows of the "Next" list, 0..6
    let card: Bool       // the card of today
    let details: Bool    // the card's detail line (lunar day, the sun)
    let moons: Bool      // mini-moons in the grid
}

enum WPlan {
    static func norm(_ f: Double) -> Double {
        let r = f.truncatingRemainder(dividingBy: 1)
        return r < 0 ? r + 1 : r
    }

    // How many times the design (needW x needH base points) fits into the widget (w x h), within lo..hi.
    static func scale(_ w: CGFloat, _ h: CGFloat, _ needW: CGFloat, _ needH: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        let k = min(w / max(1, needW), h / max(1, needH))
        return max(lo, min(hi, k))
    }

    // The gap between the lines of a design: gmin when the widget is exactly as high as the design, more when it is higher than the
    // scaled design (the spare height is shared between the gaps, up to gmax each). needH is the design's height with gaps of gmin.
    static func gap(_ h: CGFloat, _ k: CGFloat, _ needH: CGFloat, _ gaps: Int, _ gmin: CGFloat, _ gmax: CGFloat) -> CGFloat {
        if gaps <= 0 { return gmin }
        let spare = h / k - needH
        return max(gmin, min(gmax, gmin + spare / CGFloat(gaps)))
    }

    // The small Uposatha: 0 = the agreed wide arrangement (1A / 1B), 1 = stacked with the date and time in one line, 2 = in two lines.
    // Not Android's rule to the letter: there 2 follows whenever 1 does not fit at full size, which suits its narrow, tall cells; an
    // iPhone's small widget is square, where 1 mostly fails by HEIGHT and the taller 2 would only be smaller still. So of the two
    // stacked ones the bigger wins.
    static func upoArrangement(_ kWide: CGFloat, _ kStackA: CGFloat, _ kStackB: CGFloat) -> Int {
        if kWide >= 1 { return 0 }
        return (kStackA >= 1 || kStackA >= kStackB) ? 1 : 2
    }

    // The phase as one of eight names: 0 new, 1 waxing crescent, 2 first quarter, 3 waxing gibbous, 4 full, 5 waning gibbous,
    // 6 last quarter, 7 waning crescent.
    static func phaseIndex(_ phase: Double) -> Int {
        let f = norm(phase)
        if f < 0.02 || f > 0.98 { return 0 }
        if f < 0.23 { return 1 }
        if f < 0.27 { return 2 }
        if f < 0.48 { return 3 }
        if f < 0.52 { return 4 }
        if f < 0.73 { return 5 }
        if f < 0.77 { return 6 }
        return 7
    }

    // The lunar day (tithi) of a phase, 1..30: the page's own rule
    static func tithi(_ phase: Double) -> Int {
        min(30, Int((norm(phase) * 30).rounded(.down)) + 1)
    }

    // Percent of the disc that is lit, 0..100
    static func litPercent(_ phase: Double) -> Int {
        Int(((1 - cos(2 * Double.pi * norm(phase))) / 2 * 100).rounded())
    }

    // Whole days and whole hours of a time left; never negative
    static func counter(_ seconds: TimeInterval) -> (d: Int, h: Int) {
        let total = Int(max(0, seconds))
        return (total / 86400, (total % 86400) / 3600)
    }

    // The calendar's fixed parts in base points: the paddings, the month's name, the weekdays
    static let calFixed: CGFloat = 28 + 27 + 16
    static let calRow: CGFloat = 37
    static let calRowMin: CGFloat = 28
    static let calRowMoons: CGFloat = 33
    static let calNextHead: CGFloat = 22
    static let calNextRow: CGFloat = 26

    static func calCardH(_ details: Bool) -> CGFloat { 8 + 18 + 17 + 16 + 16 + (details ? 16 : 0) }

    // What a calendar of the given height (base points) shows under the month's name. The grid comes first (a week is never lower
    // than calRowMin), then the card of today, then the list of the next Uposathas: as many rows as the height has left. Whatever is
    // still spare goes to the grid (taller weeks).
    static func cal(_ hBase: CGFloat, _ weeks: Int, _ details: Bool, _ nextOn: Bool) -> WCalPlan {
        let n = CGFloat(max(1, weeks))
        let avail = hBase - calFixed
        var card = true
        var det = details
        if avail - n * calRow - calCardH(det) < 0 { det = false }
        if avail - n * calRowMin - calCardH(det) < 0 { card = false }
        let cardH: CGFloat = card ? calCardH(det) : 0
        var rows = 0
        let free = avail - n * calRow - cardH
        if nextOn && card && free >= calNextHead + calNextRow {
            rows = min(6, Int(((free - calNextHead) / calNextRow).rounded(.down)))
        }
        let listH: CGFloat = rows > 0 ? calNextHead + CGFloat(rows) * calNextRow : 0
        let rowH = (avail - cardH - listH) / n
        return WCalPlan(rows: rows, card: card, details: det, moons: rowH >= calRowMoons)
    }

    // The lowest calendar that still shows the month (base points): below it the design is scaled down instead.
    static func calMinH(_ weeks: Int) -> CGFloat { calFixed + CGFloat(weeks) * calRowMin }

    // The calendar as the mock-up of the large widget shows it: the weeks high enough for the mini-moons, and the card of today.
    static func calWantH(_ weeks: Int) -> CGFloat { calFixed + CGFloat(weeks) * calRowMoons + calCardH(false) + 1 }

    // The calendar's scale. Android scales by the width alone (its 4x4 cell is tall); an iPhone's large widget is nearly square, and
    // at that scale the height would leave no room for the mini-moons. So where the wanted calendar fits at a readable size
    // (calWantScale and up), that scale is taken; else (the medium widget) the month alone, as big as it fits.
    static let calWantScale: CGFloat = 0.9
    static func calScale(_ w: CGFloat, _ h: CGFloat, _ baseW: CGFloat, _ weeks: Int) -> CGFloat {
        let want = min(w / baseW, h / calWantH(weeks))
        if want >= calWantScale { return min(want, 1.4) }
        return scale(w, h, baseW, calMinH(weeks), 0.55, 1.4)
    }
}
