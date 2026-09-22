import XCTest
@testable import TenantGuardKit

final class TenantGuardKitTests: XCTestCase {
    private var tempHomeDir: URL!

    override func setUp() {
        super.setUp()
        TenantGuard.isRequired = false
        tempHomeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tenantguard-test-\(UUID().uuidString)", isDirectory: true)
        do { try FileManager.default.createDirectory(at: tempHomeDir, withIntermediateDirectories: true) } catch { _ = error }
    }

    override func tearDown() {
        TenantGuard.isRequired = false
        if let tempHomeDir {
            try? FileManager.default.removeItem(at: tempHomeDir)
        }
        super.tearDown()
    }

    func testInitialValueAndMutation() {
        XCTAssertFalse(TenantGuard.isRequired)
        TenantGuard.isRequired = true
        XCTAssertTrue(TenantGuard.isRequired)
        TenantGuard.isRequired = false
        XCTAssertFalse(TenantGuard.isRequired)
    }

    func testRequireContextWhenDisabled() {
        TenantGuard.isRequired = false
        // isRequired가 false이면 빈 환경변수나 파일이 없어도 exit되지 않고 즉시 반환해야 함
        TenantGuard.requireContext(environment: [:], homeDirectory: tempHomeDir.path)
    }

    func testResolvedTenantIDFromEnvironment() {
        let env = ["TENANT_ID": "tenant-alpha"]
        let resolved = TenantGuard.resolvedTenantID(environment: env, homeDirectory: tempHomeDir.path)
        XCTAssertEqual(resolved, "tenant-alpha")
    }

    func testResolvedTenantIDFromFile() throws {
        let managerDir = tempHomeDir.appendingPathComponent(".agent-tenant-isolation-manager", isDirectory: true)
        try FileManager.default.createDirectory(at: managerDir, withIntermediateDirectories: true)
        let contextFile = managerDir.appendingPathComponent("current-context.json")
        let json = """
        {
            "tenantID": "tenant-beta",
            "slug": "beta-slug"
        }
        """
        try json.data(using: .utf8)?.write(to: contextFile)

        let resolved = TenantGuard.resolvedTenantID(environment: [:], homeDirectory: tempHomeDir.path)
        XCTAssertEqual(resolved, "tenant-beta")
    }

    func testResolvedTenantIDEmptyWhenNotFound() {
        let resolved = TenantGuard.resolvedTenantID(environment: [:], homeDirectory: tempHomeDir.path)
        XCTAssertNil(resolved)
    }

    func testConcurrentIsRequiredAccess() {
        let iterationCount = 5_000
        DispatchQueue.concurrentPerform(iterations: iterationCount) { i in
            if i % 2 == 0 {
                TenantGuard.isRequired = true
            } else {
                TenantGuard.isRequired = false
            }
            _ = TenantGuard.isRequired
        }
        // 최종적으로 정상 원복 가능한지 확인
        TenantGuard.isRequired = false
        XCTAssertFalse(TenantGuard.isRequired)
    }
}
