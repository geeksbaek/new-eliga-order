import UIKit
@preconcurrency import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BackgroundRefreshCoordinator.register()
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushTokenStore.deviceToken = deviceToken.map { String(format: "%02x", $0) }.joined()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // The simulator and devices without a valid push profile can fail here; local notifications remain available.
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        let values = PushNotificationCoordinator.orderValues(from: userInfo)
        return await PushNotificationCoordinator.process(values: values)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let values = PushNotificationCoordinator.orderValues(from: response.notification.request.content.userInfo)
        await PushNotificationCoordinator.openOrder(values: values)
    }
}

@MainActor
enum PushNotificationCoordinator {
    struct OrderValues: Sendable {
        let orderID: Int?
        let status: String?
        let orderNumber: String?
    }

    static func prepareForAuthentication() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    static func didSignOut() {
        UIApplication.shared.unregisterForRemoteNotifications()
    }

    static func process(values: OrderValues) async -> UIBackgroundFetchResult {
        if let orderID = values.orderID, let status = values.status {
            await OrderLiveActivityManager.shared.applyRemoteUpdate(
                orderID: orderID,
                status: status,
                orderNumber: values.orderNumber
            )
            return .newData
        }

        let api = EligaAPI()
        guard api.client.isAuthenticated else { return .noData }
        return await OrderMonitoringCoordinator.shared.refreshOnce(using: api) ? .newData : .failed
    }

    static func openOrder(values: OrderValues) async {
        if let orderID = values.orderID, let status = values.status {
            await OrderLiveActivityManager.shared.applyRemoteUpdate(
                orderID: orderID,
                status: status,
                orderNumber: values.orderNumber
            )
        }
        AppIntentHandoff.shared.request(.tab(.orders))
    }

    nonisolated static func orderValues(from userInfo: [AnyHashable: Any]) -> OrderValues {
        let order = userInfo["order"] as? [String: Any]
        let rawOrderID = userInfo["orderId"] ?? userInfo["orderID"] ?? order?["id"]
        let orderID: Int? = switch rawOrderID {
        case let value as Int: value
        case let value as NSNumber: value.intValue
        case let value as String: Int(value)
        default: nil
        }
        let status = (userInfo["status"] as? String)
            ?? (userInfo["orderStatus"] as? String)
            ?? (order?["status"] as? String)
        let orderNumber = (userInfo["orderNo"] as? String)
            ?? (userInfo["orderNumber"] as? String)
            ?? (order?["orderNo"] as? String)
        return OrderValues(orderID: orderID, status: status, orderNumber: orderNumber)
    }
}
