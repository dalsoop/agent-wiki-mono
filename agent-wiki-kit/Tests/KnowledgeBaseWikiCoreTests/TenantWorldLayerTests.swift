import Foundation
import Testing
@testable import KnowledgeBaseWikiCore

@Suite struct TenantWorldLayerTests {
    private func makeCatalog(shared: URL, tenantA: URL, tenantB: URL) -> WorldBindingCatalog {
        WorldBindingCatalog(worlds: [
            BoundWorld(name: "gujo-wiki", rootPath: shared.path, layer: "remoteShared", parent: nil),
            BoundWorld(name: "tenant-a", rootPath: tenantA.path, layer: "tenant", parent: "gujo-wiki"),
            BoundWorld(name: "tenant-b", rootPath: tenantB.path, layer: "tenant", parent: "gujo-wiki"),
        ])
    }

    private func temporaryRoot(_ label: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("wiki-kit-tenant-\(label)-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func tenantCiteSharedObjectSucceeds() throws {
        let sharedRoot = temporaryRoot("shared")
        let tenantARoot = temporaryRoot("tenant-a")
        let tenantBRoot = temporaryRoot("tenant-b")
        defer {
            try? FileManager.default.removeItem(at: sharedRoot)
            try? FileManager.default.removeItem(at: tenantARoot)
            try? FileManager.default.removeItem(at: tenantBRoot)
        }
        let shared = LedgerStore(root: sharedRoot)
        let tenantA = LedgerStore(root: tenantARoot)
        let sharedObject = try shared.publish(
            author: "test", title: "공유 개념", type: "concept", body: "공유 본문")
        let catalog = makeCatalog(shared: sharedRoot, tenantA: tenantARoot, tenantB: tenantBRoot)
        let denial = WorldCiteGate.evaluate(
            currentWorld: "tenant-a",
            citedID: sharedObject.id,
            citedWorld: "gujo-wiki",
            catalog: catalog)
        #expect(denial == nil)
        let published = try tenantA.publish(
            author: "test",
            title: "테넌트 메모",
            type: "note",
            body: "상위 인용",
            extras: LedgerPublishExtras(cites: [.init(id: sharedObject.id, rel: "cites")]))
        #expect(published.cites.contains { $0.id == sharedObject.id && $0.rel == "cites" })
    }

    @Test func sharedCiteTenantObjectRejected() throws {
        let sharedRoot = temporaryRoot("shared")
        let tenantARoot = temporaryRoot("tenant-a")
        let tenantBRoot = temporaryRoot("tenant-b")
        defer {
            try? FileManager.default.removeItem(at: sharedRoot)
            try? FileManager.default.removeItem(at: tenantARoot)
            try? FileManager.default.removeItem(at: tenantBRoot)
        }
        let tenantA = LedgerStore(root: tenantARoot)
        let tenantObject = try tenantA.publish(
            author: "test", title: "테넌트만", type: "note", body: "비공개")
        let catalog = makeCatalog(shared: sharedRoot, tenantA: tenantARoot, tenantB: tenantBRoot)
        let denial = WorldCiteGate.evaluate(
            currentWorld: "gujo-wiki",
            citedID: tenantObject.id,
            citedWorld: "tenant-a",
            catalog: catalog)
        #expect(denial != nil)
        #expect(denial?.message.contains("upward-only") ?? false)
    }

    @Test func siblingTenantCiteRejected() throws {
        let sharedRoot = temporaryRoot("shared")
        let tenantARoot = temporaryRoot("tenant-a")
        let tenantBRoot = temporaryRoot("tenant-b")
        defer {
            try? FileManager.default.removeItem(at: sharedRoot)
            try? FileManager.default.removeItem(at: tenantARoot)
            try? FileManager.default.removeItem(at: tenantBRoot)
        }
        let tenantB = LedgerStore(root: tenantBRoot)
        let siblingObject = try tenantB.publish(
            author: "test", title: "형제 메모", type: "note", body: "다른 테넌트")
        let catalog = makeCatalog(shared: sharedRoot, tenantA: tenantARoot, tenantB: tenantBRoot)
        let denial = WorldCiteGate.evaluate(
            currentWorld: "tenant-a",
            citedID: siblingObject.id,
            citedWorld: "tenant-b",
            catalog: catalog)
        #expect(denial != nil)
        #expect(denial?.message.contains("sibling") ?? false)
    }

    @Test func envWorldLockRejectsOtherWorldPublish() {
        let denial = WorldEnvLock.denial(
            environment: [WorldEnvLock.environmentKey: "tenant-a"],
            explicitWorld: "gujo-wiki",
            isWrite: true)
        #expect(denial == "AGENT_WIKI_WORLD=tenant-a blocks --world gujo-wiki on publish")
        #expect(WorldEnvLock.denial(
            environment: [WorldEnvLock.environmentKey: "tenant-a"],
            explicitWorld: "tenant-a",
            isWrite: true) == nil)
        #expect(WorldEnvLock.denial(
            environment: [WorldEnvLock.environmentKey: "tenant-a"],
            explicitWorld: "gujo-wiki",
            isWrite: false) == nil)
    }

    @Test func searchScopeExcludesSiblingWorld() {
        let catalog = makeCatalog(
            shared: URL(fileURLWithPath: "/tmp/shared-fixture"),
            tenantA: URL(fileURLWithPath: "/tmp/tenant-a-fixture"),
            tenantB: URL(fileURLWithPath: "/tmp/tenant-b-fixture"))
        let tenantScope = WorldSearchScope.names(current: "tenant-a", catalog: catalog)
        #expect(tenantScope == ["tenant-a", "gujo-wiki"])
        #expect(!tenantScope.contains("tenant-b"))
        let sharedScope = WorldSearchScope.names(current: "gujo-wiki", catalog: catalog)
        #expect(sharedScope == ["gujo-wiki"])
        #expect(!sharedScope.contains("tenant-a"))
        #expect(!sharedScope.contains("tenant-b"))
    }

    @Test func worldListJSONIncludesLayerAndParent() {
        let catalog = makeCatalog(
            shared: URL(fileURLWithPath: "/tmp/shared-fixture"),
            tenantA: URL(fileURLWithPath: "/tmp/tenant-a-fixture"),
            tenantB: URL(fileURLWithPath: "/tmp/tenant-b-fixture"))
        let items = WorldListPresentation.items(catalog: catalog, selectedName: "tenant-a")
        let tenant = items.first { $0.name == "tenant-a" }
        #expect(tenant?.layer == "tenant")
        #expect(tenant?.parent == "gujo-wiki")
        #expect(tenant?.selected ?? false)
        let shared = items.first { $0.name == "gujo-wiki" }
        #expect(shared?.layer == "remoteShared")
        #expect(shared?.parent == nil)
        let text = WorldListPresentation.plainText(items: items)
        #expect(text.contains("tenant"))
        #expect(text.contains("remoteShared"))
    }

    @Test func tenantParentMustBeRemoteShared() {
        let catalog = WorldBindingCatalog(worlds: [
            BoundWorld(name: "gujo-wiki", rootPath: "/tmp/g", layer: "remoteShared"),
            BoundWorld(name: "person-x", rootPath: "/tmp/p", layer: "localPerson"),
        ])
        #expect(WorldTenantBinding.validateTenantParent(parentName: "gujo-wiki", catalog: catalog) == nil)
        #expect(
            WorldTenantBinding.validateTenantParent(parentName: "person-x", catalog: catalog)
                == "--parent requires remoteShared layer: person-x is localPerson")
        #expect(
            WorldTenantBinding.requireTenantFlags(layer: "tenant", parent: nil)
                == "tenant world requires --parent <shared-world>")
    }

    @Test func promotionOnlyAlongParentChain() {
        let catalog = makeCatalog(
            shared: URL(fileURLWithPath: "/tmp/shared-fixture"),
            tenantA: URL(fileURLWithPath: "/tmp/tenant-a-fixture"),
            tenantB: URL(fileURLWithPath: "/tmp/tenant-b-fixture"))
        #expect(WorldPromotionGate.denial(
            currentWorld: "tenant-a", targetWorld: "gujo", catalog: catalog) == nil)
        #expect(WorldPromotionGate.denial(
            currentWorld: "tenant-a", targetWorld: "gujo-wiki", catalog: catalog) == nil)
        let sibling = WorldPromotionGate.denial(
            currentWorld: "tenant-a", targetWorld: "tenant-b", catalog: catalog)
        #expect(sibling?.contains("parent chain") ?? false)
        let unbound = WorldPromotionGate.denial(
            currentWorld: "gujo-wiki",
            targetWorld: "tenant-a",
            catalog: catalog,
            skipChainWhenUnbound: true)
        #expect(unbound == nil)
    }

    @Test func configStorePreservesLayerParentInTempFile() throws {
        let url = temporaryRoot("cfg").appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let file = BoundLedgerFile(worlds: [
            BoundWorld(name: "gujo-wiki", rootPath: "/tmp/g", layer: "remoteShared"),
            BoundWorld(name: "tenant-a", rootPath: "/tmp/a", layer: "tenant", parent: "gujo-wiki"),
        ], currentWorld: "tenant-a")
        try WorldConfigStore.save(file, to: url)
        let loaded = WorldConfigStore.load(from: url)
        #expect(loaded.worlds?.first { $0.name == "tenant-a" }?.parent == "gujo-wiki")
        #expect(loaded.worlds?.first { $0.name == "tenant-a" }?.layer == "tenant")
    }

    @Test func parseWorldFlagsAndCiteIDs() {
        let parsed = WorldCLIFlags.parse(["tenant-a", "~/w", "--layer", "tenant", "--parent", "gujo-wiki"])
        #expect(parsed.positionals == ["tenant-a", "~/w"])
        #expect(parsed.layer == "tenant")
        #expect(parsed.parent == "gujo-wiki")
        #expect(parsed.unknownOption == nil)
        let unknown = WorldCLIFlags.parse(["n", "p", "--oops"])
        #expect(unknown.unknownOption == "--oops")
        let cites = WorldPublishCiteIDs.extract(from: ["publish", "--title", "t", "--cite", "abc", "rel"])
        #expect(cites == ["abc"])
    }
}
