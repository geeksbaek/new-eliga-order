import SwiftUI
import WidgetKit

struct RecentOrdersEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct RecentOrdersProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentOrdersEntry {
        RecentOrdersEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentOrdersEntry) -> Void) {
        let snapshot = WidgetSnapshotRepository.read()
        completion(RecentOrdersEntry(date: .now, snapshot: snapshot == .empty ? .preview : snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentOrdersEntry>) -> Void) {
        let now = Date.now
        completion(Timeline(
            entries: [RecentOrdersEntry(date: now, snapshot: WidgetSnapshotRepository.read())],
            policy: .after(now.addingTimeInterval(30 * 60))
        ))
    }
}

struct RecentCafeOrdersWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecentOrdersEntry

    var body: some View {
        let items = entry.snapshot.recentOrders
        if let first = items.first, family == .systemSmall {
            recentSpotlight(first)
        } else if items.isEmpty {
            WidgetEmptyState(
                title: "최근 주문이 없어요",
                message: entry.snapshot == .empty ? "앱을 열어 주문 내역을 동기화하세요." : "카페에서 주문하면 여기에 표시돼요.",
                systemImage: "cup.and.saucer"
            )
        } else {
            recentList(items)
        }
    }

    private func recentSpotlight(_ item: WidgetCafeItem) -> some View {
        Link(destination: item.menuURL) {
            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(title: "최근 주문", systemImage: "clock.arrow.circlepath")
                HStack(spacing: 10) {
                    WidgetThumbnail(item: item, size: 48, cornerRadius: 13)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(.headline)
                            .lineLimit(2)
                        HStack(spacing: 4) {
                            Text(item.shopName)
                            if let relative = WidgetFormat.relativeOrderLabel(item.lastOrderAt, relativeTo: entry.date) {
                                Text("·")
                                Text(relative)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }
                WidgetStatusPill(title: "주문 보기", systemImage: "chevron.right")
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityHint("메뉴 상세 정보를 엽니다")
        }
        .privacySensitive()
    }

    private func recentList(_ items: [WidgetCafeItem]) -> some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 7) {
            WidgetHeader(
                title: "카페 최근 주문",
                systemImage: "clock.arrow.circlepath",
                updatedAt: entry.snapshot.generatedAt
            )
            ForEach(items.prefix(family == .systemLarge ? 5 : 2)) { item in
                Link(destination: item.menuURL) {
                    WidgetCafeRow(
                        item: item,
                        actionTitle: "보기",
                        actionSystemImage: "chevron.right",
                        metadata: metadata(for: item),
                        thumbnailSize: family == .systemLarge ? 42 : 38
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .privacySensitive()
    }

    private func metadata(for item: WidgetCafeItem) -> String {
        guard let relative = WidgetFormat.relativeOrderLabel(item.lastOrderAt, relativeTo: entry.date) else {
            return item.shopName
        }
        return "\(item.shopName) · \(relative)"
    }
}

struct RecentCafeOrdersWidget: Widget {
    let kind = "com.leeari95.NewEligaOrder.widget.recent"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecentOrdersProvider()) { entry in
            RecentCafeOrdersWidgetView(entry: entry)
                .eligaWidgetBackground()
                .widgetURL(URL(string: "neweligaorder://orders"))
        }
        .configurationDisplayName("카페 최근 주문")
        .description("최근 주문한 카페 메뉴를 빠르게 다시 확인합니다.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemSmall) {
    RecentCafeOrdersWidget()
} timeline: {
    RecentOrdersEntry(date: .now, snapshot: .preview)
}

#Preview(as: .systemMedium) {
    RecentCafeOrdersWidget()
} timeline: {
    RecentOrdersEntry(date: .now, snapshot: .preview)
}

#Preview(as: .systemLarge) {
    RecentCafeOrdersWidget()
} timeline: {
    RecentOrdersEntry(date: .now, snapshot: .preview)
}
