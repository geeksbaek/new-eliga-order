import Foundation

enum PushTokenStore {
    private static let appGroup = "group.com.leeari95.NewEligaOrder"
    private static let tokenKey = "push.apns-device-token.v1"

    static var deviceToken: String? {
        get { UserDefaults(suiteName: appGroup)?.string(forKey: tokenKey) }
        set { UserDefaults(suiteName: appGroup)?.set(newValue, forKey: tokenKey) }
    }
}
