import SwiftUI
import WidgetKit
import AppIntents

// Home-screen widget (small, medium, large): three layers — Uposatha + kala, Day & night, Month — per the designer's spec
// (uposatha/widget/design/README.md). Layer 1 -> app tab "home", 2 -> "parts", 3 -> "cal".

enum WSize { case small, medium, large }

// The type scale of the spec (section 6), in points.
struct WMetrics {
    let label: CGFloat
    let text: CGFloat
    let to: CGFloat
    let counter: CGFloat
    let unit: CGFloat
    let moon: CGFloat

    static func of(_ size: WSize, kala: Bool) -> WMetrics {
        switch size {
        case .small: return WMetrics(label: 11.5, text: 12.5, to: 12, counter: kala ? 34 : 40, unit: 16, moon: 22)
        case .medium: return WMetrics(label: 11.5, text: 13, to: 13, counter: kala ? 38 : 44, unit: 16, moon: kala ? 66 : 76)
        case .large: return WMetrics(label: 12.5, text: 15, to: 15, counter: kala ? 54 : 58, unit: 16, moon: kala ? 90 : 100)
        }
    }
}

// The app opens through its own URL scheme (Info.plist CFBundleURLTypes; SceneDelegate -> DgShortcutsPlugin.deliver(url:)).
enum WLinks {
    static func open(_ tab: String, day: String? = nil) -> URL {
        var s = "gift.dhamma.uposatha://open?tab=" + tab
        if let d = day { s += "&day=" + d }
        return URL(string: s) ?? URL(fileURLWithPath: "/")
    }

    static func tab(_ layer: Int) -> URL {
        switch layer {
        case 1: return open("parts")
        case 2: return open("cal")
        default: return open("home")
        }
    }
}

// MARK: - Window chrome

struct WidgetChrome: ViewModifier {
    let accessory: Bool

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            // iOS 17 adds its own content margins
            content.containerBackground(for: .widget) { accessory ? Color.clear : Color.dgSurface }
        } else {
            if accessory {
                content
            } else {
                content.padding(14).background(Color.dgSurface)
            }
        }
    }
}

// MARK: - Small pieces

struct Caption: View {
    let text: String
    let size: CGFloat
    var date: String? = nil

    var body: some View {
        let tail: String = date.map { "  ·  " + $0 } ?? ""
        (Text(text.uppercased()).font(dgFont(size, .bold)).foregroundColor(.dgAccentInk).kerning(0.6)
            + Text(tail).font(dgFont(size)).foregroundColor(.dgMuted))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

struct Counter: View {
    let parts: [(String, String)]
    let size: CGFloat
    let unit: CGFloat

    private var text: Text {
        var t = Text("")
        for (i, p) in parts.enumerated() {
            t = t + Text(p.0).font(dgFont(size, .bold)).foregroundColor(.dgText)
            t = t + Text(" " + p.1 + (i < parts.count - 1 ? " " : "")).font(dgFont(unit, .medium)).foregroundColor(.dgMuted)
        }
        return t
    }

    var body: some View {
        text.lineLimit(1).minimumScaleFactor(0.6)
    }
}

// "Kala until 12:41 · 1 h 34 min left" (green) / "Vikala until dawn 07:13" (burgundy). The time left is the system's own
// ticking text: no redraws.
struct KalaRow: View {
    let snap: WSnap
    let size: CGFloat
    var withLeft: Bool = true

    var body: some View {
        if let k = snap.kala {
            line(k).lineLimit(1).minimumScaleFactor(0.75)
        }
    }

    private func line(_ k: WKala) -> Text {
        let l = snap.loc
        let color: Color = k.isKala ? Color.dgAccentInk : Color.dgVikala
        let head = l.s(k.isKala ? "kala" : "vikala", ["time": k.untilHm])
        var t = Text(head).font(dgFont(size, .semibold)).foregroundColor(color)
        if k.isKala && withLeft {
            let bits = l.s("kalaLeft").components(separatedBy: "{left}")
            t = t + Text("  ·  " + (bits.first ?? "")).font(dgFont(size)).foregroundColor(.dgMuted)
            t = t + Text(k.until, style: .relative).font(dgFont(size)).foregroundColor(.dgMuted)
            if bits.count > 1 {
                t = t + Text(bits[1]).font(dgFont(size)).foregroundColor(.dgMuted)
            }
        }
        return t
    }
}

// The layer dots as pictures: the current one long.
struct DotsRow: View {
    let count: Int
    let active: Int
    var vertical: Bool = false
    var mono: Bool = false

    var body: some View {
        if vertical {
            VStack(spacing: 4) {
                ForEach(0..<count, id: \.self) { i in dot(i) }
            }
        } else {
            HStack(spacing: 4) {
                ForEach(0..<count, id: \.self) { i in dot(i) }
            }
        }
    }

    private func dot(_ i: Int) -> some View {
        let on = i == active
        let color: Color = mono ? Color.primary.opacity(on ? 1 : 0.35) : (on ? Color.dgAccentInk : Color.dgBorderStrong)
        return Capsule()
            .fill(color)
            .frame(width: vertical ? 5 : (on ? 14 : 5), height: vertical ? (on ? 14 : 5) : 5)
    }
}

// The dots as a button (iOS 17+): a tap turns to the next layer and does not open the app. Before iOS 17 there is one layer and no dots.
struct DotsStrip: View {
    let key: String
    let count: Int
    let active: Int
    var vertical: Bool = false
    var mono: Bool = false

    var body: some View {
        if #available(iOS 17.0, *) {
            // the tap area is the whole strip (the full width, 32 pt high), not just the dots
            let w: CGFloat = vertical ? 18 : CGFloat.infinity
            let h: CGFloat = vertical ? CGFloat.infinity : 32
            Button(intent: SwitchLayerIntent(family: key, count: count, step: 1)) {
                DotsRow(count: count, active: active, vertical: vertical, mono: mono)
                    .frame(maxWidth: w, maxHeight: h)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// What the widget says when there is nothing true to show: no data, data older than 14 days, or today not covered.
struct OpenAppView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let l = Loc(lang: Loc.deviceLang())
        if WidgetFamilies.isSystem(family) {
            VStack(spacing: 8) {
                MoonView(phase: 0.5, size: 34)
                Text(l.s("openApp")).font(dgFont(13, .semibold)).foregroundColor(.dgText).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetURL(WLinks.open("home"))
        } else {
            Text(l.s("openApp")).font(dgFont(12, .semibold)).widgetURL(WLinks.open("home"))
        }
    }
}

// MARK: - Layer 1: Uposatha + kala

struct UposathaLayer: View {
    let snap: WSnap
    let size: WSize

    var body: some View {
        if let u = snap.upo {
            content(u)
        } else {
            OpenAppView()
        }
    }

    @ViewBuilder
    private func content(_ u: WUposatha) -> some View {
        let l = snap.loc
        let m = WMetrics.of(size, kala: snap.data.showKala)
        VStack(alignment: .leading, spacing: 10) {
            if size == .large {
                HStack {
                    Caption(text: l.s(snap.active ? "layer.uposathaNow" : "layer.uposatha"), size: m.label, date: l.dateShort(u.start.ymd))
                    Spacer(minLength: 8)
                    Text(l.s((snap.data.settings?.bySuttas ?? true) ? "mode.bySuttas" : "mode.notBySuttas"))
                        .font(dgFont(m.label)).foregroundColor(.dgMuted)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                if size != .small {
                    MoonView(phase: snap.heroPhase, size: m.moon, south: snap.south)
                }
                UpoTexts(snap: snap, u: u, size: size)
                if size == .small {
                    Spacer(minLength: 0)
                    MoonView(phase: snap.heroPhase, size: m.moon, south: snap.south)
                }
            }
            if size == .large {
                UpoNext(snap: snap)
            }
        }
    }
}

struct UpoTexts: View {
    let snap: WSnap
    let u: WUposatha
    let size: WSize

    private var detailLines: [String] {
        let l = snap.loc
        let v: [String: String] = [
            "phase": l.s("phase." + u.phaseName),
            "n": String(u.lunarDay),
            "startDay": l.dayShort(u.start.ymd),
            "startTime": u.start.hm,
            "endDay": l.dayShort(u.end.ymd),
            "endTime": u.end.hm
        ]
        var out: [String] = []
        if snap.data.detail {
            out.append(l.s("detail.phase", v))
            if size != .small { out.append(l.s(snap.active ? "detail.endNow" : "detail.span", v)) }
        } else {
            out.append(l.s(snap.active ? "lite.until" : "lite.from", v))
        }
        return out
    }

    var body: some View {
        let l = snap.loc
        let m = WMetrics.of(size, kala: snap.data.showKala)
        VStack(alignment: .leading, spacing: 2) {
            if size != .large {
                Caption(text: l.s(snap.active ? "layer.uposathaNow" : "layer.uposatha"),
                        size: m.label,
                        date: size == .small ? nil : l.dateShort(u.start.ymd))
            }
            Text(l.s(snap.active ? "toNow" : "to", ["n": String(u.lunarDay)]))
                .font(dgFont(m.to, .medium)).foregroundColor(.dgText).lineLimit(1).minimumScaleFactor(0.8)
            Counter(parts: l.countParts(snap.secondsToTarget), size: m.counter, unit: m.unit)
            ForEach(detailLines, id: \.self) { line in
                Text(line).font(dgFont(m.text)).foregroundColor(.dgMuted).lineLimit(1).minimumScaleFactor(0.8)
            }
            statusRow(m)
        }
    }

    // The kala row, or — with no place set — the note that the times are assumed (the app's #noonseg[data-fixed] case)
    @ViewBuilder
    private func statusRow(_ m: WMetrics) -> some View {
        if !snap.data.placeSet {
            Text(snap.loc.s(size == .small ? "noPlace.short" : "noPlace.assumed"))
                .font(dgFont(m.text)).foregroundColor(.dgMuted).lineLimit(1).minimumScaleFactor(0.8)
        } else if snap.data.showKala {
            KalaRow(snap: snap, size: m.text, withLeft: size != .small)
        }
    }
}

// "Next": the three Uposathas after this one (large)
struct UpoNext: View {
    let snap: WSnap

    var body: some View {
        let l = snap.loc
        let rows = Array(snap.rest.prefix(3))
        VStack(alignment: .leading, spacing: 7) {
            Text(l.s("next").uppercased()).font(dgFont(11.5, .bold)).foregroundColor(.dgMuted).kerning(0.6)
            ForEach(0..<rows.count, id: \.self) { i in
                HStack(spacing: 8) {
                    MoonView(phase: rows[i].listPhase, size: 18, south: snap.south)
                    Text(l.dateShort(rows[i].start.ymd)).font(dgFont(14, .semibold)).foregroundColor(.dgText)
                    Text(l.s("dayN", ["n": String(rows[i].lunarDay)])).font(dgFont(13)).foregroundColor(.dgMuted)
                    Spacer(minLength: 0)
                    Text(l.s("inDays", ["n": String(snap.daysUntil(rows[i].start.ymd))])).font(dgFont(13)).foregroundColor(.dgMuted)
                }
            }
        }
    }
}

// MARK: - Layer 2: Day & night

struct DayNightLayer: View {
    let snap: WSnap
    let size: WSize

    var body: some View {
        if let c = snap.cycle, let part = c.current(at: snap.t) {
            content(c, part)
        } else {
            OpenAppView()
        }
    }

    @ViewBuilder
    private func content(_ c: WCycle, _ part: WPart) -> some View {
        let l = snap.loc
        let names = l.partName(part.key)
        let until = l.s("until", ["time": part.toHm])
        let sub = names.1.isEmpty ? until : names.1 + " · " + until
        let titleSize: CGFloat = size == .small ? 17 : (size == .medium ? 22 : 26)
        let textSize: CGFloat = size == .large ? 14 : (size == .medium ? 13 : 12.5)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Caption(text: l.s("layer.daynight"), size: size == .large ? 12.5 : 11.5)
                Spacer(minLength: 8)
                if size != .small {
                    Text(size == .large ? l.dateShort(snap.today) : l.s("now"))
                        .font(dgFont(11.5)).foregroundColor(.dgMuted)
                }
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(names.0).font(dgFont(titleSize, .semibold)).foregroundColor(.dgText).lineLimit(1).minimumScaleFactor(0.7)
                    Text(sub).font(dgFont(textSize)).foregroundColor(.dgMuted).lineLimit(1).minimumScaleFactor(0.8)
                }
                if size != .small {
                    Spacer(minLength: 8)
                    kalaColumn(textSize)
                }
            }
            if size == .small {
                KalaRow(snap: snap, size: 12, withLeft: false)
            }
            Spacer(minLength: 4)
            DayBar(cycle: c, t: snap.t, height: size == .large ? 12 : 10)
            DayLabels(cycle: c, loc: l, full: size != .small)
            if size == .large {
                PartsList(cycle: c, current: part, loc: l).padding(.top, 8)
            }
        }
    }

    // Here kala/vikala always show, whatever the main layer's setting is: it is part of the day.
    @ViewBuilder
    private func kalaColumn(_ textSize: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            KalaRow(snap: snap, size: textSize, withLeft: false)
            if let k = snap.kala, k.isKala {
                let bits = snap.loc.s("kalaLeft").components(separatedBy: "{left}")
                (Text(bits.first ?? "") + Text(k.until, style: .relative) + Text(bits.count > 1 ? bits[1] : ""))
                    .font(dgFont(textSize - 1)).foregroundColor(.dgMuted).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }
}

// The scale of the day-and-night: three parts of the day (accent 28 %), three of the night (navy 30 %), the current one solid,
// a 2 pt "now" tick.
struct DayBar: View {
    let cycle: WCycle
    let t: Date
    let height: CGFloat

    var body: some View {
        let total = max(1, cycle.end.timeIntervalSince(cycle.start))
        let currentKey = cycle.current(at: t)?.key
        let now = cycle.fraction(t)
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                ForEach(0..<cycle.parts.count, id: \.self) { i in
                    segment(cycle.parts[i], total: total, width: w, isCurrent: cycle.parts[i].key == currentKey)
                }
                Rectangle()
                    .fill(Color.dgText)
                    .frame(width: 2, height: height + 6)
                    .offset(x: CGFloat(now) * w - 1)
            }
        }
        .frame(height: height + 6)
    }

    private func segment(_ p: WPart, total: Double, width: CGFloat, isCurrent: Bool) -> some View {
        let x0 = CGFloat(p.from.timeIntervalSince(cycle.start) / total) * width
        let x1 = CGFloat(p.to.timeIntervalSince(cycle.start) / total) * width
        let fill: Color = isCurrent ? Color.dgAccent : (p.isDay ? Color.dgAccent.opacity(0.28) : Color.dgNavyInk.opacity(0.30))
        return RoundedRectangle(cornerRadius: 2)
            .fill(fill)
            .frame(width: max(1, x1 - x0 - 2), height: height)
            .offset(x: x0)
    }
}

// Under the scale: dawn, noon, sunset and the next dawn, each at its place.
struct DayLabels: View {
    let cycle: WCycle
    let loc: Loc
    let full: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let lw: CGFloat = full ? 96 : 52
            ZStack(alignment: .topLeading) {
                label(cycle.day.sunrise.hm, full ? loc.s("sunrise") : nil, width: lw, align: .leading, x: 0)
                if full {
                    label(cycle.day.noon.hm, loc.s("noon"), width: lw, align: .center, x: centered(cycle.fraction(of: cycle.day.noon), w, lw))
                    label(cycle.day.sunset.hm, loc.s("sunset"), width: lw, align: .center, x: centered(cycle.fraction(of: cycle.day.sunset), w, lw))
                }
                label(cycle.parts.last?.toHm ?? cycle.next.sunrise.hm, nil, width: lw, align: .trailing, x: w - lw)
            }
        }
        .frame(height: 16)
    }

    private func centered(_ fraction: Double, _ w: CGFloat, _ lw: CGFloat) -> CGFloat {
        min(max(CGFloat(fraction) * w - lw / 2, 0), max(0, w - lw))
    }

    private func label(_ hm: String, _ name: String?, width: CGFloat, align: Alignment, x: CGFloat) -> some View {
        let text: String = name.map { hm + " " + $0 } ?? hm
        return Text(text)
            .font(dgFont(11.5))
            .foregroundColor(.dgMuted)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: width, alignment: align)
            .offset(x: x)
    }
}

// The six parts with their borders (large); the current one on a plate
struct PartsList: View {
    let cycle: WCycle
    let current: WPart
    let loc: Loc

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<cycle.parts.count, id: \.self) { i in
                row(cycle.parts[i])
            }
        }
    }

    private func row(_ p: WPart) -> some View {
        let isCurrent = p.key == current.key
        return HStack {
            Text(loc.s("part." + p.key)).font(dgFont(14, isCurrent ? .semibold : .regular)).foregroundColor(.dgText).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            Text(p.fromHm + "–" + p.toHm).font(dgFont(14, isCurrent ? .semibold : .regular)).foregroundColor(.dgText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(isCurrent ? Color.dgNavyInk.opacity(0.22) : Color.clear))
    }
}

// MARK: - Layer 3: Month

struct MonthLayer: View {
    let snap: WSnap
    let size: WSize

    private var ymdParts: (y: Int, m: Int, d: Int) { WTime.parseYmd(snap.today) ?? (y: 2026, m: 1, d: 1) }

    // the Uposathas not over yet, nearest first
    private var upcoming: [WUposatha] { snap.data.sortedUposathas.filter { $0.end.date > snap.t } }

    var body: some View {
        switch size {
        case .small: small
        case .medium: medium
        case .large: large
        }
    }

    private var monthRows: [[WCell]] {
        let p = ymdParts
        let first = WTime.daysFromCivil(p.y, p.m, 1)
        let lead = snap.data.weekColumn(ofDays: first)
        let next = p.m == 12 ? WTime.daysFromCivil(p.y + 1, 1, 1) : WTime.daysFromCivil(p.y, p.m + 1, 1)
        let rows = (lead + (next - first) + 6) / 7
        return snap.data.cells(from: first - lead, rows: rows, month: p.m)
    }

    private var small: some View {
        let l = snap.loc
        let p = ymdParts
        let todayNumber = WTime.daysFromCivil(p.y, p.m, p.d)
        let monday = todayNumber - snap.data.weekColumn(ofDays: todayNumber)   // the first day of this week
        return VStack(alignment: .leading, spacing: 6) {
            Caption(text: l.monthTitle(p.m), size: 11.5)
            MonthGrid(snap: snap, rows: snap.data.cells(from: monday, rows: 2, month: nil), cellHeight: 17, font: 12, linked: false)
            if let u = upcoming.first {
                Text(l.dayShort(u.start.ymd) + " · " + l.s("dayN", ["n": String(u.lunarDay)]))
                    .font(dgFont(12, .semibold)).foregroundColor(.dgText).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    private var medium: some View {
        let l = snap.loc
        let p = ymdParts
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Caption(text: l.monthTitle(p.m), size: 11.5)
                ForEach(0..<min(3, upcoming.count), id: \.self) { i in
                    HStack(spacing: 6) {
                        MoonView(phase: upcoming[i].listPhase, size: 16, south: snap.south)
                        Text(l.dayShort(upcoming[i].start.ymd)).font(dgFont(13, .semibold)).foregroundColor(.dgText)
                        Text(l.s("dayN", ["n": String(upcoming[i].lunarDay)])).font(dgFont(12)).foregroundColor(.dgMuted).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
            .frame(width: 128, alignment: .leading)
            MonthGrid(snap: snap, rows: monthRows, cellHeight: 13, font: 11, linked: true)
        }
    }

    private var large: some View {
        let l = snap.loc
        let p = ymdParts
        let prefix = String(format: "%04d-%02d", p.y, p.m)
        let inMonth = snap.data.uposathas.filter { $0.start.ymd.hasPrefix(prefix) }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Caption(text: l.monthTitle(p.m) + " " + String(p.y), size: 12.5)
                Spacer(minLength: 8)
                Text(l.uposathaCount(inMonth)).font(dgFont(12.5)).foregroundColor(.dgMuted)
            }
            MonthGrid(snap: snap, rows: monthRows, cellHeight: 34, font: 15, linked: true)
            if let u = upcoming.first {
                HStack(spacing: 8) {
                    MoonView(phase: u.listPhase, size: 22, south: snap.south)
                    Text(l.dateShort(u.start.ymd)).font(dgFont(15, .semibold)).foregroundColor(.dgText)
                    Text(l.s("dayN", ["n": String(u.lunarDay)]) + " · " + l.s("phase." + u.phaseName))
                        .font(dgFont(14)).foregroundColor(.dgMuted).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Text(l.countText(max(0, u.start.date.timeIntervalSince(snap.t)))).font(dgFont(14)).foregroundColor(.dgMuted)
                }
            }
        }
    }
}

// A grid cell: rounded, except where it joins the next / previous cell into one strip.
struct StripShape: Shape {
    var joinLeft: Bool
    var joinRight: Bool

    func path(in rect: CGRect) -> Path {
        var corners: UIRectCorner = []
        if !joinLeft { corners.formUnion([.topLeft, .bottomLeft]) }
        if !joinRight { corners.formUnion([.topRight, .bottomRight]) }
        let bezier = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: 5, height: 5))
        return Path(bezier.cgPath)
    }
}

// The month as in the app (.grid .c): the evening an Uposatha begins solid, its day a light band joined to it in one strip (it breaks at the
// row's last column), today outlined, past days muted. The week starts as the app's setting says. In the medium and large widget every
// number is a link to the calendar on that day.
struct MonthGrid: View {
    let snap: WSnap
    let rows: [[WCell]]
    let cellHeight: CGFloat
    let font: CGFloat
    let linked: Bool

    var body: some View {
        let marks = snap.data.gridMarks()
        let names = snap.data.weekdayNames(snap.loc)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<names.count, id: \.self) { i in
                    Text(names[i]).font(dgFont(10.5, .medium)).foregroundColor(.dgMuted).frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<rows.count, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<rows[r].count, id: \.self) { c in
                        cell(rows[r][c], column: c, marks: marks)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ item: WCell, column: Int, marks: WGridMarks) -> some View {
        if linked && item.inMonth {
            Link(destination: WLinks.open("cal", day: item.ymd)) { face(item, column: column, marks: marks) }
        } else {
            face(item, column: column, marks: marks)
        }
    }

    private func face(_ item: WCell, column: Int, marks: WGridMarks) -> some View {
        let solid = item.inMonth && marks.solid.contains(item.ymd)
        let light = item.inMonth && !solid && marks.light.contains(item.ymd)
        let isToday = item.ymd == snap.today
        let past = snap.daysUntil(item.ymd) < 0
        // a strip goes on into the neighbour only inside one row
        let joinRight = item.inMonth && marks.joinNext.contains(item.ymd) && column < 6
        let joinLeft = item.inMonth && marks.joinPrev.contains(item.ymd) && column > 0
        let fill: Color = solid ? Color.dgAccent : (light ? Color.dgAccent.opacity(0.30) : Color.clear)
        let ink: Color = solid ? Color.white : (light ? Color.dgAccentInk : (past ? Color.dgMuted : Color.dgText))
        let weight: Font.Weight = (solid || light) ? .semibold : .regular
        return ZStack {
            StripShape(joinLeft: joinLeft, joinRight: joinRight)
                .fill(fill)
                .padding(.leading, joinLeft ? 0 : 1)
                .padding(.trailing, joinRight ? 0 : 1)
                .padding(.vertical, 1)
            if isToday && item.inMonth {
                RoundedRectangle(cornerRadius: 5).stroke(Color.dgText, lineWidth: 1.5)
                    .padding(.horizontal, 1)
                    .padding(.vertical, 1)
            }
            Text(item.inMonth ? String(item.day) : "").font(dgFont(font, weight)).foregroundColor(ink)
        }
        .frame(maxWidth: .infinity)
        .frame(height: cellHeight)
    }
}

// MARK: - The home-screen widget: one layer and its dots

struct SystemWidgetView: View {
    let snap: WSnap
    let size: WSize
    let layer: Int
    let key: String

    // Room kept under the layer for the switch (iOS 17+). The switch's tap strip is 44 pt; on the text layers it may reach over the
    // bottom of the content (a tap there only turns the layer), on the month and the large widget the content stays clear of it.
    private var reserve: CGFloat {
        if #available(iOS 17.0, *) {
            return (layer == 2 || size == .large) ? 44 : 26
        }
        return 0
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            layerView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.bottom, reserve)
            LayerSwitch(key: key, count: 3, active: layer)
        }
        .widgetURL(WLinks.tab(layer))
    }

    @ViewBuilder
    private var layerView: some View {
        switch layer {
        case 1: DayNightLayer(snap: snap, size: size)
        case 2: MonthLayer(snap: snap, size: size)
        default: UposathaLayer(snap: snap, size: size)
        }
    }
}

// The layer switch: three wide segments between two chevrons. The whole strip (at least 44 pt high) is two buttons: the left half goes
// to the previous layer, the right half to the next (iOS 17+ App Intents). Before iOS 17 there is one layer and no switch.
struct LayerSwitch: View {
    let key: String
    let count: Int
    let active: Int

    var body: some View {
        if #available(iOS 17.0, *) {
            ZStack {
                HStack(spacing: 0) {
                    stepButton(-1)
                    stepButton(1)
                }
                picture.allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
    }

    @available(iOS 17.0, *)
    private func stepButton(_ step: Int) -> some View {
        Button(intent: SwitchLayerIntent(family: key, count: count, step: step)) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var picture: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left").font(dgFont(11, .semibold)).foregroundColor(.dgMuted)
            HStack(spacing: 6) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(i == active ? Color.dgAccent : Color.dgBorderStrong)
                        .frame(width: 22, height: 6)
                }
            }
            Image(systemName: "chevron.right").font(dgFont(11, .semibold)).foregroundColor(.dgMuted)
        }
    }
}

// MARK: - The entry view

struct UposathaWidgetView: View {
    let entry: UposathaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content.modifier(WidgetChrome(accessory: !WidgetFamilies.isSystem(family)))
    }

    @ViewBuilder
    private var content: some View {
        if let data = entry.data, data.isUsable(at: entry.date) {
            routed(WSnap(data: data, t: entry.date))
        } else {
            OpenAppView()
        }
    }

    @ViewBuilder
    private func routed(_ snap: WSnap) -> some View {
        let key = WidgetFamilies.key(family)
        switch family {
        case .systemSmall:
            SystemWidgetView(snap: snap, size: .small, layer: entry.layer, key: key)
        case .systemMedium:
            SystemWidgetView(snap: snap, size: .medium, layer: entry.layer, key: key)
        case .systemLarge:
            SystemWidgetView(snap: snap, size: .large, layer: entry.layer, key: key)
        default:
            if #available(iOS 16.0, *) {
                LockScreenView(snap: snap, layer: entry.layer, key: key)
            } else {
                OpenAppView()
            }
        }
    }
}
