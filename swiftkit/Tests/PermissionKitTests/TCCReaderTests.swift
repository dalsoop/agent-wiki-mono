import XCTest
@testable import PermissionKit

final class GrantStateTests: XCTestCase {
    func testAuthValueMapping() {
        XCTAssertEqual(GrantState.fromAuthValue("0"), .denied)
        XCTAssertEqual(GrantState.fromAuthValue("2"), .granted)
        XCTAssertEqual(GrantState.fromAuthValue("3"), .limited)
        XCTAssertEqual(GrantState.fromAuthValue("1"), .notSet)
        XCTAssertEqual(GrantState.fromAuthValue(""), .notSet)
        XCTAssertEqual(GrantState.fromAuthValue("garbage"), .notSet)
    }

    func testCodableRoundTripUsesRawValue() throws {
        let data = try JSONEncoder().encode(["screen": GrantState.granted])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"screen":"granted"}"#)
        let back = try JSONDecoder().decode([String: GrantState].self, from: data)
        XCTAssertEqual(back["screen"], .granted)
    }
}

final class TCCReaderTests: XCTestCase {
    /// 없는 경로를 가리키면 읽기 불가 — 크래시 없이 빈 결과.
    func testMissingDatabasesYieldEmptyGrants() {
        let reader = TCCReader(
            userDBPath: "/nonexistent/user/TCC.db",
            systemDBPath: "/nonexistent/system/TCC.db"
        )
        XCTAssertTrue(reader.grants().isEmpty)
        XCTAssertTrue(reader.grants(forBundleID: "net.ranode.rightclick").isEmpty)
    }

    /// 사용자 db 의 시스템 스코프 행은 enforcement 가 안 읽는다 — status 에 올리면 오판.
    func testUserDBSystemScopedRowsAreIgnored() throws {
        let sqlite3 = "/usr/bin/sqlite3"
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: sqlite3))

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pk-tcc-scope-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let user = dir.appendingPathComponent("user.db").path
        let system = dir.appendingPathComponent("system.db").path

        let seedUser = """
        CREATE TABLE access (service TEXT, client TEXT, auth_value INTEGER);
        INSERT INTO access VALUES ('kTCCServiceCamera', 'com.example.app', 2);
        INSERT INTO access VALUES ('kTCCServiceAccessibility', 'com.example.app', 2);
        INSERT INTO access VALUES ('kTCCServiceScreenCapture', 'com.example.app', 2);
        """
        let seedSystem = """
        CREATE TABLE access (service TEXT, client TEXT, auth_value INTEGER);
        INSERT INTO access VALUES ('kTCCServiceAccessibility', 'com.example.app', 0);
        """
        for (path, seed) in [(user, seedUser), (system, seedSystem)] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: sqlite3)
            p.arguments = [path, seed]
            try p.run()
            p.waitUntilExit()
            XCTAssertEqual(p.terminationStatus, 0)
        }

        let reader = TCCReader(userDBPath: user, systemDBPath: system)
        let g = reader.grants(forBundleID: "com.example.app")
        XCTAssertEqual(g["kTCCServiceCamera"], .granted, "사용자 스코프는 user db")
        XCTAssertEqual(g["kTCCServiceAccessibility"], .denied, "시스템 스코프는 system db 만")
        XCTAssertNil(g["kTCCServiceScreenCapture"], "user db 의 화면기록 가짜 행은 무시")
    }

    func testDefaultPathsPointAtTCCLocations() {
        let reader = TCCReader()
        XCTAssertTrue(reader.userDBPath.hasSuffix("Library/Application Support/com.apple.TCC/TCC.db"))
        XCTAssertEqual(reader.systemDBPath, "/Library/Application Support/com.apple.TCC/TCC.db")
    }

    /// 실제 sqlite db 를 만들어 파싱 경로(auth_value → GrantState)를 검증한다.
    func testParsesRowsFromRealSQLiteDatabase() throws {
        let sqlite3 = "/usr/bin/sqlite3"
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: sqlite3))

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pk-tcc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let userDB = dir.appendingPathComponent("user.db").path
        let systemDB = dir.appendingPathComponent("system.db").path

        let seedUser = """
        CREATE TABLE access (service TEXT, client TEXT, auth_value INTEGER);
        INSERT INTO access VALUES ('kTCCServiceAppleEvents', 'net.ranode.rightclick', 2);
        INSERT INTO access VALUES ('kTCCServicePhotos', 'com.example.other', 3);
        """
        // 시스템 스코프는 system db 에만 둔다(user 행은 무시 정책).
        let seedSystem = """
        CREATE TABLE access (service TEXT, client TEXT, auth_value INTEGER);
        INSERT INTO access VALUES ('kTCCServiceScreenCapture', 'net.ranode.rightclick', 0);
        """
        for (path, seed) in [(userDB, seedUser), (systemDB, seedSystem)] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: sqlite3)
            process.arguments = [path, seed]
            // stdin 을 끊는다 — 부하 시 sqlite3 가 프롬프트로 빠지면 wait 가 10s 를 채운다(실측 flake).
            process.standardInput = FileHandle.nullDevice
            try process.run()
            let group = DispatchGroup()
            group.enter()
            Task.detached { process.waitUntilExit(); group.leave() }
            if group.wait(timeout: .now() + 30) == .timedOut {
                process.terminate()
                return XCTFail("sqlite3 seed timed out")
            }
            XCTAssertEqual(process.terminationStatus, 0)
        }

        let reader = TCCReader(userDBPath: userDB, systemDBPath: systemDB)
        let all = reader.grants()
        XCTAssertEqual(all["net.ranode.rightclick"]?["kTCCServiceAppleEvents"], .granted)
        XCTAssertEqual(all["net.ranode.rightclick"]?["kTCCServiceScreenCapture"], .denied)
        XCTAssertEqual(all["com.example.other"]?["kTCCServicePhotos"], .limited)

        let mine = reader.grants(forBundleID: "net.ranode.rightclick")
        XCTAssertEqual(mine.count, 2)
        XCTAssertEqual(mine["kTCCServiceAppleEvents"], .granted)
        XCTAssertNil(mine["kTCCServicePhotos"])
    }

    /// 대형 stdout 이 파이프 버퍼(64KB)를 넘어도 교착 없이 전부 읽혀야 한다.
    /// 2026-08-01 사고: wait-then-read 로 user TCC 전체가 비어 status 가 사용자 권한을 놓침.
    func testLargeResultDoesNotDeadlockOnPipeBuffer() throws {
        let sqlite3 = "/usr/bin/sqlite3"
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: sqlite3))

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pk-tcc-big-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("TCC.db").path

        // ~90 bytes/row × 1200 ≈ 100KB+ > 64KB pipe buffer
        var seed = "CREATE TABLE access (service TEXT, client TEXT, auth_value INTEGER);\n"
        for i in 0..<1200 {
            seed += "INSERT INTO access VALUES ('kTCCServiceCamera', 'com.example.app\(i)', 2);\n"
        }
        // 마지막 표식 행 — 드레인이 끝까지 왔는지 확인.
        seed += "INSERT INTO access VALUES ('kTCCServiceMicrophone', 'com.example.marker', 2);\n"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: sqlite3)
        process.arguments = [db, seed]
        let err = Pipe()
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "seed failed")

        let reader = TCCReader(userDBPath: db, systemDBPath: "/nonexistent/system/TCC.db")
        let all = reader.grants()
        XCTAssertEqual(all.count, 1201, "pipe drain 실패 시 0 또는 부분 결과")
        XCTAssertEqual(all["com.example.marker"]?["kTCCServiceMicrophone"], .granted)
        XCTAssertEqual(all["com.example.app0"]?["kTCCServiceCamera"], .granted)
        XCTAssertEqual(all["com.example.app1199"]?["kTCCServiceCamera"], .granted)
    }
}
