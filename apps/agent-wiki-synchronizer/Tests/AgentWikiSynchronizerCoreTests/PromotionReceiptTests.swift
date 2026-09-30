import XCTest
import KnowledgeBaseWikiCore
@testable import AgentWikiSynchronizerCore

final class PromotionReceiptTests: XCTestCase {
    private func makeTemporaryWorld(name: String) throws -> (store: LedgerStore, world: LedgerWorld, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wiki-app-test-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("objects"), withIntermediateDirectories: true)
        let store = LedgerStore(root: dir)
        let world = LedgerWorld(name: name, rootPath: dir.path)
        return (store, world, dir)
    }

    func testPromotionReceiptRepairDryRunAndApply() throws {
        let (sourceStore, sourceWorld, sourceDir) = try makeTemporaryWorld(name: "source")
        let (targetStore, targetWorld, targetDir) = try makeTemporaryWorld(name: "target")
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: targetDir)
        }

        let sourceObj = try sourceStore.publish(
            author: "alice", title: "Original Source Concept", type: "concept", body: "Original body")
        let promotedObj = try targetStore.publish(
            author: "alice",
            title: "Original Source Concept",
            type: "concept",
            body: "Original body",
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

        // 대상(target)에만 영수증 발행하여 반쪽 상태 생성
        _ = try targetStore.publish(
            author: "alice",
            title: "프로모션 영수증",
            type: "promotion-receipt",
            body: body,
            extras: LedgerPublishExtras(cites: [
                .init(id: sourceObj.id, rel: "promotes"),
                .init(id: promotedObj.id, rel: "receipts"),
            ]))

        // verify 실패 확인
        let initialViolations = PromotionVerifier.verify(
            store: targetStore, peerWorlds: [sourceWorld, targetWorld])
        XCTAssertFalse(initialViolations.isEmpty)

        // dry-run
        let dryRun = try PromotionReceiptRepairService.repair(
            store: targetStore,
            worldName: targetWorld.name,
            peerWorlds: [sourceWorld, targetWorld],
            apply: false,
            author: "operator")
        XCTAssertEqual(dryRun.items.count, 1)
        XCTAssertEqual(dryRun.items[0].status, .dryRun)
        XCTAssertEqual(dryRun.items[0].defectKind, .missingInSource)

        // apply
        let applied = try PromotionReceiptRepairService.repair(
            store: targetStore,
            worldName: targetWorld.name,
            peerWorlds: [sourceWorld, targetWorld],
            apply: true,
            author: "operator")
        XCTAssertEqual(applied.items.count, 1)
        XCTAssertEqual(applied.items[0].status, .repaired)
        XCTAssertEqual(applied.items[0].defectKind, .missingInSource)

        // verify 통과 확인
        let finalViolations = PromotionVerifier.verify(
            store: targetStore, peerWorlds: [sourceWorld, targetWorld])
        XCTAssertTrue(finalViolations.isEmpty)
    }

    func testPromotionFailureInjectionLeavesNoHalfState() throws {
        let (sourceStore, sourceWorld, sourceDir) = try makeTemporaryWorld(name: "source")
        let (targetStore, targetWorld, targetDir) = try makeTemporaryWorld(name: "target")
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: targetDir)
        }

        let sourceObj = try sourceStore.publish(
            author: "alice", title: "Concept", type: "concept", body: "Body content")

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

        XCTAssertThrowsError(try PromotionService.publish(request))

        let targetReceipts = targetStore.scan().filter { $0.effectiveType == "promotion-receipt" }
        XCTAssertTrue(targetReceipts.isEmpty)

        let targetObjects = targetStore.scan()
        XCTAssertFalse(targetObjects.contains { $0.body == sourceObj.body })
    }
}
