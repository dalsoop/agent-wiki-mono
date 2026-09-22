import Foundation
import SessionKit

/// 파일시스템 격리 벽 (Anthropic sandbox-runtime srt 스키마 대응)
///
/// 읽기는 거부 후 허용(`denyRead` / `allowRead`),
/// 쓰기는 허용 목록만(`allowWrite`, 그 안에서 `denyWrite` 우선).
/// 상대경로는 `workdir` 기준이라는 규칙을 따르며, `resolved(workdir:)` 로 정규화한다.
public struct FilesystemWall: Codable, Equatable, Sendable {
    public var denyRead: [String]
    public var allowRead: [String]
    public var allowWrite: [String]
    public var denyWrite: [String]

    public init(
        denyRead: [String] = [],
        allowRead: [String] = [],
        allowWrite: [String] = [],
        denyWrite: [String] = []
    ) {
        self.denyRead = denyRead
        self.allowRead = allowRead
        self.allowWrite = allowWrite
        self.denyWrite = denyWrite
    }
}

/// 네트워크 격리 벽 (srt 스키마 대응: allowedDomains, deniedDomains, allowLocalBinding 지원)
public typealias NetworkWallSpec = NetworkWall

/// 실행 가능 바이너리 격리 정책
public enum ExecutablesWall: Codable, Equatable, Sendable {
    case hostPath
    case allowList([String])

    enum CodingKeys: String, CodingKey {
        case mode
        case list
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try container.decode(String.self, forKey: .mode)
        if mode == "hostPath" {
            self = .hostPath
        } else {
            let list = try container.decodeIfPresent([String].self, forKey: .list) ?? []
            self = .allowList(list)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hostPath:
            try container.encode("hostPath", forKey: .mode)
        case .allowList(let list):
            try container.encode("allowList", forKey: .mode)
            try container.encode(list, forKey: .list)
        }
    }
}

/// 셸 격리 정책
public enum ShellWall: String, Codable, Equatable, Sendable {
    case restricted
    case normal
}

/// 방의 벽(Wall). 파일시스템, 네트워크, 소켓, 실행 파일, 셸 정책을 통합 정의한다.
///
/// 상대경로는 `workdir` 기준이라는 규칙을 따르며, `resolved(workdir:)` 로 정규화된다.
public struct RoomWalls: Codable, Equatable, Sendable {
    /// 호스트 환경에서 항상 쓰기가 금지되는 시스템 민감 경로 목록
    public static let mandatoryDenyWrite: [String] = [
        ".zshrc",
        ".zshenv",
        ".zprofile",
        ".bashrc",
        ".bash_profile",
        ".profile",
        ".gitconfig",
        ".git/hooks",
    ]

    /// SwiftPM 이 홈 밑에 쓰는 캐시·보안 폴더
    public static let swiftPMHomeDirectories = [
        "Library/Caches/org.swift.swiftpm",
        "Library/org.swift.swiftpm",
        ".swiftpm",
    ]

    public var filesystem: FilesystemWall
    public var network: NetworkWallSpec
    public var unixSockets: [String]
    public var executables: ExecutablesWall
    public var shell: ShellWall

    public init(
        filesystem: FilesystemWall = FilesystemWall(),
        network: NetworkWallSpec = .closed,
        unixSockets: [String] = [],
        executables: ExecutablesWall = .allowList([]),
        shell: ShellWall = .restricted
    ) {
        self.filesystem = filesystem
        self.network = network
        self.unixSockets = unixSockets
        self.executables = executables
        self.shell = shell
    }

    /// 레거시 생성자 호환 (writePaths + NetworkWall)
    public init(writePaths: [String] = [], network: NetworkWall = .closed) {
        self.filesystem = FilesystemWall(
            denyRead: [],
            allowRead: [],
            allowWrite: writePaths,
            denyWrite: Self.mandatoryDenyWrite
        )
        self.network = network
        self.unixSockets = []
        self.executables = .allowList([])
        self.shell = .restricted
    }

    /// 레거시 writePaths 호환 프로퍼티
    public var writePaths: [String] {
        get { filesystem.allowWrite }
        set { filesystem.allowWrite = newValue }
    }

    /// 레거시 legacyNetwork 호환 프로퍼티
    public var legacyNetwork: NetworkWall {
        get { network }
        set { network = newValue }
    }

    public var isReadOnly: Bool { filesystem.allowWrite.isEmpty }

    /// 프리셋으로부터 RoomWalls 사본 생성
    public static func preset(_ preset: RoomWallPreset, toolbelt: [String] = []) -> RoomWalls {
        switch preset {
        case .readOnly:
            return RoomWalls(
                filesystem: FilesystemWall(
                    denyRead: [],
                    allowRead: ["/"],
                    allowWrite: [],
                    denyWrite: mandatoryDenyWrite
                ),
                network: .closed,
                unixSockets: [],
                executables: .allowList(toolbelt),
                shell: .restricted
            )
        case .toolbelt:
            return RoomWalls(
                filesystem: FilesystemWall(
                    denyRead: [],
                    allowRead: ["/"],
                    allowWrite: [],
                    denyWrite: mandatoryDenyWrite
                ),
                network: .closed,
                unixSockets: [],
                executables: .allowList(toolbelt),
                shell: .restricted
            )
        case .open:
            return RoomWalls(
                filesystem: FilesystemWall(
                    denyRead: [],
                    allowRead: ["/"],
                    allowWrite: ["/"],
                    denyWrite: mandatoryDenyWrite
                ),
                network: .open,
                unixSockets: [],
                executables: .hostPath,
                shell: .normal
            )
        }
    }

    /// 상대경로는 workdir 기준이라는 규칙을 적용하여 절대경로로 정규화한 RoomWalls 사본을 반환한다.
    /// workdir 가 없으면(nil 또는 빈 문자열) 상대경로는 그대로 유지된다.
    public func resolved(workdir: String?) -> RoomWalls {
        guard let workdir, !workdir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return self
        }
        let normalizedWorkdir = (workdir as NSString).standardizingPath
        func resolvePaths(_ paths: [String]) -> [String] {
            paths.map { raw in
                let trimmed = raw.replacingOccurrences(of: "/**", with: "")
                if trimmed.hasPrefix("/") { return trimmed }
                if trimmed.hasPrefix("~") { return (trimmed as NSString).expandingTildeInPath }
                return (normalizedWorkdir as NSString).appendingPathComponent(trimmed)
            }
        }
        var copy = self
        copy.filesystem.denyRead = resolvePaths(filesystem.denyRead)
        copy.filesystem.allowRead = resolvePaths(filesystem.allowRead)
        copy.filesystem.allowWrite = resolvePaths(filesystem.allowWrite)
        copy.filesystem.denyWrite = resolvePaths(filesystem.denyWrite)
        return copy
    }

    /// 에이전트 CLI 가 자기 세션·자격증명을 쓰는 홈 밑 폴더 목록
    public static func agentStatePaths(tool: AgentTool, homeDirectory: String) -> [String] {
        let home = (homeDirectory as NSString).standardizingPath
        switch tool {
        case .claude:
            return [
                (home as NSString).appendingPathComponent(".claude"),
                (home as NSString).appendingPathComponent(".claude.json"),
            ]
        case .codex:
            return [(home as NSString).appendingPathComponent(".codex")]
        case .grok:
            return [(home as NSString).appendingPathComponent(".grok")]
        case .agy:
            return [(home as NSString).appendingPathComponent(".gemini")]
        case .opencode, .cursor:
            return [(home as NSString).appendingPathComponent(".\(tool.rawValue)")]
        }
    }

    /// open 프리셋 등에서 필요한 툴체인 쓰기 경로(에이전트 상태 폴더, SwiftPM 캐시, git 공용 저장소)를
    /// 스펙의 allowWrite 에 명시적으로 추가하여 반환한다 (숨은 예외 금지).
    /// gitDir 은 호출자가 파일시스템을 확인하여 구한 공용 bare/git 디렉터리 경로.
    public func withDefaultToolchainWrites(
        for tool: AgentTool?,
        workdir: String? = nil,
        homeDirectory: String,
        gitDir: String? = nil
    ) -> RoomWalls {
        var copy = self
        var extra: [String] = []

        if let tool {
            extra.append(contentsOf: Self.agentStatePaths(tool: tool, homeDirectory: homeDirectory))
        }
        extra.append(contentsOf: Self.toolchainExtraPaths(
            shell: shell, executables: executables,
            homeDirectory: homeDirectory, gitDir: gitDir))

        for path in extra where !copy.filesystem.allowWrite.contains(path) {
            copy.filesystem.allowWrite.append(path)
        }
        return copy
    }

    private static func toolchainExtraPaths(
        shell: ShellWall,
        executables: ExecutablesWall,
        homeDirectory: String,
        gitDir: String?
    ) -> [String] {
        guard shell == .normal || executables == .hostPath else { return [] }
        let home = (homeDirectory as NSString).standardizingPath
        var paths = Self.swiftPMHomeDirectories.map { (home as NSString).appendingPathComponent($0) }
        if let gitDir, !gitDir.isEmpty {
            paths.append(gitDir)
        }
        return paths
    }

    /// 자식 벽은 부모의 부분집합. 네트워크는 교집합.
    public func intersection(child: RoomWalls) -> RoomWalls {
        let survivingPaths = child.filesystem.allowWrite.filter { childPath in
            filesystem.allowWrite.contains { parentPath in
                RoomWalls.covers(parent: parentPath, child: childPath)
            }
        }
        let interNetwork = network.intersection(child.network)

        return RoomWalls(
            filesystem: FilesystemWall(
                denyRead: Array(Set(filesystem.denyRead + child.filesystem.denyRead)),
                allowRead: child.filesystem.allowRead,
                allowWrite: survivingPaths,
                denyWrite: Array(Set(filesystem.denyWrite + child.filesystem.denyWrite))
            ),
            network: interNetwork,
            unixSockets: child.unixSockets.filter { unixSockets.contains($0) },
            executables: child.executables,
            shell: shell == .restricted ? .restricted : child.shell
        )
    }

    /// 부모 glob 이 자식 glob 을 덮는가 — 보수적 프리픽스 판정.
    public static func covers(parent: String, child: String) -> Bool {
        if parent == child { return true }
        guard parent.hasSuffix("/**") else { return false }
        let parentBase = String(parent.dropLast(3))
        let childBase = child.hasSuffix("/**") ? String(child.dropLast(3)) : child
        return childBase == parentBase || childBase.hasPrefix(parentBase + "/")
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case filesystem
        case network
        case unixSockets
        case executables
        case shell
        case writePaths
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // 1. filesystem 또는 레거시 writePaths 디코딩
        if let fs = try container.decodeIfPresent(FilesystemWall.self, forKey: .filesystem) {
            self.filesystem = fs
        } else if let wp = try container.decodeIfPresent([String].self, forKey: .writePaths) {
            self.filesystem = FilesystemWall(
                denyRead: [],
                allowRead: [],
                allowWrite: wp,
                denyWrite: Self.mandatoryDenyWrite
            )
        } else {
            self.filesystem = FilesystemWall()
        }

        // 2. network 디코딩 (NetworkWall: Bool, String, 또는 Object 지원)
        do {
            self.network = try container.decode(NetworkWall.self, forKey: .network)
        } catch {
            self.network = .closed
        }

        self.unixSockets = try container.decodeIfPresent([String].self, forKey: .unixSockets) ?? []
        self.executables = try container.decodeIfPresent(ExecutablesWall.self, forKey: .executables) ?? .allowList([])
        self.shell = try container.decodeIfPresent(ShellWall.self, forKey: .shell) ?? .restricted
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(filesystem, forKey: .filesystem)
        try container.encode(network, forKey: .network)
        try container.encode(unixSockets, forKey: .unixSockets)
        try container.encode(executables, forKey: .executables)
        try container.encode(shell, forKey: .shell)
        try container.encode(filesystem.allowWrite, forKey: .writePaths)
    }
}
