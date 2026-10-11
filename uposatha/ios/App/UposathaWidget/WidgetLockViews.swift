import SwiftUI
import WidgetKit

// Lock-screen widgets (iOS 16+): one scenario each, the same words as the home-screen widgets, monochrome (the system tints them).
// The moon is a FLAT sign (MoonGlyph): a photo turns into a white blob when tinted.
//   rectangular: the sign, "8th day · coming", "1d 7h", "Kala until 12:41"
//   circular:    the sign over "1d 7h" (the moon widget's circle: the sign over "30%")
//   inline:      "8th day · 1d 7h · Kala until 12:41" (the line over the clock)
// Here a text may shrink (the box is the system's and tiny), but it is never cut.

@available(iOS 16.0, *)
struct LockScreenView: View {
    let entry: UposathaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content.widgetURL(WLinks.open("home"))
    }

    @ViewBuilder
    private var content: some View {
        if let snap = entry.snap, let u = snap.upo {
            switch family {
            case .accessoryRectangular: LockRectangular(snap: snap, u: u)
            case .accessoryCircular: LockCircular(snap: snap, text: snap.counterText)
            default: LockInline(snap: snap, u: u)
            }
        } else {
            LockOpen()
        }
    }
}

// Nothing true to show: the sign alone in the circle, "Open Uposatha" elsewhere.
@available(iOS 16.0, *)
struct LockOpen: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryCircular {
            ZStack {
                AccessoryWidgetBackground()
                MoonGlyph(phase: 0.5, size: 30)
            }
        } else {
            Text(Loc(lang: Loc.deviceLang()).s("w.open"))
                .font(dgFont(13, .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

@available(iOS 16.0, *)
struct LockRectangular: View {
    let snap: WSnap
    let u: WUposatha

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            MoonGlyph(phase: snap.moonNow, size: 32, south: snap.south)
            VStack(alignment: .leading, spacing: 1) {
                Text(snap.status(u)).font(dgFont(12.5)).opacity(0.8)
                Text(snap.counterText).font(dgFont(15, .bold))
                if snap.kalaOn, let k = snap.kala {
                    Text(snap.kalaText(k)).font(dgFont(12.5)).opacity(0.8)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
    }
}

// The sign over one short text: the counter (the Uposatha widget) or the percent lit (the moon widget)
@available(iOS 16.0, *)
struct LockCircular: View {
    let snap: WSnap
    let text: String

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                MoonGlyph(phase: snap.moonNow, size: 24, south: snap.south)
                Text(text)
                    .font(dgFont(12, .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 5)
        }
    }
}

// The circle of the moon widget
@available(iOS 16.0, *)
struct LockMoonCircular: View {
    let entry: UposathaEntry

    var body: some View {
        if let snap = entry.snap {
            LockCircular(snap: snap, text: snap.litShort)
        } else {
            LockOpen()
        }
    }
}

// The line above the clock: text only, and one system symbol of the phase before it.
@available(iOS 16.0, *)
struct LockInline: View {
    let snap: WSnap
    let u: WUposatha

    private static let symbols: [String] = [
        "moonphase.new.moon", "moonphase.waxing.crescent", "moonphase.first.quarter", "moonphase.waxing.gibbous",
        "moonphase.full.moon", "moonphase.waning.gibbous", "moonphase.last.quarter", "moonphase.waning.crescent"
    ]

    var body: some View {
        var line: String = snap.dayN(u) + " · " + snap.counterText
        if snap.kalaOn, let k = snap.kala { line += " · " + snap.kalaText(k) }
        let symbol: String = LockInline.symbols[WPlan.phaseIndex(snap.moonNow)]
        return Label {
            Text(line)
        } icon: {
            Image(systemName: symbol)
        }
    }
}
