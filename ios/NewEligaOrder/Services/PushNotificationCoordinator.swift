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
        let values = PushNotificationCoordinator.orderValues(from: notification.request.content.userInfo)
        _ = await PushNotificationCoordinator.process(values: values)
        return [.banner, .list, .sound, .badge]
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
        let pushType: String?
        let orderID: Int?
        let status: String?
        let orderNumber: String?
        let shopID: Int?
        let shopName: String?
        let itemSummary: String?
        let total: Int?

        var isCafeOrderPush: Bool {
            guard let pushType, !pushType.isEmpty else { return orderID != nil }
            return ["CAFE_MOBILE_ORDER", "CAFE_KIOSK_ORDER"].contains(pushType.uppercased())
        }
    }

    static func prepareForAuthentication() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    @discardableResult
    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
            return true
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                if granted { UIApplication.shared.registerForRemoteNotifications() }
                return granted
            } catch {
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    static func didSignOut() {
        UIApplication.shared.unregisterForRemoteNotifications()
    }

    static func process(values: OrderValues) async -> UIBackgroundFetchResult {
        let api = EligaAPI()
        var resolved = values

        if values.isCafeOrderPush, let orderID = values.orderID, api.client.isAuthenticated {
            resolved = await hydrate(values: values, orderID: orderID, using: api)
        }

        if resolved.isCafeOrderPush,
           let orderID = resolved.orderID,
           let status = resolved.status,
           !status.isEmpty {
            await OrderLiveActivityManager.shared.applyRemoteUpdate(
                orderID: orderID,
                status: status,
                orderNumber: resolved.orderNumber,
                shopName: resolved.shopName,
                itemSummary: resolved.itemSummary,
                total: resolved.total
            )
            let phase = OrderActivityPhase(statusCode: status)
            if api.client.isAuthenticated, !phase.isTerminal {
                await OrderMonitoringCoordinator.shared.track(
                    orderID: orderID,
                    orderNumber: resolved.orderNumber,
                    shopName: resolved.shopName ?? "엘리가오더 카페",
                    using: api
                )
            }
            return .newData
        }

        guard api.client.isAuthenticated else { return .noData }
        return await OrderMonitoringCoordinator.shared.refreshOnce(using: api) ? .newData : .failed
    }

    static func openOrder(values: OrderValues) async {
        _ = await process(values: values)
        AppIntentHandoff.shared.request(.tab(.orders))
    }

    nonisolated static func orderValues(from userInfo: [AnyHashable: Any]) -> OrderValues {
        let payload = PushPayload(userInfo: userInfo)
        return OrderValues(
            pushType: payload.string(for: ["pushType", "type"]),
            orderID: payload.int(for: ["orderId", "orderID", "goodsOrderId", "id"]),
            status: payload.string(for: ["status", "orderStatus", "goodsOrderStatus", "statusCode"]),
            orderNumber: payload.string(for: ["orderNo", "orderNumber"]),
            shopID: payload.int(for: ["shopId", "shopID"]),
            shopName: payload.string(for: ["shopName", "storeName"]),
            itemSummary: payload.string(for: ["itemSummary", "goodsName", "menuName"]),
            total: payload.int(for: ["total", "totalPaidPrice", "totalSalesPrice", "totalUnitPrice"])
        )
    }

    private static func hydrate(values: OrderValues, orderID: Int, using api: EligaAPI) async -> OrderValues {
        async let snapshotRequest = try? api.fetchOrderStatus(orderID: orderID)
        async let historyRequest = try? api.fetchOrderHistory()
        let snapshot = await snapshotRequest
        let history = await historyRequest?.first { $0.id == orderID }
        let itemSummary = history.map { order in
            guard let first = order.items.first else { return "카페 주문" }
            let additional = order.items.count - 1
            return additional > 0 ? "\(first.name) 외 \(additional)개" : first.name
        }
        return OrderValues(
            pushType: values.pushType,
            orderID: orderID,
            status: values.status ?? snapshot?.status,
            orderNumber: values.orderNumber ?? snapshot?.orderNumber ?? history?.orderNumber,
            shopID: values.shopID ?? history?.shopID,
            shopName: values.shopName ?? history?.shopName,
            itemSummary: values.itemSummary ?? itemSummary,
            total: values.total ?? history?.totalPaid
        )
    }
}

private struct PushPayload: Sendable {
    private let objects: [[String: AnySendableValue]]

    init(userInfo: [AnyHashable: Any]) {
        let root = Dictionary(uniqueKeysWithValues: userInfo.map { (String(describing: $0.key), $0.value) })
        self.objects = Self.collectObjects(from: root).map { object in
            object.mapValues(AnySendableValue.init)
        }
    }

    func string(for keys: [String]) -> String? {
        for object in objects {
            for key in keys {
                guard let value = object.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value else {
                    continue
                }
                let string = value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !string.isEmpty { return string }
            }
        }
        return nil
    }

    func int(for keys: [String]) -> Int? {
        for object in objects {
            for key in keys {
                guard let value = object.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value,
                      let int = value.intValue
                else { continue }
                return int
            }
        }
        return nil
    }

    private static func collectObjects(from root: [String: Any], depth: Int = 0) -> [[String: Any]] {
        guard depth < 5 else { return [] }
        var result = [root]
        for value in root.values {
            if let dictionary = value as? [String: Any] {
                result.append(contentsOf: collectObjects(from: dictionary, depth: depth + 1))
            } else if let dictionary = value as? [AnyHashable: Any] {
                let stringDictionary = Dictionary(uniqueKeysWithValues: dictionary.map {
                    (String(describing: $0.key), $0.value)
                })
                result.append(contentsOf: collectObjects(from: stringDictionary, depth: depth + 1))
            } else if let string = value as? String,
                      let data = string.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                result.append(contentsOf: collectObjects(from: object, depth: depth + 1))
            }
        }
        return result
    }
}

private struct AnySendableValue: @unchecked Sendable {
    let raw: Any

    init(_ raw: Any) { self.raw = raw }

    var stringValue: String {
        switch raw {
        case let value as String: value
        case let value as NSNumber: value.stringValue
        default: ""
        }
    }

    var intValue: Int? {
        switch raw {
        case let value as Int: value
        case let value as NSNumber: value.intValue
        case let value as String: Int(value)
        default: nil
        }
    }
}
