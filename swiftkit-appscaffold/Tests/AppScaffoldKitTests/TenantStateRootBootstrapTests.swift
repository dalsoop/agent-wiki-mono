import Foundation
import Testing

@testable import AppScaffoldKit

@Suite struct TenantStateRootBootstrapTests {
    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("tenant-state-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func writeContext(home: URL, tenantID: String) throws {
        let dir = home.appendingPathComponent(".agent-tenant-isolation-manager", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let body = Data("{\"tenantID\":\"\(tenantID)\"}\n".utf8)
        try body.write(
            to: dir.appendingPathComponent("current-context.json"),
            options: .atomic
        )
    }

    @Test func setsTenantRootWhenEnvMissingAndContextExists() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try writeContext(home: home, tenantID: "tenant:personal")

        var assigned: (String, String)?
        let root = TenantStateRootBootstrap.apply(
            environment: [:],
            homeDirectory: home.path,
            assign: { assigned = ($0, $1) }
        )

        let expected = home.appendingPathComponent(".tenants/personal").path
        #expect(root == expected)
        #expect(assigned?.0 == TenantStateRootBootstrap.envKey)
        #expect(assigned?.1 == expected)
        #expect(
            TenantStateRootBootstrap.resolvedStateRoot(
                environment: [:], homeDirectory: home.path) == expected)
    }

    @Test func keepsExistingStateRootEvenWhenContextExists() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try writeContext(home: home, tenantID: "tenant:personal")

        var assigned: (String, String)?
        let root = TenantStateRootBootstrap.apply(
            environment: ["SWIFT_APP_STATE_ROOT": "/tmp/already-set"],
            homeDirectory: home.path,
            assign: { assigned = ($0, $1) }
        )

        #expect(root == nil)
        #expect(assigned == nil)
        #expect(
            TenantStateRootBootstrap.resolvedStateRoot(
                environment: ["SWIFT_APP_STATE_ROOT": "/tmp/already-set"],
                homeDirectory: home.path) == nil)
    }

    @Test func doesNothingWhenContextIsMissing() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }

        var assigned: (String, String)?
        let root = TenantStateRootBootstrap.apply(
            environment: [:],
            homeDirectory: home.path,
            assign: { assigned = ($0, $1) }
        )

        #expect(root == nil)
        #expect(assigned == nil)
        #expect(
            TenantStateRootBootstrap.resolvedStateRoot(
                environment: [:], homeDirectory: home.path) == nil)
    }
}
