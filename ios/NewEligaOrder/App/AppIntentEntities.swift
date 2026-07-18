import AppIntents
import CoreSpotlight
import Foundation

struct CafeMenuIndexRecord: Codable, Hashable, Sendable {
    let shopID: Int
    let displayID: Int
    let name: String
    let shopName: String
    let category: String
    let isSoldOut: Bool

    var id: String { "\(shopID):\(displayID)" }
}

struct DiningMealIndexRecord: Codable, Hashable, Sendable {
    let id: String
    let shopID: Int
    let name: String
    let calorie: Int?
    let nutrition: String
    let information: String
    let imageURL: URL?
    let mealIsSoldOut: Bool
    let courseName: String
    let coursePrice: Int
    let courseIsSoldOut: Bool
    let congestion: String?
    let origin: String
    let periodName: String
    let startTime: String
    let endTime: String
    let date: Date

    var detailContext: DiningMenuDetailContext {
        DiningMenuDetailContext(
            meal: DiningMenuItem(
                name: name,
                calorie: calorie,
                nutrition: nutrition,
                information: information,
                imageURL: imageURL,
                isSoldOut: mealIsSoldOut
            ),
            sideDishSummary: "",
            courseName: courseName,
            coursePrice: coursePrice,
            courseIsSoldOut: courseIsSoldOut,
            congestion: congestion,
            origin: origin,
            periodName: periodName,
            startTime: startTime,
            endTime: endTime,
            date: date
        )
    }
}

enum AppIntentEntityRepository {
    private static let appGroup = "group.com.leeari95.NewEligaOrder"
    private static let cafeKey = "app-intents.cafe-menus.v1"
    private static let diningKey = "app-intents.dining-meals.v1"

    static func cafeRecords() -> [CafeMenuIndexRecord] {
        decode([CafeMenuIndexRecord].self, key: cafeKey) ?? []
    }

    static func diningRecords() -> [DiningMealIndexRecord] {
        decode([DiningMealIndexRecord].self, key: diningKey) ?? []
    }

    static func save(cafe: [CafeMenuIndexRecord], dining: [DiningMealIndexRecord]) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        if let data = try? JSONEncoder().encode(cafe) { defaults.set(data, forKey: cafeKey) }
        if let data = try? JSONEncoder().encode(dining) { defaults.set(data, forKey: diningKey) }
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

struct CafeMenuEntity: IndexedEntity, Hashable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "카페 메뉴"
    static let defaultQuery = CafeMenuEntityQuery()

    let id: String
    let shopID: Int
    let displayID: Int
    let name: String
    let shopName: String
    let category: String
    let isSoldOut: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(shopName) · \(isSoldOut ? "품절" : category)",
            image: .init(systemName: isSoldOut ? "xmark.circle.fill" : "cup.and.saucer.fill")
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.contentDescription = "\(shopName)의 \(category) 메뉴"
        attributes.keywords = [name, shopName, category, "카페", "음료"]
        attributes.contentURL = URL(string: "neweligaorder://menu?shopID=\(shopID)&displayID=\(displayID)")
        return attributes
    }
}

struct CafeMenuEntityQuery: EntityQuery {
    func entities(for identifiers: [CafeMenuEntity.ID]) async throws -> [CafeMenuEntity] {
        let identifiers = Set(identifiers)
        return AppIntentEntityRepository.cafeRecords()
            .filter { identifiers.contains($0.id) }
            .map(CafeMenuEntity.init)
    }

    func suggestedEntities() async throws -> [CafeMenuEntity] {
        AppIntentEntityRepository.cafeRecords()
            .filter { !$0.isSoldOut }
            .prefix(40)
            .map(CafeMenuEntity.init)
    }

}

private extension CafeMenuEntity {
    init(record: CafeMenuIndexRecord) {
        id = record.id
        shopID = record.shopID
        displayID = record.displayID
        name = record.name
        shopName = record.shopName
        category = record.category
        isSoldOut = record.isSoldOut
    }
}

struct DiningMealEntity: IndexedEntity, Hashable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "오늘 식사"
    static let defaultQuery = DiningMealEntityQuery()

    let id: String
    let shopID: Int
    let name: String
    let courseName: String
    let periodName: String
    let date: Date

    private var title: DiningMenuTitlePresentation {
        DiningMenuTitlePresentation(rawValue: name)
    }

    var displayRepresentation: DisplayRepresentation {
        let badgePrefix = title.badges.isEmpty ? "" : "\(title.badges.joined(separator: " · ")) · "
        return DisplayRepresentation(
            title: "\(title.displayName)",
            subtitle: "\(badgePrefix)\(periodName) · \(courseName)",
            image: .init(systemName: "fork.knife")
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.contentDescription = "오늘 \(periodName) \(courseName) 식단"
        attributes.keywords = [name, title.displayName] + title.badges + [courseName, periodName, "오늘", "식단"]
        attributes.contentURL = URL(string: "neweligaorder://dining")
        return attributes
    }
}

struct DiningMealEntityQuery: EntityQuery {
    func entities(for identifiers: [DiningMealEntity.ID]) async throws -> [DiningMealEntity] {
        let identifiers = Set(identifiers)
        return AppIntentEntityRepository.diningRecords()
            .filter { identifiers.contains($0.id) }
            .map(DiningMealEntity.init)
    }

    func suggestedEntities() async throws -> [DiningMealEntity] {
        AppIntentEntityRepository.diningRecords().prefix(30).map(DiningMealEntity.init)
    }

}

private extension DiningMealEntity {
    init(record: DiningMealIndexRecord) {
        id = record.id
        shopID = record.shopID
        name = record.name
        courseName = record.courseName
        periodName = record.periodName
        date = record.date
    }
}

@MainActor
enum AppIntentSearchIndexer {
    static let indexName = "NewEligaOrder.Content"

    static func refresh(using store: AppStore) async {
        var cafeRecords: [CafeMenuIndexRecord] = []
        for shop in store.cafeShops {
            guard let menus = try? await store.api.fetchCafeMenu(shopID: shop.id) else { continue }
            cafeRecords.append(contentsOf: menus.compactMap { menu in
                guard menu.displayID > 0 else { return nil }
                return CafeMenuIndexRecord(
                    shopID: shop.id,
                    displayID: menu.displayID,
                    name: menu.name,
                    shopName: shop.name,
                    category: menu.category.isEmpty ? "카페 메뉴" : menu.category,
                    isSoldOut: menu.isSoldOut || menu.goodsID == nil
                )
            })
        }

        let today = Calendar.current.startOfDay(for: .now)
        let periods = (try? await store.api.fetchDiningMenu(shopID: store.diningShopID, date: today)) ?? []
        let diningRecords = DiningMenuFilter.periodsWithMeals(periods).flatMap { period in
            period.courses.flatMap { course in
                course.menus.map { meal in
                    DiningMealIndexRecord(
                        id: Self.diningIdentifier(
                            date: today,
                            period: period.time,
                            course: course.name,
                            meal: meal.name
                        ),
                        shopID: store.diningShopID,
                        name: meal.name,
                        calorie: meal.calorie,
                        nutrition: meal.nutrition,
                        information: meal.information,
                        imageURL: meal.imageURL,
                        mealIsSoldOut: meal.isSoldOut,
                        courseName: course.name,
                        coursePrice: course.price,
                        courseIsSoldOut: course.isSoldOut,
                        congestion: course.congestion,
                        origin: course.origin,
                        periodName: period.time.isEmpty ? "오늘의 식단" : period.time,
                        startTime: period.startTime,
                        endTime: period.endTime,
                        date: today
                    )
                }
            }
        }

        AppIntentEntityRepository.save(cafe: cafeRecords, dining: diningRecords)

        let index = CSSearchableIndex(name: indexName)
        do {
            try await index.deleteAllSearchableItems()
            try await index.indexAppEntities(cafeRecords.map(CafeMenuEntity.init))
            try await index.indexAppEntities(diningRecords.map(DiningMealEntity.init))
        } catch {
            // The local entity cache still powers Siri and Shortcuts when Spotlight indexing is unavailable.
        }
    }

    static func clear() {
        AppIntentEntityRepository.save(cafe: [], dining: [])
        Task {
            try? await CSSearchableIndex(name: indexName).deleteAllSearchableItems()
        }
    }

    private static func diningIdentifier(date: Date, period: String, course: String, meal: String) -> String {
        "\(date.timeIntervalSince1970)|\(period)|\(course)|\(meal)"
    }
}
