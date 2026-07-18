import CryptoKit
import Foundation
import ImageIO
import UIKit
import WidgetKit

private final class WidgetRefreshGeneration: @unchecked Sendable {
    static let shared = WidgetRefreshGeneration()
    private let lock = NSLock()
    private var value: UInt64 = 0

    func begin() -> UInt64 {
        lock.withLock {
            value &+= 1
            return value
        }
    }

    func invalidate() { _ = begin() }

    func isCurrent(_ generation: UInt64) -> Bool {
        lock.withLock { value == generation }
    }
}

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
        guard store.authenticationState == .authenticated else { return }
        var snapshot = readSnapshot()
        if !force, Date.now.timeIntervalSince(snapshot.generatedAt) < 15 * 60 {
            return
        }
        let generation = WidgetRefreshGeneration.shared.begin()
        var didRefreshSection = false

        if let periods = try? await store.api.fetchDiningMenu(shopID: store.diningShopID, date: .now) {
            guard canCommit(generation, store: store) else { return }
            didRefreshSection = true
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
        var refreshedRecentShopIDs: Set<Int> = []
        for shop in store.cafeShops {
            guard canCommit(generation, store: store) else { return }
            let plan = store.cafePlansByShop[shop.id] ?? nil
            let orderable = CafeRules.state(for: plan).isOrderable
            guard let items = try? await store.api.fetchRecentOrders(shopID: shop.id) else { continue }
            guard canCommit(generation, store: store) else { return }
            refreshedRecentShopIDs.insert(shop.id)
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
        if !refreshedRecentShopIDs.isEmpty {
            didRefreshSection = true
            let retained = snapshot.recentOrders.filter { !refreshedRecentShopIDs.contains($0.shopID) }
            snapshot.recentOrders = (retained + recent)
                .sorted { ($0.lastOrderAt ?? "") > ($1.lastOrderAt ?? "") }
                .prefix(12)
                .map { $0 }
        }

        var favoriteItems: [AppWidgetCafeItem] = []
        var refreshedFavoriteShopIDs: Set<Int> = []
        let favoritesByShop = Dictionary(grouping: store.favorites, by: \.shopID)
        if favoritesByShop.isEmpty {
            snapshot.favorites = []
            didRefreshSection = true
        }
        for (shopID, favorites) in favoritesByShop {
            guard canCommit(generation, store: store) else { return }
            guard let shop = store.cafeShops.first(where: { $0.id == shopID }) else { continue }
            let favoriteIDs = Set(favorites.map(\.displayID))
            guard let menus = try? await store.api.fetchCafeMenu(shopID: shopID) else { continue }
            guard canCommit(generation, store: store) else { return }
            refreshedFavoriteShopIDs.insert(shopID)
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
        if !refreshedFavoriteShopIDs.isEmpty {
            didRefreshSection = true
            let retained = snapshot.favorites.filter { !refreshedFavoriteShopIDs.contains($0.shopID) }
            snapshot.favorites = (retained + favoriteItems).sorted {
                if $0.shopName == $1.shopName { return $0.name.localizedCompare($1.name) == .orderedAscending }
                return $0.shopName.localizedCompare($1.shopName) == .orderedAscending
            }
        }

        let thumbnailURLs = (snapshot.recentOrders + snapshot.favorites)
            .compactMap(\.thumbnailURL)
        await WidgetThumbnailCache.shared.prepare(urls: thumbnailURLs, generation: generation)
        guard canCommit(generation, store: store) else { return }

        guard didRefreshSection else { return }
        snapshot.generatedAt = .now
        write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        WidgetRefreshGeneration.shared.invalidate()
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

    private static func canCommit(_ generation: UInt64, store: AppStore) -> Bool {
        !Task.isCancelled
            && store.authenticationState == .authenticated
            && WidgetRefreshGeneration.shared.isCurrent(generation)
    }
}

private actor WidgetThumbnailCache {
    static let shared = WidgetThumbnailCache()
    private static let maximumConcurrentDownloads = 4
    private static let maximumSourceBytes: Int64 = 12 * 1_024 * 1_024

    nonisolated static func cacheKey(for url: URL?) -> String? {
        guard let url else { return nil }
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".image"
    }

    func prepare(urls: [URL], generation: UInt64) async {
        guard WidgetRefreshGeneration.shared.isCurrent(generation) else { return }
        guard let directory = WidgetSharedStorage.thumbnailDirectory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let uniqueURLs = Dictionary(urls.map { ($0.absoluteString, $0) }, uniquingKeysWith: { first, _ in first })
            .values
        let activeKeys = Set(uniqueURLs.compactMap(Self.cacheKey(for:)))

        let pending = uniqueURLs.prefix(24).compactMap { url -> (URL, String)? in
            guard let key = Self.cacheKey(for: url) else { return nil }
            let destination = directory.appendingPathComponent(key)
            return FileManager.default.fileExists(atPath: destination.path) ? nil : (url, key)
        }

        for batchStart in stride(from: 0, to: pending.count, by: Self.maximumConcurrentDownloads) {
            guard WidgetRefreshGeneration.shared.isCurrent(generation) else { return }
            let batchEnd = min(batchStart + Self.maximumConcurrentDownloads, pending.count)
            let batch = pending[batchStart..<batchEnd]
            let thumbnails = await withTaskGroup(
                of: (String, Data)?.self,
                returning: [(String, Data)].self
            ) { group in
                for (url, key) in batch {
                    group.addTask { await Self.downloadThumbnail(from: url, key: key) }
                }
                var values: [(String, Data)] = []
                for await value in group {
                    if let value { values.append(value) }
                }
                return values
            }

            guard WidgetRefreshGeneration.shared.isCurrent(generation) else { return }
            for (key, data) in thumbnails {
                guard WidgetRefreshGeneration.shared.isCurrent(generation) else { return }
                try? data.write(to: directory.appendingPathComponent(key), options: .atomic)
            }
        }

        guard WidgetRefreshGeneration.shared.isCurrent(generation) else { return }
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

    nonisolated private static func downloadThumbnail(from url: URL, key: String) async -> (String, Data)? {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-image-\(UUID().uuidString)", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 20
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  response.mimeType?.hasPrefix("image/") == true,
                  response.expectedContentLength <= maximumSourceBytes || response.expectedContentLength < 0
            else { return nil }

            FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: temporaryURL)
            defer { try? handle.close() }
            var receivedBytes: Int64 = 0
            var buffer = Data()
            buffer.reserveCapacity(64 * 1_024)
            for try await byte in bytes {
                receivedBytes += 1
                guard receivedBytes <= maximumSourceBytes else { return nil }
                buffer.append(byte)
                if buffer.count >= 64 * 1_024 {
                    try Task.checkCancellation()
                    try handle.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            guard receivedBytes > 0 else { return nil }
            if !buffer.isEmpty { try handle.write(contentsOf: buffer) }
            try handle.synchronize()
            guard let thumbnail = downsample(fileURL: temporaryURL, maxPixelSize: 256) else {
                return nil
            }
            return (key, thumbnail)
        } catch {
            return nil
        }
    }

    nonisolated private static func downsample(fileURL: URL, maxPixelSize: Int) -> Data? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.82)
    }
}
