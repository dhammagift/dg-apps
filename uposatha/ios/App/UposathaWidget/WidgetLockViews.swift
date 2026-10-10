import SwiftUI
import WidgetKit
import AppIntents

// Lock-screen widgets (iOS 16+): monochrome (the system tints them), per the designer's spec section 2 and the lock-screen mock-up.
// Rectangular: layer 1 (Uposatha) and 2 (day and night), the dots vertical on the right (iOS 17+ buttons).
// Circular: counter, kala ring, date — a tap on the whole circle turns to the next. Inline: one line, no buttons.

@available(iOS 16.0, *)
struct LockScreenView: View {
    let snap: WSnap
    let layer: Int
    let key: String
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            LockRectangular(snap: snap, layer: layer, key: key)
                .widgetURL(WLinks.open(layer == 1 ? "parts" : "home"))
        case .accessoryCircular:
            LockCircular(snap: snap, layer: layer, key: key)
                .widgetURL(WLinks.tab(layer))
        default:
            LockInline(snap: snap)
                .widgetURL(WLinks.open("home"))
        }
    }
}

// The kala line for the lock screen: with no place set the times are only assumed, so it says that instead.
@available(iOS 16.0, *)
func lockKalaLine(_ snap: WSnap) -> String? {
    let l = snap.loc
    if !snap.data.placeSet { return l.s("noPlace.short") }
    guard snap.data.showKala, let k = snap.kala else { return nil }
    return l.s(k.isKala ? "kalaShort" : "vikalaShort", ["time": k.untilHm])
}

@available(iOS 16.0, *)
struct LockRectangular: View {
    let snap: WSnap
    let layer: Int
    let key: String

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if layer == 1 { dayNight } else { uposatha }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DotsStrip(key: key, count: 2, active: layer, vertical: true, mono: true)
        }
    }

    @ViewBuilder
    private var uposatha: some View {
        let l = snap.loc
        if let u = snap.upo {
            HStack(spacing: 6) {
                MoonView(phase: snap.heroPhase, size: 26, south: snap.south, mono: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(snap.active ? l.s("toNow", ["n": String(u.lunarDay)])
                                     : l.s("lock.rect", ["n": String(u.lunarDay), "count": l.countText(snap.secondsToTarget)]))
                        .font(dgFont(12.5, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(snap.active ? l.countText(snap.secondsToTarget)
                                     : l.s("lite.from", ["startDay": l.dayShort(u.start.ymd), "startTime": u.start.hm]))
                        .font(dgFont(12)).lineLimit(1).minimumScaleFactor(0.7)
                    if let line = lockKalaLine(snap) {
                        Text(line).font(dgFont(12)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
        } else {
            OpenAppView()
        }
    }

    @ViewBuilder
    private var dayNight: some View {
        let l = snap.loc
        if let c = snap.cycle, let part = c.current(at: snap.t) {
            let names = l.partName(part.key)
            let sunLine: String = snap.t < c.day.sunset.date
                ? l.s("sunset") + " " + c.day.sunset.hm
                : l.s("sunrise") + " " + c.next.sunrise.hm
            VStack(alignment: .leading, spacing: 1) {
                Text(names.0).font(dgFont(13, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Text((names.1.isEmpty ? "" : names.1 + " · ") + l.s("until", ["time": part.toHm]))
                    .font(dgFont(12)).lineLimit(1).minimumScaleFactor(0.7)
                Text(sunLine).font(dgFont(12)).lineLimit(1).minimumScaleFactor(0.7)
            }
        } else {
            OpenAppView()
        }
    }
}

@available(iOS 16.0, *)
struct LockCircular: View {
    let snap: WSnap
    let layer: Int
    let key: String

    var body: some View {
        if #available(iOS 17.0, *) {
            Button(intent: SwitchLayerIntent(family: key, count: 3, step: 1)) { face }
                .buttonStyle(.plain)
        } else {
            face
        }
    }

    @ViewBuilder
    private var face: some View {
        ZStack {
            AccessoryWidgetBackground()
            switch layer {
            case 1: ring
            case 2: date
            default: counter
            }
        }
    }

    // 1: the moon and the time to the start (or the end)
    @ViewBuilder
    private var counter: some View {
        if snap.upo != nil {
            VStack(spacing: 1) {
                MoonView(phase: snap.heroPhase, size: 24, south: snap.south, mono: true)
                Text(snap.loc.countParts(snap.secondsToTarget).map { $0.0 + $0.1 }.joined(separator: " "))
                    .font(dgFont(11, .bold)).lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 4)
        } else {
            OpenAppView()
        }
    }

    // 2: the ring of the kala (or vikala) that is on, and its end inside
    @ViewBuilder
    private var ring: some View {
        if let k = snap.kala {
            let span = max(1, k.until.timeIntervalSince(k.from))
            let done = min(1, max(0, snap.t.timeIntervalSince(k.from) / span))
            ZStack {
                Circle().stroke(Color.primary.opacity(0.25), lineWidth: 4)
                Circle().trim(from: 0, to: CGFloat(done))
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(k.untilHm).font(dgFont(12, .bold)).lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(6)
        } else {
            OpenAppView()
        }
    }

    // 3: the date of the Uposatha
    @ViewBuilder
    private var date: some View {
        if let u = snap.upo {
            VStack(spacing: 0) {
                Text(snap.loc.dayOfMonth(u.start.ymd)).font(dgFont(22, .bold))
                Text(snap.loc.monthShort(u.start.ymd)).font(dgFont(11, .medium))
            }
        } else {
            OpenAppView()
        }
    }
}

// The line above the clock: one layer, no buttons.
@available(iOS 16.0, *)
struct LockInline: View {
    let snap: WSnap

    var body: some View {
        let l = snap.loc
        if let u = snap.upo {
            Text(line(l, u))
        } else {
            OpenAppView()
        }
    }

    private func line(_ l: Loc, _ u: WUposatha) -> String {
        let n = String(u.lunarDay)
        if snap.active {
            return l.s("toNow", ["n": n]) + " " + l.countText(snap.secondsToTarget)
        }
        let count = l.countText(snap.secondsToTarget)
        guard snap.data.placeSet, snap.data.showKala, let k = snap.kala else {
            return l.s("lock.rect", ["n": n, "count": count])
        }
        if k.isKala {
            return l.s("lock.inline", ["n": n, "count": count, "time": k.untilHm])
        }
        return l.s("lock.rect", ["n": n, "count": count]) + " · " + l.s("vikalaShort", ["time": k.untilHm])
    }
}
