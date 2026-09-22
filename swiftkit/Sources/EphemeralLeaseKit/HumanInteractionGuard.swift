import Foundation

/// 인간 포커스 및 사용자 조작 감지 시 리스 만료를 유예하는 보호기
public struct HumanInteractionGuard: Sendable {
    /// 기본 인간 상호작용 유예 시간 (기본 60초)
    public let defaultGraceDuration: Duration

    public init(defaultGraceDuration: Duration = .seconds(60)) {
        self.defaultGraceDuration = defaultGraceDuration
    }

    /// 현재 시점에서 인간 개입으로 인한 만료 유예 상태인지 판정
    public func isProtected(
        lastInteractionAt: ContinuousClock.Instant?,
        now: ContinuousClock.Instant,
        graceDuration: Duration? = nil
    ) -> Bool {
        guard let lastInteractionAt else { return false }
        let grace = graceDuration ?? defaultGraceDuration
        return (now - lastInteractionAt) < grace
    }
}
