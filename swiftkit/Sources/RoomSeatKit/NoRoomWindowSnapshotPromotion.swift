import Foundation
import RoomPlacementKit
import StateRootKit

/// 옛 가짜 기본 방의 창 스냅샷을 방 없는 고객 저장소로 한 번만 복사한다.
public enum NoRoomWindowSnapshotPromotion {
    public enum Result: Sendable, Equatable {
        case noValidLegacySnapshot
        case destinationAlreadyExists(URL)
        case copied(from: URL, to: URL)
        case refusedUnsafeTestHome(URL)
        case failed(source: URL?, message: String)
    }

    @discardableResult
    public static func promote(
        homeDirectory: String? = nil,
        fileManager: FileManager = .default
    ) -> Result {
        promote(
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            environment: ProcessInfo.processInfo.environment,
            processName: ProcessInfo.processInfo.processName,
            realHomeDirectory: NSHomeDirectory()
        )
    }

    @discardableResult
    static func promote(
        homeDirectory: String?,
        fileManager: FileManager,
        environment: [String: String],
        processName: String,
        realHomeDirectory: String
    ) -> Result {
        let destination = StateRootKit.customerApplicationSupportDirectory(homeDirectory: homeDirectory)
            .appendingPathComponent("windows.json", isDirectory: false)
            .standardizedFileURL

        if isUnsafeTestHome(
            destination,
            environment: environment,
            processName: processName,
            realHomeDirectory: realHomeDirectory
        ) {
            return .refusedUnsafeTestHome(destination)
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            return .destinationAlreadyExists(destination)
        }

        let home = URL(fileURLWithPath: homeDirectory ?? realHomeDirectory, isDirectory: true)
        let support = StateRootKit.customerApplicationSupportDirectory(homeDirectory: home.path)
        // 옛 테넌트 경로는 과도기 API 로만 조립한다(no-tenant-room-path).
        let tenantsRoot = RoomPaths.tenantsRoot(environment: [:], homeDirectory: home.path)
        let candidates = [
            support.appendingPathComponent("rooms/room-default/windows.json"),
            support.appendingPathComponent("rooms/room:default/windows.json"),
            RoomPaths.tenantRoomsDirectory(root: tenantsRoot, tenant: "personal")
                .appendingPathComponent("room:default/windows.json"),
            RoomPaths.tenantRoomsDirectory(root: tenantsRoot, tenant: "default")
                .appendingPathComponent("room:default/windows.json"),
        ]

        let valid = candidates.compactMap { url -> Candidate? in
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? JSONDecoder().decode(RoomWindowsSnapshot.self, from: data) else {
                return nil
            }
            let modificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return Candidate(url: url, data: data, generatedAt: snapshot.generatedAt, modificationDate: modificationDate)
        }
        guard let selected = valid.max(by: { lhs, rhs in
            if lhs.generatedAt != rhs.generatedAt { return lhs.generatedAt < rhs.generatedAt }
            return lhs.modificationDate < rhs.modificationDate
        }) else {
            return .noValidLegacySnapshot
        }

        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard !fileManager.fileExists(atPath: destination.path) else {
                return .destinationAlreadyExists(destination)
            }
            // 임시 파일에 다 쓴 뒤 옮긴다. moveItem 은 대상이 있으면 실패하므로 덮어쓰지 않는다.
            // (`.atomic` 과 `.withoutOverwriting` 을 함께 주면 Foundation 이 프로세스를 죽인다.)
            let temporary = destination.deletingLastPathComponent()
                .appendingPathComponent(".windows.json.promote-\(UUID().uuidString)")
            try selected.data.write(to: temporary, options: .atomic)
            do {
                // 그사이 대상이 생겼으면 옮기지 않는다 — 덮어쓰지 않는다.
                guard !fileManager.fileExists(atPath: destination.path) else {
                    throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: destination.path])
                }
                try fileManager.moveItem(at: temporary, to: destination)
            } catch {
                try fileManager.removeItem(at: temporary)
                throw error
            }
            return .copied(from: selected.url, to: destination)
        } catch {
            return .failed(source: selected.url, message: error.localizedDescription)
        }
    }

    private struct Candidate {
        let url: URL
        let data: Data
        let generatedAt: Date
        let modificationDate: Date
    }

    private static let testProcessNames: Set<String> = ["xctest", "swiftpm-testing-helper"]

    private static func isUnsafeTestHome(
        _ destination: URL,
        environment: [String: String],
        processName: String,
        realHomeDirectory: String
    ) -> Bool {
        guard StateRootKit.isRunningUnderTest(environment) || testProcessNames.contains(processName) else {
            return false
        }
        let candidate = destination.standardizedFileURL.resolvingSymlinksInPath().path
        let home = URL(fileURLWithPath: realHomeDirectory, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath().path
        return candidate == home || candidate.hasPrefix(home + "/")
    }
}
