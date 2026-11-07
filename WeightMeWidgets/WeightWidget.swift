import Charts
import SwiftUI
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snapshot = WidgetSnapshot.load() ?? (context.isPreview ? .preview : nil)
        completion(SnapshotEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load())
        // The app reloads timelines whenever data changes; refresh at midnight so "today/yesterday" stays right.
        let midnight = Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 5), matchingPolicy: .nextTime) ?? .now.addingTimeInterval(86_400)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

@main
struct WeightMeWidgetBundle: WidgetBundle {
    var body: some Widget {
        WeightWidget()
    }
}

struct WeightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeightWidget", provider: SnapshotProvider()) { entry in
            WeightWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Weight")
        .description("Your latest weight and trend. Tap to log a new weight.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct WeightWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot, let latest = snapshot.latestKg {
            switch family {
            case .systemMedium: WidgetMediumView(snapshot: snapshot, latestKg: latest)
            case .accessoryRectangular: WidgetRectangularView(snapshot: snapshot, latestKg: latest)
            case .accessoryCircular: WidgetCircularView(snapshot: snapshot, latestKg: latest)
            case .accessoryInline: WidgetInlineView(snapshot: snapshot, latestKg: latest)
            default: WidgetSmallView(snapshot: snapshot, latestKg: latest)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "scalemass")
                    .font(.title2)
                Text("Open WeightMe")
                    .font(.caption)
            }
            .widgetURL(DeepLink.chart)
        }
    }
}

#Preview(as: .systemSmall) {
    WeightWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}

#Preview(as: .systemMedium) {
    WeightWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}
