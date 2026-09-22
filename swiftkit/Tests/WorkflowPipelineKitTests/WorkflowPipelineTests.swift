import XCTest
import ContentAddressedAssetKit
@testable import WorkflowPipelineKit

final class WorkflowPipelineTests: XCTestCase {

    private func makeTestSchema() -> PipelineSchema {
        let stages = [
            StageSpec(id: "draft", name: "초안 작성", order: 1, requiredSlotIDs: []),
            StageSpec(id: "review", name: "심사 요청", order: 2, requiredSlotIDs: ["business_license", "id_card"]),
            StageSpec(id: "approved", name: "승인 완료", order: 3, requiredSlotIDs: ["business_license", "id_card", "contract_signature"])
        ]

        let slots = [
            DocumentSlotSpec(id: "business_license", title: "사업자등록증", isRequired: true),
            DocumentSlotSpec(id: "id_card", title: "신분증 사본", isRequired: true),
            DocumentSlotSpec(id: "contract_signature", title: "계약서 서명본", isRequired: true),
            DocumentSlotSpec(id: "optional_portfolio", title: "포트폴리오", isRequired: false)
        ]

        return PipelineSchema(
            id: "vendor_onboarding_v1",
            title: "파트너 온보딩 파이프라인",
            stages: stages,
            slots: slots
        )
    }

    func testSchemaDefinitionAndSorting() {
        let schema = makeTestSchema()
        XCTAssertEqual(schema.id, "vendor_onboarding_v1")
        XCTAssertEqual(schema.stages.count, 3)
        XCTAssertEqual(schema.stages.map(\.id), ["draft", "review", "approved"])
        XCTAssertEqual(schema.slots.count, 4)

        XCTAssertNotNil(schema.stage(id: "review"))
        XCTAssertNil(schema.stage(id: "unknown_stage"))
        XCTAssertNotNil(schema.slot(id: "id_card"))
        XCTAssertNil(schema.slot(id: "unknown_slot"))
    }

    func testReadinessCalculationAndMissingRequiredSlots() throws {
        let schema = makeTestSchema()
        var instance = WorkflowInstance(schemaID: schema.id, currentStageID: "draft")

        // 초기 상태: 필수 슬롯 3개 모두 미충족 -> 0.0%
        XCTAssertEqual(instance.readinessPercent(against: schema), 0.0)
        let initialMissing = instance.missingRequiredSlots(against: schema)
        XCTAssertEqual(initialMissing.count, 3)
        XCTAssertEqual(Set(initialMissing.map(\.id)), Set(["business_license", "id_card", "contract_signature"]))

        // 슬롯 1개 바인딩 -> 1/3 (33.33%)
        try WorkflowEngine.bind(slotID: "business_license", assetHash: "sha256_license_hash", in: &instance, against: schema)
        let percent1 = instance.readinessPercent(against: schema)
        XCTAssertEqual(round(percent1 * 100) / 100, 33.33)

        // 선택 슬롯(optional_portfolio) 바인딩 -> 필수 슬롯 비율에는 영향 없음 (여전히 33.33%)
        try WorkflowEngine.bind(slotID: "optional_portfolio", assetHash: "sha256_portfolio_hash", in: &instance, against: schema)
        let percentOptional = instance.readinessPercent(against: schema)
        XCTAssertEqual(round(percentOptional * 100) / 100, 33.33)

        // 두 번째 필수 슬롯 바인딩 -> 2/3 (66.67%)
        try WorkflowEngine.bind(slotID: "id_card", assetHash: "sha256_id_hash", in: &instance, against: schema)
        let percent2 = instance.readinessPercent(against: schema)
        XCTAssertEqual(round(percent2 * 100) / 100, 66.67)

        // 세 번째 필수 슬롯 바인딩 -> 3/3 (100.0%)
        try WorkflowEngine.bind(slotID: "contract_signature", assetHash: "sha256_sig_hash", in: &instance, against: schema)
        XCTAssertEqual(instance.readinessPercent(against: schema), 100.0)
        XCTAssertTrue(instance.missingRequiredSlots(against: schema).isEmpty)
    }

    func testTransitionBlockedWhenRequiredSlotsMissing() throws {
        let schema = makeTestSchema()
        var instance = WorkflowInstance(schemaID: schema.id, currentStageID: "draft")

        // 1. review 단계는 business_license, id_card 필요 -> 현재 아무것도 없음
        let check1 = instance.canTransition(to: "review", in: schema)
        XCTAssertFalse(check1.canTransition)
        XCTAssertEqual(Set(check1.missingSlots), Set(["business_license", "id_card"]))

        // 직접 전이 시도 시 에러 throw 검증
        XCTAssertThrowsError(try WorkflowEngine.transition(to: "review", in: &instance, against: schema)) { error in
            guard case WorkflowEngineError.transitionBlocked(let targetStage, let missingSlots) = error else {
                XCTFail("Expected transitionBlocked error, got \(error)")
                return
            }
            XCTAssertEqual(targetStage, "review")
            XCTAssertEqual(Set(missingSlots), Set(["business_license", "id_card"]))
        }

        // 2. business_license만 바인딩 후 전이 시도 -> id_card 누락으로 차단
        try WorkflowEngine.bind(slotID: "business_license", assetHash: "hash_license", in: &instance, against: schema)
        let check2 = instance.canTransition(to: "review", in: schema)
        XCTAssertFalse(check2.canTransition)
        XCTAssertEqual(check2.missingSlots, ["id_card"])

        XCTAssertThrowsError(try WorkflowEngine.transition(to: "review", in: &instance, against: schema))
        XCTAssertEqual(instance.currentStageID, "draft")
    }

    func testSuccessfulTransitionAfterBindingRequiredSlots() throws {
        let schema = makeTestSchema()
        var instance = WorkflowInstance(schemaID: schema.id, currentStageID: "draft")

        try WorkflowEngine.bind(slotID: "business_license", assetHash: "hash_license", in: &instance, against: schema)
        try WorkflowEngine.bind(slotID: "id_card", assetHash: "hash_id_card", in: &instance, against: schema)

        // review 단계 조건 충족
        let checkReview = instance.canTransition(to: "review", in: schema)
        XCTAssertTrue(checkReview.canTransition)
        XCTAssertTrue(checkReview.missingSlots.isEmpty)

        // 전이 실행
        try WorkflowEngine.transition(to: "review", in: &instance, against: schema)
        XCTAssertEqual(instance.currentStageID, "review")

        // approved 단계는 contract_signature 추가 필요 -> 전이 차단 확인
        XCTAssertFalse(instance.canTransition(to: "approved", in: schema).canTransition)

        // contract_signature 바인딩 후 approved 단계로 전이
        try WorkflowEngine.bind(slotID: "contract_signature", assetHash: "hash_signature", in: &instance, against: schema)
        XCTAssertTrue(instance.canTransition(to: "approved", in: schema).canTransition)

        try WorkflowEngine.transition(to: "approved", in: &instance, against: schema)
        XCTAssertEqual(instance.currentStageID, "approved")
    }

    func testUnbindAndRecheck() throws {
        let schema = makeTestSchema()
        var instance = WorkflowInstance(schemaID: schema.id, currentStageID: "draft")

        try WorkflowEngine.bind(slotID: "business_license", assetHash: "hash_license", in: &instance, against: schema)
        XCTAssertEqual(instance.boundSlots["business_license"], "hash_license")

        WorkflowEngine.unbind(slotID: "business_license", in: &instance)
        XCTAssertNil(instance.boundSlots["business_license"])
        XCTAssertEqual(instance.readinessPercent(against: schema), 0.0)
    }

    func testAssetObjectBinding() throws {
        let schema = makeTestSchema()
        var instance = WorkflowInstance(schemaID: schema.id, currentStageID: "draft")

        let asset = AssetObject(
            hash: "bafybeic5678assetobjecthash",
            sizeBytes: 1024,
            mime: "application/pdf",
            createdAt: Date(),
            originalName: "business_reg.pdf"
        )

        try WorkflowEngine.bind(slotID: "business_license", asset: asset, in: &instance, against: schema)
        XCTAssertEqual(instance.boundSlots["business_license"], "bafybeic5678assetobjecthash")
    }

    func testValidationErrors() throws {
        let schema = makeTestSchema()
        var instance = WorkflowInstance(schemaID: schema.id, currentStageID: "draft")

        // 존재하지 않는 슬롯 바인딩
        XCTAssertThrowsError(try WorkflowEngine.bind(slotID: "non_existent_slot", assetHash: "hash", in: &instance, against: schema)) { error in
            XCTAssertEqual(error as? WorkflowEngineError, .slotNotFound("non_existent_slot"))
        }

        // 빈 해시 바인딩
        XCTAssertThrowsError(try WorkflowEngine.bind(slotID: "business_license", assetHash: "   ", in: &instance, against: schema)) { error in
            XCTAssertEqual(error as? WorkflowEngineError, .emptyAssetHash)
        }

        // 스키마 ID 불일치
        let otherSchema = PipelineSchema(id: "other_schema", title: "Other", stages: [], slots: [])
        XCTAssertThrowsError(try WorkflowEngine.bind(slotID: "business_license", assetHash: "hash", in: &instance, against: otherSchema)) { error in
            XCTAssertEqual(error as? WorkflowEngineError, .schemaMismatch(expected: "other_schema", actual: "vendor_onboarding_v1"))
        }

        // 존재하지 않는 단계로 전이
        XCTAssertThrowsError(try WorkflowEngine.transition(to: "non_existent_stage", in: &instance, against: schema)) { error in
            XCTAssertEqual(error as? WorkflowEngineError, .stageNotFound("non_existent_stage"))
        }
    }

    func testSchemaWithoutRequiredSlots() {
        let schema = PipelineSchema(
            id: "simple_schema",
            title: "간단 파이프라인",
            stages: [StageSpec(id: "s1", name: "단계 1", order: 1)],
            slots: [DocumentSlotSpec(id: "optional_doc", title: "선택 서류", isRequired: false)]
        )
        let instance = WorkflowInstance(schemaID: "simple_schema", currentStageID: "s1")
        XCTAssertEqual(instance.readinessPercent(against: schema), 100.0)
    }
}
