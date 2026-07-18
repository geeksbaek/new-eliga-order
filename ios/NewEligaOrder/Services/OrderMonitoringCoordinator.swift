import Foundation
import UIKit
@preconcurrency import UserNotifications

struct MonitoredOrder: Codable, Equatable, Sendable {
    let orderID: Int
    var orderNumber: String
    var shopName: String
    var phase: OrderActivityPhase
    let startedAt: Date

    var isExpired: Bool {
        Date.now.timeIntervalSince(startedAt) > OrderMonitoringPolicy.maximumLifetime
    }
}

struct OrderMonitoringStorage: @unchecked Sendable {
    private static let appGroup = "group.com.leeari95.NewEligaOrder"
    private static let key = "order-monitoring.active-orders.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
            ?? UserDefaults(suiteName: Self.appGroup)
            ?? .standard
    }

    var orders: [MonitoredOrder] {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([MonitoredOrder].self, from: data)
        else { return [] }
        return decoded
    }

    var hasActiveOrders: Bool {
        orders.contains { !$0.phase.isTerminal && !$0.isExpired }
    }

    func track(_ order: MonitoredOrder) {
        var values = orders.filter { $0.orderID != order.orderID && !$0.isExpired }
        values.append(order)
        save(values)
    }

    func update(_ order: MonitoredOrder) {
        var values = orders
        guard let index = values.firstIndex(where: { $0.orderID == order.orderID }) else { return }
        values[index] = order
        save(values)
    }

    func remove(orderID: Int) {
        save(orders.filter { $0.orderID != orderID && !$0.isExpired })
    }

    func removeExpired() {
        save(orders.filter { !$0.isExpired && !$0.phase.isTerminal })
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }

    private func save(_ values: [MonitoredOrder]) {
        if values.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else {
            defaults.set(try? JSONEncoder().encode(values), forKey: Self.key)
        }
    }
}

enum OrderMonitoringPolicy {
    static let foregroundInterval: Duration = .seconds(8)
    static let backgroundInterval: Duration = .seconds(10)
    static let retryInterval: Duration = .seconds(20)
    static let maximumLifetime: TimeInterval = 6 * 60 * 60

    static func notificationTitle(for phase: OrderActivityPhase) -> String {
        switch phase {
        case .submitted: "주문이 접수됐어요"
        case .preparing: "메뉴를 준비하고 있어요"
        case .ready: "픽업할 준비가 됐어요"
        case .completed: "픽업이 완료됐어요"
        case .cancelled: "주문이 취소됐어요"
        }
    }

    static func notificationBody(shopName: String, orderNumber: String) -> String {
        let shop = shopName.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = orderNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return switch (shop.isEmpty, number.isEmpty) {
        case (false, false): "\(shop) · 주문 \(number)"
        case (false, true): shop
        case (true, false): "주문 \(number)"
        case (true, true): "주문 상태가 변경되었습니다."
        }
    }
}

@MainActor
final class OrderMonitoringCoordinator {
    static let shared = OrderMonitoringCoordinator()

    private let storage: OrderMonitoringStorage
    private var foregroundTask: Task<Void, Never>?
    private var backgroundTask: Task<Void, Never>?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    init(storage: OrderMonitoringStorage = OrderMonitoringStorage()) {
        self.storage = storage
    }

    var hasTrackedOrders: Bool { storage.hasActiveOrders }

    func track(
        orderID: Int,
        orderNumber: String? = nil,
        shopName: String,
        using api: EligaAPI
    ) async {
        let existing = storage.orders.first { $0.orderID == orderID }
        storage.track(
            MonitoredOrder(
                orderID: orderID,
                orderNumber: orderNumber ?? existing?.orderNumber ?? String(orderID),
                shopName: shopName.isEmpty ? (existing?.shopName ?? "엘리가오더 카페") : shopName,
                phase: existing?.phase ?? .submitted,
                startedAt: existing?.startedAt ?? .now
            )
        )
        await requestNotificationAuthorizationIfNeeded()
        BackgroundRefreshCoordinator.schedule(hasActiveOrders: true)
        startForegroundMonitoring(using: api)
    }

    func applicationDidBecomeActive(using api: EligaAPI) {
        finishBackgroundExecution()
        storage.removeExpired()
        BackgroundRefreshCoordinator.schedule(hasActiveOrders: hasTrackedOrders)
        startForegroundMonitoring(using: api)
    }

    func applicationDidEnterBackground(using api: EligaAPI) {
        foregroundTask?.cancel()
        foregroundTask = nil
        storage.removeExpired()
        BackgroundRefreshCoordinator.schedule(hasActiveOrders: hasTrackedOrders)
        startBackgroundMonitoring(using: api)
    }

    @discardableResult
    func refreshOnce(using api: EligaAPI) async -> Bool {
        storage.removeExpired()
        let orders = storage.orders
        guard !orders.isEmpty else { return true }

        var hadSuccessfulRequest = false
        for var order in orders where !order.phase.isTerminal && !order.isExpired {
            guard !Task.isCancelled else { return hadSuccessfulRequest }
            do {
                let snapshot = try await api.fetchOrderStatus(orderID: order.orderID)
                let status = snapshot.status.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !status.isEmpty else { continue }
                hadSuccessfulRequest = true

                let nextPhase = OrderActivityPhase(statusCode: status)
                let nextNumber = snapshot.orderNumber.isEmpty ? order.orderNumber : snapshot.orderNumber
                let didChange = nextPhase != order.phase || nextNumber != order.orderNumber
                guard didChange else { continue }

                order.phase = nextPhase
                order.orderNumber = nextNumber
                storage.update(order)
                await OrderLiveActivityManager.shared.applyRemoteUpdate(
                    orderID: order.orderID,
                    status: status,
                    orderNumber: nextNumber
                )
                await postLocalNotification(for: order, status: status)

                if nextPhase.isTerminal {
                    storage.remove(orderID: order.orderID)
                }
            } catch is CancellationError {
                return hadSuccessfulRequest
            } catch {
                continue
            }
        }

        if !hasTrackedOrders {
            foregroundTask?.cancel()
            foregroundTask = nil
            BackgroundRefreshCoordinator.schedule(hasActiveOrders: false)
        }
        return hadSuccessfulRequest
    }

    func stopAndClear() {
        foregroundTask?.cancel()
        foregroundTask = nil
        finishBackgroundExecution()
        storage.clear()
        BackgroundRefreshCoordinator.schedule(hasActiveOrders: false)
    }

    private func startForegroundMonitoring(using api: EligaAPI) {
        guard hasTrackedOrders, foregroundTask == nil else { return }
        backgroundTask?.cancel()
        backgroundTask = nil

        foregroundTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.hasTrackedOrders else { break }
                let succeeded = await self.refreshOnce(using: api)
                do {
                    try await Task.sleep(
                        for: succeeded
                            ? OrderMonitoringPolicy.foregroundInterval
                            : OrderMonitoringPolicy.retryInterval
                    )
                } catch {
                    break
                }
            }
            self?.foregroundTask = nil
        }
    }

    private func startBackgroundMonitoring(using api: EligaAPI) {
        guard hasTrackedOrders, backgroundTask == nil else { return }

        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "EligaOrderStatusMonitoring") { [weak self] in
            Task { @MainActor in
                self?.finishBackgroundExecution()
            }
        }
        guard backgroundTaskID != .invalid else { return }

        backgroundTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.hasTrackedOrders else { break }
                let succeeded = await self.refreshOnce(using: api)
                do {
                    try await Task.sleep(
                        for: succeeded
                            ? OrderMonitoringPolicy.backgroundInterval
                            : OrderMonitoringPolicy.retryInterval
                    )
                } catch {
                    break
                }
            }
            self?.finishBackgroundExecution()
        }
    }

    private func finishBackgroundExecution() {
        backgroundTask?.cancel()
        backgroundTask = nil
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private func requestNotificationAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    private func postLocalNotification(for order: MonitoredOrder, status: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }

        let content = UNMutableNotificationContent()
        content.title = OrderMonitoringPolicy.notificationTitle(for: order.phase)
        content.body = OrderMonitoringPolicy.notificationBody(
            shopName: order.shopName,
            orderNumber: order.orderNumber
        )
        content.sound = .default
        content.userInfo = [
            "orderId": order.orderID,
            "orderNo": order.orderNumber,
            "status": status,
        ]
        let request = UNNotificationRequest(
            identifier: "order-status-\(order.orderID)-\(order.phase.rawValue)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
