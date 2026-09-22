import Foundation

/// 만료 시 자동 회수(Eviction) 대상이 될 수 있는 리소스의 종류
public enum LeasableKind: Sendable, Equatable, Codable {
    case window
    case room
    case process
    case worktree
    case custom(String)
}

/// 회수(Eviction)가 촉발된 사유
public enum EvictionReason: Sendable, Equatable {
    /// 기본 TTL(Heartbeat 만료) 초과
    case ttlExpired
    /// 무한 하트비트 루프 방지용 최대 허용 수명(maxTTL) 초과
    case maxTTLExceeded
    /// 수동 취소 또는 사용자/관리자에 의한 회수
    case manuallyRevoked(String)
    /// 에이전트 사망 또는 프로세스 비정상 종료 확인
    case unseatedOrKilled
}

/// 만료 시 자동 회수(Evict)가 가능한 모든 다형적 리소스 규약
public protocol LeasableResource: Sendable {
    /// 리소스 고유 식별자 (창 ID, Room ID, PID, Worktree 경로 등)
    var resourceID: String { get }

    /// 리소스 분류
    var kind: LeasableKind { get }

    /// 현재 인간이 해당 리소스와 상호작용(포커스, 타이핑 등) 중인지 여부 판정
    func isUnderHumanInteraction() async -> Bool

    /// 리스 만료에 따른 실제 자원 회수 집행 (창 닫기, 프로세스 종료, Worktree 정리 등)
    func evict(reason: EvictionReason) async throws
}
