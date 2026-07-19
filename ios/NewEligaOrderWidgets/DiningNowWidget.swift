import SwiftUI
import WidgetKit

struct DiningEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot

    var relevance: TimelineEntryRelevance? {
        guard let selection = DiningPeriodSelector.best(from: snapshot.diningPeriods, at: date) else { return nil }
        return TimelineEntryRelevance(score: selection.timing == .current ? 100 : 50)
    }
}

struct DiningProvider: TimelineProvider {
    func placeholder(in context: Context) -> DiningEntry {
        DiningEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (DiningEntry) -> Void) {
        let snapshot = WidgetSnapshotRepository.read()
        completion(DiningEntry(date: .now, snapshot: snapshot == .empty ? .preview : snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DiningEntry>) -> Void) {
        let snapshot = WidgetSnapshotRepository.read()
        let now = Date.now
        let refresh = DiningPeriodSelector.nextRefresh(after: now, periods: snapshot.diningPeriods)
        completion(Timeline(entries: [DiningEntry(date: now, snapshot: snapshot)], policy: .after(refresh)))
    }
}

struct DiningNowWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let entry: DiningEntry

    private var selection: DiningSelection? {
        guard Calendar.current.isDate(entry.snapshot.diningDate, inSameDayAs: entry.date) else { return nil }
        return DiningPeriodSelector.best(from: entry.snapshot.diningPeriods, at: entry.date)
    }

    var body: some View {
        if let selection {
            switch family {
            case .accessoryRectangular:
                accessoryContent(selection)
            case .systemSmall:
                smallContent(selection)
            case .systemLarge:
                largeContent(selection)
            default:
                mediumContent(selection)
            }
        } else {
            WidgetEmptyState(
                title: "오늘 식단이 없어요",
                message: entry.snapshot == .empty ? "앱을 열어 최신 식단을 불러오세요." : "등록된 메뉴를 다시 확인해 주세요.",
                systemImage: "fork.knife.circle",
                compact: family == .accessoryRectangular
            )
        }
    }

    private func smallContent(_ selection: DiningSelection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: timingLabel(selection), systemImage: timingSystemImage(selection))
            Text(selection.period.title)
                .font(.title3.bold())
                .lineLimit(1)
            Text(WidgetFormat.timeRange(start: selection.period.startTime, end: selection.period.endTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Divider()
            dishList(selection.period.dishes, limit: 2)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func mediumContent(_ selection: DiningSelection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(
                title: timingLabel(selection),
                systemImage: "fork.knife",
                updatedAt: entry.snapshot.generatedAt
            )
            HStack(alignment: .top, spacing: 14) {
                // Only as wide as its own content (title/time/pill) — it
                // must not split the widget 50/50 with the menu list, which
                // is the actually important part and needs the real room.
                VStack(alignment: .leading, spacing: 7) {
                    Text(selection.period.title)
                        .font(.title2.bold())
                        .lineLimit(1)
                        .fixedSize()
                    Label(
                        WidgetFormat.timeRange(start: selection.period.startTime, end: selection.period.endTime),
                        systemImage: "clock"
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    WidgetStatusPill(
                        title: availabilityLabel(selection.period.dishes),
                        systemImage: "checkmark.circle.fill",
                        isEmphasized: true
                    )
                    .fixedSize()
                }

                Divider()

                VStack(alignment: .leading, spacing: 7) {
                    Text("메뉴")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    dishList(selection.period.dishes, limit: 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
    }

    private func largeContent(_ selection: DiningSelection) -> some View {
        let dishLimit = dynamicTypeSize.isAccessibilitySize ? 4 : 6
        let visibleDishes = Array(selection.period.dishes.prefix(dishLimit))
        let remainingDishCount = max(0, selection.period.dishes.count - visibleDishes.count)

        return VStack(alignment: .leading, spacing: 12) {
            WidgetHeader(
                title: timingLabel(selection),
                systemImage: timingSystemImage(selection),
                updatedAt: entry.snapshot.generatedAt
            )

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(selection.period.title)
                        .font(.title2.bold())
                        .lineLimit(1)
                    Label(
                        WidgetFormat.timeRange(
                            start: selection.period.startTime,
                            end: selection.period.endTime
                        ),
                        systemImage: "clock"
                    )
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    WidgetStatusPill(
                        title: availabilityLabel(selection.period.dishes),
                        systemImage: "checkmark.circle.fill",
                        isEmphasized: true
                    )
                }

                Spacer(minLength: 8)

                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(WidgetPalette.brand)
                    .widgetAccentable()
                    .accessibilityHidden(true)
            }
            .padding(13)
            .background(WidgetPalette.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))

            HStack {
                Text("메뉴 구성")
                    .font(.headline)
                Spacer()
                Text("총 \(selection.period.dishes.count)개")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(Array(visibleDishes.enumerated()), id: \.offset) { _, dish in
                    largeDishTile(dish)
                }
            }

            if remainingDishCount > 0 {
                Text("외 \(remainingDishCount)개 메뉴는 앱에서 확인할 수 있어요")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                Text("전체 식단 보기")
                    .font(.caption.weight(.semibold))
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(WidgetPalette.brand)
            .widgetAccentable()
            .accessibilityElement(children: .combine)
            .accessibilityHint("앱의 식단 화면을 엽니다")
        }
    }

    private func largeDishTile(_ dish: WidgetDish) -> some View {
        HStack(spacing: 7) {
            Image(systemName: dish.isSoldOut ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(dish.isSoldOut ? .secondary : WidgetPalette.brand)
                .widgetAccentable(!dish.isSoldOut)

            VStack(alignment: .leading, spacing: 1) {
                Text(dish.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .strikethrough(dish.isSoldOut)
                if let badge = dish.badge, !badge.isEmpty {
                    Text(badge)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityValue(dish.isSoldOut ? "품절" : "제공 가능")
    }

    private func accessoryContent(_ selection: DiningSelection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "fork.knife")
                Text(timingLabel(selection))
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 2)
                Text(WidgetFormat.minutePrecision(selection.period.startTime))
                    .font(.caption2.monospacedDigit())
            }
            Text(selection.period.title)
                .font(.headline)
                .lineLimit(1)
            if let first = selection.period.dishes.first(where: { !$0.isSoldOut }) ?? selection.period.dishes.first {
                Text(first.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func dishList(_ dishes: [WidgetDish], limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(dishes.prefix(limit), id: \.name) { dish in
                HStack(spacing: 6) {
                    Image(systemName: dish.isSoldOut ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(dish.isSoldOut ? .secondary : WidgetPalette.brand)
                        .widgetAccentable(!dish.isSoldOut)
                    if let badge = dish.badge, !badge.isEmpty {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(WidgetPalette.brand.opacity(0.14), in: Capsule())
                            .lineLimit(1)
                    }
                    Text(dish.name)
                        .font(.caption)
                        .lineLimit(1)
                        .strikethrough(dish.isSoldOut)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(dish.isSoldOut ? "품절" : "제공 가능")
            }
        }
    }

    private func timingLabel(_ selection: DiningSelection) -> String {
        switch selection.timing {
        case .current: "지금 먹기 좋은 메뉴"
        case .upcoming: "다음 식단"
        case .ended: "오늘 마지막 식단"
        }
    }

    private func timingSystemImage(_ selection: DiningSelection) -> String {
        switch selection.timing {
        case .current: "sparkles"
        case .upcoming: "clock"
        case .ended: "checkmark"
        }
    }

    private func availabilityLabel(_ dishes: [WidgetDish]) -> String {
        let availableCount = dishes.filter { !$0.isSoldOut }.count
        return availableCount > 0 ? "\(availableCount)개 제공" : "모두 품절"
    }
}

struct DiningNowWidget: Widget {
    let kind = "com.leeari95.NewEligaOrder.widget.dining"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DiningProvider()) { entry in
            DiningNowWidgetView(entry: entry)
                .eligaWidgetBackground()
                .widgetURL(URL(string: "neweligaorder://dining"))
        }
        .configurationDisplayName("지금 식단")
        .description("현재 시간에 가장 적절한 사내 식단을 보여줍니다.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

#Preview(as: .systemSmall) {
    DiningNowWidget()
} timeline: {
    DiningEntry(date: .now, snapshot: .preview)
}

#Preview(as: .systemMedium) {
    DiningNowWidget()
} timeline: {
    DiningEntry(date: .now, snapshot: .preview)
}

#Preview(as: .systemLarge) {
    DiningNowWidget()
} timeline: {
    DiningEntry(date: .now, snapshot: .preview)
}
