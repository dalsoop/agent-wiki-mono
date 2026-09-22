import Testing
import Foundation
@testable import PagePlanningKit

@Suite("PagePlanningKit - Swift 6 Native Planning Specification Tests")
struct PageSpecTests {

    // Helper to find repo root directory
    static func findRepoRoot() -> URL {
        var current = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while current.path != "/" {
            let candidate = current.appendingPathComponent("design/gujo-web/planning/specs")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return current
            }
            current.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    // Load all 21 canonical specs from design/gujo-web/planning/specs/
    static var allCanonicalSpecs: [PageSpec] {
        let root = findRepoRoot()
        let specsDir = root.appendingPathComponent("design/gujo-web/planning/specs")
        guard let files = try? FileManager.default.contentsOfDirectory(at: specsDir, includingPropertiesForKeys: nil) else {
            return []
        }

        let yamlFiles = files.filter { $0.pathExtension == "yaml" }
        return yamlFiles.compactMap { url in
            try? PageSpecLoader.load(fileURL: url)
        }
    }

    @Test("모든 21개 Canonical PageSpec 파싱 및 무손실 로드 검증")
    func testAllSpecsParseSuccessfully() {
        let specs = Self.allCanonicalSpecs
        #expect(specs.count >= 21, "21개 이상의 Canonical Spec이 로드되어야 합니다 (현재: \(specs.count))")

        for spec in specs {
            #expect(!spec.uuid.isEmpty, "[\(spec.slugAlias)] UUID가 비어있지 않아야 함")
            #expect(!spec.tenantUuid.isEmpty, "[\(spec.slugAlias)] Tenant UUID가 비어있지 않아야 함")
            #expect(!spec.shellUuid.isEmpty, "[\(spec.slugAlias)] Shell UUID가 비어있지 않아야 함")
            #expect(spec.targetEnvironment == "PC-Desktop-1440", "[\(spec.slugAlias)] SSOT PC 1440px 규격 준수")
        }
    }

    @Test("FSM 수학적 도달 가능성 및 데드엔드 0 보장 검증 (Swift 6 Parameterized Testing)", arguments: allCanonicalSpecs)
    func testFSMReachabilityAndZeroDeadEnds(spec: PageSpec) {
        let graph = FSMGraph.build(from: spec)
        let result = graph.verify()

        #expect(
            result.deadEnds.isEmpty,
            "[\(spec.slugAlias)] 출차수가 0인 비정상 싱크 노드(데드엔드) 발견: \(result.deadEnds)"
        )

        #expect(
            result.unrecoverableStates.isEmpty,
            "[\(spec.slugAlias)] 안전 활성 상태(ready)로 복구할 수 없는 결함 상태 발견: \(result.unrecoverableStates)"
        )

        #expect(
            result.isCompliant,
            "[\(spec.slugAlias)] FSM 복구 계약 검증 실패"
        )
    }

    @Test("시맨틱 브레이킹 체인지 (Buf / Spectral Contract Diff) 검증")
    func testSemanticContractDiffEngine() {
        let base = PageSpec(
            uuid: UUID().uuidString,
            tenantUuid: UUID().uuidString,
            shellUuid: UUID().uuidString,
            slugAlias: "TEST-01",
            title: "Base Spec",
            purpose: "Testing",
            archetype: "catalog",
            blocks: [
                BlockSpec(id: "hero-1", primitive: "HeroBlock")
            ],
            states: [
                "ready": StateSpec(notice: "Ready"),
                "error": StateSpec(notice: "Error", recovery: RecoverySpec(label: "Retry", action: "retry"))
            ],
            routeContract: RouteContractSpec(
                inbound: InboundRouteSpec(carry: ["appId": "required"])
            )
        )

        // 1. Primitive mutation (BREAKING)
        let head1 = PageSpec(
            uuid: base.uuid,
            tenantUuid: base.tenantUuid,
            shellUuid: base.shellUuid,
            slugAlias: base.slugAlias,
            title: base.title,
            purpose: base.purpose,
            archetype: base.archetype,
            blocks: [
                BlockSpec(id: "hero-1", primitive: "DataTable")  // Mutated!
            ],
            states: base.states,
            routeContract: base.routeContract
        )

        let diff1 = SemanticContractDiffer(base: base, head: head1).diff()
        #expect(diff1.hasBreakingChanges, "프리미티브 타입 변경은 BREAKING 체인지여야 함")
        #expect(diff1.breaking.first?.code == "BLOCK_PRIMITIVE_MUTATED")

        // 2. Recovery removal (BREAKING)
        let head2 = PageSpec(
            uuid: base.uuid,
            tenantUuid: base.tenantUuid,
            shellUuid: base.shellUuid,
            slugAlias: base.slugAlias,
            title: base.title,
            purpose: base.purpose,
            archetype: base.archetype,
            blocks: base.blocks,
            states: [
                "ready": StateSpec(notice: "Ready"),
                "error": StateSpec(notice: "Error", recovery: nil)  // Recovery removed!
            ],
            routeContract: base.routeContract
        )

        let diff2 = SemanticContractDiffer(base: base, head: head2).diff()
        #expect(diff2.hasBreakingChanges, "복구 액션 제거는 BREAKING 체인지여야 함")
        #expect(diff2.breaking.first?.code == "RECOVERY_REMOVED")

        // 3. Additive change (NON-BREAKING)
        let head3 = PageSpec(
            uuid: base.uuid,
            tenantUuid: base.tenantUuid,
            shellUuid: base.shellUuid,
            slugAlias: base.slugAlias,
            title: base.title,
            purpose: base.purpose,
            archetype: base.archetype,
            blocks: [
                BlockSpec(id: "hero-1", primitive: "HeroBlock"),
                BlockSpec(id: "feature-1", primitive: "FeatureCluster")  // New block added!
            ],
            states: base.states,
            routeContract: RouteContractSpec(
                inbound: InboundRouteSpec(carry: ["appId": "required", "extra": "optional"])
            )
        )

        let diff3 = SemanticContractDiffer(base: base, head: head3).diff()
        #expect(!diff3.hasBreakingChanges, "블록 및 파라미터 추가는 하위 호환(ADDITIVE)이어야 함")
        #expect(diff3.additive.count == 2)
    }

    @Test("PlanningLinter: Zero-CSS 및 1440px SSOT 헌법 검증")
    func testPlanningLinterEnforcesRules() {
        let linter = PlanningLinter()

        // Valid spec
        let validSpec = PageSpec(
            uuid: UUID().uuidString,
            tenantUuid: UUID().uuidString,
            shellUuid: UUID().uuidString,
            slugAlias: "VALID-01",
            title: "Valid Spec",
            targetEnvironment: "PC-Desktop-1440",
            purpose: "Testing",
            archetype: "catalog",
            blocks: [BlockSpec(id: "b1", primitive: "HeroBlock", description: "Clean description without CSS")],
            states: [
                "ready": StateSpec(notice: "Ready"),
                "error": StateSpec(notice: "Error", recovery: RecoverySpec(label: "Retry", action: "retry"))
            ]
        )
        let defectsValid = linter.lint(spec: validSpec)
        #expect(defectsValid.isEmpty, "올바른 스펙은 결함 0건이어야 함: \(defectsValid)")

        // Invalid spec with CSS injection
        let cssSpec = PageSpec(
            uuid: "invalid-uuid",
            tenantUuid: UUID().uuidString,
            shellUuid: UUID().uuidString,
            slugAlias: "CSS-01",
            title: "CSS Spec",
            targetEnvironment: "Mobile-375",  // Violation
            purpose: "Testing",
            archetype: "invalid-archetype",  // Violation
            blocks: [BlockSpec(id: "b1", primitive: "HeroBlock", description: "Color is #ff0000 with 16px margin")],  // Violation
            states: [:]  // Missing ready
        )
        let defectsCSS = linter.lint(spec: cssSpec)
        #expect(defectsCSS.count >= 4, "CSS 침투 및 규격 위반이 모두 검출되어야 함 (검출: \(defectsCSS.count))")
    }

    @Test("SwiftUIEmitter: 토큰 바인딩 네이티브 SwiftUI 코드 사출 검증")
    func testSwiftUIEmitterGeneratesCleanCode() {
        let emitter = SwiftUIEmitter()
        let spec = PageSpec(
            uuid: UUID().uuidString,
            tenantUuid: UUID().uuidString,
            shellUuid: UUID().uuidString,
            slugAlias: "A01",
            title: "Catalog View",
            targetEnvironment: "PC-Desktop-1440",
            purpose: "Browse Apps",
            archetype: "catalog",
            blocks: [BlockSpec(id: "hero", primitive: "HeroBlock")],
            states: [
                "ready": StateSpec(notice: "Ready"),
                "error": StateSpec(notice: "Error", recovery: RecoverySpec(label: "Retry", action: "retry"))
            ]
        )

        let swiftCode = emitter.emit(spec: spec)
        #expect(swiftCode.contains("import SwiftUI"))
        #expect(swiftCode.contains("public struct A01PageView: View"))
        #expect(swiftCode.contains("GujoSpacing.canvasPadding"))
        #expect(swiftCode.contains("GujoColor.background"))
        #expect(swiftCode.contains("enum A01State: String, CaseIterable, Sendable"))
    }

    @Test("네거티브 뮤테이션(Negative Mutation): 결함 및 데드엔드 주입 시 FSM 검증기가 100% 차단하는지 증명")
    func testFSMNegativeMutationKillsPasses() {
        // Case 1: 싱크 노드(출차수 0인 갇힌 상태) 주입
        var sinkGraph = FSMGraph(states: ["ready", "trapped"])
        sinkGraph.addTransition(source: "ready", target: "trapped", trigger: "fall_into_trap")
        // trapped 에서는 나가는 전이가 없음 (out-degree == 0)
        let sinkResult = sinkGraph.verify()
        #expect(!sinkResult.isCompliant, "갇힌 싱크 노드가 있으면 무조건 검증 실패해야 함")
        #expect(sinkResult.deadEnds.contains("trapped"), "trapped 노드가 데드엔드로 적발되어야 함")

        // Case 2: 복구 불가능한 결함 상태(error -> no recovery path to ready) 주입
        var unrecGraph = FSMGraph(states: ["ready", "error", "limbo"])
        unrecGraph.addTransition(source: "ready", target: "error", trigger: "fault:error")
        unrecGraph.addTransition(source: "error", target: "limbo", trigger: "retry")
        unrecGraph.addTransition(source: "limbo", target: "limbo", trigger: "spin") // 루프만 돌고 ready 에 못 감
        let unrecResult = unrecGraph.verify()
        #expect(!unrecResult.isCompliant, "ready로 복구할 수 없는 결함 상태가 있으면 실패해야 함")
        #expect(unrecResult.unrecoverableStates.contains("error"), "error 상태가 복구 불가 상태로 판정되어야 함")

        // Case 3: PageSpec 수준에서 recovery 누락 시 PlanningLinter 와 FSMGraph 모두 즉시 차단
        let brokenSpec = PageSpec(
            uuid: UUID().uuidString,
            tenantUuid: UUID().uuidString,
            shellUuid: UUID().uuidString,
            slugAlias: "MUT-01",
            title: "Broken Spec",
            purpose: "Mutation test",
            archetype: "catalog",
            states: [
                "ready": StateSpec(notice: "Ready"),
                "error": StateSpec(notice: "Error without recovery", recovery: nil) // 결함!
            ]
        )
        let lintDefects = PlanningLinter().lint(spec: brokenSpec)
        #expect(!lintDefects.isEmpty, "Linter가 recovery 누락을 차단해야 함")
        #expect(lintDefects.contains { $0.ruleID == "fault-state-recovery-required" })

        let brokenGraph = FSMGraph.build(from: brokenSpec)
        let fsmResult = brokenGraph.verify()
        #expect(!fsmResult.isCompliant, "FSM 검증기도 복구 경로 부재를 수학적으로 차단해야 함")
        #expect(fsmResult.unrecoverableStates.contains("error"))
    }
}

