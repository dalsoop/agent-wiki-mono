import Foundation

/// macOS Seatbelt 컴파일 결과 산출물 (L3)
public struct SeatbeltCompilationResult: Equatable, Sendable {
    public var profile: String
    public var env: [String: String]
    public var writePaths: [String]

    public init(
        profile: String,
        env: [String: String] = [:],
        writePaths: [String] = []
    ) {
        self.profile = profile
        self.env = env
        self.writePaths = writePaths
    }
}

/// macOS Seatbelt (`sandbox-exec`) 프로필 순수 컴파일러 (L3)
public enum SeatbeltCompiler {
    /// RoomSpec 과 실행 환경으로부터 Seatbelt 프로필 Scheme, env, 정규화된 writePaths 를 일괄 컴파일한다.
    public static func compile(
        spec: RoomSpec,
        roomDir: String? = nil,
        home: String = NSHomeDirectory(),
        proxyPort: UInt16? = nil,
        agentTools: [String] = []
    ) -> SeatbeltCompilationResult {
        let stdRoomDir = roomDir ?? RoomPaths.roomDirectory(
            tenant: spec.tenant,
            roomID: spec.roomID.uuidString,
            homeDirectory: home
        ).path
        let resolvedWrites = PathPlanner.resolvedWritePaths(
            roomPath: stdRoomDir,
            workdir: spec.workdir,
            writePaths: spec.walls.filesystem.allowWrite
        )
        var walls = spec.walls
        walls.filesystem.allowWrite = resolvedWrites

        let gitDir = PathPlanner.gitRepositoryWritePath(workdir: spec.workdir)
        walls = resolveToolchainWrites(
            walls: walls,
            spec: spec,
            agentTools: agentTools,
            home: home,
            gitDir: gitDir
        )

        let profileStr = profile(
            walls: walls,
            workdir: spec.workdir,
            roomDir: stdRoomDir,
            home: home,
            proxyPort: proxyPort
        )

        let env = proxyEnvironment(network: walls.network, proxyPort: proxyPort)
        return SeatbeltCompilationResult(
            profile: profileStr,
            env: env,
            writePaths: walls.filesystem.allowWrite
        )
    }

    private static func resolveToolchainWrites(
        walls: RoomWalls,
        spec: RoomSpec,
        agentTools: [String],
        home: String,
        gitDir: String?
    ) -> RoomWalls {
        var currentWalls = walls
        var toolCandidates: [AgentTool] = []
        if let launchTool = spec.launch?.tool {
            toolCandidates.append(launchTool)
        }
        for name in agentTools {
            if let tool = AgentTool(rawValue: name), !toolCandidates.contains(tool) {
                toolCandidates.append(tool)
            }
        }
        if case .allowList(let list) = spec.walls.executables {
            for name in list {
                if let tool = AgentTool(rawValue: name), !toolCandidates.contains(tool) {
                    toolCandidates.append(tool)
                }
            }
        }
        if toolCandidates.isEmpty {
            return currentWalls.withDefaultToolchainWrites(
                for: nil,
                workdir: spec.workdir,
                homeDirectory: home,
                gitDir: gitDir
            )
        }
        for tool in toolCandidates {
            currentWalls = currentWalls.withDefaultToolchainWrites(
                for: tool,
                workdir: spec.workdir,
                homeDirectory: home,
                gitDir: gitDir
            )
        }
        return currentWalls
    }

    private static func proxyEnvironment(
        network: NetworkWallSpec,
        proxyPort: UInt16?
    ) -> [String: String] {
        var env: [String: String] = [:]
        switch network {
        case .open:
            env["HTTP_PROXY"] = ""
            env["HTTPS_PROXY"] = ""
            env["ALL_PROXY"] = ""
        case .closed:
            env["HTTP_PROXY"] = "http://127.0.0.1:9"
            env["HTTPS_PROXY"] = "http://127.0.0.1:9"
            env["ALL_PROXY"] = "http://127.0.0.1:9"
        case .allow:
            let proxyVal = proxyPort.map { "http://localhost:\($0)" } ?? "http://127.0.0.1:9"
            env["HTTP_PROXY"] = proxyVal
            env["HTTPS_PROXY"] = proxyVal
            env["ALL_PROXY"] = proxyVal
        }
        return env
    }

    /// 방의 벽 스펙과 디렉터리 경로들로부터 Seatbelt 프로필 Scheme 문자열을 생성한다.
    public static func profile(
        walls: RoomWalls,
        workdir: String? = nil,
        roomDir: String,
        home: String,
        proxyPort: UInt16? = nil
    ) -> String {
        let resolved = walls.resolved(workdir: workdir)
        let stdRoomDir = (roomDir as NSString).standardizingPath
        let stdTmpDir = ((roomDir as NSString).appendingPathComponent("tmp") as NSString).standardizingPath
        let stdHome = (home as NSString).standardizingPath

        var lines: [String] = [
            ";; Pure One-Way Room Sandbox Seatbelt Profile (v1)",
            "(version 1)",
            "(allow default)",
        ]

        lines.append(contentsOf: networkRules(network: resolved.network, proxyPort: proxyPort))
        lines.append(contentsOf: baseSandboxRules(home: stdHome, roomDir: stdRoomDir, tmpDir: stdTmpDir))
        lines.append(contentsOf: fileWriteRules(walls: resolved))
        lines.append(contentsOf: fileDenyRules(walls: resolved, home: stdHome))
        lines.append(contentsOf: fileReadRules(walls: resolved))

        return lines.joined(separator: "\n") + "\n"
    }

    private static func networkRules(network: NetworkWallSpec, proxyPort: UInt16?) -> [String] {
        if let port = proxyPort {
            return [
                "(deny network-outbound)",
                "(allow network-outbound (remote ip \"localhost:\(port)\"))",
                "(allow network-outbound (remote ip \"*:\(port)\"))",
            ]
        }
        if network.isClosed {
            return ["(deny network*)"]
        }
        return []
    }

    private static func baseSandboxRules(home: String, roomDir: String, tmpDir: String) -> [String] {
        [
            ";; 1. 홈 디렉터리 기본 쓰기 차단",
            "(deny file-write* (subpath \"\(escapePath(home))\"))",
            ";; 2. 룸 스크래치패드 및 임시 디렉터리만 쓰기 허용",
            "(allow file-write* (subpath \"\(escapePath(roomDir))\"))",
            "(allow file-write* (subpath \"\(escapePath(tmpDir))\"))",
            "(allow file-write* (literal \"/dev/null\"))",
            "(allow file-write* (literal \"/dev/zero\"))",
            "(allow file-write* (literal \"/dev/dtracehelper\"))",
            "(allow file-write* (literal \"/dev/tty\"))",
            "(allow file-write* (subpath \"/private/tmp\"))",
            "(allow file-write* (subpath \"/private/var/folders\"))",
        ]
    }

    private static func fileWriteRules(walls: RoomWalls) -> [String] {
        var lines: [String] = []
        var allowedPathsSeen = Set<String>()
        for raw in walls.filesystem.allowWrite {
            let std = (raw as NSString).standardizingPath
            guard !std.isEmpty, !allowedPathsSeen.contains(std) else { continue }
            allowedPathsSeen.insert(std)
            lines.append("(allow file-write* (subpath \"\(escapePath(std))\"))")
        }
        return lines
    }

    private static func fileDenyRules(walls: RoomWalls, home: String) -> [String] {
        var lines: [String] = []
        var deniedPathsSeen = Set<String>()
        for raw in walls.filesystem.denyWrite {
            let expanded: String
            if raw.hasPrefix("/") {
                expanded = raw
            } else if raw.hasPrefix("~") {
                expanded = (raw as NSString).expandingTildeInPath
            } else {
                expanded = (home as NSString).appendingPathComponent(raw)
            }
            let std = (expanded as NSString).standardizingPath
            guard !std.isEmpty, !deniedPathsSeen.contains(std) else { continue }
            deniedPathsSeen.insert(std)
            lines.append("(deny file-write* (subpath \"\(escapePath(std))\"))")
        }
        return lines
    }

    private static func fileReadRules(walls: RoomWalls) -> [String] {
        var lines: [String] = []
        for raw in walls.filesystem.denyRead {
            let std = (raw as NSString).standardizingPath
            guard !std.isEmpty else { continue }
            lines.append("(deny file-read* (subpath \"\(escapePath(std))\"))")
        }
        for raw in walls.filesystem.allowRead {
            let std = (raw as NSString).standardizingPath
            guard !std.isEmpty, std != "/" else { continue }
            lines.append("(allow file-read* (subpath \"\(escapePath(std))\"))")
        }
        return lines
    }

    public static func escapePath(_ path: String) -> String {
        let noNewlines = path.replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        return noNewlines
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
