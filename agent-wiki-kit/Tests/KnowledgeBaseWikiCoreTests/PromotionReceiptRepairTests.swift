import Foundation
import Testing
@testable import KnowledgeBaseWikiCore

@Suite struct PromotionReceiptRepairTests {
    private func makeTemporaryWorld(name: String) throws -> (store: LedgerStore, world: LedgerWorld, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kbw-test-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("objects"), withIntermediateDirectories: true)
        let store = LedgerStore(root: dir)
        let world = LedgerWorld(name: name, rootPath: dir.path)
        return (store, world, dir)
    }

    /// 대상에만 영수증 존재 시: dry-run은 1건 보고·쓰기 없음, --apply 시 복구 완료 후 verify 통과
    @Test func targetOnlyReceiptRepairsAndPassesVerify() throws {
        let (sourceStore, sourceWorld, sourceDir) = try makeTemporaryWorld(name: "source-world")
        let (targetStore, targetWorld, targetDir) = try makeTemporaryWorld(name: "target-world")
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: targetDir)
        }

        let sourceObj = try sourceStore.publish(
            author: "alice", title: "원문 개념", type: "concept", body: "테스트 본문 내용")
        let promotedObj = try targetStore.publish(
            author: "alice",
            title: "원문 개념",
            type: "concept",
            body: "테스트 본문 내용",
            extras: LedgerPublishExtras(cites: [.init(id: sourceObj.id, rel: "promotes")]))

        let receipt = PromotionReceipt(PromotionReceipt.Draft(
            sourceKind: "world",
            sourceWorldName: sourceWorld.name,
            sourceObjectId: sourceObj.id,
            sourceWorldRoot: sourceStore.root.standardizedFileURL.path,
            targetWorld: targetWorld.name,
            targetWorldRoot: targetStore.root.standardizedFileURL.path,
            targetObjectId: promotedObj.id,
            promotedAt: Date(),
            promotedBy: "alice"
        ))
        let body = try receipt.json()

        // 대상(target)에만 영수증 발행
        _ = try targetStore.publish(
            author: "alice",
            title: "프로모션 영수증",
            type: "promotion-receipt",
            body: body,
            extras: LedgerPublishExtras(cites: [
                .init(id: sourceObj.id, rel: "promotes"),
                .init(id: promotedObj.id, rel: "receipts"),
            ]))

        // 검증: 대상에만 있으므로 양방향 영수증 누락 위반 발생
        let initialViolations = PromotionVerifier.verify(
            store: targetStore, peerWorlds: [sourceWorld, targetWorld])
        #expect(!initialViolations.isEmpty)
        #expect(initialViolations.contains { $0.problem.contains("promotion bidirectional receipt 누락") })

        // 1) dry-run: 1건 보고, 원본에 쓰기 없음
        let dryRun = try PromotionReceiptRepairService.repair(
            store: targetStore,
            worldName: targetWorld.name,
            peerWorlds: [sourceWorld, targetWorld],
            apply: false,
            author: "operator")
        #expect(dryRun.items.count == 1)
        #expect(dryRun.items[0].status == .dryRun)
        #expect(dryRun.items[0].defectKind == .missingInSource)
        #expect(sourceStore.scan().filter { $0.effectiveType == "promotion-receipt" }.isEmpty)

        // 2) apply: 1건 복구 쓰기 완료
        let applied = try PromotionReceiptRepairService.repair(
            store: targetStore,
            worldName: targetWorld.name,
            peerWorlds: [sourceWorld, targetWorld],
            apply: true,
            author: "operator")
        #expect(applied.items.count == 1)
        #expect(applied.items[0].status == .repaired)
        #expect(applied.items[0].defectKind == .missingInSource)
        #expect(sourceStore.scan().filter { $0.effectiveType == "promotion-receipt" }.count == 1)

        // 3) 복구 후 verify 통과 확인
        let afterTargetViolations = PromotionVerifier.verify(
            store: targetStore, peerWorlds: [sourceWorld, targetWorld])
        #expect(afterTargetViolations.isEmpty)

        let afterSourceViolations = PromotionVerifier.verify(
            store: sourceStore, peerWorlds: [sourceWorld, targetWorld])
        #expect(afterSourceViolations.isEmpty)
    }

    /// 양쪽 다 영수증이 이미 있는 경우: 0건 보고
    @Test func bothReceiptsExistReturnsZeroItems() throws {
        let (sourceStore, sourceWorld, sourceDir) = try makeTemporaryWorld(name: "source-world")
        let (targetStore, targetWorld, targetDir) = try makeTemporaryWorld(name: "target-world")
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: targetDir)
        }

        let sourceObj = try sourceStore.publish(
            author: "alice", title: "원문 개념", type: "concept", body: "테스트 본문 내용")
        let promotedObj = try targetStore.publish(
            author: "alice",
            title: "원문 개념",
            type: "concept",
            body: "테스트 본문 내용",
            extras: LedgerPublishExtras(cites: [.init(id: sourceObj.id, rel: "promotes")]))

        let receipt = PromotionReceipt(PromotionReceipt.Draft(
            sourceKind: "world",
            sourceWorldName: sourceWorld.name,
            sourceObjectId: sourceObj.id,
            sourceWorldRoot: sourceStore.root.standardizedFileURL.path,
            targetWorld: targetWorld.name,
            targetWorldRoot: targetStore.root.standardizedFileURL.path,
            targetObjectId: promotedObj.id,
            promotedAt: Date(),
            promotedBy: "alice"
        ))
        let body = try receipt.json()

        // 양쪽 모두 영수증 발행
        _ = try targetStore.publish(
            author: "alice",
            title: "프로모션 영수증",
            type: "promotion-receipt",
            body: body,
            extras: LedgerPublishExtras(cites: [
                .init(id: sourceObj.id, rel: "promotes"),
                .init(id: promotedObj.id, rel: "receipts"),
            ]))
        _ = try sourceStore.publish(
            author: "alice",
            title: "프로모션 링크",
            type: "promotion-receipt",
            body: body,
            extras: LedgerPublishExtras(cites: [
                .init(id: sourceObj.id, rel: "receipts"),
                .init(id: promotedObj.id, rel: "promoted-as"),
            ]))

        let report = try PromotionReceiptRepairService.repair(
            store: targetStore,
            worldName: targetWorld.name,
            peerWorlds: [sourceWorld, targetWorld],
            apply: false,
            author: "operator")
        #expect(report.items.isEmpty)
    }

    /// 양쪽 다 영수증이 없는 경우: 보고만 수행, 복구 시도(쓰기) 없음
    @Test func bothReceiptsMissingReportOnly() throws {
        let (sourceStore, sourceWorld, sourceDir) = try makeTemporaryWorld(name: "source-world")
        let (targetStore, targetWorld, targetDir) = try makeTemporaryWorld(name: "target-world")
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: targetDir)
        }

        let sourceObj = try sourceStore.publish(
            author: "alice", title: "원문 개념", type: "concept", body: "테스트 본문 내용")
        _ = try targetStore.publish(
            author: "alice",
            title: "원문 개념",
            type: "concept",
            body: "테스트 본문 내용",
            extras: LedgerPublishExtras(cites: [.init(id: sourceObj.id, rel: "promotes")]))

        // 양쪽 어디에도 promotion-receipt 없음
        let dryRun = try PromotionReceiptRepairService.repair(
            store: targetStore,
            worldName: targetWorld.name,
            peerWorlds: [sourceWorld, targetWorld],
            apply: false,
            author: "operator")
        #expect(dryRun.items.count == 1)
        #expect(dryRun.items[0].defectKind == .missingBoth)
        #expect(dryRun.items[0].status == .unrepairable)

        // apply: true 일 때도 쓰기 없이 보고만 수행
        let applied = try PromotionReceiptRepairService.repair(
            store: targetStore,
            worldName: targetWorld.name,
            peerWorlds: [sourceWorld, targetWorld],
            apply: true,
            author: "operator")
        #expect(applied.items.count == 1)
        #expect(applied.items[0].defectKind == .missingBoth)
        #expect(applied.items[0].status == .unrepairable)
        #expect(targetStore.scan().filter { $0.effectiveType == "promotion-receipt" }.isEmpty)
        #expect(sourceStore.scan().filter { $0.effectiveType == "promotion-receipt" }.isEmpty)
    }

    /// 승격 중 원본 쓰기 실패 주입: 에러 반환, 대상에 반쪽 상태가 남지 않음
    @Test func promotionFailureInjectionLeavesNoHalfState() throws {
        let (sourceStore, sourceWorld, sourceDir) = try makeTemporaryWorld(name: "source-world")
        let (targetStore, targetWorld, targetDir) = try makeTemporaryWorld(name: "target-world")
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: targetDir)
        }

        let sourceObj = try sourceStore.publish(
            author: "alice", title: "원문 개념", type: "concept", body: "승격 대상 본문")

        let preview = try PromotionService.preview(
            sourceStore: sourceStore,
            source: sourceObj,
            repository: nil,
            sourceWorldName: sourceWorld.name,
            targetWorld: targetWorld,
            promotedBy: "alice")

        let request = PromotionPublishRequest(
            sourceStore: sourceStore,
            targetStore: targetStore,
            source: sourceObj,
            repository: nil,
            sourceWorldName: sourceWorld.name,
            targetWorld: targetWorld,
            promotedBy: "alice",
            confirmationToken: preview.confirmationToken,
            simulateSourceReceiptFailure: true)

        #expect(throws: PromotionError.self) {
            try PromotionService.publish(request)
        }

        // 대상(target)에 반쪽 영수증이나 찌꺼기 객체가 남지 않음을 검증
        let targetReceipts = targetStore.scan().filter { $0.effectiveType == "promotion-receipt" }
        #expect(targetReceipts.isEmpty)

        // 대상 원장에 승격 객체도 롤백되어 없어야 함
        let targetObjects = targetStore.scan()
        #expect(!targetObjects.contains { $0.body == sourceObj.body })

        // verify 검증 시 이상 없음
        let violations = PromotionVerifier.verify(
            store: targetStore, peerWorlds: [sourceWorld, targetWorld])
        #expect(violations.isEmpty)
    }
}
