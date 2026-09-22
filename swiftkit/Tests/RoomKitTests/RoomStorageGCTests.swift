import Foundation
import Testing
@testable import RoomSeatKit
@testable import FastDiskIOKit
@testable import StateRootKit

@Suite("RoomStorageGC — 룸 작업공간 격리 및 스토리지 GC 수명주기 검증")
struct RoomStorageGCTests {

    @Test("고객용 단일 룸 내 고아 임시 파일 및 사망한 세션 디렉터리 GC 정리 검증")
    func testCustomerRoomStorageGCPrunesOrphanFilesAndSessions() throws {
        let testRoomID = "room:test-gc-\(UUID().uuidString.prefix(8))"
        let roomURL = StateRootKit.customerRoomRoot(roomID: testRoomID)
        let fm = FileManager.default

        defer {
            try? fm.removeItem(at: roomURL)
        }

        // 1. 기본 룸 환경 프로비저닝
        let context = try CustomerRoomLayout.ensureDefaultRoom(roomID: testRoomID, performGC: false)
        #expect(fm.fileExists(atPath: context.roomURL.path))

        // 2. 임시 잔류 파일 및 고아 세션 생성
        let tmpDir = context.roomURL.appendingPathComponent("tmp", isDirectory: true)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let staleTmpFile = tmpDir.appendingPathComponent("build-artifact.tmp")
        try Data("stale-artifact".utf8).write(to: staleTmpFile)

        let appDir = context.roomURL.appendingPathComponent("apps/editor", isDirectory: true)
        try fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        let appTmpFile = appDir.appendingPathComponent("swap.swp")
        try Data("swap-artifact".utf8).write(to: appTmpFile)

        let sandboxesDir = context.roomURL.appendingPathComponent("sandboxes", isDirectory: true)
        let deadSessionDir = sandboxesDir.appendingPathComponent("session-9999999", isDirectory: true)
        try fm.createDirectory(at: deadSessionDir, withIntermediateDirectories: true)
        try Data("dead-state".utf8).write(to: deadSessionDir.appendingPathComponent("run.log"))

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let aliveSessionDir = sandboxesDir.appendingPathComponent("session-\(currentPID)", isDirectory: true)
        try fm.createDirectory(at: aliveSessionDir, withIntermediateDirectories: true)
        try Data("alive-state".utf8).write(to: aliveSessionDir.appendingPathComponent("run.log"))

        // 3. 좀비 윈도우 등록 (사망한 PID: 9999999)
        let zombieWindow = WindowIdentity(
            cgWindowID: 9999,
            pid: 9999999,
            roomID: testRoomID,
            bundleID: "com.apple.Terminal",
            title: "Zombie Editor"
        )
        RoomWindowManager.registerWindow(zombieWindow, tenantID: "personal")

        // 4. RoomStorageGC 실행
        let options = FastStorageGCOptions(
            maxTemporaryAge: 0, // 즉시 만료
            dryRun: false
        )

        let report = try RoomStorageGC.runCustomerRoomGC(
            roomID: testRoomID,
            options: options,
            fileManager: fm
        )

        #expect(report.isClean)
        #expect(report.fastGCReport.prunedFiles.contains(staleTmpFile.path))
        #expect(report.fastGCReport.prunedFiles.contains(appTmpFile.path))
        #expect(report.fastGCReport.prunedDirectories.contains(deadSessionDir.path))
        #expect(!fm.fileExists(atPath: staleTmpFile.path))
        #expect(!fm.fileExists(atPath: appTmpFile.path))
        #expect(!fm.fileExists(atPath: deadSessionDir.path))
        #expect(fm.fileExists(atPath: aliveSessionDir.path))
        #expect(report.prunedZombieWindowsCount >= 1)
    }

    @Test("CustomerRoomLayout.createCustomerWorkspace — GC 연동 작업공간 생성 검증")
    func testCreateCustomerWorkspaceWithGC() throws {
        let testRoomID = "room:test-ws-\(UUID().uuidString.prefix(8))"
        let roomURL = StateRootKit.customerRoomRoot(roomID: testRoomID)
        let fm = FileManager.default

        defer {
            try? fm.removeItem(at: roomURL)
        }

        let result = try CustomerRoomLayout.createCustomerWorkspace(
            roomID: testRoomID,
            fileManager: fm
        )

        #expect(result.context.roomID == testRoomID)
        #expect(fm.fileExists(atPath: result.context.roomURL.path))
        #expect(fm.fileExists(atPath: result.context.specURL.path))
        #expect(fm.fileExists(atPath: result.context.windowsURL.path))
        #expect(result.gcReport.isClean)
    }
}
