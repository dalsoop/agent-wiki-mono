import Testing
import Foundation
@testable import RoomKit

@Suite("RoomVault — 룸 격리 볼트, 수명주기(Seal/Archive), 승격 게이트")
struct RoomVaultTests {
    private func createTempRoomLayout() -> RoomVaultLayout {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("room-vault-test-\(UUID().uuidString)")
        return RoomVaultLayout(roomURL: tempDir)
    }

    @Test("RoomVaultLayout: 4대 영역 보장 및 초기화")
    func layoutCreation() throws {
        let layout = createTempRoomLayout()
        let manager = RoomVaultManager()

        #expect(!FileManager.default.fileExists(atPath: layout.rawDir.path))
        try manager.ensureLayout(at: layout)

        #expect(FileManager.default.fileExists(atPath: layout.rawDir.path))
        #expect(FileManager.default.fileExists(atPath: layout.curatedDir.path))
        #expect(FileManager.default.fileExists(atPath: layout.memoryDir.path))
        #expect(FileManager.default.fileExists(atPath: layout.skillsDir.path))
    }

    @Test("RoomVaultManager: curated 산출물 및 스킬 쓰기, 통계 검사")
    func writeAndInspect() throws {
        let layout = createTempRoomLayout()
        let manager = RoomVaultManager()

        // Curated 파일 쓰기
        let artifactData = "Final output data".data(using: .utf8) ?? Data()
        let target = try manager.writeCurated(relativePath: "reports/summary.md", data: artifactData, in: layout)
        #expect(FileManager.default.fileExists(atPath: target.path))

        // Skill 쓰기
        let skillFile = try manager.writeSkill(name: "custom-lint", content: "# Custom Lint", in: layout)
        #expect(FileManager.default.fileExists(atPath: skillFile.path))

        // Raw 로그 파일 하나 임의 추가
        let rawLog = layout.rawDir.appendingPathComponent("session.log")
        try ("agent raw stream".data(using: .utf8) ?? Data()).write(to: rawLog)

        let stats = manager.inspect(layout: layout)
        #expect(stats.curatedArtifactCount >= 1)
        #expect(stats.skillCount == 1)
        #expect(stats.rawSizeBytes > 0)
    }

    @Test("RoomLifecycleArchiver: Seal -> 불변 스냅샷 생성, Archive -> raw 정리 및 상태 전환")
    func lifecycleSealAndArchive() throws {
        let layout = createTempRoomLayout()
        let manager = RoomVaultManager()
        try manager.ensureLayout(at: layout)

        // 샘플 파일들
        _ = try manager.writeCurated(relativePath: "final.json", data: "{}".data(using: .utf8) ?? Data(), in: layout)
        _ = try manager.writeSkill(name: "builder", content: "# Builder", in: layout)

        let rawLog = layout.rawDir.appendingPathComponent("trace.log")
        try ("trace data".data(using: .utf8) ?? Data()).write(to: rawLog)

        let archiver = RoomLifecycleArchiver(vaultManager: manager)

        // 1. Seal
        let sealed = try archiver.seal(
            roomID: "room-abc-123",
            tenant: "default-tenant",
            layout: layout,
            budgetUsedTokens: 1500,
            durationSeconds: 42.5
        )

        #expect(sealed.state == .sealed)
        #expect(sealed.budgetUsedTokens == 1500)
        #expect(sealed.curatedArtifacts.contains("final.json"))
        #expect(sealed.skillNames.contains("builder"))
        #expect(FileManager.default.fileExists(atPath: layout.snapshotFile.path))
        #expect(FileManager.default.fileExists(atPath: rawLog.path))

        // 2. Archive -> raw 정리
        let archived = try archiver.archive(layout: layout, snapshot: sealed)
        #expect(archived.state == .archived)

        // rawLog 가 정리되었는지 확인
        #expect(!FileManager.default.fileExists(atPath: rawLog.path))
        // 하지만 curated 와 skills 는 온전히 보존
        #expect(FileManager.default.fileExists(atPath: layout.curatedDir.appendingPathComponent("final.json").path))
        #expect(FileManager.default.fileExists(atPath: layout.skillsDir.appendingPathComponent("builder/SKILL.md").path))
    }

    @Test("RoomPromotionGate: 충돌 감지 및 승격 영수증 발행")
    func promotionEvaluationAndExecution() throws {
        let layout = createTempRoomLayout()
        let manager = RoomVaultManager()
        let gate = RoomPromotionGate()

        _ = try manager.writeSkill(name: "export-helper", content: "# Export Helper\nv1", in: layout)

        let targetDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("target-tenant-skills-\(UUID().uuidString)")

        // 1. 타겟에 스킬이 없을 때 -> Ready
        let verdict1 = gate.evaluate(skillName: "export-helper", in: layout, targetDirectory: targetDir)
        #expect(verdict1 == .ready(autoMerge: true))

        // 2. 승격 실행
        let receipt = try gate.promote(
            skillName: "export-helper",
            roomID: "room-abc-123",
            tenant: "acme-tenant",
            in: layout,
            targetDirectory: targetDir,
            scope: .tenant("acme-tenant")
        )

        #expect(receipt.roomID == "room-abc-123")
        #expect(receipt.skillName == "export-helper")
        #expect(receipt.checkerOutcome == "verified")
        #expect(FileManager.default.fileExists(atPath: layout.receiptFile.path))

        let promotedSkill = targetDir.appendingPathComponent("export-helper/SKILL.md")
        #expect(FileManager.default.fileExists(atPath: promotedSkill.path))

        // 3. 같은 내용으로 재평가 -> Ready (autoMerge)
        let verdict2 = gate.evaluate(skillName: "export-helper", in: layout, targetDirectory: targetDir)
        #expect(verdict2 == .ready(autoMerge: true))

        // 4. 로컬에서 수정 후 다른 내용일 때 -> Conflict
        _ = try manager.writeSkill(name: "export-helper", content: "# Export Helper\nv2-modified", in: layout)
        let verdict3 = gate.evaluate(skillName: "export-helper", in: layout, targetDirectory: targetDir)
        guard case .conflict(let conflict) = verdict3 else {
            Issue.record("Expected conflict but got \(verdict3)")
            return
        }
        guard case .collision(let skillName, _) = conflict else {
            Issue.record("Expected collision conflict")
            return
        }
        #expect(skillName == "export-helper")

        // 5. forceMerge = false 일 때 예외 발생
        #expect(throws: PromotionGateError.self) {
            try gate.promote(
                skillName: "export-helper",
                roomID: "room-abc-123",
                tenant: "acme-tenant",
                in: layout,
                targetDirectory: targetDir,
                scope: .tenant("acme-tenant"),
                forceMerge: false
            )
        }

        // 6. forceMerge = true 일 때 덮어쓰기 승격 성공
        let forceReceipt = try gate.promote(
            skillName: "export-helper",
            roomID: "room-abc-123",
            tenant: "acme-tenant",
            in: layout,
            targetDirectory: targetDir,
            scope: .tenant("acme-tenant"),
            forceMerge: true
        )
        #expect(forceReceipt.skillName == "export-helper")
    }

    @Test("RoomPromotionGate: 다건 승격 시 영수증 보존 및 통계 반영")
    func multiReceiptPreservation() throws {
        let layout = createTempRoomLayout()
        let manager = RoomVaultManager()
        let gate = RoomPromotionGate()

        _ = try manager.writeSkill(name: "skill-one", content: "# Skill 1", in: layout)
        _ = try manager.writeSkill(name: "skill-two", content: "# Skill 2", in: layout)

        let targetDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("multi-receipt-test-\(UUID().uuidString)")

        // 1. Skill One 승격
        _ = try gate.promote(
            skillName: "skill-one",
            roomID: "room-multi",
            tenant: "tenant-a",
            in: layout,
            targetDirectory: targetDir,
            scope: .tenant("tenant-a")
        )

        // 2. Skill Two 승격
        _ = try gate.promote(
            skillName: "skill-two",
            roomID: "room-multi",
            tenant: "tenant-a",
            in: layout,
            targetDirectory: targetDir,
            scope: .tenant("tenant-a")
        )

        // 두 영수증 모두 receipts/ 아래에 보존되어 있어야 함
        #expect(FileManager.default.fileExists(atPath: layout.receiptFile(for: "skill-one").path))
        #expect(FileManager.default.fileExists(atPath: layout.receiptFile(for: "skill-two").path))

        let summary = manager.summary(roomID: "room-multi", tenantID: "tenant-a", in: layout)
        #expect(summary.hasReceipt)
        #expect(summary.receiptsCount == 2)
    }

    @Test("RoomPromotionGate: 테넌트 경계 탈출 시 unauthorizedScope 에러")
    func unauthorizedScopeGuard() throws {
        let layout = createTempRoomLayout()
        let manager = RoomVaultManager()
        let gate = RoomPromotionGate()

        _ = try manager.writeSkill(name: "rogue-skill", content: "# Rogue", in: layout)
        let targetDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rogue-target-\(UUID().uuidString)")

        #expect(throws: PromotionGateError.self) {
            try gate.promote(
                skillName: "rogue-skill",
                roomID: "room-guest",
                tenant: "tenant-guest",
                in: layout,
                targetDirectory: targetDir,
                scope: .tenant("tenant-corp") // 다른 테넌트로 불법 승격 시도
            )
        }
    }

    @Test("RoomLifecycleArchiver: 실행 중인 방 Seal 시도 시 cannotSealActiveRoom 에러")
    func activeRoomSealGuard() throws {
        let layout = createTempRoomLayout()
        let manager = RoomVaultManager()
        let archiver = RoomLifecycleArchiver(vaultManager: manager)

        #expect(throws: RoomLifecycleError.self) {
            try archiver.seal(
                roomID: "room-busy",
                tenant: "tenant-a",
                layout: layout,
                enforceDrain: true,
                isActive: true
            )
        }
    }

    @Test("RoomPromotionGate: auto-bump 정책 적용 시 마이너 버전 자동 승격 및 배포")
    func autoBumpVersionPromotion() throws {
        let layout = createTempRoomLayout()
        let manager = RoomVaultManager()
        let gate = RoomPromotionGate()

        let localContent = """
        ---
        name: auto-skill
        version: 1.0.0
        ---
        # Auto Skill
        Local revision
        """
        _ = try manager.writeSkill(name: "auto-skill", content: localContent, in: layout)

        let targetDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("target-tenant-autobump-\(UUID().uuidString)")
        let targetSkillDir = targetDir.appendingPathComponent("auto-skill")
        try FileManager.default.createDirectory(at: targetSkillDir, withIntermediateDirectories: true)
        let targetContent = """
        ---
        name: auto-skill
        version: 1.0.0
        ---
        # Auto Skill
        Target existing
        """
        try targetContent.write(
            to: targetSkillDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        // 1. reject 정책이면 충돌 발생
        #expect(throws: PromotionGateError.self) {
            try gate.promote(
                skillName: "auto-skill",
                roomID: "room-bump-test",
                tenant: "tenant-a",
                in: layout,
                targetDirectory: targetDir,
                scope: .tenant("tenant-a"),
                conflictPolicy: .reject
            )
        }

        // 2. autoBump 정책이면 1.1.0으로 자동 버전업 및 배포 성공
        let receipt = try gate.promote(
            skillName: "auto-skill",
            roomID: "room-bump-test",
            tenant: "tenant-a",
            in: layout,
            targetDirectory: targetDir,
            scope: .tenant("tenant-a"),
            conflictPolicy: .autoBump
        )

        #expect(receipt.resolution == "auto_bump:1.0.0->1.1.0")

        let deployed = try String(
            contentsOf: targetSkillDir.appendingPathComponent("SKILL.md"),
            encoding: .utf8
        )
        #expect(deployed.contains("version: 1.1.0"))
    }

    @Test("RoomLaunch: injectingVaultEnvironment 가 룸 볼트 및 테넌트 스킬 경로를 올바르게 주입")
    func injectingVaultEnvironmentAndSkillProxy() throws {
        let layout = createTempRoomLayout()
        let launch = RoomLaunch(tool: .claude, promptText: "Test task")

        let injected = launch.injectingVaultEnvironment(layout: layout, tenant: "tenant-sre")

        #expect(injected.env["ROOM_VAULT_PATH"] == layout.roomURL.path)
        #expect(injected.env["ROOM_SKILLS_PATH"] == layout.skillsDir.path)
        #expect(injected.env["ROOM_CURATED_PATH"] == layout.curatedDir.path)
        #expect(injected.env["ROOM_MEMORY_PATH"] == layout.memoryDir.path)
        #expect(injected.env["TENANT_SKILLS_PATH"] != nil)
        #expect(injected.workdir == layout.roomURL.path)

        let proxy = layout.makeSkillProxy(tenant: "tenant-sre")
        #expect(proxy.roomSkillsURL?.path == layout.skillsDir.path)
    }

    @Test("RoomMemoryIndexer: 테넌트 내 복수 룸의 memory 파일 교차 검색")
    func crossRoomMemorySearch() throws {
        let tenantRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-memory-search-\(UUID().uuidString)")
        let env = ["SWIFT_APP_STATE_ROOT": tenantRoot.path]

        let room1 = RoomVaultLayout.forRoom(tenant: "tenant-ops", roomID: "room-1", environment: env)
        let room2 = RoomVaultLayout.forRoom(tenant: "tenant-ops", roomID: "room-2", environment: env)

        let manager = RoomVaultManager()
        try manager.ensureLayout(at: room1)
        try manager.ensureLayout(at: room2)

        let mem1 = "Connection pool starvation occurred due to unclosed socket in worker A."
        let mem2 = "Memory leak in background cache manager was identified and patched."

        try mem1.write(
            to: room1.memoryDir.appendingPathComponent("incident.txt"),
            atomically: true,
            encoding: .utf8
        )
        try mem2.write(
            to: room2.memoryDir.appendingPathComponent("cache.txt"),
            atomically: true,
            encoding: .utf8
        )

        let indexer = RoomMemoryIndexer()
        let results = indexer.search(query: "starvation", tenant: "tenant-ops", environment: env)

        #expect(results.count == 1)
        #expect(results.first?.roomID == "room-1")
        #expect(results.first?.fileName == "incident.txt")
        #expect(results.first?.matchedText.contains("Connection pool starvation") == true)
    }
}
