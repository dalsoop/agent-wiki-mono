import Foundation

/// 다형적 리소스의 TTL 및 생명주기를 총괄하는 중앙 코디네이터 액터
public actor LeaseCoordinator {
    private var resources: [String: any LeasableResource] = [:]
    private var leases: [String: LeaseContract] = [:]
    private let clock: ContinuousClock
    private let humanGuard: HumanInteractionGuard
    private var wakeRegistrationID: UUID?

    private let enableSleepWakeCompensation: Bool
    private var didConfigureSleepWake = false

    public init(
        clock: ContinuousClock = ContinuousClock(),
        humanGuard: HumanInteractionGuard = HumanInteractionGuard(),
        enableSleepWakeCompensation: Bool = true
    ) {
        self.clock = clock
        self.humanGuard = humanGuard
        self.enableSleepWakeCompensation = enableSleepWakeCompensation
    }

    private func configureSleepWakeIfNeeded() {
        guard enableSleepWakeCompensation, !didConfigureSleepWake else { return }
        didConfigureSleepWake = true
        let registrationID = SleepWakeCompensator.shared.registerOnWake { [weak self] grace in
            guard let self else { return }
            Task {
                await self.compensateForWake(graceDuration: grace)
            }
        }
        self.wakeRegistrationID = registrationID
    }

    deinit {
        if let wakeRegistrationID {
            SleepWakeCompensator.shared.unregister(id: wakeRegistrationID)
        }
    }

    /// 리소스 점유 리스 신규 발급
    @discardableResult
    public func acquire(
        resource: any LeasableResource,
        holderIdentity: String,
        ttl: Duration,
        maxTTL: Duration
    ) throws -> LeaseContract {
        configureSleepWakeIfNeeded()
        let id = resource.resourceID
        if let existing = leases[id], existing.state == .active {
            throw LeaseError.leaseAlreadyExists(id)
        }

        let contract = LeaseContract(
            resourceID: id,
            holderIdentity: holderIdentity,
            ttl: ttl,
            maxTTL: maxTTL,
            clock: clock,
            humanGraceDuration: humanGuard.defaultGraceDuration
        )
        resources[id] = resource
        leases[id] = contract
        return contract
    }

    /// 에이전트의 하트비트 수신 및 수명 연장
    @discardableResult
    public func heartbeat(
        resourceID: String,
        holderIdentity: String? = nil,
        extendBy: Duration? = nil
    ) throws -> LeaseContract {
        guard var lease = leases[resourceID] else {
            throw LeaseError.resourceNotFound(resourceID)
        }
        guard lease.state == .active || lease.state == .pausedByHuman else {
            throw LeaseError.leaseExpired(resourceID)
        }
        if let holder = holderIdentity, lease.holderIdentity != holder {
            throw LeaseError.leaseLocked("Resource \(resourceID) is held by \(lease.holderIdentity), not \(holder)")
        }

        let now = clock.now
        // Max TTL 하드 실링 검사 (Astra Defect 2: 무한 루프 방지)
        let totalElapsed = now - lease.grantedAt
        if totalElapsed >= lease.maxTTL {
            throw LeaseError.maxTTLExceeded("Maximum TTL of \(lease.maxTTL) exceeded for \(resourceID)")
        }

        let extensionDuration = extendBy ?? lease.ttl
        let candidateExpiry = now + extensionDuration
        let maxAllowedExpiry = lease.grantedAt + lease.maxTTL

        lease.expiresAt = min(candidateExpiry, maxAllowedExpiry)
        lease.totalRenewCount += 1
        lease.lastHeartbeatAt = now
        leases[resourceID] = lease
        return lease
    }

    /// 사용자 조작 감지 기록 (포커스 등)
    public func recordHumanInteraction(resourceID: String) {
        guard var lease = leases[resourceID], lease.state == .active || lease.state == .pausedByHuman else { return }
        lease.lastHumanInteractionAt = clock.now
        leases[resourceID] = lease
    }

    /// 인간 작업으로 인한 리스 일시 정지
    public func pauseByHuman(resourceID: String) throws {
        guard var lease = leases[resourceID], lease.state == .active else {
            throw LeaseError.resourceNotFound(resourceID)
        }
        lease.state = .pausedByHuman
        leases[resourceID] = lease
    }

    /// 인간 작업 완료 후 리스 재개
    public func resumeFromHuman(resourceID: String, additionalTTL: Duration? = nil) throws {
        guard var lease = leases[resourceID], lease.state == .pausedByHuman else {
            throw LeaseError.resourceNotFound(resourceID)
        }
        let now = clock.now
        lease.state = .active
        let extensionDuration = additionalTTL ?? lease.ttl
        lease.expiresAt = now + extensionDuration
        leases[resourceID] = lease
    }

    /// 리스 정상 반납
    public func release(resourceID: String) {
        leases[resourceID]?.state = .released
        resources.removeValue(forKey: resourceID)
        leases.removeValue(forKey: resourceID)
    }

    /// 특정 리소스의 계약 단방향 조회
    public func getContract(resourceID: String) -> LeaseContract? {
        leases[resourceID]
    }

    /// 활성 리스 전체 목록 조회
    public func allActiveLeases() -> [LeaseContract] {
        leases.values.filter { $0.state == .active || $0.state == .pausedByHuman }
    }

    /// 주기적 스위프 틱. 만료 평가, 인간 인터랙션 검사, 회수(Evict) 집행
    @discardableResult
    public func tick() async -> [String: EvictionReason] {
        let now = clock.now
        var evicted: [String: EvictionReason] = [:]

        for (id, lease) in leases {
            guard lease.state == .active else { continue }
            let totalElapsed = now - lease.grantedAt
            let isMaxExceeded = totalElapsed >= lease.maxTTL
            let isTimeExpired = now >= lease.expiresAt
            guard isMaxExceeded || isTimeExpired else { continue }
            let reason: EvictionReason = isMaxExceeded ? .maxTTLExceeded : .ttlExpired
            guard await evictIfUnprotected(id: id, lease: lease, reason: reason, now: now) else { continue }
            evicted[id] = reason
        }

        return evicted
    }

    private func evictIfUnprotected(
        id: String,
        lease: LeaseContract,
        reason: EvictionReason,
        now: ContinuousClock.Instant
    ) async -> Bool {
        guard !humanGuard.isProtected(
            lastInteractionAt: lease.lastHumanInteractionAt,
            now: now,
            graceDuration: lease.humanGraceDuration
        ) else { return false }
        guard let resource = resources[id] else {
            leases[id]?.state = .evicted
            return false
        }
        guard !(await isUnderHumanInteraction(resource, lease: lease, id: id, now: now)) else {
            return false
        }
        leases[id]?.state = .evicting
        return await finishEviction(resource, id: id, reason: reason)
    }

    private func isUnderHumanInteraction(
        _ resource: any LeasableResource,
        lease: LeaseContract,
        id: String,
        now: ContinuousClock.Instant
    ) async -> Bool {
        let isUnderHuman = await withTimeout(duration: .milliseconds(500), fallback: false) {
            await resource.isUnderHumanInteraction()
        }
        guard isUnderHuman else { return false }
        var protectedLease = lease
        protectedLease.lastHumanInteractionAt = now
        leases[id] = protectedLease
        return true
    }

    private func finishEviction(
        _ resource: any LeasableResource,
        id: String,
        reason: EvictionReason
    ) async -> Bool {
        let success = await withTimeout(duration: .seconds(2), fallback: false) {
            do {
                try await resource.evict(reason: reason)
                return true
            } catch {
                return false
            }
        }
        guard success else {
            leases[id]?.state = .active
            return false
        }
        leases[id]?.state = .evicted
        resources.removeValue(forKey: id)
        leases.removeValue(forKey: id)
        return true
    }

    /// Sleep/Wake 발생 시 모든 활성 리스에 유예 시간 주입 (Astra Defect 1)
    public func compensateForWake(graceDuration: Duration) {
        let now = clock.now
        for (id, var lease) in leases {
            guard lease.state == .active else { continue }
            lease.expiresAt = max(lease.expiresAt, now + graceDuration)
            leases[id] = lease
        }
    }

    private func withTimeout<T: Sendable>(
        duration: Duration,
        fallback: T,
        operation: @escaping @Sendable () async -> T
    ) async -> T {
        await withTaskGroup(of: T.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                do {
                    try await ContinuousClock().sleep(for: duration)
                } catch {
                    return fallback
                }
                return fallback
            }
            let first = await group.next() ?? fallback
            group.cancelAll()
            return first
        }
    }
}
