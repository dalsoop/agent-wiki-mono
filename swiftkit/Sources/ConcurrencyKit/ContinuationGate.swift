import Foundation
#if canImport(os)
import os

extension OSAllocatedUnfairLock where State: Sendable {
    @discardableResult
    public func exchange(_ newValue: State) -> State {
        withLock { state in
            let old = state
            state = newValue
            return old
        }
    }
}
#endif

/// Swift Concurrency의 Continuation에 대한 이중 resume(SIGTRAP 즉사 크래시)을 원천 차단하는 게이트.
///
/// Linux 에서도 컴파일되는 `LockedState<Bool>` 로 최초 1회의 `resume`만 원자적으로 통과시키고,
/// 이후의 중복 호출은 `guard !resumed.exchange(true)`를 통해 no-op으로 안전하게 무시합니다.
public final class ContinuationGate<T: Sendable, E: Error>: Sendable {
    private let resumed = LockedState(false)
    private let resumeHandler: @Sendable (Result<T, E>) -> Void

    /// CheckedContinuation을 감싸는 게이트를 초기화합니다.
    public init(_ continuation: CheckedContinuation<T, E>) {
        self.resumeHandler = { result in
            continuation.resume(with: result)
        }
    }

    /// UnsafeContinuation을 감싸는 게이트를 초기화합니다.
    public init(_ continuation: UnsafeContinuation<T, E>) {
        self.resumeHandler = { result in
            continuation.resume(with: result)
        }
    }

    /// 커스텀 resume 클로저를 감싸는 게이트를 초기화합니다.
    public init(onFirstResume: @escaping @Sendable (Result<T, E>) -> Void) {
        self.resumeHandler = onFirstResume
    }

    /// 단 1회만 원자적으로 `resume(returning:)`을 허용하고 이후 호출은 no-op 처리합니다.
    @discardableResult
    public func resume(returning value: T) -> Bool {
        guard !resumed.exchange(true) else { return false }
        resumeHandler(.success(value))
        return true
    }

    /// 단 1회만 원자적으로 `resume(throwing:)`을 허용하고 이후 호출은 no-op 처리합니다.
    @discardableResult
    public func resume(throwing error: E) -> Bool {
        guard !resumed.exchange(true) else { return false }
        resumeHandler(.failure(error))
        return true
    }

    /// 단 1회만 원자적으로 `resume(with:)`을 허용하고 이후 호출은 no-op 처리합니다.
    @discardableResult
    public func resume(with result: Result<T, E>) -> Bool {
        guard !resumed.exchange(true) else { return false }
        resumeHandler(result)
        return true
    }

    /// 이미 resume되었는지 여부를 확인합니다.
    public var hasResumed: Bool {
        resumed.withLock { $0 }
    }
}

extension ContinuationGate where T == Void {
    /// 단 1회만 원자적으로 `resume()`을 허용하고 이후 호출은 no-op 처리합니다.
    @discardableResult
    public func resume() -> Bool {
        resume(returning: ())
    }
}

/// 단 1회 실행 여부를 원자적으로 관리하는 게이트.
public final class OnceGate: Sendable {
    private let gate = LockedState(false)

    public init() {}

    /// 단 1회만 true를 반환하고(게이트 열림), 이후 호출은 false를 반환합니다.
    public func open() -> Bool {
        !gate.exchange(true)
    }

    /// 게이트가 이미 열렸는지 여부
    public var isOpened: Bool {
        gate.withLock { $0 }
    }
}
