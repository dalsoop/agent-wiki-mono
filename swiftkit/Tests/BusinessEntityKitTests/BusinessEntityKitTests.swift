import XCTest
@testable import BusinessEntityKit

final class BusinessEntityKitTests: XCTestCase {
    var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bek-\(UUID().uuidString)", isDirectory: true)
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch { _ = error }
        TenantBridge.entitiesURLOverride = dir.appendingPathComponent("entities.json")
    }

    override func tearDown() {
        TenantBridge.entitiesURLOverride = nil
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testExplicitWins() {
        write(active: "ranode", slugs: ["ranode"])
        let r = TenantBridge.resolve(explicit: "otherco")
        XCTAssertEqual(r.slug, "otherco")
        XCTAssertEqual(r.source, .override)
    }

    func testActiveSlug() throws {
        write(active: "ranode", slugs: ["ranode", "otherco"])
        let r = TenantBridge.resolve()
        XCTAssertEqual(r.slug, "ranode")
        XCTAssertEqual(r.source, .businessEntity)
    }

    func testMissingFileFallsBack() {
        let r = TenantBridge.resolve()
        XCTAssertEqual(r.slug, TenantBridge.fallbackSlug)
        XCTAssertEqual(r.source, .fallback)
    }

    func testSkipsArchivedWhenNoActive() {
        let root: [String: Any] = [
            "entities": [
                ["slug": "old", "archived": true],
                ["slug": "live", "archived": false],
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: root)
        try! data.write(to: TenantBridge.entitiesURL)
        XCTAssertEqual(TenantBridge.resolve().slug, "live")
    }

    func testConcurrentEntitiesURLOverrideAccess() {
        let dummyURL1 = URL(fileURLWithPath: "/tmp/test1.json")
        let dummyURL2 = URL(fileURLWithPath: "/tmp/test2.json")
        DispatchQueue.concurrentPerform(iterations: 5_000) { i in
            if i % 2 == 0 {
                TenantBridge.entitiesURLOverride = dummyURL1
            } else {
                TenantBridge.entitiesURLOverride = dummyURL2
            }
            _ = TenantBridge.entitiesURLOverride
            _ = TenantBridge.entitiesURL
        }
    }

    private func write(active: String, slugs: [String]) {
        let entities = slugs.map { ["slug": $0, "archived": false] as [String: Any] }
        let data = try! JSONSerialization.data(withJSONObject: ["activeSlug": active, "entities": entities])
        try! data.write(to: TenantBridge.entitiesURL)
    }
}
