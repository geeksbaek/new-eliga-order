@preconcurrency import ActivityKit
import Foundation

@MainActor
final class OrderLiveActivityManager {
    static let shared = OrderLiveActivityManager()

    private enum Storage {
        static let appGroup = "group.com.leeari95.NewEligaOrder"
        static let tokenKey = "live-activity.push-tokens.v1"
    }

    private init() {}

    func start(orderID: Int, shopName: String, cart: Cart) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              !Activity<OrderActivityAttributes>.activities.contains(where: { $0.attributes.orderID == orderID })
        else { return }

        let attributes = OrderActivityAttributes(
            orderID: orderID,
            shopName: shopName.isEmpty ? "엘리가오더 카페" : shopName,
            itemSummary: Self.itemSummary(cart.items),
            total: cart.total
        )
        let state = OrderActivityAttributes.ContentState(
            phase: .submitted,
            statusText: "주문을 접수하고 있어요",
            orderNumber: String(orderID),
            updatedAt: .now
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: .now.addingTimeInterval(15 * 60)),
                pushType: .token
            )
            observePushToken(for: activity)
        } catch {
            // Ordering must succeed even when Live Activities are disabled by the system.
        }
    }

    func refresh(using api: EligaAPI) async {
        for activity in Activity<OrderActivityAttributes>.activities {
            do {
                let snapshot = try await api.fetchOrderStatus(orderID: activity.attributes.orderID)
                await update(activity: activity, snapshot: snapshot)
            } catch is CancellationError {
                return
            } catch {
                continue
            }
        }
    }

    func applyRemoteUpdate(orderID: Int, status: String, orderNumber: String?) async {
        guard let activity = Activity<OrderActivityAttributes>.activities.first(where: {
            $0.attributes.orderID == orderID
        }) else { return }
        let snapshot = OrderStatusSnapshot(
            orderID: orderID,
            orderNumber: orderNumber ?? String(orderID),
            status: status
        )
        await update(activity: activity, snapshot: snapshot)
    }

    func endAll() async {
        for activity in Activity<OrderActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
            removePushToken(for: activity.id)
        }
    }

    private func update(
        activity: Activity<OrderActivityAttributes>,
        snapshot: OrderStatusSnapshot
    ) async {
        let phase = OrderActivityPhase(statusCode: snapshot.status)
        let state = OrderActivityAttributes.ContentState(
            phase: phase,
            statusText: Self.statusText(for: phase),
            orderNumber: snapshot.orderNumber.isEmpty ? String(snapshot.orderID) : snapshot.orderNumber,
            updatedAt: .now
        )
        let content = ActivityContent(
            state: state,
            staleDate: phase.isTerminal ? nil : .now.addingTimeInterval(15 * 60)
        )

        if phase.isTerminal {
            let dismissalDate = Date.now.addingTimeInterval(phase == .cancelled ? 5 * 60 : 15 * 60)
            await activity.end(content, dismissalPolicy: .after(dismissalDate))
            removePushToken(for: activity.id)
        } else {
            await activity.update(content)
        }
    }

    private func observePushToken(for activity: Activity<OrderActivityAttributes>) {
        Task {
            for await token in activity.pushTokenUpdates {
                storePushToken(token.map { String(format: "%02x", $0) }.joined(), for: activity.id)
            }
        }
    }

    private func storePushToken(_ token: String, for activityID: String) {
        guard let defaults = UserDefaults(suiteName: Storage.appGroup) else { return }
        var values = defaults.dictionary(forKey: Storage.tokenKey) as? [String: String] ?? [:]
        values[activityID] = token
        defaults.set(values, forKey: Storage.tokenKey)
    }

    private func removePushToken(for activityID: String) {
        guard let defaults = UserDefaults(suiteName: Storage.appGroup) else { return }
        var values = defaults.dictionary(forKey: Storage.tokenKey) as? [String: String] ?? [:]
        values.removeValue(forKey: activityID)
        defaults.set(values, forKey: Storage.tokenKey)
    }

    private static func itemSummary(_ items: [CartItem]) -> String {
        guard let first = items.first else { return "카페 주문" }
        let additional = items.count - 1
        return additional > 0 ? "\(first.name) 외 \(additional)개" : first.name
    }

    private static func statusText(for phase: OrderActivityPhase) -> String {
        switch phase {
        case .submitted: "주문이 접수됐어요"
        case .preparing: "메뉴를 준비하고 있어요"
        case .ready: "픽업할 준비가 됐어요"
        case .completed: "픽업이 완료됐어요"
        case .cancelled: "주문이 취소됐어요"
        }
    }
}
