import XCTest
import KnowledgeBaseWikiCore

final class TenantWorldLayerTests: XCTestCase {
    /// kit 이관 후 앱은 발행 왕복 통합만 남긴다.
    func testTenantCiteSharedObjectSucceeds() throws {
        let sharedRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("wiki-t16-shared-\(UUID().uuidString)", isDirectory: true)
        let tenantRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("wiki-t16-tenant-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: sharedRoot)
            try? FileManager.default.removeItem(at: tenantRoot)
        }
        let shared = LedgerStore(root: sharedRoot)
        let tenantA = LedgerStore(root: tenantRoot)
        let sharedObject = try shared.publish(
            author: "test", title: "공유 개념", type: "concept", body: "공유 본문")
        let catalog = WorldBindingCatalog(worlds: [
            BoundWorld(name: "gujo-wiki", rootPath: sharedRoot.path, layer: "remoteShared"),
            BoundWorld(name: "tenant-a", rootPath: tenantRoot.path, layer: "tenant", parent: "gujo-wiki"),
        ])
        XCTAssertNil(WorldCiteGate.evaluate(
            currentWorld: "tenant-a",
            citedID: sharedObject.id,
            citedWorld: "gujo-wiki",
            catalog: catalog))
        let published = try tenantA.publish(
            author: "test",
            title: "테넌트 메모",
            type: "note",
            body: "상위 인용",
            extras: LedgerPublishExtras(cites: [.init(id: sharedObject.id, rel: "cites")]))
        XCTAssertTrue(published.cites.contains { $0.id == sharedObject.id && $0.rel == "cites" })
    }

    func testConfigStorePreservesLayerParentInTempFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wiki-t16-cfg-\(UUID().uuidString)", isDirectory: true)
        let url = dir.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = BoundLedgerFile(worlds: [
            BoundWorld(name: "gujo-wiki", rootPath: "/tmp/g", layer: "remoteShared"),
            BoundWorld(name: "tenant-a", rootPath: "/tmp/a", layer: "tenant", parent: "gujo-wiki"),
        ], currentWorld: "tenant-a")
        try WorldConfigStore.save(file, to: url)
        let loaded = WorldConfigStore.load(from: url)
        XCTAssertEqual(loaded.worlds?.first { $0.name == "tenant-a" }?.parent, "gujo-wiki")
        XCTAssertEqual(loaded.worlds?.first { $0.name == "tenant-a" }?.layer, "tenant")
    }
}
