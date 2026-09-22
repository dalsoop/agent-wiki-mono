import Testing
import Foundation
@testable import RoomKit

/// work-todo 레거시 RoomWalls 삭제 후 마이그레이션·intersection 골든 테스트.
/// 저장된 JSON(`network: Bool`, `writePaths`)이 RoomKit.RoomWalls 로 올바르게 디코딩되는지,
/// 불변식 6(자식 벽 ⊆ 부모 벽)이 RoomKit 연산으로 동일하게 동작하는지 증명한다.
@Suite struct RoomWallsMigrationTests {

    // MARK: - 레거시 JSON 디코딩

    @Test func decodeLegacyBoolNetworkFalse() throws {
        let json = """
        {"writePaths":["apps/foo/**"],"network":false}
        """
        let walls = try JSONDecoder().decode(RoomWalls.self, from: Data(json.utf8))
        #expect(walls.filesystem.allowWrite == ["apps/foo/**"])
        #expect(walls.network.isClosed)
    }

    @Test func decodeLegacyBoolNetworkTrue() throws {
        let json = """
        {"writePaths":["apps/bar/**"],"network":true}
        """
        let walls = try JSONDecoder().decode(RoomWalls.self, from: Data(json.utf8))
        #expect(walls.filesystem.allowWrite == ["apps/bar/**"])
        #expect(walls.network.isFullyOpen)
    }

    @Test func decodeLegacyEmptyWalls() throws {
        let json = """
        {"writePaths":[],"network":false}
        """
        let walls = try JSONDecoder().decode(RoomWalls.self, from: Data(json.utf8))
        #expect(walls.isReadOnly)
        #expect(walls.network.isClosed)
    }

    @Test func encodeNewFormatAndRoundTrip() throws {
        let walls = RoomWalls(writePaths: ["src/**"], network: .open)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(walls)
        let decoded = try JSONDecoder().decode(RoomWalls.self, from: data)
        #expect(decoded.filesystem.allowWrite == ["src/**"])
        #expect(decoded.network.isFullyOpen)
    }

    // MARK: - intersection (불변식 6)

    @Test func intersectionSubsetPaths() {
        let parent = RoomWalls(
            filesystem: FilesystemWall(allowWrite: ["apps/foo/**", "apps/bar/**"]),
            network: .open
        )
        let child = RoomWalls(
            filesystem: FilesystemWall(allowWrite: ["apps/foo/Sources/**"]),
            network: .closed
        )
        let result = parent.intersection(child: child)
        #expect(result.filesystem.allowWrite == ["apps/foo/Sources/**"])
        #expect(result.network.isClosed)
    }

    @Test func intersectionExceedingPathsDropped() {
        let parent = RoomWalls(
            filesystem: FilesystemWall(allowWrite: ["apps/foo/**"]),
            network: .closed
        )
        let child = RoomWalls(
            filesystem: FilesystemWall(allowWrite: ["apps/foo/Sources/**", "apps/bar/**"]),
            network: .open
        )
        let result = parent.intersection(child: child)
        #expect(result.filesystem.allowWrite == ["apps/foo/Sources/**"])
        #expect(result.network.isClosed)
    }

    @Test func intersectionIdenticalPaths() {
        let parent = RoomWalls(
            filesystem: FilesystemWall(allowWrite: ["apps/foo/**"]),
            network: .open
        )
        let child = RoomWalls(
            filesystem: FilesystemWall(allowWrite: ["apps/foo/**"]),
            network: .open
        )
        let result = parent.intersection(child: child)
        #expect(result.filesystem.allowWrite == ["apps/foo/**"])
        #expect(result.network.isFullyOpen)
    }

    @Test func intersectionEmptyParentDropsAll() {
        let parent = RoomWalls(
            filesystem: FilesystemWall(allowWrite: []),
            network: .closed
        )
        let child = RoomWalls(
            filesystem: FilesystemWall(allowWrite: ["apps/foo/**"]),
            network: .open
        )
        let result = parent.intersection(child: child)
        #expect(result.filesystem.allowWrite.isEmpty)
        #expect(result.network.isClosed)
    }

    @Test func coversGlobParentCoversChild() {
        #expect(RoomWalls.covers(parent: "apps/foo/**", child: "apps/foo/Sources/**"))
        #expect(RoomWalls.covers(parent: "apps/foo/**", child: "apps/foo/**"))
        #expect(!RoomWalls.covers(parent: "apps/foo/**", child: "apps/bar/**"))
        #expect(!RoomWalls.covers(parent: "apps/foo", child: "apps/foo/Sources"))
    }

    // MARK: - NetworkWall childExceedsParent

    @Test func networkChildExceedsParent() {
        #expect(NetworkWall.childExceedsParent(child: .open, parent: .closed))
        #expect(!NetworkWall.childExceedsParent(child: .closed, parent: .open))
        #expect(!NetworkWall.childExceedsParent(child: .closed, parent: .closed))
        #expect(!NetworkWall.childExceedsParent(child: .open, parent: .open))
    }
}
