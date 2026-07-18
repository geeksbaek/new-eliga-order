import Foundation
import Darwin

struct PreferencesStore: @unchecked Sendable {
    private enum Key {
        static let rememberedUserID = "eliga.userId"
        static let lastShopID = "eliga.lastShopId"
        static let favorites = "eliga.cafe.favorites"
        static let diningPreferences = "eliga.dining.preferences"
        static let lunchNotification = "eliga.notification.lunch"
        static let dinnerNotification = "eliga.notification.dinner"
        static let lunchTime = "eliga.notification.lunch.time"
        static let dinnerTime = "eliga.notification.dinner.time"
        static let quickOrderSession = "eliga.quickOrder.recovery"
    }

    private let defaults: UserDefaults
    private let quickOrderJournalURL: URL

    init(defaults: UserDefaults = .standard, quickOrderJournalURL: URL? = nil) {
        self.defaults = defaults
        self.quickOrderJournalURL = quickOrderJournalURL ?? Self.defaultQuickOrderJournalURL
    }

    var rememberedUserID: String {
        get { defaults.string(forKey: Key.rememberedUserID) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: Key.rememberedUserID) }
    }

    var lastShopID: Int? {
        get {
            guard defaults.object(forKey: Key.lastShopID) != nil else { return nil }
            return defaults.integer(forKey: Key.lastShopID)
        }
        nonmutating set { defaults.set(newValue, forKey: Key.lastShopID) }
    }

    var favorites: Set<FavoriteMenu> {
        get {
            guard let data = defaults.data(forKey: Key.favorites),
                  let decoded = try? JSONDecoder().decode(Set<FavoriteMenu>.self, from: data)
            else { return [] }
            return decoded
        }
        nonmutating set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.favorites) }
    }

    var diningPreferences: [String] {
        get { defaults.stringArray(forKey: Key.diningPreferences) ?? [] }
        nonmutating set { defaults.set(newValue, forKey: Key.diningPreferences) }
    }

    var lunchNotificationEnabled: Bool {
        get { defaults.bool(forKey: Key.lunchNotification) }
        nonmutating set { defaults.set(newValue, forKey: Key.lunchNotification) }
    }

    var dinnerNotificationEnabled: Bool {
        get { defaults.bool(forKey: Key.dinnerNotification) }
        nonmutating set { defaults.set(newValue, forKey: Key.dinnerNotification) }
    }

    var lunchTime: Date {
        get { defaults.object(forKey: Key.lunchTime) as? Date ?? Self.date(hour: 11, minute: 20) }
        nonmutating set { defaults.set(newValue, forKey: Key.lunchTime) }
    }

    var dinnerTime: Date {
        get { defaults.object(forKey: Key.dinnerTime) as? Date ?? Self.date(hour: 17, minute: 20) }
        nonmutating set { defaults.set(newValue, forKey: Key.dinnerTime) }
    }

    var quickOrderSession: QuickOrderSession? {
        get {
            let data = (try? Data(contentsOf: quickOrderJournalURL, options: .mappedIfSafe))
                ?? defaults.data(forKey: Key.quickOrderSession)
            guard let data else { return nil }
            return try? JSONDecoder().decode(QuickOrderSession.self, from: data)
        }
        nonmutating set {
            try? saveQuickOrderSession(newValue)
        }
    }

    /// 서버 장바구니를 변경하기 전에 복구 정보를 atomic file에 기록하고 fsync한다.
    /// UserDefaults는 마이그레이션/호환용 보조 사본일 뿐, 복구의 내구성 경계로 사용하지 않는다.
    nonmutating func saveQuickOrderSession(_ session: QuickOrderSession?) throws {
        let directory = quickOrderJournalURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )

        if let session {
            let data = try JSONEncoder().encode(session)
            try data.write(to: quickOrderJournalURL, options: .atomic)
            let handle = try FileHandle(forWritingTo: quickOrderJournalURL)
            try handle.synchronize()
            try handle.close()
            try Self.synchronizeDirectory(directory)
            defaults.set(data, forKey: Key.quickOrderSession)
        } else {
            if FileManager.default.fileExists(atPath: quickOrderJournalURL.path) {
                try FileManager.default.removeItem(at: quickOrderJournalURL)
                try Self.synchronizeDirectory(directory)
            }
            defaults.removeObject(forKey: Key.quickOrderSession)
        }
    }

    private static var defaultQuickOrderJournalURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("com.leeari95.NewEligaOrder", isDirectory: true)
            .appendingPathComponent("quick-order-recovery.json", isDirectory: false)
    }

    private static func synchronizeDirectory(_ directory: URL) throws {
        let descriptor = open(directory.path, O_RDONLY)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    private static func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
    }
}
