import Foundation

private final class FoundationModelCancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

private final class FoundationModelResultWaiter<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var cancelRequested = false
    private var finished = false

    func value(of task: Task<Result<Value, CancellationError>, Never>) async throws -> Value {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let shouldCancel = lock.withLock {
                    if cancelRequested || finished { return true }
                    self.continuation = continuation
                    return false
                }
                if shouldCancel {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                Task.detached { [weak self] in
                    self?.resolve(await task.value)
                }
            }
        } onCancel: {
            cancel()
        }
    }

    func cancel() {
        let continuation = lock.withLock { () -> CheckedContinuation<Value, Error>? in
            cancelRequested = true
            guard !finished else { return nil }
            finished = true
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(throwing: CancellationError())
    }

    private func resolve(_ result: Result<Value, CancellationError>) {
        let continuation = lock.withLock { () -> CheckedContinuation<Value, Error>? in
            guard !finished else { return nil }
            finished = true
            defer { self.continuation = nil }
            return self.continuation
        }
        guard let continuation else { return }
        switch result {
        case .success(let value): continuation.resume(returning: value)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }
}

/// Foundation Models 추론은 직렬화하고, 시작된 XPC 요청은 뷰 Task 취소와 분리한다.
/// 대기 중인 요청은 건너뛰며, 이미 시작된 요청은 안전하게 끝내되 취소된 호출자는 즉시 반환한다.
actor FoundationModelRequestCoordinator {
    static let shared = FoundationModelRequestCoordinator()

    private var tail: Task<Void, Never>?
    private let enqueueObserver: (@Sendable () async -> Void)?

    init(enqueueObserver: (@Sendable () async -> Void)? = nil) {
        self.enqueueObserver = enqueueObserver
    }

    func perform<Value: Sendable>(
        _ operation: @escaping @Sendable () async -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        let predecessor = tail
        let priority = Task.currentPriority
        let cancellation = FoundationModelCancellationFlag()
        let request = Task<Result<Value, CancellationError>, Never>.detached(priority: priority) {
            if let predecessor { await predecessor.value }
            guard !cancellation.isCancelled else { return .failure(CancellationError()) }
            return .success(await operation())
        }
        tail = Task.detached(priority: priority) { _ = await request.value }
        if let enqueueObserver { await enqueueObserver() }

        let waiter = FoundationModelResultWaiter<Value>()
        return try await withTaskCancellationHandler {
            try await waiter.value(of: request)
        } onCancel: {
            cancellation.cancel()
            waiter.cancel()
        }
    }
}
