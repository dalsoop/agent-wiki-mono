import Foundation
import RoomPlacementKit
import StateRootKit

/// 룸 윈도우 격리 및 가상 워크스페이스 스냅샷 관리자 (Tier 1 순수 도메인 Kit)
public enum RoomWindowManager {

    // MARK: - windows.json 영속화 및 관리

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var snapshotCache: [String: RoomWindowsSnapshot] = [:]

    private static func cacheKey(roomID: String, tenantID: String?) -> String {
        "\(tenantID ?? ""):\(roomID)"
    }

    /// 메모리 스냅샷 캐시 전체 초기화 (테스트 및 격리 검증용)
    public static func clearMemoryCache() {
        cacheLock.lock()
        snapshotCache.removeAll()
        cacheLock.unlock()
    }

    private static func getCachedSnapshot(forKey key: String) -> RoomWindowsSnapshot? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return snapshotCache[key]
    }

    private static func storeCachedSnapshot(_ snapshot: RoomWindowsSnapshot, forKey key: String, shouldCache: Bool) {
        guard shouldCache else { return }
        cacheLock.lock()
        defer { cacheLock.unlock() }
        snapshotCache[key] = snapshot
    }

    /// 룸 전용 windows.json 스냅샷 로드 (기본 FileManager 시 메모리 캐시 0ms 반환)
    public static func loadSnapshot(
        roomID: String,
        tenantID: String? = nil,
        fileManager: FileManager = .default
    ) -> RoomWindowsSnapshot {
        let key = cacheKey(roomID: roomID, tenantID: tenantID)
        let isDefaultManager = (fileManager == .default)
        if isDefaultManager, let cached = getCachedSnapshot(forKey: key) {
            return cached
        }

        let url = RoomPaths.windowsURL(roomID: roomID, tenant: tenantID)
        guard fileManager.fileExists(atPath: url.path) else {
            let empty = RoomWindowsSnapshot(roomID: roomID, generatedAt: Date(), windows: [])
            storeCachedSnapshot(empty, forKey: key, shouldCache: isDefaultManager)
            return empty
        }

        guard let data = try? Data(contentsOf: url) else {
            // C04: 파일이 물리적으로 존재하나 읽기/파싱에 실패한 경우 기존 손상 파일을 빈 스냅샷으로 덮어쓰지 않음
            return RoomWindowsSnapshot(roomID: roomID, generatedAt: Date(), windows: [])
        }
        let snapshot: RoomWindowsSnapshot
        do {
            snapshot = try JSONDecoder().decode(RoomWindowsSnapshot.self, from: data)
        } catch {
            return RoomWindowsSnapshot(roomID: roomID, generatedAt: Date(), windows: [])
        }

        storeCachedSnapshot(snapshot, forKey: key, shouldCache: isDefaultManager)
        return snapshot
    }

    /// 룸 전용 windows.json 스냅샷 저장 (디스크 쓰기 성공 후 메모리 캐시 동기화)
    public static func saveSnapshot(
        _ snapshot: RoomWindowsSnapshot,
        tenantID: String? = nil,
        fileManager: FileManager = .default
    ) throws {
        let key = cacheKey(roomID: snapshot.roomID, tenantID: tenantID)
        let url = RoomPaths.windowsURL(roomID: snapshot.roomID, tenant: tenantID)
        let parentDir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)

        // C09: 디스크 저장이 성공한 직후에만 메모리 캐시를 갱신하여 미저장 상태의 정본 오인을 원천 차단
        if fileManager == .default {
            cacheLock.lock()
            snapshotCache[key] = snapshot
            cacheLock.unlock()
        }
    }

    /// 새 창 식별자 등록
    @discardableResult
    public static func registerWindow(
        _ identity: WindowIdentity,
        tenantID: String? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        var snapshot = loadSnapshot(roomID: identity.roomID, tenantID: tenantID, fileManager: fileManager)
        snapshot.windows.removeAll { $0.cgWindowID == identity.cgWindowID }
        snapshot.windows.append(identity)
        snapshot.generatedAt = Date()
        do {
            try saveSnapshot(snapshot, tenantID: tenantID, fileManager: fileManager)
            return true
        } catch {
            return false
        }
    }

    /// 창 식별자 등록 해제
    @discardableResult
    public static func unregisterWindow(
        cgWindowID: UInt32,
        roomID: String,
        tenantID: String? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        var snapshot = loadSnapshot(roomID: roomID, tenantID: tenantID, fileManager: fileManager)
        let originalCount = snapshot.windows.count
        snapshot.windows.removeAll { $0.cgWindowID == cgWindowID }
        guard snapshot.windows.count < originalCount else { return false }
        snapshot.generatedAt = Date()
        do {
            try saveSnapshot(snapshot, tenantID: tenantID, fileManager: fileManager)
            return true
        } catch {
            return false
        }
    }

    /// 사망한 프로세스(PID)의 잔여 창 레코드를 windows.json 스냅샷에서 프루닝
    @discardableResult
    public static func pruneZombieWindows(
        roomID: String,
        tenantID: String? = nil,
        activePIDs: Set<pid_t>
    ) throws -> Int {
        var snapshot = loadSnapshot(roomID: roomID, tenantID: tenantID)
        let beforeCount = snapshot.windows.count
        snapshot.windows.removeAll { !activePIDs.contains($0.pid) }
        let pruned = beforeCount - snapshot.windows.count
        if pruned > 0 {
            snapshot.generatedAt = Date()
            try saveSnapshot(snapshot, tenantID: tenantID)
        }
        return pruned
    }

    // MARK: - 도구 프로필 및 런타임 인자 주입 규약

    /// VS Code 등 에디터 기동 시 프로필 격리 인자 생성
    public static func editorLaunchArguments(for context: AppRuntimeContext) -> [String] {
        [
            "--user-data-dir", context.profileURL.path,
            context.room.worktreeURL.path
        ]
    }

    /// 브라우저 도구 기동 시 세션 및 프로필 격리 인자 생성
    public static func browserLaunchArguments(for context: AppRuntimeContext) -> [String] {
        [
            "--session", context.room.roomID,
            "--user-data-dir", context.profileURL.path
        ]
    }

    /// 서브 프로세스 및 터미널용 룸/테넌트 환경변수 맵 생성
    public static func isolatedEnvironment(for context: AppRuntimeContext) -> [String: String] {
        [
            "ROOM_ID": context.room.roomID,
            "TENANT_ID": context.room.tenant.tenantID,
            "SWIFT_APP_STATE_ROOT": context.room.tenant.rootURL.path,
            "ROOM_WORKTREE": context.room.worktreeURL.path,
            "ROOM_APP_SQLITE": context.databaseURL.path,
            "ROOM_DOCUMENTS": context.cloudDocumentsURL.path
        ]
    }
}
