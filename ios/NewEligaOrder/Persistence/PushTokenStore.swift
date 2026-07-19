import Foundation

enum PushTokenStore {
    private static let appGroup = "group.com.leeari95.NewEligaOrder"
    private static let tokenKey = "push.apns-device-token.v1"
    static let fallbackRegistrationToken = "ios-native-new-eliga-order"
    static let didChangeNotification = Notification.Name("PushTokenStore.didChange")

    static var deviceToken: String? {
        get { UserDefaults(suiteName: appGroup)?.string(forKey: tokenKey) }
        set {
            let defaults = UserDefaults(suiteName: appGroup)
            guard defaults?.string(forKey: tokenKey) != newValue else { return }
            defaults?.set(newValue, forKey: tokenKey)
            NotificationCenter.default.post(name: didChangeNotification, object: newValue)
        }
    }

    static var registrationToken: String {
        deviceToken ?? fallbackRegistrationToken
    }
}
