import SwiftUI
import WidgetKit
import AppIntents

// The home-screen widgets: a port of Android's WidgetViews.java (the redesign of 2026-10-10).
//
// A design is written in "base points": the sizes of its smallest widget. For the size the system gives (GeometryReader), every line
// is measured with the real font (Lato, WidgetTheme.swift), the design's width and height are summed up, and the whole design is
// scaled by k = how many times it fits (WPlan.scale): a bigger phone shows the SAME widget bigger. Nothing is cut with an ellipsis
// (every text is one line at its own size) and a big widget is not left with small text.
// One wording table for every size: the extension of WSnap in WidgetModel.swift.
// Nothing here computes the moon, the sun or an Uposatha: the designs lay out what the page handed over.

// The app opens through its own URL scheme (Info.plist CFBundleURLTypes; SceneDelegate -> DgShortcutsPlugin.deliver(url:)).
enum WLinks {
    static func open(_ tab: String, day: String? = nil) -> URL {
        var s = "gift.dhamma.uposatha://open?tab=" + tab
        if let d = day { s += "&day=" + d }
        return URL(string: s) ?? URL(fileURLWithPath: "/")
    }

    // The slide of a big widget -> the app's tab
    static func tab(_ layer: Int) -> URL {
        switch layer {
        case 1: return open("parts")
        case 2: return open("cal")
        default: return open("home")
        }
    }
}

// MARK: - Window chrome

// The card: the app's card tint (not white / black). The designs carry their own paddings, so nothing is added here.
struct WidgetChrome: ViewModifier {
    let accessory: Bool

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) { accessory ? Color.clear : Color.dgSurface }
        } else {
            if accessory {
                content
            } else {
                content.background(Color.dgSurface)
            }
        }
    }
}

// MARK: - Measuring (base points)

enum WM {
    // The height of a line of Lato (ascent + descent = 1.2 em, no extra leading)
    static func lh(_ size: CGFloat) -> CGFloat { size * 1.2 }
    static func mx(_ v: CGFloat...) -> CGFloat { v.max() ?? 0 }
    // The frame of the big moon (the disc and the halo's room around it)
    static func box(_ disc: CGFloat) -> CGFloat { disc / MoonView.discShare }
    // The transparent margin of the moon's frame on each side: rows under the moon are moved in by it, so their left edge is the disc's
    static func inset(_ disc: CGFloat) -> CGFloat { (box(disc) - disc) / 2 }
    // The width of a text at a size
    static func mw(_ weight: DgWeight, _ size: CGFloat, _ s: String) -> CGFloat { measuredWidth(s, size, weight) }
    // The scale of a design in a widget; 3 % of the width is kept spare for the difference between measuring and drawing
    static func fit(_ w: CGFloat, _ h: CGFloat, _ needW: CGFloat, _ needH: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        WPlan.scale(w, h, needW * 1.03, needH, lo, hi)
    }
}

// MARK: - The pieces every design is made of (sizes are already multiplied by the scale)

// One line of text: never wrapped, never cut, exactly one line of Lato high.
struct WLine: View {
    let text: String
    let size: CGFloat
    var weight: DgWeight = .regular
    var color: Color = Color.dgText

    var body: some View {
        Text(text)
            .font(dgFont(size, weight))
            .foregroundColor(color)
            .lineLimit(1)
            .fixedSize()
            .frame(height: size * 1.2)
    }
}

// The counter "1d 7h": the digits big, the units small beside them on the same baseline.
struct WCounter: View {
    let seconds: TimeInterval
    let size: CGFloat
    let loc: Loc

    var body: some View {
        let c = WPlan.counter(seconds)
        let unit: CGFloat = size * 0.42
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if c.d > 0 {
                Text(String(c.d)).font(dgFont(size)).foregroundColor(Color.dgText)
                Text(loc.s("unit.d")).font(dgFont(unit, .semibold)).foregroundColor(Color.dgText)
                    .padding(.leading, size * 0.05)
                    .padding(.trailing, size * 0.17)
            }
            Text(String(c.h)).font(dgFont(size)).foregroundColor(Color.dgText)
            Text(loc.s("unit.h")).font(dgFont(unit, .semibold)).foregroundColor(Color.dgText)
                .padding(.leading, size * 0.05)
        }
        .lineLimit(1)
        .fixedSize()
        .frame(height: size * 1.2)
    }

    static func width(_ seconds: TimeInterval, _ size: CGFloat, _ loc: Loc) -> CGFloat {
        let c = WPlan.counter(seconds)
        let unit: CGFloat = size * 0.42
        var total: CGFloat = 0
        if c.d > 0 {
            total += WM.mw(.regular, size, String(c.d)) + size * 0.05
            total += WM.mw(.semibold, unit, loc.s("unit.d")) + size * 0.17
        }
        total += WM.mw(.regular, size, String(c.h)) + size * 0.05
        total += WM.mw(.semibold, unit, loc.s("unit.h"))
        return total
    }
}

// "Kala until 12:41" (green) / "Vikala until 05:50" (red): the same words on every widget.
struct WKalaLine: View {
    let snap: WSnap
    let kala: WKala
    let size: CGFloat

    var body: some View {
        let accent: Color = kala.isKala ? Color.dgAccentInk : Color.dgVikala
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(snap.kalaWord(kala)).font(dgFont(size, .bold)).foregroundColor(accent)
            Text(snap.loc.s("w.untilMid")).font(dgFont(size)).foregroundColor(Color.dgText)
            Text(kala.untilHm).font(dgFont(size, .bold)).foregroundColor(accent)
        }
        .lineLimit(1)
        .fixedSize()
        .frame(height: size * 1.2)
    }

    static func width(_ snap: WSnap, _ kala: WKala, _ size: CGFloat) -> CGFloat {
        let word: CGFloat = WM.mw(.bold, size, snap.kalaWord(kala))
        let mid: CGFloat = WM.mw(.regular, size, snap.loc.s("w.untilMid"))
        return word + mid + WM.mw(.bold, size, kala.untilHm)
    }
}

// "30% ↑": how much of the moon is lit, and whether it is growing.
struct WPercent: View {
    let snap: WSnap
    let size: CGFloat
    var color: Color = Color.dgText

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(snap.litText).font(dgFont(size, .semibold)).foregroundColor(color)
            Text(snap.growing ? " ↑" : " ↓").font(dgFont(size * 0.8)).foregroundColor(Color.dgMuted)
        }
        .lineLimit(1)
        .fixedSize()
        .frame(height: size * 1.2)
    }

    static func width(_ snap: WSnap, _ size: CGFloat) -> CGFloat {
        WM.mw(.semibold, size, snap.litText) + size * 0.8
    }
}

// The sun of a day: sunrise, noon and sunset, spread over the width.
struct SunRow: View {
    let day: WDay
    let loc: Loc
    let k: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            item(loc.s("sunrise"), day.sunrise.hm)
            Spacer(minLength: 0)
            item(loc.s("noon"), day.noon.hm)
            Spacer(minLength: 0)
            item(loc.s("sunset"), day.sunset.hm)
        }
    }

    private func item(_ name: String, _ hm: String) -> some View {
        HStack(spacing: 0) {
            WLine(text: name + " ", size: 12 * k, color: Color.dgText2)
            WLine(text: hm, size: 12 * k, weight: .semibold, color: Color.dgText)
        }
    }
}

// The list "Next": up to `count` Uposathas after the current one: moon, the date it begins on, the day, "in N d".
// The date column is as wide as the widest date of the list, so the rows line up. Nothing to list: nothing is drawn.
struct NextList: View {
    let snap: WSnap
    let count: Int
    let k: CGFloat
    var extraPad: CGFloat = 0     // more room above and below each row (base points)

    var body: some View {
        let rows: [WUposatha] = Array(snap.rest.prefix(max(0, count)))
        if !rows.isEmpty {
            list(rows)
        }
    }

    private func list(_ rows: [WUposatha]) -> some View {
        let dates: [String] = rows.map { snap.dateLabel($0.start.ymd) }
        let dateW: CGFloat = dates.map { WM.mw(.semibold, 13, $0) }.max() ?? 0
        let column: CGFloat = (8 + dateW * 1.03 + 12) * k
        return VStack(alignment: .leading, spacing: 0) {
            WLine(text: snap.loc.s("next").uppercased(), size: 10.5 * k, color: Color.dgMuted)
            ForEach(0..<rows.count, id: \.self) { i in
                HStack(alignment: .center, spacing: 0) {
                    MoonView(phase: rows[i].nominal, disc: 18 * k, south: snap.south, mini: true)
                    WLine(text: dates[i], size: 13 * k, weight: .semibold, color: Color.dgText)
                        .padding(.leading, 8 * k)
                        .frame(width: column, alignment: .leading)
                    WLine(text: snap.dayN(rows[i]), size: 13 * k, color: Color.dgText2)
                    Spacer(minLength: 0)
                    WLine(text: snap.inText(rows[i]), size: 13 * k, color: Color.dgMuted)
                }
                .padding(.vertical, (3.5 + extraPad) * k)
            }
        }
    }
}

// The day bar: six parts from dawn to dawn, each as wide as it lasts, the current one in the accent, a mark at "now"
// (Android's WidgetBar.java: the bar 9 high in a strip of 13, gaps of 2, round ends).
struct DayBar: View {
    let cycle: WCycle
    let t: Date
    let width: CGFloat
    let k: CGFloat

    static let height: CGFloat = 13     // base points, with the "now" mark that sticks out above and below

    var body: some View {
        let barH: CGFloat = 9 * k
        let fullH: CGFloat = DayBar.height * k
        let n: Int = cycle.parts.count
        let cur: Int = cycle.currentIndex(at: t)
        let mark: CGFloat = min(max(CGFloat(cycle.fraction(t)) * width, k), max(k, width - k))
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                ForEach(0..<n, id: \.self) { i in
                    segment(i, n, cur, barH)
                }
            }
            .frame(width: width, height: barH, alignment: .topLeading)
            .clipShape(Capsule())
            .offset(y: (fullH - barH) / 2)
            RoundedRectangle(cornerRadius: k)
                .fill(Color.dgText)
                .frame(width: 2 * k, height: fullH)
                .offset(x: mark - k)
        }
        .frame(width: width, height: fullH, alignment: .topLeading)
    }

    private func segment(_ i: Int, _ n: Int, _ cur: Int, _ barH: CGFloat) -> some View {
        let p = cycle.parts[i]
        let gap: CGFloat = 2 * k
        let x0: CGFloat = CGFloat(cycle.fraction(p.from)) * width + (i == 0 ? 0 : gap / 2)
        let x1: CGFloat = CGFloat(cycle.fraction(p.to)) * width - (i == n - 1 ? 0 : gap / 2)
        var fill: Color = i < n / 2 ? Color.dgPartDay : Color.dgPartNight
        if i == cur { fill = Color.dgAccent }
        return RoundedRectangle(cornerRadius: 2 * k)
            .fill(fill)
            .frame(width: max(0, x1 - x0), height: barH)
            .offset(x: x0)
    }
}

// The times under the day bar, spread over its width.
struct TickRow: View {
    let ticks: [String]
    let size: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<ticks.count, id: \.self) { i in
                if i > 0 {
                    Spacer(minLength: 0)
                }
                WLine(text: ticks[i], size: size, color: Color.dgMuted)
            }
        }
    }
}

// MARK: - Moon (small)

struct MoonOnlyDesign: View {
    let snap: WSnap
    let w: CGFloat
    let h: CGFloat

    var body: some View {
        let disc: CGFloat = 44
        let ps: CGFloat = 13
        let needW: CGFloat = 12 + max(WM.box(disc), WPercent.width(snap, ps))
        let needH: CGFloat = 12 + WM.box(disc) + 1 + WM.lh(ps)
        let k: CGFloat = WM.fit(w, h, needW, needH, 0.6, 3)
        VStack(spacing: k) {
            MoonView(phase: snap.moonNow, disc: disc * k, south: snap.south)
            WPercent(snap: snap, size: ps * k)
        }
        .frame(width: w, height: h)
    }
}

// MARK: - Uposatha (small): the agreed 1A / 1B

struct UpoSmallDesign: View {
    let snap: WSnap
    let u: WUposatha
    let w: CGFloat
    let h: CGFloat

    private enum B {
        static let cs: CGFloat = 34      // the counter
        static let t: CGFloat = 11.5     // the date, the time, the moon line
        static let st: CGFloat = 12.5    // the title, the kala line
        static let g: CGFloat = 3        // the least gap between the blocks
    }

    private struct Plan {
        let arr: Int          // 0 wide, 1 stacked (date and time in one line), 2 stacked (in two lines)
        let k: CGFloat
        let gap: CGFloat      // base points
        let inset: CGFloat    // base points
        let det: Bool
        let kala: Bool
    }

    private func plan() -> Plan {
        let det: Bool = snap.data.detail
        let kala: Bool = snap.kalaOn
        let day: String = snap.dayN(u)
        let st: String = snap.stateWord
        let cntW: CGFloat = WCounter.width(snap.secondsToTarget, B.cs, snap.loc)
        var kW: CGFloat = 0
        if kala, let kk = snap.kala { kW = WKalaLine.width(snap, kk, B.st) }
        let dtW: CGFloat = WM.mw(.semibold, B.t, snap.whenDate(u))
        let tmW: CGFloat = WM.mw(.regular, B.t, snap.whenTime(u))
        let stMax: CGFloat = max(WM.mw(.bold, B.st, day), WM.mw(.bold, B.st, st))
        let mlW: CGFloat = det ? WM.mw(.regular, B.t, snap.moonLine) : 0
        let phW: CGFloat = det ? WM.mw(.regular, B.t, snap.phaseWord) : 0
        let pcW: CGFloat = det ? WPercent.width(snap, B.t) : 0
        var tail: CGFloat = 0
        if det { tail += B.g + WM.lh(B.t) }
        if kala { tail += B.g + WM.lh(B.st) }
        let gaps: Int = 1 + (det ? 1 : 0) + (kala ? 1 : 0)
        // 0: wide, the agreed arrangement: the day beside the moon, the date and time at the right of the counter
        let in0: CGFloat = WM.inset(44)
        let head0: CGFloat = WM.box(44) - in0 + 5 + WM.mw(.bold, B.st, day + " · " + st)
        let w0: CGFloat = 24 + WM.mx(head0, cntW + 8 + max(dtW, tmW), mlW, kW)
        let h0: CGFloat = 24 + WM.box(44) + B.g + WM.lh(B.cs) + tail
        // 1: stacked, the date and time in one line under the counter
        let in1: CGFloat = WM.inset(40)
        let head1: CGFloat = WM.box(40) - in1 + 6 + stMax
        let when1: CGFloat = dtW + WM.mw(.regular, B.t, " ") + tmW
        let w1: CGFloat = 24 + WM.mx(head1, cntW, when1, mlW, kW)
        let top1: CGFloat = 24 + WM.box(40) + B.g
        let h1: CGFloat = top1 + WM.lh(B.cs) + 1 + WM.lh(B.t) + tail
        // 2: stacked, a narrow widget: the date and the time in two lines; with details the percent under the moon and the phase's name alone
        let in2: CGFloat = WM.inset(38)
        let head2: CGFloat = max(WM.box(38), pcW) - in2 + 6 + stMax
        let w2: CGFloat = 24 + WM.mx(head2, cntW, dtW, tmW, phW, kW)
        let top2: CGFloat = 24 + WM.box(38) + B.g
        var h2: CGFloat = top2 + WM.lh(B.cs) + 1 + 2 * WM.lh(B.t) + tail
        if det { h2 += 1 + WM.lh(B.t) }
        let k0: CGFloat = WPlan.scale(w, h, w0 * 1.03, h0, 0.1, 9)
        let k1: CGFloat = WPlan.scale(w, h, w1 * 1.03, h1, 0.1, 9)
        let k2: CGFloat = WPlan.scale(w, h, w2 * 1.03, h2, 0.1, 9)
        let arr: Int = WPlan.upoArrangement(k0, k1, k2)
        let needW: CGFloat = arr == 0 ? w0 : (arr == 1 ? w1 : w2)
        let needH: CGFloat = arr == 0 ? h0 : (arr == 1 ? h1 : h2)
        let inn: CGFloat = arr == 0 ? in0 : (arr == 1 ? in1 : in2)
        let k: CGFloat = WM.fit(w, h, needW, needH, 0.6, 2.2)
        let gap: CGFloat = WPlan.gap(h, k, needH, gaps, B.g, 12)
        return Plan(arr: arr, k: k, gap: gap, inset: inn, det: det, kala: kala)
    }

    var body: some View {
        let p = plan()
        let k: CGFloat = p.k
        content(p)
            .padding(EdgeInsets(top: 12 * k, leading: (12 - p.inset) * k, bottom: 12 * k, trailing: 12 * k))
            .frame(width: w, height: h, alignment: .leading)
    }

    private func content(_ p: Plan) -> some View {
        let k: CGFloat = p.k
        let lead: CGFloat = p.inset * k
        let gap: CGFloat = p.gap * k
        return VStack(alignment: .leading, spacing: 0) {
            if p.arr == 0 {
                wideHead(p)
            } else {
                stackHead(p)
            }
            if p.det {
                WLine(text: p.arr == 2 ? snap.phaseWord : snap.moonLine, size: B.t * k, color: Color.dgMuted)
                    .padding(.leading, lead)
                    .padding(.top, gap)
            }
            if p.kala, let kk = snap.kala {
                WKalaLine(snap: snap, kala: kk, size: B.st * k)
                    .padding(.leading, lead)
                    .padding(.top, gap)
            }
        }
    }

    // The moon and the title beside it; under them the counter with the date and time at its right, on the counter's baseline
    @ViewBuilder
    private func wideHead(_ p: Plan) -> some View {
        let k: CGFloat = p.k
        HStack(alignment: .center, spacing: 0) {
            MoonView(phase: snap.moonNow, disc: 44 * k, south: snap.south)
            WLine(text: snap.status(u), size: B.st * k, weight: .bold, color: Color.dgAccentInk)
                .padding(.leading, 5 * k)
        }
        HStack(alignment: .bottom, spacing: 0) {
            WCounter(seconds: snap.secondsToTarget, size: B.cs * k, loc: snap.loc)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                WLine(text: snap.whenDate(u), size: B.t * k, weight: .semibold, color: Color.dgText)
                WLine(text: snap.whenTime(u), size: B.t * k, color: Color.dgMuted)
            }
            .padding(.bottom, B.cs * 0.14 * k)
        }
        .padding(.leading, p.inset * k)
        .padding(.top, p.gap * k)
    }

    // The same lines, stacked: the title in two lines beside the moon, the date and time under the counter
    @ViewBuilder
    private func stackHead(_ p: Plan) -> some View {
        let k: CGFloat = p.k
        let lead: CGFloat = p.inset * k
        let disc: CGFloat = p.arr == 1 ? 40 : 38
        HStack(alignment: .center, spacing: 0) {
            VStack(spacing: k) {
                MoonView(phase: snap.moonNow, disc: disc * k, south: snap.south)
                if p.arr == 2 && p.det {
                    WPercent(snap: snap, size: B.t * k)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                WLine(text: snap.dayN(u), size: B.st * k, weight: .bold, color: Color.dgAccentInk)
                WLine(text: snap.stateWord, size: B.st * k, weight: .bold, color: Color.dgAccentInk)
            }
            .padding(.leading, 6 * k)
        }
        WCounter(seconds: snap.secondsToTarget, size: B.cs * k, loc: snap.loc)
            .padding(.leading, lead)
            .padding(.top, p.gap * k)
        if p.arr == 1 {
            HStack(spacing: 0) {
                WLine(text: snap.whenDate(u), size: B.t * k, weight: .semibold, color: Color.dgText)
                WLine(text: " " + snap.whenTime(u), size: B.t * k, color: Color.dgMuted)
            }
            .padding(.leading, lead)
            .padding(.top, k)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                WLine(text: snap.whenDate(u), size: B.t * k, weight: .semibold, color: Color.dgText)
                WLine(text: snap.whenTime(u), size: B.t * k, color: Color.dgMuted)
            }
            .padding(.leading, lead)
            .padding(.top, k)
        }
    }
}

// MARK: - Uposatha (medium; the tall variant on the large widget)

struct UpoMediumDesign: View {
    let snap: WSnap
    let u: WUposatha
    let w: CGFloat
    let h: CGFloat

    private enum B {
        static let d: CGFloat = 80       // the moon's disc
        static let cs: CGFloat = 40      // the counter
        static let t: CGFloat = 13       // the date, the time, the moon line, the detail line
        static let st: CGFloat = 14      // the title
        static let ks: CGFloat = 13.5    // the kala line
    }

    private struct Plan {
        let k: CGFloat
        let tall: Bool           // the block at the top, then the next Uposathas and the sun of today
        let rows: Int
        let extraPad: CGFloat
        let detail: String       // "" = no detail line
        let kala: Bool
    }

    private func plan() -> Plan {
        let kala: Bool = snap.kalaOn
        let detail: String = snap.data.detail ? snap.detailLine(u) : ""
        let det: Bool = !detail.isEmpty
        let inn: CGFloat = WM.inset(B.d)
        var kW: CGFloat = 0
        if kala, let kk = snap.kala { kW = WKalaLine.width(snap, kk, B.ks) }
        let whenW: CGFloat = max(WM.mw(.semibold, B.t, snap.whenDate(u)), WM.mw(.regular, B.t, snap.whenTime(u)))
        let stW: CGFloat = WM.mw(.bold, B.st, snap.status(u))
        let cntW: CGFloat = WCounter.width(snap.secondsToTarget, B.cs, snap.loc) + 12 + whenW
        let mlW: CGFloat = WM.mw(.regular, B.t, snap.moonLine)
        let dlW: CGFloat = det ? WM.mw(.regular, B.t, detail) : 0
        let col: CGFloat = WM.mx(stW, cntW, mlW, dlW, kW)
        var colH: CGFloat = WM.lh(B.st) + 4 + WM.lh(B.cs) + 4 + WM.lh(B.t)
        if det { colH += 2 + WM.lh(B.t) }
        if kala { colH += 5 + WM.lh(B.ks) }
        let moonW: CGFloat = 28 - inn + WM.box(B.d)
        let needW: CGFloat = moonW + 12 - inn + col
        let heroH: CGFloat = max(WM.box(B.d), colH)
        let sun: CGFloat = 8 + WM.lh(12)
        let listHead: CGFloat = 10 + 16
        let tallH: CGFloat = 24 + heroH + listHead + 2 * 26 + sun
        let kTall: CGFloat = WPlan.scale(w, h, needW * 1.03, tallH, 0.6, 1.6)
        let tall: Bool = kTall >= 1 && h / kTall - (24 + heroH + listHead + sun) >= 2 * 26
        if !tall {
            let k: CGFloat = WM.fit(w, h, needW, 24 + heroH, 0.6, 2.2)
            return Plan(k: k, tall: false, rows: 0, extraPad: 0, detail: detail, kala: kala)
        }
        // what is still left is shared by the rows, so the sun sits right under the list
        let free: CGFloat = h / kTall - 26 - heroH - listHead - sun
        let rows: Int = min(8, Int((free / 26).rounded(.down)))
        let spare: CGFloat = free - CGFloat(rows) * 26
        let extra: CGFloat = rows > 0 ? min(10, spare / CGFloat(rows)) / 2 : 0
        return Plan(k: kTall, tall: true, rows: rows, extraPad: extra, detail: detail, kala: kala)
    }

    var body: some View {
        let p = plan()
        let k: CGFloat = p.k
        let inn: CGFloat = WM.inset(B.d)
        if p.tall {
            VStack(alignment: .leading, spacing: 0) {
                hero(p)
                NextList(snap: snap, count: p.rows, k: k, extraPad: p.extraPad)
                    .padding(.leading, inn * k)
                    .padding(.top, 10 * k)
                Spacer(minLength: 0)
                if let d = snap.dayNow {
                    SunRow(day: d, loc: snap.loc, k: k)
                        .padding(.leading, inn * k)
                        .padding(.top, 8 * k)
                }
            }
            .padding(EdgeInsets(top: 14 * k, leading: (14 - inn) * k, bottom: 12 * k, trailing: 14 * k))
            .frame(width: w, height: h, alignment: .topLeading)
        } else {
            hero(p)
                .padding(EdgeInsets(top: 12 * k, leading: (14 - inn) * k, bottom: 12 * k, trailing: 14 * k))
                .frame(width: w, height: h)
        }
    }

    private func hero(_ p: Plan) -> some View {
        let k: CGFloat = p.k
        let inn: CGFloat = WM.inset(B.d)
        return HStack(alignment: .center, spacing: 0) {
            MoonView(phase: snap.moonNow, disc: B.d * k, south: snap.south)
            column(p).padding(.leading, (12 - inn) * k)
        }
    }

    private func column(_ p: Plan) -> some View {
        let k: CGFloat = p.k
        return VStack(alignment: .leading, spacing: 0) {
            WLine(text: snap.status(u), size: B.st * k, weight: .bold, color: Color.dgAccentInk)
            HStack(alignment: .bottom, spacing: 0) {
                WCounter(seconds: snap.secondsToTarget, size: B.cs * k, loc: snap.loc)
                VStack(alignment: .leading, spacing: 0) {
                    WLine(text: snap.whenDate(u), size: B.t * k, weight: .semibold, color: Color.dgText)
                    WLine(text: snap.whenTime(u), size: B.t * k, color: Color.dgMuted)
                }
                .padding(.leading, 12 * k)
                .padding(.bottom, B.cs * 0.14 * k)
            }
            .padding(.top, 4 * k)
            WLine(text: snap.moonLine, size: B.t * k, color: Color.dgMuted)
                .padding(.top, 4 * k)
            if !p.detail.isEmpty {
                WLine(text: p.detail, size: B.t * k, color: Color.dgText2)
                    .padding(.top, 2 * k)
            }
            if p.kala, let kk = snap.kala {
                WKalaLine(snap: snap, kala: kk, size: B.ks * k)
                    .padding(.top, 5 * k)
            }
        }
    }
}

// MARK: - Day & night

struct DayNightDesign: View {
    let snap: WSnap
    let cycle: WCycle
    let kala: WKala
    let w: CGFloat
    let h: CGFloat

    var body: some View {
        if w < 200 {
            narrow
        } else {
            wide
        }
    }

    // A small widget: the same lines, stacked
    private var narrow: some View {
        let l: Loc = snap.loc
        let part: WPart = cycle.parts[cycle.currentIndex(at: snap.t)]
        let ns: CGFloat = 18.5
        let t: CGFloat = 12.5
        let s: CGFloat = 11.5
        let g: CGFloat = 4
        let name: String = l.partName(part.key).0
        let until: String = l.s("w.until", ["time": part.toHm])
        let left: String = snap.kalaLeft(kala)
        let ticks: [String] = [cycle.parts[0].fromHm, cycle.day.sunset.hm, cycle.parts[cycle.parts.count - 1].toHm]
        let tick01: CGFloat = WM.mw(.regular, s, ticks[0]) + 8 + WM.mw(.regular, s, ticks[1])
        let ticksW: CGFloat = tick01 + 8 + WM.mw(.regular, s, ticks[2])
        let nameH: CGFloat = WM.lh(ns) + WM.lh(t)
        let textH: CGFloat = nameH + g + WM.lh(t) + 1 + WM.lh(s)
        let needH: CGFloat = 24 + textH + g + DayBar.height + 1 + WM.lh(s)
        let nameW: CGFloat = WM.mw(.semibold, ns, name)
        let untilW: CGFloat = WM.mw(.regular, t, until)
        let leftW: CGFloat = WM.mw(.regular, s, left)
        let needW: CGFloat = 24 + WM.mx(nameW, untilW, WKalaLine.width(snap, kala, t), leftW, ticksW)
        let k: CGFloat = WM.fit(w, h, needW, needH, 0.6, 2.2)
        let gap: CGFloat = WPlan.gap(h, k, needH, 2, g, 12) * k
        return VStack(alignment: .leading, spacing: 0) {
            WLine(text: name, size: ns * k, weight: .semibold, color: Color.dgText)
            WLine(text: until, size: t * k, color: Color.dgMuted)
            WKalaLine(snap: snap, kala: kala, size: t * k)
                .padding(.top, gap)
            WLine(text: left, size: s * k, color: Color.dgMuted)
                .padding(.top, k)
            DayBar(cycle: cycle, t: snap.t, width: w - 24 * k, k: k)
                .padding(.top, gap)
            TickRow(ticks: ticks, size: s * k)
                .padding(.top, k)
        }
        .padding(12 * k)
        .frame(width: w, height: h, alignment: .leading)
    }

    // A wide widget; a tall one adds the six parts with their borders and the sun
    private var wide: some View {
        let l: Loc = snap.loc
        let cur: Int = cycle.currentIndex(at: snap.t)
        let part: WPart = cycle.parts[cur]
        let ns: CGFloat = 22
        let t: CGFloat = 12.5
        let ks: CGFloat = 13.5
        let s: CGFloat = 11.5
        let row: CGFloat = 25
        let names: (String, String) = l.partName(part.key)
        var desc: String = names.1
        if !desc.isEmpty && l.lang == "ru" && part.key == "majjhanhika" { desc += " дня" }
        let until: String = l.s("w.until", ["time": part.toHm])
        let sub: String = desc.isEmpty ? until : desc + " · " + until
        let left: String = snap.kalaLeft(kala)
        let leftW: CGFloat = max(WM.mw(.semibold, ns, names.0), WM.mw(.regular, t, sub))
        let rightW: CGFloat = max(WKalaLine.width(snap, kala, ks), WM.mw(.regular, t, left))
        let needW: CGFloat = 32 + leftW + 16 + rightW
        let nameH: CGFloat = WM.lh(ns) + WM.lh(t)
        let head: CGFloat = nameH + 12 + DayBar.height + 1 + WM.lh(s)
        let listH: CGFloat = 8 + 6 * row + 8 + WM.lh(12)
        let tall: Bool = h >= 24 + head + listH
        let needH: CGFloat = 24 + head + (tall ? listH : 0)
        let k: CGFloat = WM.fit(w, h, needW, needH, 0.6, tall ? 1.5 : 2.2)
        let ticks: [String] = [cycle.parts[0].fromHm, cycle.day.noon.hm, cycle.day.sunset.hm, cycle.parts[cycle.parts.count - 1].toHm]
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    WLine(text: names.0, size: ns * k, weight: .semibold, color: Color.dgText)
                    WLine(text: sub, size: t * k, color: Color.dgMuted)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    WKalaLine(snap: snap, kala: kala, size: ks * k)
                    WLine(text: left, size: t * k, color: Color.dgMuted)
                        .padding(.top, k)
                }
            }
            DayBar(cycle: cycle, t: snap.t, width: w - 32 * k, k: k)
                .padding(.top, 12 * k)
            TickRow(ticks: ticks, size: s * k)
                .padding(.top, k)
            if tall {
                partList(cur, k)
                    .padding(.top, 8 * k)
                SunRow(day: cycle.day, loc: l, k: k)
                    .padding(.top, 8 * k)
            }
        }
        .padding(.horizontal, 16 * k)
        .padding(.vertical, 12 * k)
        .frame(width: w, height: h)
    }

    // The six parts with their borders; they share the height that is left, the current one on a plate
    private func partList(_ cur: Int, _ k: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<cycle.parts.count, id: \.self) { i in
                partRow(i, i == cur, k)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func partRow(_ i: Int, _ on: Bool, _ k: CGFloat) -> some View {
        let p: WPart = cycle.parts[i]
        let weight: DgWeight = on ? DgWeight.bold : DgWeight.regular
        let plate: Color = on ? Color.dgPlate : Color.clear
        return HStack(alignment: .center, spacing: 0) {
            WLine(text: snap.loc.s("part." + p.key), size: 13 * k, weight: weight, color: Color.dgText)
            Spacer(minLength: 4)
            WLine(text: p.fromHm + "–" + p.toHm, size: 13 * k, weight: weight, color: Color.dgText)
        }
        .padding(.horizontal, 8 * k)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8 * k).fill(plate))
    }
}

// MARK: - Calendar

// One day of the grid: a tile (today in the gold frame), the number (a date of an Uposatha: in a filled circle) and a mini-moon under
// it. The dates of one Uposatha (the evening it begins on, its day) are joined into a capsule: a band from the middle of a date to
// the middle of the next one, across the gap between the tiles; at the end of a row it stops at the edge and goes on in the next row.
// The tile takes the cell it is given; what is drawn in it never changes the grid's size.
struct CalCell: View {
    let day: Int
    let k: CGFloat
    let solid: Bool
    let joinLeft: Bool       // the date before is a date of an Uposatha too: the band reaches the left edge
    let joinRight: Bool
    let bold: Bool
    let ink: Color
    let tile: Color
    let ring: Bool
    let moonOn: Bool
    let phase: Double
    let moonSize: CGFloat
    let south: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9 * k)
                .fill(tile)
                .padding(1.5 * k)
            face
            frameRing.padding(1.5 * k)   // today's frame over the capsule of an Uposatha, not under it
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // The two halves behind the number, as wide as the whole cell (no gap to the neighbour)
    @ViewBuilder
    private var joins: some View {
        if joinLeft || joinRight {
            HStack(spacing: 0) {
                Rectangle().fill(joinLeft ? Color.dgAccent : Color.clear)
                Rectangle().fill(joinRight ? Color.dgAccent : Color.clear)
            }
            .frame(height: 22 * k)
        }
    }

    @ViewBuilder
    private var frameRing: some View {
        if ring {
            // a translucent plaque and its frame, over the capsule of an Uposatha (a frame alone can be lost on it)
            RoundedRectangle(cornerRadius: 9 * k).fill(Color.dgGold.opacity(0.4))
                .overlay(RoundedRectangle(cornerRadius: 9 * k).strokeBorder(Color.dgGold, lineWidth: 1.5))
        }
    }

    private var face: some View {
        VStack(spacing: k) {
            number
                .frame(maxWidth: .infinity)
                .background(joins)
            if moonOn {
                MoonView(phase: phase, disc: moonSize * k, south: south, mini: true)
            }
        }
    }

    @ViewBuilder
    private var number: some View {
        let weight: DgWeight = bold ? DgWeight.bold : DgWeight.regular
        let label = Text(String(day)).font(dgFont(13.5 * k, weight)).foregroundColor(ink).lineLimit(1).fixedSize()
        if solid {
            label.frame(width: 22 * k, height: 22 * k).background(Circle().fill(Color.dgAccent))
        } else {
            label.frame(height: 13.5 * 1.2 * k)
        }
    }
}

// The arrows of the calendar: today's month and the next two (the data reaches about eleven weeks ahead). iOS 17+ buttons that
// do not open the app; before iOS 17 there are no arrows.
struct MonthNav: View {
    let offset: Int
    let k: CGFloat

    var body: some View {
        if #available(iOS 17.0, *) {
            HStack(spacing: 0) {
                arrow(-1, offset > 0)
                arrow(1, offset < 2)
            }
        }
    }

    @available(iOS 17.0, *)
    @ViewBuilder
    private func arrow(_ step: Int, _ enabled: Bool) -> some View {
        if enabled {
            Button(intent: SwitchLayerIntent(family: "month", count: 3, step: step)) {
                picture(step, 1)
            }
            .buttonStyle(.plain)
        } else {
            picture(step, 0.27)
        }
    }

    private func picture(_ step: Int, _ alpha: Double) -> some View {
        Image(systemName: step < 0 ? "chevron.left" : "chevron.right")
            .font(Font.system(size: 12 * k, weight: .semibold))
            .foregroundColor(Color.dgText2)
            .opacity(alpha)
            .frame(width: 28 * k, height: 22 * k)
            .contentShape(Rectangle())
    }
}

struct CalendarDesign: View {
    let snap: WSnap
    let month: Int           // 0 = today's month, up to 2 ahead
    let w: CGFloat
    let h: CGFloat

    private struct Plan {
        let k: CGFloat
        let year: Int
        let mon: Int
        let rows: [[WCell]]
        let cal: WCalPlan
    }

    private static let baseW: CGFloat = 290

    private func plan() -> Plan {
        let today = WTime.parseYmd(snap.today) ?? (y: 2026, m: 1, d: 1)
        let m0: Int = today.m - 1 + min(max(month, 0), 2)
        let year: Int = today.y + m0 / 12
        let mon: Int = m0 % 12 + 1
        let first: Int = WTime.daysFromCivil(year, mon, 1)
        let next: Int = mon == 12 ? WTime.daysFromCivil(year + 1, 1, 1) : WTime.daysFromCivil(year, mon + 1, 1)
        let lead: Int = snap.data.weekColumn(ofDays: first)
        let weeks: Int = (lead + (next - first) + 6) / 7
        let k: CGFloat = WPlan.calScale(w, h, CalendarDesign.baseW, weeks)
        let cal: WCalPlan = WPlan.cal(h / k, weeks, snap.data.detail, true)
        let rows: [[WCell]] = snap.data.cells(from: first - lead, rows: weeks, month: mon)
        return Plan(k: k, year: year, mon: mon, rows: rows, cal: cal)
    }

    var body: some View {
        let p = plan()
        let k: CGFloat = p.k
        VStack(alignment: .leading, spacing: 0) {
            header(p)
            weekdays(k)
            grid(p)
            if p.cal.card {
                card(p).padding(.top, 8 * k)
            }
            if p.cal.rows > 0 {
                NextList(snap: snap, count: p.cal.rows, k: k).padding(.top, 8 * k)
            }
        }
        .padding(14 * k)
        .frame(width: w, height: h, alignment: .top)
    }

    private func header(_ p: Plan) -> some View {
        let k: CGFloat = p.k
        let title: String = snap.loc.monthTitle(p.mon) + " " + String(p.year)
        return HStack(alignment: .center, spacing: 0) {
            WLine(text: title, size: 17 * k, weight: .semibold, color: Color.dgText)
            Spacer(minLength: 0)
            MonthNav(offset: min(max(month, 0), 2), k: k)
        }
        .padding(.leading, 2 * k)
        .frame(height: 22 * k)
        .padding(.bottom, 5 * k)
    }

    // "MO TU WE" / "ПН ВТ СР", in the order of the app's own week
    private func weekdays(_ k: CGFloat) -> some View {
        let ru: Bool = snap.loc.lang == "ru"
        let names: [String] = snap.data.weekdayNames(snap.loc).map { ru ? $0.uppercased() : String($0.prefix(2)).uppercased() }
        return HStack(spacing: 0) {
            ForEach(0..<names.count, id: \.self) { i in
                WLine(text: names[i], size: 10.5 * k, color: Color.dgMuted)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 3 * k)
    }

    // Whole weeks, the neighbouring months' days in grey; the weeks share the height that is left
    private func grid(_ p: Plan) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<p.rows.count, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<p.rows[r].count, id: \.self) { c in
                        cell(p.rows[r][c], p)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // A date of an Uposatha: the evening it begins on, or its own day
    private func marked(_ ymd: String) -> Bool {
        snap.data.startingOn(ymd) != nil || snap.data.uposathaOn(ymd) != nil
    }

    // Every date of an Uposatha carries the same solid mark, and neighbouring dates are joined (CalCell). A day opens the app's
    // calendar on it.
    private func cell(_ item: WCell, _ p: Plan) -> some View {
        let data: WData = snap.data
        let inMonth: Bool = item.inMonth
        let isToday: Bool = item.ymd == snap.today
        let past: Bool = item.ymd < snap.today
        let startOf: WUposatha? = data.startingOn(item.ymd)
        let dayOf: WUposatha? = data.uposathaOn(item.ymd)
        // every date of an Uposatha carries the same solid mark, the evening it begins on and its own day (owner, 2026-10-11: on the day
        // itself the dim tile read as "no Uposatha today")
        let solid: Bool = inMonth && (startOf != nil || dayOf != nil)
        let band: Bool = false
        let dayNo: Int? = WTime.dayNumber(item.ymd)
        let joinLeft: Bool = solid && (dayNo.map { marked(WTime.ymdString(fromDays: $0 - 1)) } ?? false)
        let joinRight: Bool = solid && (dayNo.map { marked(WTime.ymdString(fromDays: $0 + 1)) } ?? false)
        let bold: Bool = solid || band || (isToday && inMonth)
        var ink: Color = Color.dgText
        if solid { ink = Color.white }
        else if band { ink = Color.dgAccentInk }
        else if !inMonth || past { ink = Color.dgMuted }
        var tile: Color = Color.dgTile
        if !inMonth { tile = Color.clear }
        else if isToday { tile = Color.dgGoldBg }
        else if band { tile = Color.dgBand }
        let moonOn: Bool = p.cal.moons && inMonth && (solid || band || data.allMoons)
        var phase: Double = 0
        if moonOn {
            if solid { phase = (startOf ?? dayOf)?.nominal ?? 0 }
            else if band { phase = dayOf?.nominal ?? 0 }
            else { phase = snap.phaseOn(item.ymd) }
        }
        let moonSize: CGFloat = data.allMoons ? 12 : 11
        let face = CalCell(day: item.day, k: p.k, solid: solid, joinLeft: joinLeft, joinRight: joinRight, bold: bold, ink: ink, tile: tile, ring: isToday && inMonth,
                           moonOn: moonOn, phase: phase, moonSize: moonSize, south: snap.south)
        return Link(destination: WLinks.open("cal", day: item.ymd)) { face }
    }

    // The card of today: the date, the Uposatha, the moon; with details also the lunar day and the sun
    private func card(_ p: Plan) -> some View {
        let k: CGFloat = p.k
        let t: CGFloat = 12.5
        let l: Loc = snap.loc
        let dateText: String = l.weekdayLong(snap.today) + ", " + l.dayOfMonth(snap.today) + " " + l.monthOf(snap.today)
        let until: String = untilText(t)
        var moon: String = snap.moonLine
        if p.cal.details { moon += " · " + l.s("w.lunarDay", ["n": String(WPlan.tithi(snap.moonNow))]) }
        let sun: String = p.cal.details ? sunText(t) : ""
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                WLine(text: dateText, size: 13.5 * k, weight: .bold, color: Color.dgText)
                Spacer(minLength: 0)
                if snap.active {
                    WLine(text: l.s("w.upoDay"), size: 10.5 * k, weight: .semibold, color: Color.dgAccentInk)
                        .padding(.horizontal, 8 * k)
                        .padding(.vertical, 1.5 * k)
                        .background(RoundedRectangle(cornerRadius: 9 * k).fill(Color.dgBand))
                }
            }
            if let u = snap.upo {
                HStack(spacing: 0) {
                    WLine(text: snap.status(u), size: t * k, weight: .bold, color: Color.dgAccentInk)
                    WLine(text: until, size: t * k, color: Color.dgMuted)
                }
                .padding(.top, k)
            }
            WLine(text: moon, size: t * k, color: Color.dgText2)
            if !sun.isEmpty {
                WLine(text: sun, size: t * k, color: Color.dgMuted)
            }
        }
        .padding(.horizontal, 12 * k)
        .padding(.vertical, 9 * k)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14 * k).fill(Color.dgTile))
    }

    // " · until Sat 10 Oct, 18:00" / " · Sat 17 Oct, from 18:00"; when that does not fit beside the title, the short form
    private func untilText(_ t: CGFloat) -> String {
        guard let u = snap.upo else { return "" }
        let l: Loc = snap.loc
        let full: String
        let brief: String
        if snap.active {
            let end: String = snap.dateLabel(u.end.ymd) + ", " + u.end.hm
            full = " · " + l.s("w.until", ["time": end])
            brief = " · " + l.s("w.until", ["time": u.end.hm])
        } else {
            brief = " · " + snap.dateLabel(u.start.ymd)
            full = brief + ", " + l.s("w.from", ["time": u.start.hm])
        }
        let room: CGFloat = CalendarDesign.baseW - 28 - 24 - 2 - WM.mw(.bold, t, snap.status(u))
        return WM.mw(.regular, t, full) <= room ? full : brief
    }

    // The sun of today; when the three do not fit in the line, the noon goes (the kala line has it)
    private func sunText(_ t: CGFloat) -> String {
        guard let d = snap.dayNow else { return "" }
        let l: Loc = snap.loc
        let rise: String = l.s("sunrise") + " " + d.sunrise.hm
        let down: String = l.s("sunset") + " " + d.sunset.hm
        let all: String = rise + " · " + l.s("noon") + " " + d.noon.hm + " · " + down
        let room: CGFloat = CalendarDesign.baseW - 28 - 24 - 2
        return WM.mw(.regular, t, all) <= room ? all : rise + " · " + down
    }
}

// MARK: - No data yet

// What a widget says when there is nothing true to show: no data, data older than 30 days, or now not covered. No times: it never
// shows a wrong one.
struct PlaceholderDesign: View {
    let stale: Bool
    var small: Bool = false
    let w: CGFloat
    let h: CGFloat

    var body: some View {
        let l = Loc(lang: Loc.deviceLang())
        let title: String = l.s("w.open")
        let note: String = l.s(stale ? "w.stale" : "w.noData")
        let tiny: Bool = small || h < 90 || w < 100
        let disc: CGFloat = tiny ? 30 : 44
        let titleSize: CGFloat = tiny ? 11 : 12.5
        let noteW: CGFloat = tiny ? 0 : WM.mw(.regular, 11, note)
        let noteH: CGFloat = tiny ? 0 : 1 + WM.lh(11)
        let needW: CGFloat = 16 + WM.mx(WM.box(disc), WM.mw(.semibold, 12.5, title), noteW)
        let needH: CGFloat = 16 + WM.box(disc) + 2 + WM.lh(12.5) + noteH
        let k: CGFloat = WM.fit(w, h, needW, needH, 0.5, 2.2)
        VStack(spacing: 0) {
            MoonView(phase: 0.5, disc: disc * k)
            WLine(text: title, size: titleSize * k, weight: .semibold, color: Color.dgText)
                .padding(.top, 2 * k)
            if !tiny {
                WLine(text: note, size: 11 * k, color: Color.dgMuted)
                    .padding(.top, k)
            }
        }
        .frame(width: w, height: h)
    }
}

// MARK: - The big widgets: three slides and their switch

// The switch of the slides: a segment per slide between two chevrons, at the bottom. The strip is two buttons: the left half goes to the
// slide before, the right half to the next (iOS 17+ App Intents, they do not open the app). Before iOS 17 there is one slide and no switch.
struct LayerSwitch: View {
    let key: String
    let count: Int
    let active: Int

    var body: some View {
        if #available(iOS 17.0, *) {
            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    stepButton(-1)
                    stepButton(1)
                }
                picture
                    .padding(.bottom, 7)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
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
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "chevron.left").font(Font.system(size: 10, weight: .semibold)).foregroundColor(Color.dgMuted)
            ForEach(0..<count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(i == active ? Color.dgAccent : Color.dgBorderStrong)
                    .frame(width: 22, height: 5)
            }
            Image(systemName: "chevron.right").font(Font.system(size: 10, weight: .semibold)).foregroundColor(Color.dgMuted)
        }
    }
}

// A big widget is one of the designs at the widget's own size: 0 the Uposatha, 1 Day & night, 2 the calendar (the large only:
// WidgetFamilies.layerCount; the medium's switch has two segments and turns 0 <-> 1).
struct SlidesView: View {
    let snap: WSnap
    let key: String
    let layer: Int
    let month: Int
    let w: CGFloat
    let h: CGFloat

    // The height the switch takes from the designs (iOS 17+). It is drawn in the designs' own bottom padding, so only a little is
    // taken: with more, the calendar of the large widget loses its mini-moons (the weeks get lower than WPlan.calRowMoons).
    static var reserve: CGFloat {
        if #available(iOS 17.0, *) { return 10 }
        return 0
    }

    var body: some View {
        let room: CGFloat = h - SlidesView.reserve
        ZStack(alignment: .bottom) {
            slide(room)
                .frame(width: w, height: h, alignment: .top)
            LayerSwitch(key: key, count: WidgetFamilies.layerCount(key), active: layer)
        }
        .widgetURL(WLinks.tab(layer))
    }

    @ViewBuilder
    private func slide(_ room: CGFloat) -> some View {
        if layer == 2 {
            CalendarDesign(snap: snap, month: month, w: w, h: room)
        } else if layer == 1 {
            if let c = snap.cycle, let kk = snap.kala {
                DayNightDesign(snap: snap, cycle: c, kala: kk, w: w, h: room)
            } else {
                PlaceholderDesign(stale: true, w: w, h: room)
            }
        } else {
            if let u = snap.upo {
                UpoMediumDesign(snap: snap, u: u, w: w, h: room)
            } else {
                PlaceholderDesign(stale: true, w: w, h: room)
            }
        }
    }
}

// MARK: - The entry views

// "UposathaWidget": small = the Uposatha, medium / large = the slides, lock screen = WidgetLockViews.swift
struct UposathaWidgetView: View {
    let entry: UposathaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content.modifier(WidgetChrome(accessory: !WidgetFamilies.isSystem(family)))
    }

    @ViewBuilder
    private var content: some View {
        if WidgetFamilies.isSystem(family) {
            GeometryReader { geo in
                system(geo.size.width, geo.size.height)
            }
        } else {
            if #available(iOS 16.0, *) {
                LockScreenView(entry: entry)
            }
        }
    }

    @ViewBuilder
    private func system(_ w: CGFloat, _ h: CGFloat) -> some View {
        if let snap = entry.snap {
            if family == .systemSmall {
                if let u = snap.upo {
                    UpoSmallDesign(snap: snap, u: u, w: w, h: h)
                        .widgetURL(WLinks.open("home"))
                } else {
                    PlaceholderDesign(stale: true, w: w, h: h)
                        .widgetURL(WLinks.open("home"))
                }
            } else {
                SlidesView(snap: snap, key: WidgetFamilies.key(family), layer: entry.layer, month: entry.month, w: w, h: h)
            }
        } else {
            PlaceholderDesign(stale: entry.stale, w: w, h: h)
                .widgetURL(WLinks.open("home"))
        }
    }
}

// "UposathaMoonWidget": the moon as it is now and how much of it is lit
struct MoonWidgetView: View {
    let entry: UposathaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(WLinks.open("home"))
            .modifier(WidgetChrome(accessory: !WidgetFamilies.isSystem(family)))
    }

    @ViewBuilder
    private var content: some View {
        if WidgetFamilies.isSystem(family) {
            GeometryReader { geo in
                if let snap = entry.snap {
                    MoonOnlyDesign(snap: snap, w: geo.size.width, h: geo.size.height)
                } else {
                    PlaceholderDesign(stale: entry.stale, small: true, w: geo.size.width, h: geo.size.height)
                }
            }
        } else {
            if #available(iOS 16.0, *) {
                LockMoonCircular(entry: entry)
            }
        }
    }
}

// "UposathaDayWidget": the part of the day that is on, kala / vikala, the scale from dawn to dawn
struct DayWidgetView: View {
    let entry: UposathaEntry

    var body: some View {
        GeometryReader { geo in
            if let snap = entry.snap, let c = snap.cycle, let kk = snap.kala {
                DayNightDesign(snap: snap, cycle: c, kala: kk, w: geo.size.width, h: geo.size.height)
            } else {
                PlaceholderDesign(stale: entry.stale || entry.data != nil, w: geo.size.width, h: geo.size.height)
            }
        }
        .widgetURL(WLinks.open("parts"))
        .modifier(WidgetChrome(accessory: false))
    }
}
