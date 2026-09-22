import Foundation
import Testing
@testable import RoomKit

@Suite("RoomIsolation 및 WindowPolicy 단위 검증")
struct RoomIsolationTests {

    @Test("TenantContext -> RoomContext -> AppRuntimeContext 단방향 하향 주입 경로 검증")
    func testTopDownIsolationPaths() throws {
        let tempHome = URL(fileURLWithPath: "/Users/tester")
        let tenant = TenantContext.make(tenantID: "tenant:company", homeURL: tempHome)

        #expect(tenant.tenantSlug == "company")
        #expect(tenant.rootURL.path == "/Users/tester/.tenants/company")
        #expect(tenant.documentsURL.path == "/Users/tester/.tenants/company/Documents/Gujo")

        let room = RoomContext.make(tenant: tenant, roomID: "ROOM-101", roomSlug: "refactor-auth")
        #expect(room.roomURL.path == "/Users/tester/.tenants/company/rooms/ROOM-101")
        #expect(room.worktreeURL.path == "/Users/tester/.tenants/company/rooms/ROOM-101/worktree")
        #expect(room.specURL.path == "/Users/tester/.tenants/company/rooms/ROOM-101/spec.json")
        #expect(room.windowsURL.path == "/Users/tester/.tenants/company/rooms/ROOM-101/windows.json")

        let app = AppRuntimeContext.make(room: room, appSlug: "agent-browser")
        #expect(app.appDirectoryURL.path == "/Users/tester/.tenants/company/rooms/ROOM-101/apps/agent-browser")
        #expect(app.databaseURL.path == "/Users/tester/.tenants/company/rooms/ROOM-101/apps/agent-browser/app.sqlite")
        #expect(app.profileURL.path == "/Users/tester/.tenants/company/rooms/ROOM-101/apps/agent-browser/profile")
        #expect(app.cloudDocumentsURL.path == "/Users/tester/.tenants/company/Documents/Gujo/refactor-auth/agent-browser")

        // 역산 검증
        let resolved = RoomContext.resolve(fromPath: "/Users/tester/.tenants/company/rooms/ROOM-101/worktree/subfolder/file.txt")
        #expect(resolved != nil)
        #expect(resolved?.roomID == "ROOM-101")
        #expect(resolved?.tenant.tenantSlug == "company")
    }

    @Test("RoomSpec 구 JSON 호환 — windowPolicy 키가 없어도 .default 로 디코딩")
    func testLegacyRoomSpecDecodingWithoutWindowPolicy() throws {
        let legacyJSON = try #require("""
        {
            "roomID": "77777777-7777-7777-7777-777777777777",
            "task": "레거시 윈도우 정책 방",
            "verdict": "ok",
            "walls": {
                "filesystem": {
                    "denyRead": [],
                    "allowRead": [],
                    "allowWrite": [],
                    "denyWrite": []
                }
            }
        }
        """.data(using: .utf8))

        let spec = try JSONDecoder().decode(RoomSpec.self, from: legacyJSON)
        #expect(spec.windowPolicy == .default)
        #expect(spec.windowPolicy.mode == WindowIsolationMode.strictBaseline)
        #expect(spec.windowPolicy.autoFocusOnEnter)
        #expect(spec.windowPolicy.deactivationAction == .hide)
        #expect(spec.windowPolicy.maxWindowCount == 8)
    }


    @Test("WindowIdentity 및 RoomWindowsSnapshot 직렬화 왕복 검증")
    func testWindowIdentitySnapshotRoundTrip() throws {
        let win = WindowIdentity(
            cgWindowID: 402,
            pid: 1234,
            birthMachTime: 998877,
            roomID: "ROOM-101",
            bundleID: "com.microsoft.VSCode",
            spawnToken: "token-abc",
            title: "[ROOM-101] VSCode"
        )
        let snapshot = RoomWindowsSnapshot(roomID: "ROOM-101", windows: [win])

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(RoomWindowsSnapshot.self, from: data)

        #expect(decoded.roomID == "ROOM-101")
        #expect(decoded.windows.count == 1)
        #expect(decoded.windows[0].cgWindowID == 402)
        #expect(decoded.windows[0].bundleID == "com.microsoft.VSCode")
        #expect(decoded.windows[0].spawnToken == "token-abc")
    }

    @Test("RoomWindowManager 도구 기동 인자 및 환경변수 주입 검증")
    func testRoomWindowManagerLaunchArgumentsAndEnvironment() throws {
        let tempHome = URL(fileURLWithPath: "/Users/tester")
        let tenant = TenantContext.make(tenantID: "tenant:company", homeURL: tempHome)
        let room = RoomContext.make(tenant: tenant, roomID: "ROOM-101", roomSlug: "refactor-auth")
        let app = AppRuntimeContext.make(room: room, appSlug: "vscode")

        let editorArgs = RoomWindowManager.editorLaunchArguments(for: app)
        #expect(editorArgs == [
            "--user-data-dir",
            "/Users/tester/.tenants/company/rooms/ROOM-101/apps/vscode/profile",
            "/Users/tester/.tenants/company/rooms/ROOM-101/worktree"
        ])

        let browserArgs = RoomWindowManager.browserLaunchArguments(for: app)
        #expect(browserArgs == [
            "--session",
            "ROOM-101",
            "--user-data-dir",
            "/Users/tester/.tenants/company/rooms/ROOM-101/apps/vscode/profile"
        ])

        let env = RoomWindowManager.isolatedEnvironment(for: app)
        #expect(env["ROOM_ID"] == "ROOM-101")
        #expect(env["TENANT_ID"] == "tenant:company")
        #expect(env["ROOM_WORKTREE"] == "/Users/tester/.tenants/company/rooms/ROOM-101/worktree")
        #expect(env["ROOM_APP_SQLITE"] == "/Users/tester/.tenants/company/rooms/ROOM-101/apps/vscode/app.sqlite")
    }

    @Test("CustomerRoomLayout — 기기 로컬 단일 정본 경로 및 ensureDefaultRoom 자동 프로비저닝 검증")
    func testCustomerRoomLayoutAndDefaultRoomAutoProvisioning() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("customer-room-test-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let customerRoom = CustomerRoomLayout.makeCustomerRoomContext(
            roomID: "room:default"
        )
        #expect(customerRoom.roomID == "room:default")
        #expect(customerRoom.roomSlug == "default")
        #expect(customerRoom.tenant.tenantSlug == "personal")
        #expect(customerRoom.roomURL.path.contains("net.ranode.shared/rooms/room-default"))
        #expect(customerRoom.specURL.lastPathComponent == "spec.json")
        #expect(customerRoom.windowsURL.lastPathComponent == "windows.json")

        // ensureDefaultRoom 실행 검증
        let ensured = try CustomerRoomLayout.ensureDefaultRoom(
            roomID: "room:default"
        )
        #expect(FileManager.default.fileExists(atPath: ensured.roomURL.path))
        #expect(FileManager.default.fileExists(atPath: ensured.specURL.path))
        #expect(FileManager.default.fileExists(atPath: ensured.windowsURL.path))

        // 역산 검증: 고객용 로컬 경로로부터 RoomContext 복원
        let resolvedCustomer = RoomContext.resolve(fromPath: ensured.roomURL.appendingPathComponent("apps/monorepo/state.json").path)
        #expect(resolvedCustomer != nil)
        #expect(resolvedCustomer?.roomID == "room:default")
        #expect(resolvedCustomer?.tenant.tenantSlug == "personal")
    }
}
