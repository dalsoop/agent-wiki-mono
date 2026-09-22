import Foundation
import FastDiskIOKit
import StateRootKit

/// 룸 저장소 가비지 컬렉션 결과
public struct RoomStorageGCReport: Sendable, Equatable, Codable {
    public let roomID: String
    public let roomPath: String
    public var fastGCReport: FastStorageGCReport
    public var prunedZombieWindowsCount: Int

    public init(
        roomID: String,
        roomPath: String,
        fastGCReport: FastStorageGCReport = FastStorageGCReport(),
        prunedZombieWindowsCount: Int = 0
    ) {
        self.roomID = roomID
        self.roomPath = roomPath
        self.fastGCReport = fastGCReport
        self.prunedZombieWindowsCount = prunedZombieWindowsCount
    }

    public var isClean: Bool {
        fastGCReport.isClean
    }
}

/// 룸 작업공간 및 파일시스템 격리 스토리지 GC 엔진 (Workspace Isolation & Storage GC)
public enum RoomStorageGC: Sendable {

    /// 고객용 단일 룸(`StateRootKit.customerRoomRoot()`)의 수명주기 가비지 컬렉션 실행
    @discardableResult
    public static func runCustomerRoomGC(
        roomID: String = CustomerRoomLayout.defaultRoomID,
        options: FastStorageGCOptions = .default,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> RoomStorageGCReport {
        let targetURL = CustomerRoomLayout.roomURL(roomID: roomID, fileManager: fileManager)
        return try executeStorageGC(
            roomID: roomID,
            roomPath: targetURL.path,
            options: options,
            fileManager: fileManager,
            now: now
        )
    }

    /// 임의의 RoomContext 대상 수명주기 가비지 컬렉션 실행
    @discardableResult
    public static func runStorageGC(
        for context: RoomContext,
        options: FastStorageGCOptions = .default,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> RoomStorageGCReport {
        try executeStorageGC(
            roomID: context.roomID,
            roomPath: context.roomURL.path,
            options: options,
            fileManager: fileManager,
            now: now
        )
    }

    /// 내부 공용 스토리지 GC 실행 로직
    public static func executeStorageGC(
        roomID: String,
        roomPath: String,
        options: FastStorageGCOptions = .default,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> RoomStorageGCReport {
        guard fileManager.fileExists(atPath: roomPath) else {
            return RoomStorageGCReport(roomID: roomID, roomPath: roomPath)
        }

        var report = RoomStorageGCReport(roomID: roomID, roomPath: roomPath)

        // 1. 고아 임시 잔류 파일/캐시/세션 디렉터리 FastStorageGC 수명주기 스윕
        let gcResult = try FastStorageGC.collectGarbage(
            at: roomPath,
            options: options,
            fileManager: fileManager,
            now: now
        )
        report.fastGCReport = gcResult

        // 2. windows.json 내 사망한 좀비 프로세스(PID) 잔여 윈도우 프루닝
        report.prunedZombieWindowsCount = pruneZombiesIfActivePIDProvided(
            roomID: roomID,
            options: options
        )

        return report
    }

    private static func pruneZombiesIfActivePIDProvided(
        roomID: String,
        options: FastStorageGCOptions
    ) -> Int {
        guard let activePIDs = options.activePIDs else {
            return pruneZombiesAgainstRunningProcesses(roomID: roomID)
        }
        do {
            return try RoomWindowManager.pruneZombieWindows(roomID: roomID, activePIDs: activePIDs)
        } catch {
            fputs("RoomStorageGC: failed to prune zombie windows for room \(roomID): \(error.localizedDescription)\n", stderr)
            return 0
        }
    }

    private static func pruneZombiesAgainstRunningProcesses(roomID: String) -> Int {
        let snapshot = RoomWindowManager.loadSnapshot(roomID: roomID)
        guard !snapshot.windows.isEmpty else { return 0 }

        var alivePIDs = Set<pid_t>()
        for window in snapshot.windows {
            guard FastStorageGC.isProcessAlive(window.pid) else { continue }
            alivePIDs.insert(window.pid)
        }

        do {
            return try RoomWindowManager.pruneZombieWindows(roomID: roomID, activePIDs: alivePIDs)
        } catch {
            fputs("RoomStorageGC: failed to prune zombie windows for room \(roomID): \(error.localizedDescription)\n", stderr)
            return 0
        }
    }
}
