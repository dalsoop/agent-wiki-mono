import Foundation
import os

/// macOS 잠자기(Sleep) 후 깨어남(Wake) 시 대량 만료 오폭(Mass Eviction)을 방지하는 보정기
public final class SleepWakeCompensator: Sendable {
    public static let shared = SleepWakeCompensator()

    private let callbacks = OSAllocatedUnfairLock(
        initialState: [UUID: @Sendable (Duration) -> Void]()
    )

    private init() {}

    /// Wake 이벤트 구독 등록
    public func registerOnWake(callback: @escaping @Sendable (Duration) -> Void) -> UUID {
        let id = UUID()
        callbacks.withLock { $0[id] = callback }
        return id
    }

    /// 구독 해제
    public func unregister(id: UUID) {
        callbacks.withLock { $0.removeValue(forKey: id) }
    }

    /// 수동 또는 테스트 환경에서 Wake 이벤트를 시뮬레이션
    public func notifyWake(graceDuration: Duration = .seconds(30)) {
        let registered = callbacks.withLock { Array($0.values) }
        for callback in registered {
            callback(graceDuration)
        }
    }
}
