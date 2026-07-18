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
                VStack(alignment: .leading, spacing: 7) {
                    Text(selection.period.title)
                        .font(.title2.bold())
                        .lineLimit(1)
                    Label(
                        WidgetFormat.timeRange(start: selection.period.startTime, end: selection.period.endTime),
                        systemImage: "clock"
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    WidgetStatusPill(
                        title: availabilityLabel(selection.period.dishes),
                        systemImage: "checkmark.circle.fill",
                        isEmphasized: true
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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
                        .foregroundStyle(dish.isSoldOut ? .secondary : WidgetPalette.orange)
                        .widgetAccentable(!dish.isSoldOut)
                    if let badge = dish.badge, !badge.isEmpty {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WidgetPalette.orange)
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
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
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
