import WidgetKit
import SwiftUI

// MARK: - Families

enum WidgetFamilies {
    static var supported: [WidgetFamily] {
        var list: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
        if #available(iOS 16.0, *) {
            list.append(contentsOf: [.accessoryRectangular, .accessoryCircular, .accessoryInline])
        }
        return list
    }

    static func isSystem(_ f: WidgetFamily) -> Bool {
        switch f {
        case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge: return true
        default: return false
        }
    }

    // The key the layer of a widget size is kept under (App Group defaults "layer.<key>")
    static func key(_ f: WidgetFamily) -> String {
        switch f {
        case .systemSmall: return "small"
        case .systemMedium: return "medium"
        case .systemLarge: return "large"
        default: return String(describing: f)   // accessoryRectangular, accessoryCircular, accessoryInline
        }
    }

    static func layerCount(_ key: String) -> Int {
        switch key {
        case "small", "medium", "large", "accessoryCircular": return 3
        case "accessoryRectangular": return 2
        default: return 1
        }
    }
}

// MARK: - Timeline

struct UposathaEntry: TimelineEntry {
    let date: Date
    let data: WData?      // nil: nothing usable, the widget says "Open Uposatha"
    let layer: Int
    let isSample: Bool

    // The bundled sample, shown at the moment it was made: for the placeholder and the widget gallery.
    static func sample() -> UposathaEntry {
        let data = WStore.sample()
        let when = data?.generatedAt.flatMap({ WTime.parseISO($0) }) ?? Date()
        return UposathaEntry(date: when, data: data, layer: 0, isSample: true)
    }
}

struct UposathaProvider: TimelineProvider {
    func placeholder(in context: Context) -> UposathaEntry {
        UposathaEntry.sample()
    }

    func getSnapshot(in context: Context, completion: @escaping (UposathaEntry) -> Void) {
        if context.isPreview {
            completion(UposathaEntry.sample())
            return
        }
        completion(Self.build(now: Date(), family: context.family).entries[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UposathaEntry>) -> Void) {
        let built = Self.build(now: Date(), family: context.family)
        completion(Timeline(entries: built.entries, policy: .after(built.reload)))
    }

    // Entries for the next 24 hours: every half hour, every moment the data names (dawn, noon, sunset, the parts, an Uposatha's
    // start and end) and the hours of the counter. One timeline is one refresh of the system's budget; the widget counts nothing itself.
    static func build(now: Date, family: WidgetFamily) -> (entries: [UposathaEntry], reload: Date) {
        let key = WidgetFamilies.key(family)
        guard let data = WStore.load(), data.isUsable(at: now) else {
            // no data, stale data, or today not covered: "Open Uposatha" (the app's next start reloads the widgets)
            return ([UposathaEntry(date: now, data: nil, layer: 0, isSample: false)], now.addingTimeInterval(3 * 3600))
        }
        let count = WidgetFamilies.layerCount(key)
        let layer = min(max(WStore.layer(key), 0), count - 1)
        let dates = data.timelineDates(from: now)
        let list = dates.map { UposathaEntry(date: $0, data: data, layer: layer, isSample: false) }
        let last = dates.last ?? now
        return (list, max(last, now.addingTimeInterval(900)))
    }
}

// MARK: - The widget

struct UposathaWidget: Widget {
    let kind: String = "UposathaWidget"

    private var descriptionText: String {
        Loc.deviceLang() == "ru" ? "Ближайшая упосатха, kala и месяц." : "The next Uposatha, kala and the month."
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UposathaProvider()) { entry in
            UposathaWidgetView(entry: entry)
        }
        .configurationDisplayName("Uposatha")
        .description(descriptionText)
        .supportedFamilies(WidgetFamilies.supported)
    }
}

@main
struct UposathaWidgetBundle: WidgetBundle {
    var body: some Widget {
        UposathaWidget()
    }
}
