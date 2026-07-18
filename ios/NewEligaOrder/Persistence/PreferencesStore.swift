import Foundation

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
    }

    private let defaults = UserDefaults.standard

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

    private static func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
    }
}
