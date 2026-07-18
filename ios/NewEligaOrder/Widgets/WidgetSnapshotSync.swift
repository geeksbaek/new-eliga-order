import CryptoKit
import Foundation
import WidgetKit

private enum WidgetSharedStorage {
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

private struct AppWidgetDish: Codable, Sendable {
    let name: String
    let badge: String?
    let isSoldOut: Bool
}

private struct AppWidgetDiningPeriod: Codable, Sendable {
    let title: String
    let startTime: String
    let endTime: String
    let dishes: [AppWidgetDish]
}

private struct AppWidgetCafeItem: Codable, Sendable {
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
}

private struct AppWidgetSnapshot: Codable, Sendable {
    var generatedAt: Date
    var diningDate: Date
    var diningPeriods: [AppWidgetDiningPeriod]
    var recentOrders: [AppWidgetCafeItem]
    var favorites: [AppWidgetCafeItem]

    static let empty = AppWidgetSnapshot(
        generatedAt: .distantPast,
        diningDate: .distantPast,
        diningPeriods: [],
        recentOrders: [],
        favorites: []
    )
}

@MainActor
enum WidgetSnapshotSync {
    static func refresh(using store: AppStore, force: Bool = false) async {
        var snapshot = readSnapshot()
        if !force, Date.now.timeIntervalSince(snapshot.generatedAt) < 15 * 60 {
            return
        }

        if let periods = try? await store.api.fetchDiningMenu(shopID: store.diningShopID, date: .now) {
            let visiblePeriods = DiningMenuFilter.periodsWithMeals(periods)
            snapshot.diningDate = Calendar.current.startOfDay(for: .now)
            snapshot.diningPeriods = visiblePeriods.map { period in
                AppWidgetDiningPeriod(
                    title: period.time.isEmpty ? "오늘의 식단" : period.time,
                    startTime: period.startTime,
                    endTime: period.endTime,
                    dishes: period.courses.flatMap(\.menus).map {
                        AppWidgetDish(
                            name: $0.titlePresentation.displayName,
                            badge: $0.titlePresentation.badges.first,
                            isSoldOut: $0.isSoldOut
                        )
                    }
                )
            }
        }

        var recent: [AppWidgetCafeItem] = []
        for shop in store.cafeShops {
            let plan = store.cafePlansByShop[shop.id] ?? nil
            let orderable = CafeRules.state(for: plan).isOrderable
            let items = (try? await store.api.fetchRecentOrders(shopID: shop.id)) ?? []
            recent.append(contentsOf: items.prefix(5).map { item in
                AppWidgetCafeItem(
                    id: "\(shop.id):\(item.displayID)",
                    shopID: shop.id,
                    displayID: item.displayID,
                    name: item.name,
                    shopName: shop.name,
                    price: nil,
                    thumbnailURL: item.thumbnailURL,
                    thumbnailKey: WidgetThumbnailCache.cacheKey(for: item.thumbnailURL),
                    lastOrderAt: item.lastOrderAt,
                    isSoldOut: item.isSoldOut || !item.isOnSale,
                    isOrderable: orderable
                )
            })
        }
        if !recent.isEmpty {
            snapshot.recentOrders = recent
                .sorted { ($0.lastOrderAt ?? "") > ($1.lastOrderAt ?? "") }
                .prefix(12)
                .map { $0 }
        }

        var favoriteItems: [AppWidgetCafeItem] = []
        let favoritesByShop = Dictionary(grouping: store.favorites, by: \.shopID)
        for (shopID, favorites) in favoritesByShop {
            guard let shop = store.cafeShops.first(where: { $0.id == shopID }) else { continue }
            let favoriteIDs = Set(favorites.map(\.displayID))
            let menus = (try? await store.api.fetchCafeMenu(shopID: shopID)) ?? []
            let plan = store.cafePlansByShop[shopID] ?? nil
            let orderable = CafeRules.state(for: plan).isOrderable
            favoriteItems.append(contentsOf: menus.filter { favoriteIDs.contains($0.displayID) }.map { item in
                AppWidgetCafeItem(
                    id: "\(shopID):\(item.displayID)",
                    shopID: shopID,
                    displayID: item.displayID,
                    name: item.name,
                    shopName: shop.name,
                    price: item.price,
                    thumbnailURL: item.thumbnailURL,
                    thumbnailKey: WidgetThumbnailCache.cacheKey(for: item.thumbnailURL),
                    lastOrderAt: nil,
                    isSoldOut: item.isSoldOut || item.goodsID == nil,
                    isOrderable: orderable
                )
            })
        }
        snapshot.favorites = favoriteItems.sorted {
            if $0.shopName == $1.shopName { return $0.name.localizedCompare($1.name) == .orderedAscending }
            return $0.shopName.localizedCompare($1.shopName) == .orderedAscending
        }

        let thumbnailURLs = (snapshot.recentOrders + snapshot.favorites)
            .compactMap(\.thumbnailURL)
        await WidgetThumbnailCache.shared.prepare(urls: thumbnailURLs)

        snapshot.generatedAt = .now
        write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        WidgetSharedStorage.defaults?.removeObject(forKey: WidgetSharedStorage.snapshotKey)
        WidgetThumbnailCache.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func readSnapshot() -> AppWidgetSnapshot {
        guard let data = WidgetSharedStorage.defaults?.data(forKey: WidgetSharedStorage.snapshotKey),
              let snapshot = try? JSONDecoder().decode(AppWidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    private static func write(_ snapshot: AppWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        WidgetSharedStorage.defaults?.set(data, forKey: WidgetSharedStorage.snapshotKey)
    }
}

private actor WidgetThumbnailCache {
    static let shared = WidgetThumbnailCache()

    nonisolated static func cacheKey(for url: URL?) -> String? {
        guard let url else { return nil }
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".image"
    }

    func prepare(urls: [URL]) async {
        guard let directory = WidgetSharedStorage.thumbnailDirectory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let uniqueURLs = Dictionary(urls.map { ($0.absoluteString, $0) }, uniquingKeysWith: { first, _ in first })
            .values
        let activeKeys = Set(uniqueURLs.compactMap(Self.cacheKey(for:)))

        await withTaskGroup(of: Void.self) { group in
            for url in uniqueURLs.prefix(24) {
                guard let key = Self.cacheKey(for: url) else { continue }
                let destination = directory.appendingPathComponent(key)
                guard !FileManager.default.fileExists(atPath: destination.path) else { continue }

                group.addTask {
                    do {
                        let (data, response) = try await URLSession.shared.data(from: url)
                        guard let response = response as? HTTPURLResponse,
                              (200..<300).contains(response.statusCode),
                              !data.isEmpty,
                              data.count <= 1_000_000
                        else { return }
                        try data.write(to: destination, options: .atomic)
                    } catch {
                        return
                    }
                }
            }
        }

        guard let cached = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in cached where !activeKeys.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    nonisolated static func clear() {
        guard let directory = WidgetSharedStorage.thumbnailDirectory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}
