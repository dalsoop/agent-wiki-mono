import Foundation

/// 최대 동시 실행 프로세스 또는 비동기 작업 수를 제한하는 한계 조절자(Process Limiter).
/// 무제한 동시 프로세스 생성으로 인한 시스템 자원 고갈 및 커널 PID 고갈을 방지하며,
/// 대기 중인 Task가 취소될 경우 즉시 `CancellationError`를 방출하여 교착 상태(Deadlock/Hang)를 차단한다.
public actor BoundedProcessLimiter {
    public let maxConcurrent: Int
    private var inFlight: Int = 0
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []
    private var cancelledIds: Set<UUID> = []

    public init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    /// 현재 실행 중인 작업 수
    public var currentInFlight: Int {
        inFlight
    }

    /// 대기 중인 작업 수
    public var waitingCount: Int {
        waiters.count
    }

    /// 동시성 슬롯을 획득한다.
    /// 슬롯이 가용하지 않으면 대기 큐에 진입하며, Task가 취소되면 즉시 `CancellationError`를 던진다.
    public func acquire() async throws {
        try Task.checkCancellation()

        if inFlight < maxConcurrent {
            inFlight += 1
            return
        }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                addWaiter(id: id, continuation: continuation)
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(id: id)
            }
        }
    }

    private func addWaiter(id: UUID, continuation: CheckedContinuation<Void, Error>) {
        if cancelledIds.remove(id) != nil || Task.isCancelled {
            continuation.resume(throwing: CancellationError())
            return
        }
        waiters.append((id: id, continuation: continuation))
    }

    private func cancelWaiter(id: UUID) {
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            let waiter = waiters.remove(at: index)
            waiter.continuation.resume(throwing: CancellationError())
        } else {
            cancelledIds.insert(id)
        }
    }

    /// 동시성 슬롯을 반납한다. 대기 중인 작업이 있다면 다음 작업을 깨운다.
    public func release() {
        while !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.continuation.resume()
            return
        }
        inFlight = max(0, inFlight - 1)
    }

    /// 최대 동시성 한계 내에서 에러를 던질 수 있는 비동기 클로저를 실행한다.
    public func withLimit<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try await acquire()
        do {
            let result = try await operation()
            release()
            return result
        } catch {
            release()
            throw error
        }
    }

    /// 최대 동시성 한계 내에서 에러를 던지지 않는 비동기 클로저를 실행한다.
    public func withLimit<T: Sendable>(_ operation: @Sendable () async -> T) async throws -> T {
        try await acquire()
        let result = await operation()
        release()
        return result
    }
}
