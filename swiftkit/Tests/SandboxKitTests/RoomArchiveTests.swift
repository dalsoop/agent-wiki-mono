import Foundation
@testable import SandboxKit
import XCTest

final class RoomArchiveTests: XCTestCase {
    var tempHome: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempHome, FileManager.default.fileExists(atPath: tempHome.path) {
            try? FileManager.default.removeItem(at: tempHome)
        }
        try super.tearDownWithError()
    }

    func testSoftArchiveMovesToArchiveDirectory() throws {
        let ctx = try SandboxContext.allocate(tenant: "nike", roomID: "room-nike-promo", homeDirectory: tempHome.path)
        let sampleFile = ctx.sandboxDirectory.appendingPathComponent("draft.json")
        try "draft content".write(to: sampleFile, atomically: true, encoding: .utf8)

        let archiveName = try RoomArchive.archive(roomID: "room-nike-promo", homeDirectory: tempHome.path)

        // 활성 샌드박스에서는 사라짐
        XCTAssertFalse(FileManager.default.fileExists(atPath: ctx.sandboxDirectory.path))

        // .archive/ 보관소에 존재
        let archived = try RoomArchive.listArchived(homeDirectory: tempHome.path)
        XCTAssertEqual(archived.count, 1)
        XCTAssertEqual(archived[0].archiveName, archiveName)
        XCTAssertEqual(archived[0].originalRoomID, "room-nike-promo")
        XCTAssertEqual(archived[0].tenantSlug, "nike")
        XCTAssertFalse(archived[0].isExpired)
    }

    func testPruneExpiredDeletesOnlyAfter7Days() throws {
        let ctx = try SandboxContext.allocate(tenant: "acme", roomID: "room-acme-old", homeDirectory: tempHome.path)
        let archiveName = try RoomArchive.archive(
            roomID: "room-acme-old",
            homeDirectory: tempHome.path,
            retentionDays: 7.0,
            now: Date().addingTimeInterval(-8 * 86400) // 8일 전 아카이브된 것으로 시뮬레이션
        )

        let archived = try RoomArchive.listArchived(homeDirectory: tempHome.path, now: Date())
        XCTAssertEqual(archived.count, 1)
        XCTAssertTrue(archived[0].isExpired)

        let purged = try RoomArchive.pruneExpired(homeDirectory: tempHome.path, now: Date())
        XCTAssertEqual(purged, [archiveName])

        let remaining = try RoomArchive.listArchived(homeDirectory: tempHome.path)
        XCTAssertEqual(remaining.count, 0)
    }

    func testRestoreReturnsArchivedRoomToActive() throws {
        let ctx = try SandboxContext.allocate(tenant: "brand", roomID: "room-brand-restore", homeDirectory: tempHome.path)
        let archiveName = try RoomArchive.archive(roomID: "room-brand-restore", homeDirectory: tempHome.path)

        let restoredID = try RoomArchive.restore(archiveName: archiveName, homeDirectory: tempHome.path)
        XCTAssertEqual(restoredID, "room-brand-restore")
        XCTAssertTrue(FileManager.default.fileExists(atPath: ctx.sandboxDirectory.path))
    }
}
