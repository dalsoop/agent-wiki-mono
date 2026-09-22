import Foundation
import os
import Testing
@testable import EphemeralLeaseKit

/// 테스트용 가상 리소스
final class MockLeasableResource: LeasableResource, Sendable {
    private struct State {
        var humanActive = false
        var evictedReason: EvictionReason?
        var evictionCount = 0
    }

    let resourceID: String
    let kind: LeasableKind
    private let state = OSAllocatedUnfairLock(initialState: State())

    var humanActive: Bool {
        get { state.withLock { $0.humanActive } }
        set { state.withLock { $0.humanActive = newValue } }
    }

    var evictedReason: EvictionReason? { state.withLock { $0.evictedReason } }
    var evictionCount: Int { state.withLock { $0.evictionCount } }

    init(resourceID: String, kind: LeasableKind = .window) {
        self.resourceID = resourceID
        self.kind = kind
    }

    func isUnderHumanInteraction() async -> Bool {
        state.withLock { $0.humanActive }
    }

    func evict(reason: EvictionReason) async throws {
        state.withLock {
            $0.evictedReason = reason
            $0.evictionCount += 1
        }
    }
}

@Suite(.serialized)
struct EphemeralLeaseKitTests {

    @Test func testBasicAcquireAndEviction() async throws {
        let coordinator = LeaseCoordinator(enableSleepWakeCompensation: false)
        let mock = MockLeasableResource(resourceID: "win-1", kind: .window)

        // TTL 50ms, MaxTTL 500ms
        let contract = try await coordinator.acquire(
            resource: mock,
            holderIdentity: "agent:test",
            ttl: .milliseconds(50),
            maxTTL: .milliseconds(500)
        )
        #expect(contract.resourceID == "win-1")
        #expect(contract.state == .active)

        // 바로 틱을 치면 아직 만료 전이므로 evict되지 않음
        var evicted = await coordinator.tick()
        #expect(evicted.isEmpty)
        #expect(mock.evictedReason == nil)

        // 60ms 대기 후 틱
        try await Task.sleep(for: .milliseconds(70))
        evicted = await coordinator.tick()
        #expect(evicted["win-1"] == .ttlExpired)
        #expect(mock.evictedReason == .ttlExpired)
        #expect(mock.evictionCount == 1)

        let after = await coordinator.getContract(resourceID: "win-1")
        #expect(after == nil)
    }

    @Test func testHeartbeatExtendsLease() async throws {
        let coordinator = LeaseCoordinator(enableSleepWakeCompensation: false)
        let mock = MockLeasableResource(resourceID: "win-2", kind: .window)

        try await coordinator.acquire(
            resource: mock,
            holderIdentity: "agent:test",
            ttl: .milliseconds(100),
            maxTTL: .seconds(2)
        )

        // 60ms 경과 후 하트비트 전송 (+100ms 연장)
        try await Task.sleep(for: .milliseconds(60))
        let renewed = try await coordinator.heartbeat(resourceID: "win-2", holderIdentity: "agent:test")
        #expect(renewed.totalRenewCount == 1)

        // 추가 60ms 경과 (최초 발급으로부터 120ms 경과했으나 연장되었으므로 생존)
        try await Task.sleep(for: .milliseconds(60))
        let evicted = await coordinator.tick()
        #expect(evicted.isEmpty)
        #expect(mock.evictedReason == nil)
    }

    @Test func testMaxTTLExceededPreventsInfiniteLoop() async throws {
        let coordinator = LeaseCoordinator(enableSleepWakeCompensation: false)
        let mock = MockLeasableResource(resourceID: "win-3", kind: .process)

        // TTL 100ms, MaxTTL 150ms
        try await coordinator.acquire(
            resource: mock,
            holderIdentity: "agent:test",
            ttl: .milliseconds(100),
            maxTTL: .milliseconds(150)
        )

        // 계속 하트비트를 보내도 MaxTTL(150ms)을 넘기면 만료
        try await Task.sleep(for: .milliseconds(80))
        _ = try await coordinator.heartbeat(resourceID: "win-3")

        try await Task.sleep(for: .milliseconds(100))
        // 180ms 경과 시점: maxTTL(150ms) 초과
        let evicted = await coordinator.tick()
        #expect(evicted["win-3"] == .maxTTLExceeded)
        #expect(mock.evictedReason == .maxTTLExceeded)
    }

    @Test func testHumanInteractionProtectsResource() async throws {
        let coordinator = LeaseCoordinator(
            humanGuard: HumanInteractionGuard(defaultGraceDuration: .milliseconds(200)),
            enableSleepWakeCompensation: false
        )
        let mock = MockLeasableResource(resourceID: "win-4", kind: .window)
        mock.humanActive = true

        try await coordinator.acquire(
            resource: mock,
            holderIdentity: "agent:test",
            ttl: .milliseconds(50),
            maxTTL: .seconds(1)
        )

        try await Task.sleep(for: .milliseconds(70))
        // TTL은 지났으나 humanActive = true 이므로 evict 되지 않음
        let evicted = await coordinator.tick()
        #expect(evicted.isEmpty)
        #expect(mock.evictedReason == nil)

        // 인간 개입이 해제된 후 유예 기간 경과 시 회수
        mock.humanActive = false
        try await Task.sleep(for: .milliseconds(250))
        let evictedLater = await coordinator.tick()
        #expect(evictedLater["win-4"] == .ttlExpired)
    }

    @Test func testPauseAndResumeByHuman() async throws {
        let coordinator = LeaseCoordinator(enableSleepWakeCompensation: false)
        let mock = MockLeasableResource(resourceID: "win-5", kind: .window)

        try await coordinator.acquire(
            resource: mock,
            holderIdentity: "agent:test",
            ttl: .milliseconds(50),
            maxTTL: .seconds(1)
        )

        // 인간 작업으로 일시 정지
        try await coordinator.pauseByHuman(resourceID: "win-5")
        let pausedContract = await coordinator.getContract(resourceID: "win-5")
        #expect(pausedContract?.state == .pausedByHuman)

        // 70ms 대기 후에도 evict되지 않음
        try await Task.sleep(for: .milliseconds(70))
        let evicted = await coordinator.tick()
        #expect(evicted.isEmpty)

        // 작업 재개
        try await coordinator.resumeFromHuman(resourceID: "win-5", additionalTTL: .milliseconds(100))
        let resumed = await coordinator.getContract(resourceID: "win-5")
        #expect(resumed?.state == .active)
    }

    @Test func testSleepWakeCompensation() async throws {
        let coordinator = LeaseCoordinator(enableSleepWakeCompensation: false)
        let mock = MockLeasableResource(resourceID: "win-6", kind: .window)

        try await coordinator.acquire(
            resource: mock,
            holderIdentity: "agent:test",
            ttl: .milliseconds(60),
            maxTTL: .seconds(1)
        )

        // 50ms 후 잠자기에서 깨어남 시뮬레이션 (+200ms 유예 보정 주입)
        try await Task.sleep(for: .milliseconds(50))
        await coordinator.compensateForWake(graceDuration: .milliseconds(200))

        // 추가 50ms 경과 (최초로부터 100ms 경과했으나 보정으로 인해 생존)
        try await Task.sleep(for: .milliseconds(50))
        let evicted = await coordinator.tick()
        #expect(evicted.isEmpty)
    }
}
