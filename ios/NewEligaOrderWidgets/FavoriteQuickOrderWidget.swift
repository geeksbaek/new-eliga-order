import AppIntents
import SwiftUI
import WidgetKit

struct FavoriteOrdersEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let selectedFavoriteID: String?

    var displayedItems: [WidgetCafeItem] {
        guard let selectedFavoriteID,
              let selected = snapshot.favorites.first(where: { $0.id == selectedFavoriteID })
        else { return snapshot.favorites }
        return [selected]
    }
}

struct FavoriteOrdersProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FavoriteOrdersEntry {
        FavoriteOrdersEntry(date: .now, snapshot: .preview, selectedFavoriteID: nil)
    }

    func snapshot(for configuration: FavoriteWidgetConfiguration, in context: Context) async -> FavoriteOrdersEntry {
        let snapshot = WidgetSnapshotRepository.read()
        return FavoriteOrdersEntry(
            date: .now,
            snapshot: snapshot == .empty ? .preview : snapshot,
            selectedFavoriteID: configuration.favorite?.id
        )
    }

    func timeline(for configuration: FavoriteWidgetConfiguration, in context: Context) async -> Timeline<FavoriteOrdersEntry> {
        let now = Date.now
        return Timeline(
            entries: [FavoriteOrdersEntry(
                date: now,
                snapshot: WidgetSnapshotRepository.read(),
                selectedFavoriteID: configuration.favorite?.id
            )],
            policy: .after(now.addingTimeInterval(30 * 60))
        )
    }
}

struct FavoriteQuickOrderWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FavoriteOrdersEntry

    var body: some View {
        let items = entry.displayedItems
        if let first = items.first, family == .systemSmall {
            favoriteSpotlight(first)
        } else if let first = items.first, items.count == 1 {
            selectedFavoriteSpotlight(first)
        } else if items.isEmpty {
            WidgetEmptyState(
                title: "즐겨찾기가 없어요",
                message: entry.snapshot == .empty ? "앱을 열어 즐겨찾기를 동기화하세요." : "카페 메뉴에서 별표를 눌러 추가하세요.",
                systemImage: "star"
            )
        } else {
            favoriteList(items)
        }
    }

    private func favoriteSpotlight(_ item: WidgetCafeItem) -> some View {
        Link(destination: destination(for: item)) {
            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(title: "즐겨찾기", systemImage: "star.fill")
                HStack(spacing: 10) {
                    WidgetThumbnail(item: item, size: 48, cornerRadius: 13)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(.headline)
                            .lineLimit(2)
                        HStack(spacing: 4) {
                            Text(item.shopName)
                            if let price = item.price {
                                Text("·")
                                Text(WidgetFormat.won(price))
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }
                WidgetStatusPill(
                    title: actionTitle(for: item),
                    systemImage: actionSystemImage(for: item),
                    isEmphasized: canQuickOrder(item)
                )
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityHint(actionTitle(for: item))
        }
        .privacySensitive()
    }

    private func selectedFavoriteSpotlight(_ item: WidgetCafeItem) -> some View {
        Link(destination: destination(for: item)) {
            VStack(alignment: .leading, spacing: 10) {
                WidgetHeader(
                    title: "선택한 즐겨찾기",
                    systemImage: "star.fill",
                    updatedAt: entry.snapshot.generatedAt
                )
                HStack(spacing: 14) {
                    WidgetThumbnail(
                        item: item,
                        size: family == .systemLarge ? 96 : 76,
                        cornerRadius: 18
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name)
                            .font(family == .systemLarge ? .title2.bold() : .headline)
                            .lineLimit(2)
                        Text(item.shopName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let price = item.price {
                            Text(WidgetFormat.won(price))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        WidgetStatusPill(
                            title: actionTitle(for: item),
                            systemImage: actionSystemImage(for: item),
                            isEmphasized: canQuickOrder(item)
                        )
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityHint(actionTitle(for: item))
        }
        .privacySensitive()
    }

    private func favoriteList(_ items: [WidgetCafeItem]) -> some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 7) {
            WidgetHeader(
                title: "즐겨찾기 바로 주문",
                systemImage: "star.fill",
                updatedAt: entry.snapshot.generatedAt
            )
            ForEach(items.prefix(family == .systemLarge ? 5 : 2)) { item in
                Link(destination: destination(for: item)) {
                    WidgetCafeRow(
                        item: item,
                        actionTitle: actionTitle(for: item),
                        actionSystemImage: actionSystemImage(for: item),
                        metadata: item.price.map { "\(item.shopName) · \(WidgetFormat.won($0))" } ?? item.shopName,
                        thumbnailSize: family == .systemLarge ? 42 : 38,
                        isActionEnabled: canQuickOrder(item)
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .privacySensitive()
    }

    private func destination(for item: WidgetCafeItem) -> URL {
        item.isOrderable && !item.isSoldOut ? item.quickOrderURL : item.menuURL
    }

    private func actionTitle(for item: WidgetCafeItem) -> String {
        if item.isSoldOut { return "품절" }
        return item.isOrderable ? "바로 주문" : "메뉴 보기"
    }

    private func actionSystemImage(for item: WidgetCafeItem) -> String {
        if item.isSoldOut { return "xmark.circle" }
        return item.isOrderable ? "bolt.fill" : "clock"
    }

    private func canQuickOrder(_ item: WidgetCafeItem) -> Bool {
        item.isOrderable && !item.isSoldOut
    }
}

struct FavoriteQuickOrderWidget: Widget {
    let kind = "com.leeari95.NewEligaOrder.widget.favorites"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: FavoriteWidgetConfiguration.self,
            provider: FavoriteOrdersProvider()
        ) { entry in
            FavoriteQuickOrderWidgetView(entry: entry)
                .eligaWidgetBackground()
                .widgetURL(URL(string: "neweligaorder://cafe"))
        }
        .configurationDisplayName("즐겨찾기 바로 주문")
        .description("즐겨찾기 메뉴를 보고 안전한 주문 확인 단계로 바로 이동합니다.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemSmall) {
    FavoriteQuickOrderWidget()
} timeline: {
    FavoriteOrdersEntry(date: .now, snapshot: .preview, selectedFavoriteID: nil)
}

#Preview(as: .systemMedium) {
    FavoriteQuickOrderWidget()
} timeline: {
    FavoriteOrdersEntry(date: .now, snapshot: .preview, selectedFavoriteID: nil)
}

#Preview(as: .systemLarge) {
    FavoriteQuickOrderWidget()
} timeline: {
    FavoriteOrdersEntry(date: .now, snapshot: .preview, selectedFavoriteID: nil)
}
