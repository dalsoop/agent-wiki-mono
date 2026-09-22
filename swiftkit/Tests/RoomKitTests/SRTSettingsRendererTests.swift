import XCTest
@testable import RoomKit

final class SRTSettingsRendererTests: XCTestCase {
    func testReadOnlyPresetRender() throws {
        let walls = RoomWalls.preset(.readOnly)
        let result = SRTSettingsRenderer.render(
            walls: walls,
            workdir: "/tmp/work",
            roomDir: "/tmp/room",
            home: "/Users/test"
        )
        XCTAssertTrue(result.settingsJSON.contains("\"denyRead\""))
        XCTAssertTrue(result.settingsJSON.contains("\"allowWrite\""))
        // readOnly 에는 allowWrite 가 비어 있지만, 방 폴더와 /private/tmp 이 자동으로 추가된다
        XCTAssertTrue(result.settingsJSON.contains("/tmp/room"))
        XCTAssertTrue(result.settingsJSON.contains("/private/tmp"))
    }

    func testOpenPresetRender() throws {
        let walls = RoomWalls.preset(.open)
        let result = SRTSettingsRenderer.render(
            walls: walls,
            workdir: "/tmp/work",
            roomDir: "/tmp/room",
            home: "/Users/test"
        )
        XCTAssertTrue(result.settingsJSON.contains("allowLocalBinding"))
        // open 은 network 가 열려 있으므로 deniedDomains 가 없어야 한다
        XCTAssertFalse(result.settingsJSON.contains("\"deniedDomains\""))
    }

    func testClosedNetworkRender() throws {
        let walls = RoomWalls(
            filesystem: FilesystemWall(allowRead: ["/"]),
            network: .closed
        )
        let result = SRTSettingsRenderer.render(
            walls: walls,
            workdir: nil,
            roomDir: "/tmp/room",
            home: "/Users/test"
        )
        XCTAssertTrue(result.settingsJSON.contains("\"deniedDomains\""))
    }

    func testAllowDomainsNetworkRender() throws {
        let walls = RoomWalls(
            filesystem: FilesystemWall(),
            network: .allow(domains: ["github.com", "api.anthropic.com"])
        )
        let result = SRTSettingsRenderer.render(
            walls: walls,
            workdir: nil,
            roomDir: "/tmp/room",
            home: "/Users/test"
        )
        XCTAssertTrue(result.settingsJSON.contains("github.com"))
        XCTAssertTrue(result.settingsJSON.contains("api.anthropic.com"))
    }

    func testExecutablesAllowListUnsupported() throws {
        let walls = RoomWalls(
            filesystem: FilesystemWall(),
            network: .closed,
            executables: .allowList(["claude", "git"])
        )
        let result = SRTSettingsRenderer.render(
            walls: walls,
            workdir: nil,
            roomDir: "/tmp/room",
            home: "/Users/test"
        )
        XCTAssertFalse(result.unsupported.isEmpty)
        XCTAssertTrue(result.unsupported.first?.contains("executables.allowList") == true)
    }

    func testHostPathExecutablesNotUnsupported() throws {
        let walls = RoomWalls(
            filesystem: FilesystemWall(),
            network: .closed,
            executables: .hostPath
        )
        let result = SRTSettingsRenderer.render(
            walls: walls,
            workdir: nil,
            roomDir: "/tmp/room",
            home: "/Users/test"
        )
        XCTAssertTrue(result.unsupported.allSatisfy { !$0.contains("executables") })
    }

    func testEnableWeakerNestedSandbox() throws {
        let walls = RoomWalls.preset(.readOnly)
        let result = SRTSettingsRenderer.render(
            walls: walls,
            workdir: nil,
            roomDir: "/tmp/room",
            home: "/Users/test"
        )
        XCTAssertTrue(result.settingsJSON.contains("enableWeakerNestedSandbox"))
    }

    func testValidJSON() throws {
        let walls = RoomWalls.preset(.toolbelt, toolbelt: ["claude"])
        let result = SRTSettingsRenderer.render(
            walls: walls,
            workdir: "/tmp/work",
            roomDir: "/tmp/room",
            home: "/Users/test"
        )
        let data = result.settingsJSON.data(using: .utf8)!
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        // 키가 있는 것과 srt 스키마를 채운 것은 다르다 — 빈 사전도 NotNil 이다.
        let filesystem = try XCTUnwrap(parsed["filesystem"] as? [String: Any])
        let network = try XCTUnwrap(parsed["network"] as? [String: Any])
        XCTAssertEqual(
            Set(filesystem.keys), ["denyRead", "allowRead", "allowWrite", "denyWrite"])
        XCTAssertTrue(network.keys.contains("allowedDomains"), "\(network.keys)")
    }
}
