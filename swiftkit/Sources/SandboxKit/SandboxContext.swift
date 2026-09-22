import Foundation
import StateRootKit

/// `{home}/.sandboxes` · `{home}/.tenants/<slug>` 조립. 호출자가 준 home 을 루트로 고정한다
/// (`SWIFT_APP_STATE_ROOT` 오버라이드로 테넌트 리맵·테스트 격리를 타지 않게).
enum SandboxLayout {
    static func url(_ relative: String, homeDirectory: String) -> URL {
        StateRootKit.url(
            relative,
            environment: ["SWIFT_APP_STATE_ROOT": homeDirectory],
            homeDirectory: homeDirectory
        )
    }
}

/// 룸 샌드박스의 할당, 환경 봉인, 수명주기 관리를 담당하는 컨텍스트.
public final class SandboxContext: Sendable {
    public let roomID: String
    public let tenantSlug: String
    public let agentID: String?
    public let sandboxDirectory: URL
    public let tmpDirectory: URL
    public let readOnlyMasterRoot: URL

    public static let sandboxesDirectoryName = ".sandboxes"

    public init(
        roomID: String,
        tenantSlug: String,
        agentID: String? = nil,
        sandboxDirectory: URL,
        tmpDirectory: URL,
        readOnlyMasterRoot: URL
    ) {
        self.roomID = roomID
        self.tenantSlug = tenantSlug
        self.agentID = agentID
        self.sandboxDirectory = sandboxDirectory
        self.tmpDirectory = tmpDirectory
        self.readOnlyMasterRoot = readOnlyMasterRoot
    }

    /// 신규 룸 샌드박스를 디스크에 원자적으로 할당한다.
    public static func allocate(
        tenant: String,
        agentID: String? = nil,
        roomID: String? = nil,
        homeDirectory: String = StateRootKit.resolveHost(environment: [:])
    ) throws -> SandboxContext {
        var cleanTenant = tenant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleanTenant.hasPrefix("tenant:") {
            cleanTenant = String(cleanTenant.dropFirst(7))
        }
        cleanTenant = cleanTenant.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        if cleanTenant.isEmpty { cleanTenant = "default" }

        let rawRoom = roomID ?? "room-\(cleanTenant)-\(UUID().uuidString.prefix(8).lowercased())"
        var cleanRoomID = rawRoom.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        if cleanRoomID.isEmpty { cleanRoomID = "room-default" }

        let sandboxesRoot = SandboxLayout.url(sandboxesDirectoryName, homeDirectory: homeDirectory)
        let roomDir = sandboxesRoot.appendingPathComponent(cleanRoomID, isDirectory: true)
        let tmpDir = roomDir.appendingPathComponent("tmp", isDirectory: true)
        let masterRoot = SandboxLayout.url(".tenants/\(cleanTenant)", homeDirectory: homeDirectory)

        let fm = FileManager.default
        try fm.createDirectory(at: roomDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        return SandboxContext(
            roomID: cleanRoomID,
            tenantSlug: cleanTenant,
            agentID: agentID,
            sandboxDirectory: roomDir,
            tmpDirectory: tmpDir,
            readOnlyMasterRoot: masterRoot
        )
    }

    /// 샌드박스 내부 프로세스에 주입할 격리 환경변수 테이블을 생성한다.
    public func makeEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var env = base
        env["TENANT_ID"] = tenantSlug
        env["GUJO_TENANT_ID"] = tenantSlug
        env["SWIFT_APP_STATE_ROOT"] = sandboxDirectory.path
        env["TMPDIR"] = tmpDirectory.path
        if let agentID {
            env["AGENT_ID"] = agentID
        }
        env["SANDBOX_ROOM_ID"] = roomID
        env["SANDBOX_ACTIVE"] = "1"
        return env
    }

    /// 샌드박스를 보호할 Seatbelt 커널 프로필을 생성한다.
    public func generateProfile(allowNetwork: Bool = true, extraAllowedPaths: [String] = []) -> SeatbeltProfile {
        SeatbeltProfile(
            sandboxPath: sandboxDirectory.path,
            tmpPath: tmpDirectory.path,
            allowedWritePaths: extraAllowedPaths,
            allowNetwork: allowNetwork
        )
    }

    /// 샌드박스 디렉터리를 7일 보관소(.archive/)로 이동 보관(기본값)하거나 즉시 영구 소각한다.
    public func teardown(archive: Bool = true) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sandboxDirectory.path) else { return }

        if archive {
            try RoomArchive.archive(
                roomID: roomID,
                homeDirectory: sandboxDirectory.deletingLastPathComponent().deletingLastPathComponent().path
            )
        } else {
            try fm.removeItem(at: sandboxDirectory)
        }
    }
}
