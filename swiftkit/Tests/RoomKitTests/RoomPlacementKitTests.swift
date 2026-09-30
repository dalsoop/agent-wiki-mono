import XCTest
@testable import RoomPlacementKit

final class RoomPlacementKitTests: XCTestCase {
    /// XCTest 는 테스트 메서드마다 인스턴스를 새로 만들므로 폴더가 겹치지 않는다.
    private let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("room-placement-kit-tests-\(UUID().uuidString)", isDirectory: true)

    override func setUpWithError() throws {
        try super.setUpWithError()
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }

    // MARK: - 1. roomDirectory ignores tenant and uses SWIFT_APP_ROOMS_ROOT

    func testRoomDirectoryIgnoresTenantAndUsesRoomsRootEnv() {
        let tempHome = tempDirectory.appendingPathComponent("home", isDirectory: true)
        let customRooms = tempDirectory.appendingPathComponent("custom-rooms", isDirectory: true)

        // 1-1. 기본: <home>/.rooms
        let defaultRoot = RoomPaths.roomsRoot(homeDirectory: tempHome.path)
        XCTAssertEqual(defaultRoot.path, tempHome.appendingPathComponent(".rooms", isDirectory: true).path)

        // 1-2. SWIFT_APP_ROOMS_ROOT 환경변수 우선
        let envRoot = RoomPaths.roomsRoot(
            environment: ["SWIFT_APP_ROOMS_ROOT": customRooms.path],
            homeDirectory: tempHome.path
        )
        XCTAssertEqual(envRoot.path, customRooms.path)

        // 1-3. roomDirectory 는 tenant 파라미터를 무시하고 roomsRoot 를 사용
        let roomA = RoomPaths.roomDirectory(
            tenant: "tenant-alpha",
            roomID: "ROOM-100",
            environment: ["SWIFT_APP_ROOMS_ROOT": customRooms.path],
            homeDirectory: tempHome.path
        )
        let roomB = RoomPaths.roomDirectory(
            tenant: "tenant-beta",
            roomID: "ROOM-100",
            environment: ["SWIFT_APP_ROOMS_ROOT": customRooms.path],
            homeDirectory: tempHome.path
        )
        let roomNoTenant = RoomPaths.roomDirectory(
            roomID: "ROOM-100",
            environment: ["SWIFT_APP_ROOMS_ROOT": customRooms.path],
            homeDirectory: tempHome.path
        )

        XCTAssertEqual(roomA.path, customRooms.appendingPathComponent("ROOM-100", isDirectory: true).path)
        XCTAssertEqual(roomA.path, roomB.path, "tenant 매개변수가 달라도 동일한 단일 루트 경로를 반환해야 합니다.")
        XCTAssertEqual(roomA.path, roomNoTenant.path)

        // 1-4. specURL 및 windowsURL 헬퍼 검증
        let specURL = RoomPaths.specURL(
            tenant: "tenant-alpha",
            roomID: "ROOM-100",
            environment: ["SWIFT_APP_ROOMS_ROOT": customRooms.path],
            homeDirectory: tempHome.path
        )
        XCTAssertEqual(specURL.path, customRooms.appendingPathComponent("ROOM-100/spec.json", isDirectory: false).path)

        let windowsURL = RoomPaths.windowsURL(
            roomID: "ROOM-100",
            tenant: "tenant-alpha",
            environment: ["SWIFT_APP_ROOMS_ROOT": customRooms.path],
            homeDirectory: tempHome.path
        )
        XCTAssertEqual(windowsURL.path, customRooms.appendingPathComponent("ROOM-100/windows.json", isDirectory: false).path)
    }

    /// 없는 방 + 테넌트 없음 → 단일 루트. `"default"` 테넌트 경로를 만들지 않는다.
    func testWindowsURLUnknownRoomWithoutTenantUsesRoomsRoot() {
        let tempHome = tempDirectory.appendingPathComponent("home-missing", isDirectory: true)
        let blocked = [RoomPaths.roomsRootEnvironmentKey: ""]
        let url = RoomPaths.windowsURL(
            roomID: "ROOM-MISSING",
            tenant: nil,
            environment: blocked,
            homeDirectory: tempHome.path
        )
        let expected = tempHome
            .appendingPathComponent(".rooms", isDirectory: true)
            .appendingPathComponent("ROOM-MISSING", isDirectory: true)
            .appendingPathComponent("windows.json", isDirectory: false)
        XCTAssertEqual(url.path, expected.path)
        XCTAssertFalse(url.path.contains("/.tenants/"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    }

    /// 없는 방 + 명시 테넌트, 단일 루트 꺼짐 → 그 테넌트의 예전 경로.
    func testWindowsURLUnknownRoomWithExplicitTenantUsesTenantPath() {
        let tempHome = tempDirectory.appendingPathComponent("home-explicit", isDirectory: true)
        let blocked = [RoomPaths.roomsRootEnvironmentKey: ""]
        let url = RoomPaths.windowsURL(
            roomID: "ROOM-MISSING",
            tenant: "tenant:acme",
            environment: blocked,
            homeDirectory: tempHome.path
        )
        let expected = tempHome
            .appendingPathComponent(".tenants/acme/rooms/ROOM-MISSING/windows.json", isDirectory: false)
        XCTAssertEqual(url.standardizedFileURL.path, expected.standardizedFileURL.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    }

    // MARK: - 1b. 이전 전에는 예전 테넌트 경로, roomsRoot 가 생기면 단일 루트

    func testRoomDirectoryStaysOnTenantPathUntilRoomsRootExists() throws {
        let tempHome = tempDirectory.appendingPathComponent("home", isDirectory: true)
        let legacy = tempHome.appendingPathComponent(".tenants/team-dev/rooms/ROOM-1", isDirectory: true)
        let single = tempHome.appendingPathComponent(".rooms/ROOM-1", isDirectory: true)

        XCTAssertFalse(RoomPaths.isSingleRootActive(homeDirectory: tempHome.path))
        XCTAssertEqual(
            RoomPaths.roomDirectory(tenant: "tenant:team-dev", roomID: "ROOM-1", homeDirectory: tempHome.path).path,
            legacy.path
        )

        try FileManager.default.createDirectory(
            at: tempHome.appendingPathComponent(".rooms", isDirectory: true), withIntermediateDirectories: true)

        XCTAssertTrue(RoomPaths.isSingleRootActive(homeDirectory: tempHome.path))
        XCTAssertEqual(
            RoomPaths.roomDirectory(tenant: "tenant:team-dev", roomID: "ROOM-1", homeDirectory: tempHome.path).path,
            single.path
        )
    }

    // MARK: - 2. Lookup hit in the new root; hit via transitional tenant path; miss returns nil

    func testFindRoomDirectoryHitInNewRoot() throws {
        let tempHome = tempDirectory.appendingPathComponent("home", isDirectory: true)
        let newRoomDir = tempHome.appendingPathComponent(".rooms/ROOM-NEW", isDirectory: true)
        try FileManager.default.createDirectory(at: newRoomDir, withIntermediateDirectories: true)

        let found = RoomPaths.findRoomDirectory(
            roomID: "ROOM-NEW",
            homeDirectory: tempHome.path
        )
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.resolvingSymlinksInPath().path, newRoomDir.resolvingSymlinksInPath().path)
    }

    func testFindRoomDirectoryHitViaTransitionalTenantPath() throws {
        let tempHome = tempDirectory.appendingPathComponent("home", isDirectory: true)
        let legacyTenantRoom = tempHome.appendingPathComponent(".tenants/team-dev/rooms/ROOM-LEGACY", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyTenantRoom, withIntermediateDirectories: true)

        // 2-1. tenant 가 명시된 경우 (stat-only 전환 폴백)
        let foundWithTenant = RoomPaths.findRoomDirectory(
            roomID: "ROOM-LEGACY",
            tenant: "team-dev",
            homeDirectory: tempHome.path
        )
        XCTAssertNotNil(foundWithTenant)
        XCTAssertEqual(foundWithTenant?.resolvingSymlinksInPath().path, legacyTenantRoom.resolvingSymlinksInPath().path)

        // tenant slug 에 "tenant:" 접두사가 있어도 정상 정규화
        let foundWithPrefixedTenant = RoomPaths.findRoomDirectory(
            roomID: "ROOM-LEGACY",
            tenant: "tenant:team-dev",
            homeDirectory: tempHome.path
        )
        XCTAssertEqual(foundWithPrefixedTenant?.resolvingSymlinksInPath().path, legacyTenantRoom.resolvingSymlinksInPath().path)

        // 2-2. tenant 가 생략된 경우 (각 tenant 폴더 탐색, _ 폴더는 건너뜀)
        let foundWithoutTenant = RoomPaths.findRoomDirectory(
            roomID: "ROOM-LEGACY",
            tenant: nil,
            homeDirectory: tempHome.path
        )
        XCTAssertNotNil(foundWithoutTenant)
        XCTAssertEqual(foundWithoutTenant?.resolvingSymlinksInPath().path, legacyTenantRoom.resolvingSymlinksInPath().path)
    }

    func testFindRoomDirectoryMissReturnsNil() throws {
        let tempHome = tempDirectory.appendingPathComponent("home", isDirectory: true)
        let dummyTenant = tempHome.appendingPathComponent(".tenants/team-dev/rooms", isDirectory: true)
        try FileManager.default.createDirectory(at: dummyTenant, withIntermediateDirectories: true)

        let miss = RoomPaths.findRoomDirectory(
            roomID: "NON-EXISTENT-ROOM",
            tenant: "team-dev",
            homeDirectory: tempHome.path
        )
        XCTAssertNil(miss)

        let missNoTenant = RoomPaths.findRoomDirectory(
            roomID: "NON-EXISTENT-ROOM",
            tenant: nil,
            homeDirectory: tempHome.path
        )
        XCTAssertNil(missNoTenant)
    }

    // MARK: - 3. Performance guard: 4,000 room folders and legacy subfolders

    func testPerformanceGuardWith4000RoomsAndMiss() throws {
        let tempHome = tempDirectory.appendingPathComponent("home", isDirectory: true)
        let tenantRooms = tempHome.appendingPathComponent(".tenants/giant-tenant/rooms", isDirectory: true)
        try FileManager.default.createDirectory(at: tenantRooms, withIntermediateDirectories: true)

        // 4,000개 룸 폴더 생성
        for i in 0..<4000 {
            let roomFolder = tenantRooms.appendingPathComponent("room-\(i)", isDirectory: true)
            try FileManager.default.createDirectory(at: roomFolder, withIntermediateDirectories: false)
        }

        // spec.json 을 가진 레거시 2-depth 서브폴더도 추가
        let legacySubdir = tenantRooms.appendingPathComponent("legacy-layout/child-room", isDirectory: true)
        try FileManager.default.createDirectory(at: legacySubdir, withIntermediateDirectories: true)
        let specData = Data(#"{"roomID": "CHILD-SPEC"}"#.utf8)
        try specData.write(to: legacySubdir.appendingPathComponent("spec.json", isDirectory: false))

        // O(1) 탐색 성능 검증: stat-only 이므로 4,000개 폴더를 열거하거나 spec.json 을 읽지 않고 즉시 반환
        let start = DispatchTime.now()
        let result = RoomPaths.findRoomDirectory(
            roomID: "DOES-NOT-EXIST-AT-ALL",
            tenant: "giant-tenant",
            homeDirectory: tempHome.path
        )
        let end = DispatchTime.now()
        let elapsedNano = end.uptimeNanoseconds - start.uptimeNanoseconds
        let elapsedMs = Double(elapsedNano) / 1_000_000.0

        XCTAssertNil(result)
        XCTAssertLessThan(elapsedMs, 50.0, "4,000개 폴더가 있어도 탐색 miss는 50ms 미만(실측: \(elapsedMs)ms)으로 완료되어야 합니다.")

        // tenant nil 인 경우도 .tenants 폴더 목록만 stat 하므로 빠름
        let startNoTenant = DispatchTime.now()
        let resultNoTenant = RoomPaths.findRoomDirectory(
            roomID: "DOES-NOT-EXIST-AT-ALL",
            tenant: nil,
            homeDirectory: tempHome.path
        )
        let endNoTenant = DispatchTime.now()
        let elapsedNanoNoTenant = endNoTenant.uptimeNanoseconds - startNoTenant.uptimeNanoseconds
        let elapsedMsNoTenant = Double(elapsedNanoNoTenant) / 1_000_000.0

        XCTAssertNil(resultNoTenant)
        XCTAssertLessThan(elapsedMsNoTenant, 50.0, "tenant 미지정 시에도 탐색 miss는 50ms 미만(실측: \(elapsedMsNoTenant)ms)으로 완료되어야 합니다.")
    }

    // MARK: - 4. legacyRoomFolders finds legacy rooms and declared ids

    func testLegacyRoomFolders() throws {
        let tenantRooms = tempDirectory.appendingPathComponent("rooms", isDirectory: true)
        try FileManager.default.createDirectory(at: tenantRooms, withIntermediateDirectories: true)

        // 4-1. 표준 UUID 폴더는 스킵되어야 함
        let uuidName = UUID().uuidString
        let uuidDir = tenantRooms.appendingPathComponent(uuidName, isDirectory: true)
        try FileManager.default.createDirectory(at: uuidDir, withIntermediateDirectories: true)

        // 4-2. 숨김 폴더 및 언더스코어 폴더는 스킵되어야 함
        let hiddenDir = tenantRooms.appendingPathComponent(".hidden-room", isDirectory: true)
        try FileManager.default.createDirectory(at: hiddenDir, withIntermediateDirectories: true)
        let underscoreDir = tenantRooms.appendingPathComponent("_base-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: underscoreDir, withIntermediateDirectories: true)

        // 4-3. 직접 레거시 비-UUID 폴더 (spec.json 선언)
        let directLegacyDir = tenantRooms.appendingPathComponent("legacy-direct-slug", isDirectory: true)
        try FileManager.default.createDirectory(at: directLegacyDir, withIntermediateDirectories: true)
        let directSpec = Data(#"{"roomID": "DIRECT-DECLARED-001"}"#.utf8)
        try directSpec.write(to: directLegacyDir.appendingPathComponent("spec.json", isDirectory: false))

        // 4-4. 2-depth 레이아웃 폴더 (ROOM.json 선언)
        let layoutDir = tenantRooms.appendingPathComponent("custom-layout", isDirectory: true)
        let childDir = layoutDir.appendingPathComponent("nested-room", isDirectory: true)
        try FileManager.default.createDirectory(at: childDir, withIntermediateDirectories: true)
        let childRoomJSON = Data(#"{"id": "NESTED-DECLARED-002"}"#.utf8)
        try childRoomJSON.write(to: childDir.appendingPathComponent("ROOM.json", isDirectory: false))

        // 4-5. 2-depth 레이아웃 폴더 (자체 선언 파일 없음 -> 폴더명 사용)
        let fallbackChildDir = layoutDir.appendingPathComponent("fallback-child-slug", isDirectory: true)
        try FileManager.default.createDirectory(at: fallbackChildDir, withIntermediateDirectories: true)

        let legacyRooms = RoomPaths.legacyRoomFolders(inTenantRoomsDirectory: tenantRooms)
        let legacyMap = Dictionary(uniqueKeysWithValues: legacyRooms.map { ($0.roomID, $0.url.resolvingSymlinksInPath().path) })

        XCTAssertNil(legacyMap[uuidName], "UUID 항목은 마이그레이션 대상에서 제외되어야 합니다.")
        XCTAssertNil(legacyMap[".hidden-room"], "숨김 항목은 제외되어야 합니다.")
        XCTAssertNil(legacyMap["_base-bin"], "언더스코어 항목은 제외되어야 합니다.")

        XCTAssertEqual(legacyMap["DIRECT-DECLARED-001"], directLegacyDir.resolvingSymlinksInPath().path)
        XCTAssertEqual(legacyMap["NESTED-DECLARED-002"], childDir.resolvingSymlinksInPath().path)
        XCTAssertEqual(legacyMap["fallback-child-slug"], fallbackChildDir.resolvingSymlinksInPath().path)
    }
}
