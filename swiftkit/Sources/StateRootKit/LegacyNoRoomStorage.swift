import Foundation

/// 옛 가짜 기본 방(`rooms/room-default`, `rooms/room:default`)에 있던 앱 저장소를 방 없는 저장소
/// (`net.ranode.shared/<slug>`)로 옮긴다. 공개 입구는 `StateRootKit.promoteLegacyNoRoomStorage`.
public enum LegacyNoRoomStorage {
    public enum PromotionResult: Sendable, Equatable {
        case noLegacyStorage
        case destinationAlreadyExists(URL)
        case promoted(from: URL, to: URL, leftBehind: URL?)
        case refusedUnsafeTestHome(URL)
        case failed(source: URL, message: String)
    }

    @discardableResult
    static func promote(
        slug: String,
        homeDirectory: String?,
        environment: [String: String],
        processName: String,
        realHomeDirectory: String
    ) -> PromotionResult {
        let fileManager = FileManager.default
        let destination = StateRootKit.noRoomAppStorageURL(slug: slug, homeDirectory: homeDirectory)
            .standardizedFileURL
        let supportRoot = StateRootKit.customerApplicationSupportDirectory(homeDirectory: homeDirectory)
        // 실제 폴더만 후보다. 이미 옮긴 자리에는 호환 심링크가 남아 있으므로 다시 옮기지 않는다.
        let candidates = ["room-default", "room:default"].map {
            supportRoot
                .appendingPathComponent("rooms", isDirectory: true)
                .appendingPathComponent($0, isDirectory: true)
                .appendingPathComponent(slug, isDirectory: true)
                .standardizedFileURL
        }.filter { isRealDirectory($0, fileManager: fileManager) }

        guard !candidates.isEmpty else { return .noLegacyStorage }

        if isUnsafeTestHomePath(
            destination.path,
            environment: environment,
            processName: processName,
            realHomeDirectory: realHomeDirectory
        ) {
            writeLegacyPromotionWarning(slug: slug, reason: "test process refused real-home promotion")
            return .refusedUnsafeTestHome(destination)
        }

        // 새 저장소가 이미 있으면 옛 저장소를 그대로 둔다. 읽을 때마다 불리므로 경고하지 않는다.
        guard !fileManager.fileExists(atPath: destination.path) else {
            return .destinationAlreadyExists(destination)
        }

        let source = candidates.max { lhs, rhs in
            legacyStorageModificationDate(at: lhs, fileManager: fileManager)
                < legacyStorageModificationDate(at: rhs, fileManager: fileManager)
        } ?? candidates[0]
        let leftBehind = candidates.first { $0 != source }

        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard !fileManager.fileExists(atPath: destination.path) else {
                return .destinationAlreadyExists(destination)
            }
            try fileManager.moveItem(at: source, to: destination)
            if let linkError = linkLegacyPath(source, to: destination, fileManager: fileManager) {
                writeLegacyPromotionWarning(slug: slug, reason: "compatibility link not created: \(linkError)")
            }
            if leftBehind != nil {
                writeLegacyPromotionWarning(slug: slug, reason: "older legacy storage left in place")
            }
            return .promoted(from: source, to: destination, leftBehind: leftBehind)
        } catch {
            writeLegacyPromotionWarning(slug: slug, reason: "move failed; legacy storage left in place: \(error)")
            return .failed(source: source, message: error.localizedDescription)
        }
    }

    /// 옛 빌드가 옛 경로로 읽고 써도 새 저장소를 보도록, 옮긴 자리에 새 경로를 가리키는 심링크를 남긴다.
    /// 이 심링크가 없으면 아직 재설치하지 않은 앱이 옛 경로에 빈 폴더를 새로 만들어 데이터가 사라진 것처럼 보인다.
    private static func linkLegacyPath(_ legacy: URL, to destination: URL, fileManager: FileManager) -> Error? {
        do {
            try fileManager.createSymbolicLink(at: legacy, withDestinationURL: destination)
            return nil
        } catch {
            return error
        }
    }

    /// 심링크가 아닌 실제 폴더.
    private static func isRealDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return false }
        return attributes[.type] as? FileAttributeType == .typeDirectory
    }

    private static func legacyStorageModificationDate(at directory: URL, fileManager: FileManager) -> Date {
        let stateURL = directory.appendingPathComponent("state.json")
        let selectedURL = fileManager.fileExists(atPath: stateURL.path) ? stateURL : directory
        guard let values = try? selectedURL.resourceValues(forKeys: [.contentModificationDateKey]) else {
            return .distantPast
        }
        return values.contentModificationDate ?? .distantPast
    }

    /// `swift test` 가 테스트를 돌리는 프로세스 이름.
    private static let testProcessNames: Set<String> = ["xctest", "swiftpm-testing-helper"]

    private static func isUnsafeTestHomePath(
        _ path: String,
        environment: [String: String],
        processName: String,
        realHomeDirectory: String
    ) -> Bool {
        guard StateRootKit.isRunningUnderTest(environment) || testProcessNames.contains(processName) else { return false }
        let candidate = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        let home = URL(fileURLWithPath: realHomeDirectory).standardizedFileURL.resolvingSymlinksInPath().path
        return candidate == home || candidate.hasPrefix(home + "/")
    }

    private static func writeLegacyPromotionWarning(slug: String, reason: String) {
        FileHandle.standardError.write(
            Data("StateRootKit: legacy no-room storage for \(slug) left behind (\(reason))\n".utf8)
        )
    }
}
