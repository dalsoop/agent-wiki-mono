import Foundation
import Testing
import CommandKit
@testable import RuleMiningKit

@Suite("HomeostasisFleetOrchestratorTests - DNA-RNA 생명주기 및 5대 방벽 시뮬레이션")
struct HomeostasisFleetOrchestratorTests {

    // MARK: - Mock 에이전트 편제
    final class MockSensor: SensorAgentProtocol, Sendable {
        let ticketToReturn: RNAPerturbationTicket?
        init(ticketToReturn: RNAPerturbationTicket?) {
            self.ticketToReturn = ticketToReturn
        }

        func scanDrift(in directory: URL, genome: HomeostasisGenome) async throws -> RNAPerturbationTicket? {
            return ticketToReturn
        }
    }

    final class MockWorker: RemediationWorkerAgentProtocol, Sendable {
        let agentIdentity: String
        let patchToReturn: RemediationPatch

        init(agentIdentity: String = "agent:worker-01@macbook", patchToReturn: RemediationPatch) {
            self.agentIdentity = agentIdentity
            self.patchToReturn = patchToReturn
        }

        func remediate(ticket: RNAPerturbationTicket, in directory: URL) async throws -> RemediationPatch {
            return patchToReturn
        }
    }

    final class MockReviewer: ReviewerVerifierAgentProtocol, @unchecked Sendable {
        let agentIdentity: String
        let verifier: AntiCorruptionGateVerifier
        let tiaSuccess: Bool

        var apoptosisCount = 0
        var sleepConsolidatedCount = 0

        init(
            agentIdentity: String = "agent:reviewer-01@macbook",
            verifier: AntiCorruptionGateVerifier = AntiCorruptionGateVerifier(),
            tiaSuccess: Bool = true
        ) {
            self.agentIdentity = agentIdentity
            self.verifier = verifier
            self.tiaSuccess = tiaSuccess
        }

        func verify(patch: RemediationPatch, ticket: RNAPerturbationTicket, genome: HomeostasisGenome, directory: URL) async throws -> GateVerificationResult {
            return verifier.verify(
                patch: patch,
                genome: genome,
                ticket: ticket,
                reviewerAgent: agentIdentity,
                tiaResult: tiaSuccess
            )
        }

        func executeApoptosis(in directory: URL, reason: String) async throws {
            apoptosisCount += 1
        }

        func consolidateToSleepCycle(patch: RemediationPatch, genome: HomeostasisGenome) async throws {
            sleepConsolidatedCount += 1
        }
    }

    private func makeTestOrchestrator() -> HomeostasisFleetOrchestrator {
        let okSnapshot = HostCompileGate.Snapshot(load1: 1.0, ncpu: 8, loadPerCore: 0.1, frontendCount: 0, hold: false, reason: "ok")
        let okProvider = MockHostCompileGateProvider(stubSnapshot: okSnapshot)
        return HomeostasisFleetOrchestrator(hostGateProvider: okProvider)
    }

    // MARK: - Test Cases

    @Test("정상 수복 사이클: 5대 방벽 및 TIA 100% 통과 후 수면 주기 각인")
    func testSuccessfulRemediationCycle() async throws {
        let orchestrator = makeTestOrchestrator()
        let genome = HomeostasisGenome(slug: "test-app-swift")
        let ticket = RNAPerturbationTicket(
            targetSlug: "test-app-swift",
            scopeFiles: ["Sources/Main.swift"],
            missingKits: ["AppPersistenceKit"],
            stress: HormoneStressMetric(driftSeverity: 0.3, oscillationCount: 0)
        )
        let cleanPatch = RemediationPatch(
            authorAgent: "agent:worker-01@macbook",
            touchedFiles: ["Sources/Main.swift"],
            gitDiff: "+ import AppPersistenceKit\n+ AppPersistence.save(data)",
            leveragedKits: ["AppPersistenceKit"],
            rationale: "공용 킷 표준 I/O 채택"
        )

        let sensor = MockSensor(ticketToReturn: ticket)
        let worker = MockWorker(agentIdentity: "agent:worker-01@macbook", patchToReturn: cleanPatch)
        let reviewer = MockReviewer(agentIdentity: "agent:reviewer-01@macbook", tiaSuccess: true)

        let report = try await orchestrator.executeCycle(
            directory: URL(fileURLWithPath: "/tmp/test-app-swift"),
            genome: genome,
            sensor: sensor,
            worker: worker,
            reviewer: reviewer
        )

        #expect(report.isSuccess == true)
        #expect(report.apoptosisTriggered == false)
        #expect(reviewer.sleepConsolidatedCount == 1)
        #expect(reviewer.apoptosisCount == 0)
    }

    @Test("Gate 2 위반: 빈 catch {} 꼼수 코드 감지 시 즉각 세포자멸사(Apoptosis) 소각")
    func testSemanticPurityViolationTriggersApoptosis() async throws {
        let orchestrator = makeTestOrchestrator()
        let genome = HomeostasisGenome(slug: "test-app-swift")
        let ticket = RNAPerturbationTicket(
            targetSlug: "test-app-swift",
            scopeFiles: ["Sources/Main.swift"],
            missingKits: ["AppPersistenceKit"],
            stress: HormoneStressMetric(driftSeverity: 0.3, oscillationCount: 0)
        )
        // 꼼수 diff: 빈 catch {} 삽입
        let sneakyPatch = RemediationPatch(
            authorAgent: "agent:worker-01@macbook",
            touchedFiles: ["Sources/Main.swift"],
            gitDiff: "+ do { try save() } catch { }",
            leveragedKits: [],
            rationale: "에러 무마"
        )

        let sensor = MockSensor(ticketToReturn: ticket)
        let worker = MockWorker(agentIdentity: "agent:worker-01@macbook", patchToReturn: sneakyPatch)
        let reviewer = MockReviewer(agentIdentity: "agent:reviewer-01@macbook", tiaSuccess: true)

        let report = try await orchestrator.executeCycle(
            directory: URL(fileURLWithPath: "/tmp/test-app-swift"),
            genome: genome,
            sensor: sensor,
            worker: worker,
            reviewer: reviewer
        )

        #expect(report.isSuccess == false)
        #expect(report.apoptosisTriggered == true)
        #expect(reviewer.apoptosisCount == 1)
        #expect(reviewer.sleepConsolidatedCount == 0)
        #expect(report.rejectionReasons.contains(where: { $0.contains("semanticPurityViolation") }))
    }

    @Test("Gate 3 위반: Scope Lock 탈출 (미인가 파일 무단 수정) 시 즉각 소각")
    func testScopeEscapeTriggersApoptosis() async throws {
        let orchestrator = makeTestOrchestrator()
        let genome = HomeostasisGenome(slug: "test-app-swift")
        let ticket = RNAPerturbationTicket(
            targetSlug: "test-app-swift",
            scopeFiles: ["Sources/Main.swift"],
            missingKits: ["AppPersistenceKit"],
            stress: HormoneStressMetric(driftSeverity: 0.2, oscillationCount: 0)
        )
        // Bounding Box 밖의 Package.swift까지 무단 침범
        let trespassingPatch = RemediationPatch(
            authorAgent: "agent:worker-01@macbook",
            touchedFiles: ["Sources/Main.swift", "Unauthorized/Secrets.swift"],
            gitDiff: "+ some changes",
            leveragedKits: [],
            rationale: "무단 스코프 탈출"
        )

        let sensor = MockSensor(ticketToReturn: ticket)
        let worker = MockWorker(agentIdentity: "agent:worker-01@macbook", patchToReturn: trespassingPatch)
        let reviewer = MockReviewer(agentIdentity: "agent:reviewer-01@macbook", tiaSuccess: true)

        let report = try await orchestrator.executeCycle(
            directory: URL(fileURLWithPath: "/tmp/test-app-swift"),
            genome: genome,
            sensor: sensor,
            worker: worker,
            reviewer: reviewer
        )

        #expect(report.isSuccess == false)
        #expect(report.apoptosisTriggered == true)
        #expect(report.rejectionReasons.contains(where: { $0.contains("unapprovedScopeEscape") }))
    }

    @Test("Gate 1 위반: Maker-Checker 위반 (수정자와 리뷰어가 동일 신원일 때 차단)")
    func testMakerCheckerViolationBlock() async throws {
        let orchestrator = makeTestOrchestrator()
        let genome = HomeostasisGenome(slug: "test-app-swift")
        let ticket = RNAPerturbationTicket(
            targetSlug: "test-app-swift",
            scopeFiles: ["Sources/Main.swift"],
            missingKits: [],
            stress: HormoneStressMetric(driftSeverity: 0.1, oscillationCount: 0)
        )
        let cleanPatch = RemediationPatch(
            authorAgent: "agent:same-identity@macbook",
            touchedFiles: ["Sources/Main.swift"],
            gitDiff: "+ good diff",
            leveragedKits: [],
            rationale: "자가 승인 시도"
        )

        let sensor = MockSensor(ticketToReturn: ticket)
        let worker = MockWorker(agentIdentity: "agent:same-identity@macbook", patchToReturn: cleanPatch)
        // 동일 신원
        let reviewer = MockReviewer(agentIdentity: "agent:same-identity@macbook", tiaSuccess: true)

        let report = try await orchestrator.executeCycle(
            directory: URL(fileURLWithPath: "/tmp/test-app-swift"),
            genome: genome,
            sensor: sensor,
            worker: worker,
            reviewer: reviewer
        )

        #expect(report.isSuccess == false)
        #expect(report.rejectionReasons.contains(where: { $0.contains("makerCheckerViolation") }))
    }

    @Test("Gate 4: 3회 이상 실패 시 항진동 서킷 브레이커 사전 발동")
    func testAntiOscillationCircuitBreaker() async throws {
        let orchestrator = makeTestOrchestrator()
        let genome = HomeostasisGenome(slug: "test-app-swift")
        // 진동 횟수 3회
        let overloadedTicket = RNAPerturbationTicket(
            targetSlug: "test-app-swift",
            scopeFiles: ["Sources/Main.swift"],
            missingKits: [],
            stress: HormoneStressMetric(driftSeverity: 0.5, oscillationCount: 3)
        )
        let patch = RemediationPatch(
            authorAgent: "agent:worker-01@macbook",
            touchedFiles: ["Sources/Main.swift"],
            gitDiff: "+ clean diff",
            leveragedKits: [],
            rationale: "정상 diff"
        )

        let sensor = MockSensor(ticketToReturn: overloadedTicket)
        let worker = MockWorker(agentIdentity: "agent:worker-01@macbook", patchToReturn: patch)
        let reviewer = MockReviewer(agentIdentity: "agent:reviewer-01@macbook", tiaSuccess: true)

        let report = try await orchestrator.executeCycle(
            directory: URL(fileURLWithPath: "/tmp/test-app-swift"),
            genome: genome,
            sensor: sensor,
            worker: worker,
            reviewer: reviewer
        )

        #expect(report.isSuccess == false)
        #expect(report.apoptosisTriggered == true)
        #expect(report.summary.contains("서킷 브레이커"))
        #expect(reviewer.apoptosisCount == 1)
    }

    // MARK: - AIMD 부하 조절 및 HostCompileGate 상태 연동 테스트

    @Test("AIMD 동적 부하 조절: HostCompileGate hold 시 Multiplicative Decrease 수축 및 해제 시 회복")
    func testHostCompileGateThrottlingAndRecovery() async throws {
        // 1. 게이트 차단 상태 (hold: true, frontendCount 16 >= 16)
        let blockedSnapshot = HostCompileGate.Snapshot(
            load1: 12.0,
            ncpu: 16,
            loadPerCore: 0.75,
            frontendCount: 16,
            hold: true,
            reason: "swift-frontend 16>=16"
        )
        let blockedProvider = MockHostCompileGateProvider(stubSnapshot: blockedSnapshot)
        let orchestrator = HomeostasisFleetOrchestrator(
            hostGateProvider: blockedProvider,
            limiter: AIMDConcurrencyLimiter(initialLimit: 4.0, minLimit: 1.0, maxLimit: 16.0, backoffRatio: 0.5)
        )

        let genome = HomeostasisGenome(slug: "throttled-app-swift")
        let sensor = MockSensor(ticketToReturn: nil)
        let worker = MockWorker(patchToReturn: RemediationPatch(authorAgent: "worker", touchedFiles: [], gitDiff: "", leveragedKits: [], rationale: ""))
        let reviewer = MockReviewer()

        // 첫 사이클: 게이트 차단으로 조기 반환 및 AIMD 한도 4.0 -> 2.0 수축
        let report1 = try await orchestrator.executeCycle(
            directory: URL(fileURLWithPath: "/tmp/throttled-app-swift"),
            genome: genome,
            sensor: sensor,
            worker: worker,
            reviewer: reviewer
        )

        #expect(report1.isSuccess == false)
        #expect(report1.rejectionReasons.contains(where: { $0.contains("HostCompileGate") }))
        let limitAfterDrop = await orchestrator.limiter.currentLimit
        #expect(limitAfterDrop == 2.0)

        // 2. 게이트 정상 해제 상태 (hold: false)
        let okSnapshot = HostCompileGate.Snapshot(
            load1: 2.0,
            ncpu: 16,
            loadPerCore: 0.12,
            frontendCount: 0,
            hold: false,
            reason: "ok"
        )
        let okProvider = MockHostCompileGateProvider(stubSnapshot: okSnapshot)
        let recoveredOrchestrator = HomeostasisFleetOrchestrator(
            hostGateProvider: okProvider,
            limiter: AIMDConcurrencyLimiter(initialLimit: 2.0, minLimit: 1.0, maxLimit: 16.0, backoffRatio: 0.5, additiveIncrement: 1.0)
        )

        // 정상 사이클 실행 (결손 없음: 완만한 Additive Increase 회복)
        let report2 = try await recoveredOrchestrator.executeCycle(
            directory: URL(fileURLWithPath: "/tmp/throttled-app-swift"),
            genome: genome,
            sensor: sensor,
            worker: worker,
            reviewer: reviewer
        )

        #expect(report2.isSuccess == true)
        let limitAfterRecovery = await recoveredOrchestrator.limiter.currentLimit
        #expect(limitAfterRecovery > 2.0)
    }

    // MARK: - 생체 전주기 E2E 라이프사이클 테스트 (낮 세션 수복 ➔ 밤 수면 주기 ➔ 차세대 DNA 래칫 각인)

    @Test("생체 전주기 E2E 파이프라인: 낮 세션 수복 성공 ➔ SWS/REM 수면 주기 ➔ 차세대 DNA 래칫 각인")
    func testIntegratedE2ELifecycleWithDNARatchet() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do { try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true) } catch { _ = error }
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let isolatedEpisodeStore = WakeEpisodeStore(storeDirectory: tempDir.appendingPathComponent("wake-episodes"))
        let dreamSimulator = DreamSimulatorEngine()
        let isolatedSleepOrchestrator = SleepCycleOrchestrator(
            episodeStore: isolatedEpisodeStore,
            dreamSimulator: dreamSimulator,
            storageDirectory: tempDir.appendingPathComponent("sleep")
        )

        let okSnapshot = HostCompileGate.Snapshot(load1: 1.0, ncpu: 8, loadPerCore: 0.1, frontendCount: 0, hold: false, reason: "ok")
        let okProvider = MockHostCompileGateProvider(stubSnapshot: okSnapshot)

        let orchestrator = HomeostasisFleetOrchestrator(
            hostGateProvider: okProvider,
            sleepOrchestrator: isolatedSleepOrchestrator,
            episodeStore: isolatedEpisodeStore,
            limiter: AIMDConcurrencyLimiter(initialLimit: 4.0)
        )

        let initialGenome = HomeostasisGenome(
            slug: "core-service-swift",
            canonicalVersion: "1.0.0",
            invariants: [
                GenomeInvariant(ruleID: "rule-seed-01", description: "Seed invariant")
            ],
            requiredKits: ["AppPersistenceKit"]
        )

        let ticket = RNAPerturbationTicket(
            targetSlug: "core-service-swift",
            scopeFiles: ["Sources/CoreService.swift"],
            missingKits: ["AppPersistenceKit"],
            stress: HormoneStressMetric(driftSeverity: 0.2, oscillationCount: 0, buildLatencyMs: 120.0)
        )

        let validPatch = RemediationPatch(
            authorAgent: "agent:worker-01@macbook",
            touchedFiles: ["Sources/CoreService.swift"],
            gitDiff: "+ import AppPersistenceKit\n+ AppPersistenceKit.persist(data)",
            leveragedKits: ["AppPersistenceKit"],
            rationale: "공용 퍼시스턴스 킷 연동으로 결손 수복"
        )

        let sensor = MockSensor(ticketToReturn: ticket)
        let worker = MockWorker(agentIdentity: "agent:worker-01@macbook", patchToReturn: validPatch)
        let reviewer = MockReviewer(agentIdentity: "agent:reviewer-01@macbook", tiaSuccess: true)

        let sampleCorpus = [
            "class SafeService { func run() { let x = 1 } }",
            "struct SafeModel { let name: String }"
        ]

        // E2E 통합 라이프사이클 실행
        let report = try await orchestrator.executeFullLifecycle(
            directory: URL(fileURLWithPath: "/tmp/core-service-swift"),
            genome: initialGenome,
            sensor: sensor,
            worker: worker,
            reviewer: reviewer,
            sampleCorpus: sampleCorpus,
            dryRun: false
        )

        // 1. 생체 주기 완수 검증
        #expect(report.isSuccess == true)
        #expect(report.initialPhase == .wake)
        #expect(report.finalPhase == .awakening)
        #expect(report.hotPathReport.isSuccess == true)
        #expect(report.sleepCycleResult != nil)

        // 2. 차세대 DNA 래칫 각인 검증
        let ratcheted = try #require(report.ratchetedGenome)
        #expect(ratcheted.slug == initialGenome.slug)
        #expect(ratcheted.canonicalVersion == "1.0.1") // 버전 1.0.0 -> 1.0.1 래칫 승격
        #expect(ratcheted.invariants.contains(where: { $0.ruleID == "rule-seed-01" })) // 이전 세대 불변식 100% 보존
        #expect(ratcheted.invariants.count >= initialGenome.invariants.count) // 단조 증가 (Ratchet)
        #expect(ratcheted.merkleProof != initialGenome.merkleProof) // 암호학적 머클 증명 갱신

        // 3. 에피소드 및 텔레메트리 적층 확인
        let recordedEpisodes = isolatedEpisodeStore.queryEpisodes()
        #expect(!recordedEpisodes.isEmpty)
        #expect(recordedEpisodes.contains(where: { $0.agentId == "agent:worker-01@macbook" }))
    }

    @Test("생체 전주기 실패 격리: 각성기 방벽 위반 시 Apoptosis 소각 및 수면기 전이 차단")
    func testIntegratedLifecycleFailureHaltsAtWakePhase() async throws {
        let orchestrator = makeTestOrchestrator()
        let genome = HomeostasisGenome(slug: "faulty-app-swift", canonicalVersion: "1.0.0")

        let ticket = RNAPerturbationTicket(
            targetSlug: "faulty-app-swift",
            scopeFiles: ["Sources/Main.swift"],
            missingKits: [],
            stress: HormoneStressMetric(driftSeverity: 0.3, oscillationCount: 0)
        )

        // Gate 2 꼼수 위반 diff
        let badPatch = RemediationPatch(
            authorAgent: "agent:worker-bad@macbook",
            touchedFiles: ["Sources/Main.swift"],
            gitDiff: "+ do { try dangerousCall() } catch { }",
            leveragedKits: [],
            rationale: "빈 catch로 에러 은폐"
        )

        let sensor = MockSensor(ticketToReturn: ticket)
        let worker = MockWorker(agentIdentity: "agent:worker-bad@macbook", patchToReturn: badPatch)
        let reviewer = MockReviewer(agentIdentity: "agent:reviewer-01@macbook", tiaSuccess: true)

        let report = try await orchestrator.executeFullLifecycle(
            directory: URL(fileURLWithPath: "/tmp/faulty-app-swift"),
            genome: genome,
            sensor: sensor,
            worker: worker,
            reviewer: reviewer
        )

        #expect(report.isSuccess == false)
        #expect(report.hotPathReport.apoptosisTriggered == true)
        #expect(report.sleepCycleResult == nil) // 수면기 진입 차단
        #expect(report.ratchetedGenome == nil) // 차세대 DNA 각인 취소
        #expect(reviewer.apoptosisCount == 1)
        #expect(report.finalPhase == HomeostasisPhase.wake)
    }
}

