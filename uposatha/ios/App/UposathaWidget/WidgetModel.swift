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
    let lang: String?
    let bySuttas: Bool?
    let detail: Bool?
    let showKala: Bool?
    let placeSet: Bool?
    let south: Bool?
    let weekStart: Int?      // 0 = the week starts on Sunday, 1 = Monday
}

struct WToday: Codable {
    let ymd: String?
    let moon: Double?
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
    let settings: WSettings?
    let today: WToday?
    let uposathas: [WUposatha]
    let days: [WDay]

    private enum CodingKeys: String, CodingKey { case generatedAt, tz, settings, today, uposathas, days }

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

    // The bundled sample, for the widget gallery and the placeholder.
    static func sample() -> WData? {
        guard let url = Bundle.main.url(forResource: "widget-sample", withExtension: "json"),
              let raw = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WData.self, from: raw)
    }

    // The layer shown, per widget SIZE (iOS gives a widget no identity of its own without a configuration, so two widgets of the same size
    // show the same layer).
    static func layer(_ key: String) -> Int { defaults?.integer(forKey: "layer." + key) ?? 0 }
    static func setLayer(_ key: String, _ value: Int) { defaults?.set(value, forKey: "layer." + key) }
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

    // The counter's pieces: [("1", "д"), ("7", "ч")] — days and hours, no minutes; under an hour "<1 ч".
    func countParts(_ seconds: TimeInterval) -> [(String, String)] {
        let total = Int(max(0, seconds))
        let d = total / 86400
        let h = (total % 86400) / 3600
        let du = s("unit.d"), hu = s("unit.h")
        if d > 0 { return [(String(d), du), (String(h), hu)] }
        if h > 0 { return [(String(h), hu)] }
        return [("<1", hu)]
    }

    func countText(_ seconds: TimeInterval) -> String {
        countParts(seconds).map { $0.0 + " " + $0.1 }.joined(separator: " ")
    }

    // "4 Uposathas", "4 упосатхи"
    func uposathaCount(_ n: Int) -> String {
        let key: String
        if lang == "ru" {
            let last = n % 10, last2 = n % 100
            if last == 1 && last2 != 11 { key = "uposatha.1" }
            else if last >= 2 && last <= 4 && !(last2 >= 12 && last2 <= 14) { key = "uposatha.2" }
            else { key = "uposatha.5" }
        } else {
            key = n == 1 ? "uposatha.1" : "uposatha.2"
        }
        return String(n) + " " + s(key)
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

    func current(at t: Date) -> WPart? {
        guard var cur = parts.first else { return nil }
        for p in parts where p.from <= t { cur = p }
        return cur
    }

    func fraction(_ t: Date) -> Double {
        let a = start.timeIntervalSince1970, b = end.timeIntervalSince1970
        guard b > a else { return 0 }
        return min(1, max(0, (t.timeIntervalSince1970 - a) / (b - a)))
    }

    func fraction(of m: WMoment) -> Double { fraction(m.date) }
}

struct WGridMarks {
    var solid: Set<String> = []
    var light: Set<String> = []
    var joinNext: Set<String> = []   // a solid date whose strip goes on into the next date
    var joinPrev: Set<String> = []   // a light date that continues the strip of the date before it
}

extension WUposatha {
    // The plain phase of this Uposatha's day, for a moon in a list row (full 0.5, new 0, quarters .25 / .75, the 14th a crescent or gibbous)
    var listPhase: Double {
        switch lunarDay {
        case 15:
            if phaseName == "full" { return 0.5 }
            if phaseName == "new" { return 0 }
        case 8:
            if phaseName == "firstQuarter" { return 0.25 }
            if phaseName == "lastQuarter" { return 0.75 }
        case 14:
            return phase > 0 && phase < 0.5 ? 0.375 : 0.875
        default:
            break
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
    var placeSet: Bool { settings?.placeSet ?? true }
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

    // Whether the data can say what is true at `t`: not older than 14 days, and `t` falls inside the days it covers.
    // Outside that the widget shows "Open Uposatha" and no times: it never shows a wrong one.
    func isUsable(at t: Date) -> Bool {
        guard days.count >= 2, let first = days.first, let last = days.last else { return false }
        if let g = generatedAt.flatMap({ WTime.parseISO($0) }), t.timeIntervalSince(g) > 14 * 86400 { return false }
        return t >= first.sunrise.date && t < last.kalaStart
    }

    var coverageEnd: Date? { days.last?.kalaStart }

    // The place's UTC offset around a moment, from the data itself (rounded to a quarter of an hour).
    func offset(of m: WMoment) -> Double {
        guard let l = WTime.localSeconds(m.ymd, m.hm) else { return 0 }
        return ((m.ms / 1000 - l) / 900).rounded() * 900
    }

    func localYmd(at t: Date) -> String {
        var anchor = days.first?.sunrise
        for d in days where d.sunrise.date <= t { anchor = d.sunrise }
        let off = anchor.map { offset(of: $0) } ?? 0
        let secs = t.timeIntervalSince1970 + off
        return WTime.ymdString(fromDays: Int((secs / 86400).rounded(.down)))
    }

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

    // What the big counter counts to: the end of the Uposatha that is on, else the start of the next one.
    func counterTarget(at t: Date) -> Date? {
        let list = sortedUposathas
        if let c = list.first(where: { $0.start.date <= t && t < $0.end.date }) { return c.end.date }
        return list.first(where: { $0.start.date > t })?.start.date
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

    // The month grid's marks (the page's own rule): the evening-start date is solid, `day` a light band joined to it when both sit in one row;
    // on a date that is both (back-to-back 14th and 15th) the solid one wins, and the strip runs through it.
    func gridMarks() -> WGridMarks {
        var marks = WGridMarks()
        for u in uposathas {
            marks.solid.insert(u.start.ymd)
            if u.day != u.start.ymd {
                marks.light.insert(u.day)
                if let a = WTime.dayNumber(u.start.ymd), let b = WTime.dayNumber(u.day), b == a + 1 {
                    marks.joinNext.insert(u.start.ymd)
                    marks.joinPrev.insert(u.day)
                }
            }
        }
        return marks
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
        // a mark every half hour: the "now" tick of the day scale moves with it
        var g = (floor(now.timeIntervalSince1970 / 1800) + 1) * 1800
        while g <= horizon.timeIntervalSince1970 { stamps.append(g); g += 1800 }
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

// MARK: - A moment's view of the data (what the layers print)

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

    init(data: WData, t: Date) {
        self.data = data
        self.t = t
        self.loc = Loc(lang: data.lang)
        let list = data.sortedUposathas
        let on = list.first(where: { $0.start.date <= t && t < $0.end.date })
        let chosen = on ?? list.first(where: { $0.start.date > t })
        self.upo = chosen
        self.active = on != nil
        self.target = chosen.map { on != nil ? $0.end.date : $0.start.date }
        self.kala = data.kala(at: t)
        self.cycle = data.cycle(at: t)
        self.today = data.localYmd(at: t)
        if let c = chosen {
            self.rest = list.filter { $0.start.ms > c.start.ms }
        } else {
            self.rest = []
        }
    }

    var south: Bool { data.south }

    // The real phase of the moon now: the page's today.moon (at generatedAt) carried on by the clock (a lunation is 29.530588853 days).
    var heroPhase: Double {
        let base = data.today?.moon ?? upo?.phase ?? 0.5
        var gone = 0.0
        if let g = data.generatedAt.flatMap({ WTime.parseISO($0) }) { gone = t.timeIntervalSince(g) / (29.530588853 * 86400) }
        var f = (base + gone).truncatingRemainder(dividingBy: 1)
        if f < 0 { f += 1 }
        return f
    }

    var secondsToTarget: TimeInterval { (target ?? t).timeIntervalSince(t) }

    // days from the place's today to a date
    func daysUntil(_ ymd: String) -> Int {
        guard let a = WTime.dayNumber(today), let b = WTime.dayNumber(ymd) else { return 0 }
        return b - a
    }
}
