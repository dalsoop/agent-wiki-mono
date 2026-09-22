import Foundation
import XCTest
import StateRootKit
@testable import StateMirrorKit

final class CustomerRoomStateMirrorTests: XCTestCase {
    private struct TestState: Codable, Equatable, Sendable {
        let status: String
        let counter: Int
    }

    private var temporaryDirectory: URL!

    override func setUp() {
        super.setUp()
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("customer-room-tests-\(UUID().uuidString)", isDirectory: true)
        do { try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true) } catch { _ = error }
    }

    override func tearDown() {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        super.tearDown()
    }

    func testCustomerAppStorageURLResolution() {
        let slug = "agent-monorepo-inspector"
        let home = "/Users/customer"
        let url = StateMirrorKit.customerAppStorageURL(
            slug: slug,
            roomID: "room:default",
            homeDirectory: home
        )

        XCTAssertTrue(url.path.hasPrefix(home))
        XCTAssertTrue(url.path.contains("Library/Application Support/net.ranode.shared/rooms/room-default/\(slug)"))

        let mirrorURL = StateMirrorKit.customerMirrorURL(
            slug: slug,
            roomID: "room:default",
            homeDirectory: home
        )
        XCTAssertEqual(mirrorURL.lastPathComponent, "state.json")
        XCTAssertEqual(mirrorURL.deletingLastPathComponent().path, url.path)
    }

    func testCustomRoomIDStoragePath() {
        let slug = "window-switcher-hud-swift"
        let roomID = "BD400651-BA69-4607-A9EA-7A91E3C5DC6E"
        let home = "/Users/customer"
        let url = StateMirrorKit.customerAppStorageURL(
            slug: slug,
            roomID: roomID,
            homeDirectory: home
        )

        XCTAssertEqual(
            url.path,
            "\(home)/Library/Application Support/net.ranode.shared/rooms/\(roomID)/\(slug)"
        )
    }

    func testAtomicFileWriterIntegrity() throws {
        let writer = AtomicFileWriter()
        let fileURL = temporaryDirectory.appendingPathComponent("nested/dir/test.json")
        let testData = "{\"hello\":\"world\"}".data(using: .utf8)!

        try writer.write(testData, to: fileURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let readData = try Data(contentsOf: fileURL)
        XCTAssertEqual(readData, testData)

        // 덮어쓰기 테스트
        let updatedData = "{\"hello\":\"updated\"}".data(using: .utf8)!
        try writer.write(updatedData, to: fileURL)

        let readUpdated = try Data(contentsOf: fileURL)
        XCTAssertEqual(readUpdated, updatedData)

        // 임시 파일 잔여물 검사
        let parentDir = fileURL.deletingLastPathComponent()
        let entries = try FileManager.default.contentsOfDirectory(atPath: parentDir.path)
        let tmpFiles = entries.filter { $0.hasSuffix(".tmp") }
        XCTAssertTrue(tmpFiles.isEmpty, "임시 파일이 잔존하지 않아야 한다: \(tmpFiles)")
    }

    func testSelfHealingStoreSaveAndLoad() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("state.json")
        let store = StateMirrorSelfHealingStore<TestState>(
            app: "test-app",
            url: fileURL
        )

        let initial = TestState(status: "ok", counter: 42)
        try store.save(initial)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let loaded = try store.loadOrSelfHeal()
        XCTAssertEqual(loaded.app, "test-app")
        XCTAssertEqual(loaded.state, initial)

        // 두 번째 저장 시 .bak 갱신 확인
        let next = TestState(status: "updated", counter: 43)
        try store.save(next)

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.bakURL.path))
        let bakData = try Data(contentsOf: store.bakURL)
        let bakEnvelope = try JSONDecoder().decode(StateMirrorEnvelope<TestState>.self, from: bakData)
        XCTAssertEqual(bakEnvelope.state, initial)

        let loadedNext = try store.loadOrSelfHeal()
        XCTAssertEqual(loadedNext.state, next)
    }

    func testSelfHealingStoreRecoversFromBakWhenCorrupted() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("state.json")
        let store = StateMirrorSelfHealingStore<TestState>(
            app: "test-app",
            url: fileURL
        )

        let state1 = TestState(status: "v1", counter: 1)
        let state2 = TestState(status: "v2", counter: 2)

        try store.save(state1)
        try store.save(state2) // 이제 .bak 에는 state1 이 저장되어 있음

        // 원본 파일을 쓰레기 바이트로 손상시킴
        let corruptedBytes = "MALFORMED_GARBAGE_DATA".data(using: .utf8)!
        try corruptedBytes.write(to: fileURL)

        // loadOrSelfHeal 호출 시 .bak 으로부터 자가 치유되어 state1 이 복구되어야 함
        let recovered = try store.loadOrSelfHeal()
        XCTAssertEqual(recovered.state, state1)

        // 손상 파일이 .corrupt.<timestamp> 로 격리되었는지 검증
        let parentDir = fileURL.deletingLastPathComponent()
        let entries = try FileManager.default.contentsOfDirectory(atPath: parentDir.path)
        let corruptEntries = entries.filter { $0.contains(".corrupt.") }
        XCTAssertFalse(corruptEntries.isEmpty, "손상 파일이 격리되어야 한다")
    }

    func testSelfHealingStoreFailClosedWhenBothCorrupted() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("state.json")
        let store = StateMirrorSelfHealingStore<TestState>(
            app: "test-app",
            url: fileURL
        )

        let validState = TestState(status: "ok", counter: 10)
        try store.save(validState)

        // 원본 파일 및 .bak 모두 손상
        let garbage = "{ broken json".data(using: .utf8)!
        try garbage.write(to: fileURL)
        try garbage.write(to: store.bakURL)

        XCTAssertThrowsError(try store.loadOrSelfHeal()) { error in
            guard let storeError = error as? StateMirrorStoreError else {
                XCTFail("StateMirrorStoreError 기대했으나 \(error) 발생")
                return
            }
            if case .corruptUnrecoverable = storeError {
                // 성공 (Fail-Closed)
            } else {
                XCTFail("corruptUnrecoverable 기대했으나 \(storeError) 발생")
            }
        }
    }

    func testPruneQuarantinedFiles() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("state.json")
        let dir = fileURL.deletingLastPathComponent()

        // 7개의 더미 격리 파일 생성
        for i in 1...7 {
            let corruptURL = dir.appendingPathComponent("state.json.corrupt.\(1000 + i)")
            try "corrupted \(i)".data(using: .utf8)!.write(to: corruptURL)
        }

        let pruned = StateMirrorSelfHealingStore<TestState>.pruneQuarantinedFiles(at: fileURL, maxKeep: 3)
        XCTAssertEqual(pruned, 4)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("state.json.corrupt.") }
        XCTAssertEqual(remaining.count, 3)
    }

    func testRoomScopedPublishAndRead() throws {
        let app = "CustomerRoomPilotApp"
        let roomID = "BD400651-BA69-4607-A9EA-7A91E3C5DC6E"
        let state = TestState(status: "running", counter: 99)

        StateMirror.publishRoom(app: app, roomID: roomID, state)
        defer { StateMirror.clearRoom(app: app, roomID: roomID) }

        let readEnvelope = try StateMirror.readRoom(app: app, roomID: roomID, as: TestState.self)
        XCTAssertEqual(readEnvelope.app, app)
        XCTAssertEqual(readEnvelope.state, state)

        StateMirror.clearRoom(app: app, roomID: roomID)
        XCTAssertThrowsError(try StateMirror.readRoom(app: app, roomID: roomID, as: TestState.self))
    }

    func testResolveMirrorURLWithRoom() {
        let app = "TestApp"
        let roomID = "ROOM-TEST-123"
        let home = "/Users/testuser"

        // roomID 명시 지정
        let resolved = StateMirror.resolveMirrorURL(
            app: app,
            roomID: roomID,
            environment: [:],
            homeDirectory: home
        )
        XCTAssertTrue(resolved.path.contains("rooms/ROOM-TEST-123/\(app)/state.json"))

        // 환경변수 CUSTOMER_ROOM_ID 지정
        let envResolved = StateMirror.resolveMirrorURL(
            app: app,
            roomID: nil,
            environment: ["CUSTOMER_ROOM_ID": "ROOM-ENV-999"],
            homeDirectory: home
        )
        XCTAssertTrue(envResolved.path.contains("rooms/ROOM-ENV-999/\(app)/state.json"))

        // 환경변수 ROOM_ID 우선순위 지정
        let roomEnvResolved = StateMirror.resolveMirrorURL(
            app: app,
            roomID: nil,
            environment: ["ROOM_ID": "ROOM-ENV-111", "CUSTOMER_ROOM_ID": "ROOM-ENV-999"],
            homeDirectory: home
        )
        XCTAssertTrue(roomEnvResolved.path.contains("rooms/ROOM-ENV-111/\(app)/state.json"))

        // 일반 환경 폴백
        let fallback = StateMirror.resolveMirrorURL(
            app: app,
            roomID: nil,
            environment: [:],
            homeDirectory: home
        )
        XCTAssertEqual(fallback.path, "\(home)/.swift-app-state/\(app).json")
    }
}
