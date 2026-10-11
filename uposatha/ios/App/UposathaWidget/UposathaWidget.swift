import WidgetKit
import SwiftUI

// Three widgets in one bundle (the redesign of 2026-10-10, the same designs as Android's WidgetViews.java):
//   "UposathaWidget"      small = the Uposatha (one scenario); medium = two slides (Uposatha / Day & night); large = three
//                         (Uposatha / Day & night / Calendar); lock screen: rectangular, circular, inline
//   "UposathaMoonWidget"  small = the moon and how much of it is lit; lock screen: circular
//   "UposathaDayWidget"   small = Day & night
// The kind strings never change: a widget already on a home screen is found by its kind.

// MARK: - Families

enum WidgetFamilies {
    static var uposatha: [WidgetFamily] {
        var list: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
        if #available(iOS 16.0, *) {
            list.append(contentsOf: [.accessoryRectangular, .accessoryCircular, .accessoryInline])
        }
        return list
    }

    static var moon: [WidgetFamily] {
        var list: [WidgetFamily] = [.systemSmall]
        if #available(iOS 16.0, *) {
            list.append(.accessoryCircular)
        }
        return list
    }

    static func isSystem(_ f: WidgetFamily) -> Bool {
        switch f {
        case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge: return true
        default: return false
        }
    }

    // The key the slide of a widget size is kept under (App Group defaults "layer.<key>")
    static func key(_ f: WidgetFamily) -> String {
        switch f {
        case .systemSmall: return "small"
        case .systemMedium: return "medium"
        case .systemLarge: return "large"
        default: return "other"
        }
    }

    // Small widgets are ONE scenario. The medium has two slides (Uposatha, Day & night): a month at its height would be unreadable,
    // the calendar lives in the large widget, which has all three.
    static func layerCount(_ key: String) -> Int {
        switch key {
        case "medium": return 2
        case "large": return 3
        default: return 1
        }
    }

    // The slide a size shows: the stored one (iOS 17+, the switch), else its own: the medium opens on the Uposatha, the large on
    // the calendar. Before iOS 17 there is no switch, so it is always the size's own.
    static func layer(_ key: String) -> Int {
        let count = layerCount(key)
        if count <= 1 { return 0 }
        let stored = WStore.layer(key)
        return (stored >= 0 && stored < count) ? stored : 0   // a slide this size does not have (an old stored 2 on the medium): the first
    }
}

// MARK: - Timeline

struct UposathaEntry: TimelineEntry {
    let date: Date
    let data: WData?      // nil: nothing usable, the widget says "Open Uposatha"
    let layer: Int
    let month: Int        // the calendar's month: 0 = today's, up to 2 ahead
    let stale: Bool       // there is data, but it is too old or does not cover now
    let isSample: Bool

    // What the designs print; nil: the placeholder
    var snap: WSnap? {
        guard let d = data, d.isUsable(at: date) else { return nil }
        return WSnap(data: d, t: date)
    }

    // The bundled sample, shown at the moment it was made: for the placeholder and the widget gallery.
    static func sample(_ family: WidgetFamily) -> UposathaEntry {
        let data = WStore.sample()
        let when = data?.generatedAt.flatMap({ WTime.parseISO($0) }) ?? Date()
        let layer = WidgetFamilies.key(family) == "large" ? 2 : 0
        return UposathaEntry(date: when, data: data, layer: layer, month: 0, stale: false, isSample: true)
    }
}

struct UposathaProvider: TimelineProvider {
    func placeholder(in context: Context) -> UposathaEntry {
        UposathaEntry.sample(context.family)
    }

    func getSnapshot(in context: Context, completion: @escaping (UposathaEntry) -> Void) {
        if context.isPreview {
            completion(UposathaEntry.sample(context.family))
            return
        }
        completion(Self.build(now: Date(), family: context.family).entries[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UposathaEntry>) -> Void) {
        let built = Self.build(now: Date(), family: context.family)
        completion(Timeline(entries: built.entries, policy: .after(built.reload)))
    }

    // Entries for the next 24 hours: every quarter of an hour, every moment the data names (dawn, noon, sunset, the parts, an Uposatha's
    // start and end) and the hours of the counter. One timeline is one refresh of the system's budget; the widget counts nothing itself.
    static func build(now: Date, family: WidgetFamily) -> (entries: [UposathaEntry], reload: Date) {
        let key = WidgetFamilies.key(family)
        let loaded = WStore.load()
        guard let data = loaded, data.isUsable(at: now) else {
            // no data, stale data, or today not covered: "Open Uposatha" (the app's next start reloads the widgets)
            let empty = UposathaEntry(date: now, data: nil, layer: 0, month: 0, stale: loaded != nil, isSample: false)
            return ([empty], now.addingTimeInterval(3 * 3600))
        }
        let layer = WidgetFamilies.layer(key)
        // a month chosen on another day is forgotten, so the arrows start from today's month again
        if WStore.monthOffset(data, at: now) == 0 && WStore.layer("month") != 0 { WStore.setLayer("month", 0) }
        let dates = data.timelineDates(from: now)
        var list: [UposathaEntry] = []
        for d in dates {
            list.append(UposathaEntry(date: d, data: data, layer: layer, month: WStore.monthOffset(data, at: d), stale: false, isSample: false))
        }
        let last = dates.last ?? now
        return (list, max(last, now.addingTimeInterval(900)))
    }
}

// MARK: - The widgets

// The designs carry their own paddings (scaled with the design, as on Android), so the system's content margins of iOS 17 are off.
extension WidgetConfiguration {
    func dgNoMargins() -> some WidgetConfiguration {
        if #available(iOS 17.0, *) {
            return self.contentMarginsDisabled()
        }
        return self
    }
}

enum WidgetNames {
    static var ru: Bool { Loc.deviceLang() == "ru" }
    static var upoText: String { ru ? "Ближайшая упосатха, kala и календарь." : "The next Uposatha, kala and the calendar." }
    static var moonName: String { ru ? "Луна" : "Moon" }
    static var moonText: String { ru ? "Луна сейчас и сколько её освещено." : "The moon now and how much of it is lit." }
    static var dayName: String { ru ? "День и ночь" : "Day & night" }
    static var dayText: String { ru ? "Часть суток, kala и шкала от рассвета до рассвета." : "The part of the day, kala and the scale from dawn to dawn." }
}

struct UposathaWidget: Widget {
    let kind: String = "UposathaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UposathaProvider()) { entry in
            UposathaWidgetView(entry: entry)
        }
        .configurationDisplayName("Uposatha")
        .description(WidgetNames.upoText)
        .supportedFamilies(WidgetFamilies.uposatha)
        .dgNoMargins()
    }
}

struct UposathaMoonWidget: Widget {
    let kind: String = "UposathaMoonWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UposathaProvider()) { entry in
            MoonWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetNames.moonName)
        .description(WidgetNames.moonText)
        .supportedFamilies(WidgetFamilies.moon)
        .dgNoMargins()
    }
}

struct UposathaDayWidget: Widget {
    let kind: String = "UposathaDayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UposathaProvider()) { entry in
            DayWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetNames.dayName)
        .description(WidgetNames.dayText)
        .supportedFamilies([.systemSmall])
        .dgNoMargins()
    }
}

@main
struct UposathaWidgetBundle: WidgetBundle {
    var body: some Widget {
        UposathaWidget()
        UposathaMoonWidget()
        UposathaDayWidget()
    }
}
