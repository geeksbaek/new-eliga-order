import Foundation

struct AuthTokens: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
}

enum ShopKind: String, Codable, Sendable {
    case cafe = "CAFE"
    case cafeteria = "CAFETERIA"
    case restaurant = "RESTAURANT"
    case unknown
}

struct Shop: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let kind: ShopKind
    let isOpen: Bool

    var canOrder: Bool { kind == .cafe && id != 7 }
}

struct CafeCategory: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let isVisibleOnMobile: Bool
    let goodsCount: Int
}

struct CafeMenuItem: Identifiable, Hashable, Sendable {
    var id: Int { displayID }
    let displayID: Int
    let goodsID: Int?
    let name: String
    let categoryID: Int?
    let category: String
    let price: Int
    let isSoldOut: Bool
    let description: String?
    let calorie: Int?
    let nutrition: String?
    let label: String?
    let displayName: String
    let thumbnailURL: URL?

    func matches(search query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        return [name, category, description ?? "", displayName]
            .contains { $0.localizedCaseInsensitiveContains(normalized) }
    }
}

enum CafeMenuFilter {
    static func items(
        in menus: [CafeMenuItem],
        selectedCategoryID: Int?,
        searchText: String,
        favoriteDisplayIDs: Set<Int> = []
    ) -> [CafeMenuItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return prioritized(
                menus.filter { $0.matches(search: query) },
                favoriteDisplayIDs: favoriteDisplayIDs
            )
        }
        let filteredMenus = selectedCategoryID.map { categoryID in
            menus.filter { $0.categoryID == categoryID }
        } ?? menus
        return prioritized(filteredMenus, favoriteDisplayIDs: favoriteDisplayIDs)
    }

    static func sections(
        shops: [Shop],
        menusByShop: [Int: [CafeMenuItem]],
        searchText: String,
        favoriteDisplayIDsByShop: [Int: Set<Int>] = [:]
    ) -> [CafeMenuSearchSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return shops.compactMap { shop in
            let alphabeticalMatches = (menusByShop[shop.id] ?? [])
                .filter { $0.matches(search: query) }
                .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            let matches = prioritized(
                alphabeticalMatches,
                favoriteDisplayIDs: favoriteDisplayIDsByShop[shop.id] ?? []
            )
            guard !matches.isEmpty else { return nil }
            return CafeMenuSearchSection(shop: shop, items: matches)
        }
    }

    static func prioritized(
        _ menus: [CafeMenuItem],
        favoriteDisplayIDs: Set<Int>
    ) -> [CafeMenuItem] {
        menus.enumerated()
            .sorted { lhs, rhs in
                let lhsPriority = priority(
                    for: lhs.element,
                    favoriteDisplayIDs: favoriteDisplayIDs
                )
                let rhsPriority = priority(
                    for: rhs.element,
                    favoriteDisplayIDs: favoriteDisplayIDs
                )
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    static func prioritySections(
        from menus: [CafeMenuItem],
        favoriteDisplayIDs: Set<Int>
    ) -> [CafeMenuPrioritySection] {
        var grouped: [CafeMenuPriorityGroup: [CafeMenuItem]] = [:]
        for menu in menus {
            let group: CafeMenuPriorityGroup
            if favoriteDisplayIDs.contains(menu.displayID) {
                group = .favorite
            } else {
                switch menu.label?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
                case "BEST": group = .best
                case "NEW": group = .new
                default: group = .standard
                }
            }
            grouped[group, default: []].append(menu)
        }
        return CafeMenuPriorityGroup.allCases.compactMap { group in
            guard let items = grouped[group], !items.isEmpty else { return nil }
            return CafeMenuPrioritySection(group: group, items: items)
        }
    }

    private static func priority(
        for menu: CafeMenuItem,
        favoriteDisplayIDs: Set<Int>
    ) -> Int {
        if favoriteDisplayIDs.contains(menu.displayID) { return 0 }
        switch menu.label?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "BEST": return 1
        case "NEW": return 2
        default: return 3
        }
    }
}

enum CafeMenuPriorityGroup: String, CaseIterable, Sendable {
    case favorite
    case best
    case new
    case standard

    var title: String {
        switch self {
        case .favorite: "즐겨찾기"
        case .best: "BEST"
        case .new: "NEW"
        case .standard: "전체 메뉴"
        }
    }

    var systemImage: String {
        switch self {
        case .favorite: "star.fill"
        case .best: "flame.fill"
        case .new: "sparkles"
        case .standard: "cup.and.saucer"
        }
    }
}

struct CafeMenuPrioritySection: Identifiable, Sendable {
    var id: String { group.rawValue }
    let group: CafeMenuPriorityGroup
    let items: [CafeMenuItem]
}

struct CafeMenuSearchSection: Identifiable, Hashable, Sendable {
    var id: Int { shop.id }
    let shop: Shop
    let items: [CafeMenuItem]
}

struct OptionMenu: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let price: Int
}

struct GoodsOption: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let allowsMultipleSelection: Bool
    let menus: [OptionMenu]
}

struct GoodsVariant: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let displayName: String
    let price: Int
    let isSoldOut: Bool
    let description: String?
    let calorie: Int?
    let nutrition: String?
    let thumbnailURL: URL?
    let options: [GoodsOption]
}

struct MenuDetail: Hashable, Sendable {
    let displayID: Int
    let shopID: Int?
    let label: String?
    let thumbnailURL: URL?
    let variants: [GoodsVariant]
}

struct DiningMenuItem: Identifiable, Hashable, Sendable {
    var id: String { "\(name)|\(information)" }
    let name: String
    let calorie: Int?
    let nutrition: String
    let information: String
    let imageURL: URL?
    let isSoldOut: Bool

    var titlePresentation: DiningMenuTitlePresentation {
        DiningMenuTitlePresentation(rawValue: name)
    }
}

struct DiningMenuTitlePresentation: Equatable, Sendable {
    let displayName: String
    let badges: [String]

    init(rawValue: String) {
        let original = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var remainder = original
        var parsedBadges: [String] = []

        while remainder.first == "[", parsedBadges.count < 3,
              let closingBracket = remainder.firstIndex(of: "]") {
            let valueStart = remainder.index(after: remainder.startIndex)
            let value = remainder[valueStart..<closingBracket]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { break }

            parsedBadges.append(value)
            remainder = remainder[remainder.index(after: closingBracket)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if parsedBadges.isEmpty || remainder.isEmpty {
            displayName = original
            badges = []
        } else {
            displayName = remainder
            badges = parsedBadges
        }
    }
}

enum DiningPreferenceRules {
    static func containsExact(_ name: String, in preferences: [String]) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        return preferences.contains {
            $0.caseInsensitiveCompare(normalized) == .orderedSame
        }
    }

    static func toggling(_ name: String, in preferences: [String]) -> [String] {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return preferences }
        if containsExact(normalized, in: preferences) {
            return preferences.filter {
                $0.caseInsensitiveCompare(normalized) != .orderedSame
            }
        }
        return preferences + [normalized]
    }
}

struct DiningCourse: Identifiable, Hashable, Sendable {
    var id: String { "\(name)|\(origin)" }
    let name: String
    let price: Int
    let menus: [DiningMenuItem]
    let isSoldOut: Bool
    let congestion: String?
    let origin: String
}

struct DiningPeriod: Identifiable, Hashable, Sendable {
    var id: String { "\(time)|\(startTime)|\(endTime)" }
    let time: String
    let startTime: String
    let endTime: String
    let courses: [DiningCourse]
}

struct DiningMenuDetailContext: Hashable, Sendable {
    let meal: DiningMenuItem
    let sideDishSummary: String
    let courseName: String
    let coursePrice: Int
    let courseIsSoldOut: Bool
    let congestion: String?
    let origin: String
    let periodName: String
    let startTime: String
    let endTime: String
    let date: Date

    var isSoldOut: Bool { meal.isSoldOut || courseIsSoldOut }

    var servingTime: String {
        AppFormat.timeRange(start: startTime, end: endTime)
    }
}

enum DiningMenuFilter {
    static func periodsWithMeals(_ periods: [DiningPeriod]) -> [DiningPeriod] {
        periods.compactMap { period in
            let courses = period.courses.compactMap { course -> DiningCourse? in
                let meals = course.menus.filter {
                    !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                guard !meals.isEmpty else { return nil }
                return DiningCourse(
                    name: course.name,
                    price: course.price,
                    menus: meals,
                    isSoldOut: course.isSoldOut,
                    congestion: course.congestion,
                    origin: course.origin
                )
            }
            guard !courses.isEmpty else { return nil }
            return DiningPeriod(
                time: period.time,
                startTime: period.startTime,
                endTime: period.endTime,
                courses: courses
            )
        }
    }
}

struct CartOption: Hashable, Sendable {
    let option: String
    let value: String
}

struct CartItem: Identifiable, Hashable, Sendable {
    let id: Int
    let goodsID: Int
    let name: String
    let quantity: Int
    let price: Int
    let options: [CartOption]
    let thumbnailURL: URL?

    var lineTotal: Int { price * quantity }
}

struct Cart: Hashable, Sendable {
    let id: Int?
    let shopID: Int?
    let items: [CartItem]

    static let empty = Cart(id: nil, shopID: nil, items: [])
    var total: Int { items.reduce(0) { $0 + $1.lineTotal } }
    var itemCount: Int { items.reduce(0) { $0 + $1.quantity } }
}

struct SelectedOption: Hashable, Sendable {
    let optionID: Int
    let menuIDs: [Int]
}

struct CartRestoreLine: Hashable, Sendable {
    let goodsID: Int
    let quantity: Int
    let options: [SelectedOption]
}

struct CartSnapshot: Sendable {
    let cart: Cart
    let restoreLines: [CartRestoreLine]
}

struct PaymentReason: Identifiable, Hashable, Sendable {
    let id: Int
    let reason: String
}

struct OrderLine: Identifiable, Hashable, Sendable {
    var id: String { "\(name)|\(quantity)|\(price)|\(options.joined())" }
    let name: String
    let quantity: Int
    let price: Int
    let options: [String]
}

struct OrderHistory: Identifiable, Hashable, Sendable {
    let id: Int
    let orderNumber: String
    let shopID: Int
    let shopName: String
    let shopType: String
    let status: String
    let orderedAt: String
    let totalPaid: Int
    let items: [OrderLine]
}

struct OrderStatusSnapshot: Equatable, Sendable {
    let orderID: Int
    let orderNumber: String
    let status: String
}

struct CafeQuickItem: Identifiable, Hashable, Sendable {
    var id: String { "\(displayID)|\(goodsID)|\(lastOrderAt ?? "")" }
    let displayID: Int
    let goodsID: Int
    let name: String
    let quantity: Int
    let thumbnailURL: URL?
    let isSoldOut: Bool
    let isOnSale: Bool
    let lastOrderAt: String?
    let orderCountHint: Int?
}

struct CafeSalesPlan: Hashable, Sendable {
    let shopID: Int
    let isOpen: Bool
    let isBreakTime: Bool
    let isLastOrder: Bool
    let autoOpenTime: String?
    let autoCloseTime: String?
    let usesLastOrder: Bool
    let lastOrderTime: String?
    let openDays: [String]
    let isOrderPaused: Bool
}

enum CafeOrderState: Equatable, Sendable {
    case checking
    case open(hours: String)
    case closed(message: String)

    var isOrderable: Bool {
        if case .open = self { return true }
        return false
    }
}

struct FavoriteMenu: Codable, Hashable, Identifiable, Sendable {
    var id: String { "\(shopID):\(displayID)" }
    let shopID: Int
    let displayID: Int
    let name: String
}

struct QuickOrderSession: Sendable {
    let shopID: Int
    let goodsID: Int
    let quantity: Int
    let stashedLines: [CartRestoreLine]
}
