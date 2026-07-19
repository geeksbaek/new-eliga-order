import AppIntents
import Foundation
import UIKit

enum WidgetSharedStorage {
    static let appGroup = "group.com.leeari95.NewEligaOrder"
    static let snapshotKey = "widget.snapshot.v1"
    static let thumbnailDirectoryName = "WidgetThumbnails"

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }
    static var thumbnailDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(thumbnailDirectoryName, isDirectory: true)
    }
}

struct WidgetDish: Codable, Hashable, Sendable {
    let name: String
    let badge: String?
    let isSoldOut: Bool
}

struct WidgetDiningPeriod: Codable, Hashable, Sendable {
    let title: String
    let startTime: String
    let endTime: String
    let dishes: [WidgetDish]
}

struct WidgetCafeItem: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let shopID: Int
    let displayID: Int
    let name: String
    let shopName: String
    let price: Int?
    let thumbnailURL: URL?
    let thumbnailKey: String?
    let lastOrderAt: String?
    let isSoldOut: Bool
    let isOrderable: Bool

    var menuURL: URL {
        var components = URLComponents()
        components.scheme = "neweligaorder"
        components.host = "menu"
        components.queryItems = [
            URLQueryItem(name: "shopID", value: String(shopID)),
            URLQueryItem(name: "displayID", value: String(displayID)),
        ]
        return components.url ?? URL(string: "neweligaorder://cafe")!
    }

    var quickOrderURL: URL {
        var components = URLComponents()
        components.scheme = "neweligaorder"
        components.host = "quick-order"
        components.queryItems = [
            URLQueryItem(name: "shopID", value: String(shopID)),
            URLQueryItem(name: "displayID", value: String(displayID)),
        ]
        return components.url ?? menuURL
    }
}

struct WidgetSnapshot: Codable, Hashable, Sendable {
    var generatedAt: Date
    var diningDate: Date
    var diningPeriods: [WidgetDiningPeriod]
    var recentOrders: [WidgetCafeItem]
    var favorites: [WidgetCafeItem]

    static let empty = WidgetSnapshot(
        generatedAt: .distantPast,
        diningDate: .distantPast,
        diningPeriods: [],
        recentOrders: [],
        favorites: []
    )

    static let preview = WidgetSnapshot(
        generatedAt: .now,
        diningDate: Calendar.current.startOfDay(for: .now),
        diningPeriods: [
            WidgetDiningPeriod(
                title: "중식",
                startTime: "11:30",
                endTime: "13:30",
                dishes: [
                    WidgetDish(name: "소불고기와 잡곡밥", badge: "밸런스바이츠", isSoldOut: false),
                    WidgetDish(name: "된장찌개", badge: nil, isSoldOut: false),
                    WidgetDish(name: "계절 샐러드", badge: nil, isSoldOut: false),
                ]
            ),
        ],
        recentOrders: [
            WidgetCafeItem(id: "5:1", shopID: 5, displayID: 1, name: "아이스 아메리카노", shopName: "kafé 5F", price: nil, thumbnailURL: nil, thumbnailKey: nil, lastOrderAt: "2026-07-18T12:40:00+09:00", isSoldOut: false, isOrderable: true),
            WidgetCafeItem(id: "5:2", shopID: 5, displayID: 2, name: "카페 라떼", shopName: "kafé 5F", price: nil, thumbnailURL: nil, thumbnailKey: nil, lastOrderAt: "2026-07-17T15:10:00+09:00", isSoldOut: false, isOrderable: true),
        ],
        favorites: [
            WidgetCafeItem(id: "5:1", shopID: 5, displayID: 1, name: "아이스 아메리카노", shopName: "kafé 5F", price: 1_500, thumbnailURL: nil, thumbnailKey: nil, lastOrderAt: nil, isSoldOut: false, isOrderable: true),
            WidgetCafeItem(id: "5:2", shopID: 5, displayID: 2, name: "카페 라떼", shopName: "kafé 5F", price: 2_000, thumbnailURL: nil, thumbnailKey: nil, lastOrderAt: nil, isSoldOut: false, isOrderable: true),
        ]
    )
}

enum WidgetThumbnailRepository {
    static func image(for key: String?) -> UIImage? {
        guard let key, let directory = WidgetSharedStorage.thumbnailDirectory else { return nil }
        return UIImage(contentsOfFile: directory.appendingPathComponent(key).path)
    }
}

enum WidgetSnapshotRepository {
    static func read() -> WidgetSnapshot {
        guard let data = WidgetSharedStorage.defaults?.data(forKey: WidgetSharedStorage.snapshotKey),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }
}

struct DiningSelection: Sendable {
    enum Timing: Sendable, Equatable {
        case current
        case upcoming
        case ended
    }

    let period: WidgetDiningPeriod
    let timing: Timing
}

enum DiningPeriodSelector {
    static func best(
        from periods: [WidgetDiningPeriod],
        at date: Date,
        calendar: Calendar = .current
    ) -> DiningSelection? {
        let resolved = periods.compactMap { period -> (WidgetDiningPeriod, Date, Date)? in
            guard let start = time(period.startTime, on: date, calendar: calendar),
                  let end = time(period.endTime, on: date, calendar: calendar)
            else { return nil }
            return (period, start, end)
        }.sorted { $0.1 < $1.1 }

        if let current = resolved.first(where: { date >= $0.1 && date < $0.2 }) {
            return DiningSelection(period: current.0, timing: .current)
        }
        if let upcoming = resolved.first(where: { date < $0.1 }) {
            return DiningSelection(period: upcoming.0, timing: .upcoming)
        }
        guard let last = resolved.last else { return periods.first.map { DiningSelection(period: $0, timing: .ended) } }
        return DiningSelection(period: last.0, timing: .ended)
    }

    static func nextRefresh(
        after date: Date,
        periods: [WidgetDiningPeriod],
        calendar: Calendar = .current
    ) -> Date {
        let boundaries = periods.flatMap { period in
            [time(period.startTime, on: date, calendar: calendar), time(period.endTime, on: date, calendar: calendar)]
                .compactMap { $0 }
                .filter { $0 > date.addingTimeInterval(5 * 60) }
        }
        let regularRefresh = date.addingTimeInterval(30 * 60)
        return boundaries.min().map { min($0, regularRefresh) } ?? regularRefresh
    }

    private static func time(_ value: String, on date: Date, calendar: Calendar) -> Date? {
        let values = value.split(separator: ":").compactMap { Int($0) }
        guard values.count >= 2 else { return nil }
        return calendar.date(bySettingHour: values[0], minute: values[1], second: 0, of: date)
    }
}

struct FavoriteMenuEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "즐겨찾기 메뉴"
    static let defaultQuery = FavoriteMenuQuery()

    let id: String
    let name: String
    let shopName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(shopName)", image: .init(systemName: "star.fill"))
    }
}

struct FavoriteMenuQuery: EntityQuery {
    func entities(for identifiers: [FavoriteMenuEntity.ID]) async throws -> [FavoriteMenuEntity] {
        WidgetSnapshotRepository.read().favorites
            .filter { identifiers.contains($0.id) }
            .map(FavoriteMenuEntity.init)
    }

    func suggestedEntities() async throws -> [FavoriteMenuEntity] {
        WidgetSnapshotRepository.read().favorites.map(FavoriteMenuEntity.init)
    }
}

private extension FavoriteMenuEntity {
    init(item: WidgetCafeItem) {
        id = item.id
        name = item.name
        shopName = item.shopName
    }
}

struct FavoriteWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "즐겨찾기 주문"
    static let description = IntentDescription("한 메뉴를 고르거나 즐겨찾기 전체를 표시합니다.")

    @Parameter(title: "대표 메뉴")
    var favorite: FavoriteMenuEntity?
}
