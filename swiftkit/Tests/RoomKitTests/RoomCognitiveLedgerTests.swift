import XCTest
@testable import RoomKit
import StateRootKit

final class RoomCognitiveLedgerTests: XCTestCase {
    private var tempBaseDir: URL = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempBaseDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("room-cognitive-tests-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempBaseDir, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create temporary directory: \(error)")
        }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempBaseDir)
        super.tearDown()
    }

    /// [레드팀 검증 1]: 마이크로 가계산 초경량 토큰 경제 및 불변 해시 잠금
    func testMicroPrecomputeCommitmentAndTokenEconomy() throws {
        let roomURL = tempBaseDir.appendingPathComponent("room-micro", isDirectory: true)
        let layout = RoomVaultLayout(roomURL: roomURL)
        let ledger = RoomCognitiveLedger()

        let precompute = RoomPrecompute(
            roomID: "room-micro",
            tenantID: "tenant:test",
            tier: .standard,
            targets: ["Sources/RoomKit/Cognitive/RoomPrecompute.swift"],
            estimate: CognitiveEstimate(
                lines: 35,
                durationSec: 45,
                declaredImports: ["CryptoKit"]
            ),
            predecessorRoomIDs: ["room-prior"]
        )

        // SHA-256 고정 해시가 비어있지 않아야 함
        XCTAssertFalse(precompute.commitmentHash.isEmpty)
        XCTAssertEqual(precompute.commitmentHash.count, 64)

        // 저장 및 로드
        let saved = try ledger.recordPrecompute(precompute, in: layout)
        XCTAssertEqual(saved.roomID, "room-micro")

        let loaded = ledger.readPrecompute(in: layout)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.commitmentHash, precompute.commitmentHash)
        XCTAssertEqual(loaded?.targets, ["Sources/RoomKit/Cognitive/RoomPrecompute.swift"])

        // JSON 직렬화 크기가 500바이트(약 128 토큰) 이하인지 엄격 검증
        let encoder = JSONEncoder()
        let data = try encoder.encode(loaded)
        XCTAssertLessThan(data.count, 500, "Micro-Precompute JSON must remain within token economy (<= 500 bytes)")
    }

    /// [레드팀 검증 2]: 기계적 실측 프로브(Mechanical Probe) 및 조작/스쿱침범 자동 Breach 거부
    func testMechanicalProbeDriftCalculationAndBreachRejection() throws {
        let probe = RoomMechanicalProbe()

        let precompute = RoomPrecompute(
            roomID: "room-eval",
            tenantID: "tenant:test",
            targets: ["apps/agent-work-todo/Sources/RoomModels.swift"],
            estimate: CognitiveEstimate(lines: 20, durationSec: 30)
        )

        // 시나리오 A: 계획과 거의 일치 (정상 Pass)
        let goodMeasurement = RoomMechanicalProbe.Measurement(
            actualTouchedFiles: ["apps/agent-work-todo/Sources/RoomModels.swift"],
            actualLinesAdded: 15,
            actualLinesDeleted: 5,
            actualDurationSec: 28.0,
            detectedImports: []
        )
        let goodDelta = probe.evaluate(precompute: precompute, measurement: goodMeasurement)
        XCTAssertEqual(goodDelta.verdict, .pass)
        XCTAssertLessThanOrEqual(goodDelta.driftScore, 15.0)
        XCTAssertFalse(goodDelta.requiresFalsificationSynapse)

        // 시나리오 B: 미신고 파일 대량 수정 및 미신고 임포트 추가 (치명적 Breach & 기각)
        let rogueMeasurement = RoomMechanicalProbe.Measurement(
            actualTouchedFiles: [
                "apps/agent-work-todo/Sources/RoomModels.swift",
                "swiftkit/Sources/RoomKit/RoomVaultLayout.swift", // 미신고 수정 1
                "apps/agent-colony-observatory/main.swift"       // 미신고 수정 2
            ],
            actualLinesAdded: 180,
            actualLinesDeleted: 40,
            actualDurationSec: 250.0,
            detectedImports: ["AppKit", "Darwin"] // 미신고 임포트
        )
        let rogueDelta = probe.evaluate(precompute: precompute, measurement: rogueMeasurement)
        XCTAssertEqual(rogueDelta.verdict, .breach)
        XCTAssertGreaterThan(rogueDelta.driftScore, 35.0)
        XCTAssertTrue(rogueDelta.requiresFalsificationSynapse)
        XCTAssertEqual(rogueDelta.unauthorizedImports, ["AppKit", "Darwin"])
    }

    /// [레드팀 검증 3]: 반증 시 자동 시냅스 결선 및 물리적 쓰기 마스크(Synaptic Write Mask) 차단
    func testAutomaticSynapseWeavingAndWriteMaskInterception() throws {
        let tenant = "tenant:test"
        let env = ["SWIFT_APP_STATE_ROOT": tempBaseDir.path]

        // 1. 과거 실패한 룸 설정
        let pastRoomURL = RoomPaths.roomDirectory(tenant: tenant, roomID: "room-failure-1", environment: env)
        let pastLayout = RoomVaultLayout(roomURL: pastRoomURL)
        let ledger = RoomCognitiveLedger()

        let pastPrecompute = RoomPrecompute(
            roomID: "room-failure-1",
            tenantID: tenant,
            targets: ["swiftkit/Sources/RoomKit/FlawedCore.swift"],
            estimate: CognitiveEstimate(lines: 10, durationSec: 20),
            predecessorRoomIDs: ["room-genesis"]
        )
        try ledger.recordPrecompute(pastPrecompute, in: pastLayout)

        // 기각된 델타 기록
        let pastDelta = RoomDelta(
            roomID: "room-failure-1",
            tenantID: tenant,
            commitmentHash: pastPrecompute.commitmentHash,
            actualTouchedFiles: ["swiftkit/Sources/RoomKit/FlawedCore.swift"],
            actualLinesAdded: 200,
            actualLinesDeleted: 0,
            actualDurationSec: 180.0,
            driftFile: 0.0,
            driftLines: 0.9,
            driftTime: 0.8,
            driftCoupling: 0.0,
            driftScore: 65.0,
            verdict: .breach,
            requiresFalsificationSynapse: true
        )
        try ledger.recordDelta(pastDelta, in: pastLayout)

        // 2. 과거 룸에 invalidates 시냅스가 자동으로 생성되었는지 확인
        let synapses = ledger.readSynapses(in: pastLayout)
        XCTAssertEqual(synapses.count, 1)
        XCTAssertEqual(synapses.first?.targetRoomID, "room-genesis")
        XCTAssertEqual(synapses.first?.kind, .invalidates)

        // 3. 신규 룸에서 과거 실패 룸의 경로를 감지하는 SynapseMask 추출
        let mask = ledger.buildSynapseMask(for: "room-next", tenant: tenant, environment: env)
        XCTAssertTrue(mask.maskedFilePaths.contains("swiftkit/Sources/RoomKit/FlawedCore.swift"))
        XCTAssertTrue(mask.blockingRoomIDs.contains("room-failure-1"))

        // 4. 신규 룸이 동일한 실패 파일 수정을 시도할 때 위반(Violation)으로 물리적 감지
        let violations = mask.checkViolations(against: [
            "swiftkit/Sources/RoomKit/FlawedCore.swift",
            "swiftkit/Sources/RoomKit/SafeCode.swift"
        ])
        XCTAssertEqual(violations, ["swiftkit/Sources/RoomKit/FlawedCore.swift"])
    }

    /// [레드팀 검증 4]: 긴급 P0 비상 탈출구 (Break-Glass) 우회 동작 검증
    func testBreakGlassProtocol() {
        let probe = RoomMechanicalProbe()

        let precompute = RoomPrecompute(
            roomID: "room-p0",
            tenantID: "tenant:test",
            targets: ["Sources/Main.swift"],
            estimate: CognitiveEstimate(lines: 5, durationSec: 10)
        )

        // 계획보다 100배 많은 파일을 건드렸으나 긴급 장애 티켓 사유로 Break-Glass 발동
        let emergencyMeasurement = RoomMechanicalProbe.Measurement(
            actualTouchedFiles: ["Sources/Main.swift", "Sources/EmergencyFix.swift"],
            actualLinesAdded: 500,
            actualLinesDeleted: 200,
            actualDurationSec: 900.0,
            isBreakGlass: true,
            breakGlassReason: "P0: Kernel panic hotfix under INCIDENT-991"
        )

        let delta = probe.evaluate(precompute: precompute, measurement: emergencyMeasurement)
        XCTAssertEqual(delta.verdict, .bypassed)
        XCTAssertTrue(delta.isBreakGlass)
        XCTAssertEqual(delta.breakGlassReason, "P0: Kernel panic hotfix under INCIDENT-991")
    }
}
