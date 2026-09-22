import Foundation
import Testing
@testable import KnowledgeBaseWikiCore

@Suite struct FleetRegistryTests {
    @Test func roundTripSaveLoad() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fleet-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FleetStore(fileURL: url)
        var reg = FleetRegistry(
            workspaceRoots: ["/tmp/ws"],
            worlds: [
                FleetWorldEntry(
                    name: "gujo-wiki", rootPath: "/Users/x/gujo-wiki",
                    kind: .personal, defaultWeight: 0.5),
                FleetWorldEntry(
                    name: "swift-app-mono", rootPath: "/Users/x/mono/main/.wiki",
                    kind: .repo, defaultWeight: 1.0),
            ])
        try store.save(reg)
        let loaded = try store.load()
        #expect(loaded.version == 1)
        #expect(loaded.worlds.count == 2)
        #expect(loaded.worlds.first { $0.name == "gujo-wiki" }?.defaultWeight == 0.5)
        #expect(loaded.workspaceRoots == ["/tmp/ws"])

        reg = try store.register(
            name: "laravel-mono", rootPath: "/Users/x/laravel/.wiki", kind: .repo)
        #expect(reg.worlds.count == 3)
        #expect(reg.worlds.contains { $0.name == "laravel-mono" })
    }

    @Test func emptyLoadWhenMissingFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fleet-missing-\(UUID().uuidString).json")
        let store = FleetStore(fileURL: url)
        let reg = try store.load()
        #expect(reg.worlds.isEmpty)
    }

    @Test func doctorFlagsMissingAndRelative() throws {
        let reg = FleetRegistry(worlds: [
            FleetWorldEntry(name: "ghost", rootPath: "/no/such/wiki-\(UUID().uuidString)", kind: .repo),
            FleetWorldEntry(name: "rel", rootPath: "apps/bar/.wiki", kind: .repo),
            FleetWorldEntry(
                name: "tmpish",
                rootPath: "/var/folders/0l/fake/tmp.xxx/mono/.wiki",
                kind: .repo),
        ])
        let report = FleetDiagnostics.doctor(
            registry: reg,
            ledgerConfig: LedgerConfig(worlds: [], currentWorld: nil)
        )
        #expect(report.hasErrors)
        #expect(report.issues.contains { $0.code == "missing-path" })
        #expect(report.issues.contains { $0.code == "relative-path" })
        #expect(report.issues.contains { $0.code == "ephemeral-path" })
    }

    @Test func scanFindsWikiUnderWorkspace() throws {
        let fm = FileManager.default
        let ws = fm.temporaryDirectory.appendingPathComponent("ws-\(UUID().uuidString)")
        let mono = ws.appendingPathComponent("demo-mono")
        let wiki = mono.appendingPathComponent("main/.wiki/objects")
        try fm.createDirectory(at: wiki, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: ws) }

        let candidates = FleetDiagnostics.scan(
            workspaceRoots: [ws.path],
            registry: FleetRegistry(),
            personalWikiPaths: []
        )
        #expect(candidates.contains { $0.name == "demo-mono" && $0.kind == .repo })
        #expect(candidates.contains {
            $0.rootPath.hasSuffix("demo-mono/main/.wiki") || $0.rootPath.hasSuffix("demo-mono/main/.wiki/")
        })
    }

    @Test func registerReplacesSameName() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fleet-rep-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FleetStore(fileURL: url)
        _ = try store.register(name: "a", rootPath: "/tmp/a1", kind: .repo)
        let reg = try store.register(name: "a", rootPath: "/tmp/a2", kind: .repo, defaultWeight: 0.3)
        #expect(reg.worlds.filter { $0.name == "a" }.count == 1)
        #expect(reg.worlds.first?.rootPath == "/tmp/a2")
        #expect(reg.worlds.first?.defaultWeight == 0.3)
    }
}
