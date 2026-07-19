import BackgroundTasks
import Foundation

private final class BackgroundTaskCompletion: @unchecked Sendable {
    private let task: BGTask

    init(task: BGTask) {
        self.task = task
    }

    func finish(success: Bool) {
        task.setTaskCompleted(success: success)
    }
}

enum BackgroundRefreshCoordinator {
    static let identifier = "com.leeari95.NewEligaOrder.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    static func schedule(hasActiveOrders: Bool = OrderMonitoringStorage().hasActiveOrders) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date.now.addingTimeInterval(hasActiveOrders ? 60 : 30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // The system can reject duplicate or unavailable background requests; foreground refresh remains active.
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule(hasActiveOrders: OrderMonitoringStorage().hasActiveOrders)
        let completion = BackgroundTaskCompletion(task: task)
        let operation = Task { @MainActor in
            await performRefresh()
        }
        task.expirationHandler = {
            operation.cancel()
        }
        Task {
            let succeeded = await operation.value
            completion.finish(success: succeeded && !operation.isCancelled)
        }
    }

    @MainActor
    private static func performRefresh() async -> Bool {
        let store = AppStore()
        guard store.authenticationState == .authenticated else { return false }
        do {
            try await store.bootstrap()
            guard !Task.isCancelled else { return false }
            let refreshedOrders = await OrderMonitoringCoordinator.shared.refreshOnce(using: store.api)
            schedule(hasActiveOrders: OrderMonitoringCoordinator.shared.hasTrackedOrders)
            return refreshedOrders && !Task.isCancelled
        } catch is CancellationError {
            return false
        } catch {
            return false
        }
    }
}
