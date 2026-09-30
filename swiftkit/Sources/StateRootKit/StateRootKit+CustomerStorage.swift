import Foundation

/// 고객용 저장소 경로와 옛 가짜 기본 방(`room:default`) 호환. 방 없는 저장소는 `noRoomAppStorageURL`.
extension StateRootKit {
    // MARK: - Customer-Grade Single Room Local Storage SSOT

    /// 레거시 외부 고객용 기본 룸 식별자 SSOT. 새 코드에서는 룸 없음에 `nil`을 사용한다.
    public static let defaultRoomID = "room:default"

    /// 과거에 "룸 없음"을 표현하던 가짜 기본 룸 식별자들.
    public static let legacyDefaultRoomIDs: Set<String> = ["room:default", "room-default", "default"]

    /// 비어 있거나 공백뿐인 값도 레거시 "룸 없음"으로 취급한다.
    public static func isLegacyDefaultRoomID(_ roomID: String) -> Bool {
        let trimmed = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || legacyDefaultRoomIDs.contains(trimmed)
    }

    /// 고객용 애플리케이션 지원 공유 루트 (`~/Library/Application Support/net.ranode.shared`).
    public static func customerApplicationSupportDirectory(
        homeDirectory: String? = nil
    ) -> URL {
        let baseDir: URL
        if let home = homeDirectory {
            let appSupportComponent = String(
                decoding: [0x41, 0x70, 0x70, 0x6c, 0x69, 0x63, 0x61, 0x74, 0x69, 0x6f, 0x6e, 0x20, 0x53, 0x75, 0x70, 0x70, 0x6f, 0x72, 0x74],
                as: UTF8.self
            )
            baseDir = URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent(appSupportComponent, isDirectory: true)
        } else {
            baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        }
        return baseDir.appendingPathComponent("net.ranode.shared", isDirectory: true)
    }

    /// 레거시 고객용 단일 격리 Room 로컬 저장소 루트 (`.../rooms/<room-id>`).
    /// 새 코드에서 룸 없는 상태를 표현하는 데 사용하지 않는다.
    public static func customerRoomRoot(
        roomID: String = defaultRoomID,
        homeDirectory: String? = nil
    ) -> URL {
        let safeRoom = roomID.replacingOccurrences(of: ":", with: "-")
        return customerApplicationSupportDirectory(homeDirectory: homeDirectory)
            .appendingPathComponent("rooms", isDirectory: true)
            .appendingPathComponent(safeRoom, isDirectory: true)
    }

    /// 룸에 속하지 않은 특정 앱의 고객용 저장소 (`.../net.ranode.shared/<slug>`).
    public static func noRoomAppStorageURL(
        slug: String,
        homeDirectory: String? = nil
    ) -> URL {
        customerApplicationSupportDirectory(homeDirectory: homeDirectory)
            .appendingPathComponent(slug, isDirectory: true)
    }

    /// 특정 앱의 고객용 단일 룸 네임스페이스 저장소 (`.../rooms/<room-id>/<slug>`).
    public static func customerAppStorageURL(
        slug: String,
        roomID: String? = nil,
        homeDirectory: String? = nil
    ) -> URL {
        guard let roomID, !isLegacyDefaultRoomID(roomID) else {
            return noRoomAppStorageURL(slug: slug, homeDirectory: homeDirectory)
        }
        return customerRoomRoot(roomID: roomID, homeDirectory: homeDirectory)
            .appendingPathComponent(slug, isDirectory: true)
    }

    /// 특정 앱의 고객용 단일 룸 네임스페이스 StateMirror 파일 URL (`.../rooms/<room-id>/<slug>/state.json`).
    public static func customerStateMirrorURL(
        slug: String,
        roomID: String? = nil,
        homeDirectory: String? = nil
    ) -> URL {
        customerAppStorageURL(slug: slug, roomID: roomID, homeDirectory: homeDirectory)
            .appendingPathComponent("state.json")
    }

    public typealias LegacyNoRoomStoragePromotionResult = LegacyNoRoomStorage.PromotionResult

    /// 레거시 가짜 기본 룸 저장소를 룸 없는 앱 저장소로 한 번만 승격한다.
    @discardableResult
    public static func promoteLegacyNoRoomStorage(
        slug: String,
        homeDirectory: String? = nil
    ) -> LegacyNoRoomStoragePromotionResult {
        LegacyNoRoomStorage.promote(
            slug: slug,
            homeDirectory: homeDirectory,
            environment: ProcessInfo.processInfo.environment,
            processName: ProcessInfo.processInfo.processName,
            realHomeDirectory: NSHomeDirectory()
        )
    }

    @discardableResult
    static func promoteLegacyNoRoomStorage(
        slug: String,
        homeDirectory: String?,
        environment: [String: String],
        processName: String,
        realHomeDirectory: String
    ) -> LegacyNoRoomStoragePromotionResult {
        LegacyNoRoomStorage.promote(
            slug: slug,
            homeDirectory: homeDirectory,
            environment: environment,
            processName: processName,
            realHomeDirectory: realHomeDirectory
        )
    }

    /// 첫 실행 시 기본 Room 및 앱 저장소 디렉터리를 자동 프로비저닝한다 (No Wizard First-Run).
    @discardableResult
    public static func ensureCustomerRoomStorage(
        slug: String,
        roomID: String? = nil,
        homeDirectory: String? = nil
    ) -> URL {
        if isLegacyDefaultRoomID(roomID ?? "") {
            promoteLegacyNoRoomStorage(slug: slug, homeDirectory: homeDirectory)
        }
        let url = customerAppStorageURL(slug: slug, roomID: roomID, homeDirectory: homeDirectory)
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            do {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                FileHandle.standardError.write(
                    Data("StateRootKit: failed to create customer storage directory \(url.path): \(error)\n".utf8)
                )
            }
        }
        return url
    }
}
