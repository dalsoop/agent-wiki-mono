import Foundation
import Testing
@testable import CredentialLifecycleKit

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func daysAgo(_ n: Int) -> Date { now.addingTimeInterval(-Double(n) * 86_400) }
private func daysAhead(_ n: Int) -> Date { now.addingTimeInterval(Double(n) * 86_400) }

private func cred(_ id: Int = 1, owner: String = "svc", scopes: [String] = ["read_api"],
                  created: Date = daysAgo(200), used: Date? = nil,
                  expires: Date? = nil, revoked: Bool = false) -> ManagedCredential {
    ManagedCredential(
        identity: .init(id: CredentialID(id), name: "t\(id)", owner: owner),
        life: .init(scopes: scopes, createdAt: created, lastUsedAt: used, expiresAt: expires, revoked: revoked)
    )
}

@Suite("판정")
struct AuditTests {
    @Test("최근 쓰인 것은 문제 없음")
    func fresh() {
        let v = CredentialAudit.judge(cred(used: daysAgo(3)), now: now)
        #expect(v.severity == .ok)
        #expect(v.idleDays == 3)
    }

    @Test("방치 + 쓰기권한이 가장 위험하다")
    func staleWrite() {
        let v = CredentialAudit.judge(cred(scopes: ["api"], used: daysAgo(90)), now: now)
        #expect(v.flags.contains(.staleWriteCapable))
        #expect(v.severity == .critical)
    }

    @Test("읽기 전용은 방치돼도 warning 에 머문다")
    func staleReadOnly() {
        let v = CredentialAudit.judge(cred(scopes: ["read_api"], used: daysAgo(90)), now: now)
        #expect(v.severity == .warning)
    }

    @Test("쓰기 스코프 어휘는 정책으로 주입된다 — 제공자마다 다르다")
    func scopeVocabularyIsInjectable() {
        var policy = CredentialPolicy.default
        policy.writeCapableScopes = ["can-write"]
        let apiOnly = CredentialAudit.judge(cred(scopes: ["api"], used: daysAgo(90)),
                                            policy: policy, now: now)
        #expect(!apiOnly.flags.contains(.staleWriteCapable))
        let custom = CredentialAudit.judge(cred(scopes: ["can-write"], used: daysAgo(90)),
                                           policy: policy, now: now)
        #expect(custom.flags.contains(.staleWriteCapable))
    }

    @Test("유예기간 안에 안 쓴 것은 방치가 아니다")
    func graceWindow() {
        #expect(CredentialAudit.judge(cred(created: daysAgo(3)), now: now).flags.isEmpty)
    }

    @Test("유예기간 지나도록 미사용이면 방치")
    func neverUsed() {
        let v = CredentialAudit.judge(cred(created: daysAgo(30)), now: now)
        #expect(v.flags.contains(.neverUsed))
        #expect(v.flags.contains(.stale))
    }

    @Test("만료됐는데 살아 있으면 critical")
    func expired() {
        let v = CredentialAudit.judge(cred(used: daysAgo(1), expires: daysAgo(5)), now: now)
        #expect(v.severity == .critical)
        #expect(v.daysUntilExpiry == -5)
    }

    @Test("폐기된 것은 집계에서 빠진다")
    func revokedExcluded() {
        let r = CredentialAudit.report(source: "s",
                                       credentials: [cred(1, used: daysAgo(1)),
                                                     cred(2, used: daysAgo(999), revoked: true)],
                                       now: now)
        #expect(r.totalActive == 1)
        #expect(r.stale == 0)
    }
}

@Suite("폭주 감지")
struct BurstTests {
    @Test("2분 간격 6개를 한 무리로 잡는다")
    func cluster() {
        let creds = (0..<6).map {
            cred(100 + $0, created: daysAgo(50).addingTimeInterval(Double($0) * 120))
        }
        let bursts = CredentialAudit.detectBursts(creds)
        #expect(bursts.count == 1)
        #expect(bursts.first?.count == 6)
    }

    @Test("드문드문 만든 것은 폭주가 아니다")
    func spreadOut() {
        let creds = (0..<6).map { cred(200 + $0, created: daysAgo(100 - $0 * 5)) }
        #expect(CredentialAudit.detectBursts(creds).isEmpty)
    }

    @Test("소유자가 다르면 섞이지 않는다")
    func perOwner() {
        var creds: [ManagedCredential] = []
        for (i, owner) in ["a", "b"].enumerated() {
            creds += (0..<5).map {
                cred(i * 1000 + $0, owner: owner,
                     created: daysAgo(50).addingTimeInterval(Double($0) * 60))
            }
        }
        #expect(CredentialAudit.detectBursts(creds).count == 2)
    }
}

@Suite("발급된 값 보호")
struct IssuedRedactionTests {
    @Test("설명 문자열에 값이 새지 않는다")
    func descriptionRedacts() {
        let issued = IssuedCredential(id: CredentialID(9), name: "n", value: "glpat-SUPERSECRET1234")
        #expect(!"\(issued)".contains("SUPERSECRET"))
        #expect(!issued.debugDescription.contains("SUPERSECRET"))
    }

    @Test("마스킹은 앞 4자만 남긴다")
    func masked() {
        let issued = IssuedCredential(id: CredentialID(9), name: "n", value: "glpat-SUPERSECRET1234")
        #expect(issued.maskedValue.hasPrefix("glpa"))
        #expect(!issued.maskedValue.contains("SECRET"))
    }

    @Test("짧은 값은 통째로 가린다")
    func shortValue() {
        #expect(IssuedCredential(id: CredentialID(1), name: "n", value: "abc").maskedValue
                == "<redacted>")
    }
}

@Suite("회전 순서 강제")
struct RotationOrderTests {
    private func progress() -> RotationProgress {
        RotationProgress(target: cred(1),
                         consumers: [CredentialConsumer(id: "c1", kind: .file, location: "/etc/x")])
    }

    @Test("소비처 파악이 첫 단계")
    func startsAtDiscovered() {
        #expect(progress().stage == .consumersDiscovered)
    }

    @Test("발급을 건너뛰고 교체 완료로 갈 수 없다")
    func cannotSkipIssue() {
        var p = progress()
        p.markUpdated("c1")
        #expect(throws: RotationError.self) { try p.finishUpdatingConsumers() }
    }

    @Test("검증 없이 폐기로 갈 수 없다 — 이게 이 라이브러리의 존재 이유")
    func cannotRevokeBeforeVerify() throws {
        var p = progress()
        try p.recordIssued(CredentialID(2))
        p.markUpdated("c1")
        try p.finishUpdatingConsumers()
        #expect(throws: RotationError.self) { try p.recordRevoked() }
    }

    @Test("교체 안 된 소비처가 남으면 다음 단계로 못 간다")
    func pendingConsumersBlock() throws {
        var p = RotationProgress(target: cred(1), consumers: [
            CredentialConsumer(id: "c1", kind: .file, location: "/etc/x"),
            CredentialConsumer(id: "c2", kind: .manual, location: "브라우저 세션"),
        ])
        try p.recordIssued(CredentialID(2))
        p.markUpdated("c1")
        #expect(p.pendingManual.count == 1)
        #expect(throws: RotationError.self) { try p.finishUpdatingConsumers() }
    }

    @Test("순서대로 가면 완료된다")
    func happyPath() throws {
        var p = progress()
        try p.recordIssued(CredentialID(2))
        p.markUpdated("c1")
        try p.finishUpdatingConsumers()
        try p.recordVerified()
        try p.recordRevoked()
        #expect(p.isComplete)
        #expect(p.newCredentialID == CredentialID(2))
    }
}

// MARK: - 조율기 통합

private actor FakeProvider: CredentialProvider {
    nonisolated let sourceName = "fake"
    private var revoked: [CredentialID] = []
    private let owned: [String: CredentialID]

    init(valueToID: [String: CredentialID]) { self.owned = valueToID }

    func listCredentials() async throws -> [ManagedCredential] { [] }
    func issue(like target: ManagedCredential, name: String) async throws -> IssuedCredential {
        IssuedCredential(id: CredentialID(999), name: name, value: "new-secret-value")
    }
    func revoke(id: CredentialID) async throws { revoked.append(id) }
    func identify(value: String) async throws -> CredentialID? { owned[value] }
    func revokedIDs() -> [CredentialID] { revoked }
}

private final class FakeScanner: ConsumerScanner, @unchecked Sendable {
    let found: [(value: String, consumer: CredentialConsumer)]
    private(set) var replaced: [String] = []
    init(_ found: [(String, CredentialConsumer)]) {
        self.found = found.map { (value: $0.0, consumer: $0.1) }
    }
    func scan() async throws -> [(value: String, consumer: CredentialConsumer)] { found }
    func replace(_ consumer: CredentialConsumer, with newValue: String) async throws -> Bool {
        guard !consumer.requiresManualStep else { return false }
        replaced.append(consumer.id)
        return true
    }
}

@Suite("회전 조율")
struct CoordinatorTests {
    private let target = cred(7)

    @Test("소비처를 못 찾으면 회전하지 않는다 — 모르는 채로 바꾸는 게 사고다")
    func refusesWithoutConsumers() async {
        let coordinator = RotationCoordinator(provider: FakeProvider(valueToID: [:]),
                                              scanners: [FakeScanner([])])
        await #expect(throws: RotationError.self) {
            _ = try await coordinator.discoverConsumers(for: target)
        }
    }

    @Test("내 자격증명을 들고 있는 소비처만 잡는다")
    func matchesOnlyTarget() async throws {
        let scanner = FakeScanner([
            ("mine", CredentialConsumer(id: "c1", kind: .file, location: "/a")),
            ("other", CredentialConsumer(id: "c2", kind: .file, location: "/b")),
        ])
        let coordinator = RotationCoordinator(
            provider: FakeProvider(valueToID: ["mine": target.id, "other": CredentialID(8)]),
            scanners: [scanner])
        let progress = try await coordinator.discoverConsumers(for: target)
        #expect(progress.consumers.map(\.id) == ["c1"])
    }

    @Test("검증에 실패하면 구 자격증명을 폐기하지 않는다")
    func failedVerifyKeepsOld() async throws {
        let provider = FakeProvider(valueToID: ["mine": target.id])
        let coordinator = RotationCoordinator(
            provider: provider,
            scanners: [FakeScanner([("mine", CredentialConsumer(id: "c1", kind: .file, location: "/a"))])])
        var progress = try await coordinator.discoverConsumers(for: target)
        await #expect(throws: RotationError.self) {
            try await coordinator.rotate(&progress, newName: "n") { _ in false }
        }
        #expect(await provider.revokedIDs().isEmpty)
        #expect(progress.stage == .consumersUpdated)
    }

    @Test("정상 경로에서만 구 자격증명이 폐기된다")
    func happyPathRevokes() async throws {
        let provider = FakeProvider(valueToID: ["mine": target.id])
        let coordinator = RotationCoordinator(
            provider: provider,
            scanners: [FakeScanner([("mine", CredentialConsumer(id: "c1", kind: .file, location: "/a"))])])
        var progress = try await coordinator.discoverConsumers(for: target)
        try await coordinator.rotate(&progress, newName: "n") { _ in true }
        #expect(progress.isComplete)
        #expect(await provider.revokedIDs() == [target.id])
    }

    @Test("사람이 해야 하는 소비처가 있으면 멈추고 알린다")
    func manualConsumerStops() async throws {
        let provider = FakeProvider(valueToID: ["mine": target.id, "manual": target.id])
        let coordinator = RotationCoordinator(
            provider: provider,
            scanners: [FakeScanner([
                ("mine", CredentialConsumer(id: "c1", kind: .file, location: "/a")),
                ("manual", CredentialConsumer(id: "c2", kind: .manual, location: "SaaS 콘솔")),
            ])])
        var progress = try await coordinator.discoverConsumers(for: target)
        await #expect(throws: RotationError.self) {
            try await coordinator.rotate(&progress, newName: "n") { _ in true }
        }
        #expect(await provider.revokedIDs().isEmpty)
    }
}
