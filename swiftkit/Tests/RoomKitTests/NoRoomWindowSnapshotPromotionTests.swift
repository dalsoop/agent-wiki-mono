import Foundation
import Testing
@testable import RoomSeatKit
import StateRootKit

@Suite("No-room windows.json promotion")
struct NoRoomWindowSnapshotPromotionTests {
    @Test("newest valid generatedAt wins and invalid JSON is ignored")
    func selectsNewestValidSnapshot() throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let support = StateRootKit.customerApplicationSupportDirectory(homeDirectory: home.path)
        let older = support.appendingPathComponent("rooms/room-default/windows.json")
        let newer = home.appendingPathComponent(".tenants/personal/rooms/room:default/windows.json")
        let invalid = home.appendingPathComponent(".tenants/default/rooms/room:default/windows.json")
        try writeSnapshot(at: older, generatedAt: Date(timeIntervalSince1970: 100), marker: "older")
        try writeSnapshot(at: newer, generatedAt: Date(timeIntervalSince1970: 200), marker: "newer")
        try FileManager.default.createDirectory(at: invalid.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: invalid)

        let result = NoRoomWindowSnapshotPromotion.promote(homeDirectory: home.path)
        let destination = support.appendingPathComponent("windows.json")
        #expect(result == .copied(from: newer, to: destination))
        let promoted = try JSONDecoder().decode(RoomWindowsSnapshot.self, from: Data(contentsOf: destination))
        #expect(promoted.windows.first?.bundleID == "newer")
        #expect(FileManager.default.fileExists(atPath: newer.path))
    }

    @Test("existing destination is never overwritten")
    func doesNotOverwriteDestination() throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let support = StateRootKit.customerApplicationSupportDirectory(homeDirectory: home.path)
        let destination = support.appendingPathComponent("windows.json")
        let legacy = support.appendingPathComponent("rooms/room-default/windows.json")
        try writeSnapshot(at: destination, generatedAt: Date(timeIntervalSince1970: 10), marker: "existing")
        try writeSnapshot(at: legacy, generatedAt: Date(timeIntervalSince1970: 20), marker: "legacy")

        #expect(NoRoomWindowSnapshotPromotion.promote(homeDirectory: home.path) == .destinationAlreadyExists(destination))
        let preserved = try JSONDecoder().decode(RoomWindowsSnapshot.self, from: Data(contentsOf: destination))
        #expect(preserved.windows.first?.bundleID == "existing")
    }

    @Test("test process refuses a destination inside the real home")
    func refusesRealHomeUnderTest() {
        let simulatedRealHome = temporaryHome()
        defer { try? FileManager.default.removeItem(at: simulatedRealHome) }
        let result = NoRoomWindowSnapshotPromotion.promote(
            homeDirectory: simulatedRealHome.path,
            fileManager: .default,
            environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"],
            processName: "xctest",
            realHomeDirectory: simulatedRealHome.path
        )
        let destination = StateRootKit.customerApplicationSupportDirectory(homeDirectory: simulatedRealHome.path)
            .appendingPathComponent("windows.json")
        #expect(result == .refusedUnsafeTestHome(destination))
    }

    private func temporaryHome() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("no-room-window-promotion-\(UUID().uuidString)", isDirectory: true)
    }

    private func writeSnapshot(at url: URL, generatedAt: Date, marker: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let snapshot = RoomWindowsSnapshot(
            roomID: "",
            generatedAt: generatedAt,
            windows: [WindowIdentity(cgWindowID: 1, pid: 1, roomID: "", bundleID: marker)]
        )
        try JSONEncoder().encode(snapshot).write(to: url)
    }
}
