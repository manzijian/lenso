import SwiftUI
import WidgetKit

struct LensoEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct LensoProvider: TimelineProvider {
    func placeholder(in context: Context) -> LensoEntry {
        LensoEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (LensoEntry) -> Void) {
        let snapshot = context.isPreview ? WidgetSnapshot.sample : (WidgetSnapshotStore.load() ?? .empty)
        completion(LensoEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LensoEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshotStore.load() ?? .empty
        let entry = LensoEntry(date: now, snapshot: snapshot)
        // 主 App 写入快照时会主动 reload；这里 20 分钟兜底一次。
        let next = Calendar.current.date(byAdding: .minute, value: 20, to: now)
            ?? now.addingTimeInterval(1200)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct LensoStatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LensoWidgetKind.identifier, provider: LensoProvider()) { entry in
            LensoWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetCardBackground()
                }
        }
        .configurationDisplayName("LENSO 截图记录")
        .description("今日概览、时段分布与本月热力图。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct LensoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LensoStatsWidget()
    }
}
