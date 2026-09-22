import Foundation

/// 리스 점유 상태
public enum LeaseState: String, Sendable, Codable, Equatable {
    /// 활성 상태 (타이머 차감 중)
    case active
    /// 인간 작업으로 인해 일시 유예(동결)된 상태
    case pausedByHuman
    /// 만료되어 회수 작업이 진행 중인 상태 (하트비트 차단 락)
    case evicting
    /// 완전히 회수된 상태
    case evicted
    /// 정상 완료 또는 명시적으로 반납된 상태
    case released
}

/// 리스 조작 중 발생 가능한 에러
public enum LeaseError: Error, Sendable, Equatable {
    case resourceNotFound(String)
    case leaseAlreadyExists(String)
    case leaseExpired(String)
    case maxTTLExceeded(String)
    case leaseLocked(String)
    case evictionFailed(String, String)
}

/// 리스 계약 모델
public struct LeaseContract: Sendable, Equatable {
    /// 리소스 고유 식별자
    public let resourceID: String
    /// 리소스를 점유한 에이전트 식별자
    public let holderIdentity: String
    /// 단일 하트비트 유효 시간 (TTL)
    public let ttl: Duration
    /// 무한 하트비트 루프를 방지하는 절대 상한선 (Max TTL)
    public let maxTTL: Duration
    /// 리스 최초 발급 시각
    public var grantedAt: ContinuousClock.Instant
    /// 리스 만료 예정 시각
    public var expiresAt: ContinuousClock.Instant
    /// 누적 하트비트 연장 횟수
    public var totalRenewCount: Int
    /// 현재 상태
    public var state: LeaseState
    /// 마지막 하트비트 시각
    public var lastHeartbeatAt: ContinuousClock.Instant
    /// 마지막 인간 인터랙션 감지 시각
    public var lastHumanInteractionAt: ContinuousClock.Instant?
    /// 인간 인터랙션 이후 보장되는 유예 완충 시간
    public var humanGraceDuration: Duration

    public init(
        resourceID: String,
        holderIdentity: String,
        ttl: Duration,
        maxTTL: Duration,
        clock: ContinuousClock = ContinuousClock(),
        humanGraceDuration: Duration = .seconds(60)
    ) {
        let now = clock.now
        self.resourceID = resourceID
        self.holderIdentity = holderIdentity
        self.ttl = ttl
        self.maxTTL = maxTTL
        self.grantedAt = now
        self.expiresAt = now + ttl
        self.totalRenewCount = 0
        self.state = .active
        self.lastHeartbeatAt = now
        self.lastHumanInteractionAt = nil
        self.humanGraceDuration = humanGraceDuration
    }
}
