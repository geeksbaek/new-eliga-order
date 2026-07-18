import Foundation

/// Keeps Foundation Models inference away from view-task cancellation and prevents
/// multiple sessions from aggregating transcripts at the same time.
///
/// This is intentionally an unstructured, serialized queue. A caller may stop
/// waiting when its view disappears, but cancelling that caller must not cancel an
/// in-flight Foundation Models XPC request. iOS 27 beta can otherwise trap inside
/// `TranscriptWritingAggregator` while cancellation races aggregation.
actor FoundationModelRequestCoordinator {
    static let shared = FoundationModelRequestCoordinator()

    private var tail: Task<Void, Never>?

    func perform<Value: Sendable>(
        _ operation: @escaping @Sendable () async -> Value
    ) async -> Value {
        let predecessor = tail
        let priority = Task.currentPriority
        let request = Task.detached(priority: priority) {
            if let predecessor {
                await predecessor.value
            }
            return await operation()
        }
        tail = Task.detached(priority: priority) {
            _ = await request.value
        }
        return await request.value
    }
}
