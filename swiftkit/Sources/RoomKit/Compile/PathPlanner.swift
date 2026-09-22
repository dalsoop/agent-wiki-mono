import Foundation

/// 방의 bin/ 심링크 계획 산출물
public struct PathPlan: Equatable, Sendable {
    public var links: [(name: String, destination: String)]
    public var excluded: [String]

    public init(links: [(name: String, destination: String)] = [], excluded: [String] = []) {
        self.links = links
        self.excluded = excluded
    }

    public var names: Set<String> { Set(links.map(\.name)) }

    public static func == (lhs: PathPlan, rhs: PathPlan) -> Bool {
        let lhsFormatted = lhs.links.map { "\($0.name)=\($0.destination)" }
        let rhsFormatted = rhs.links.map { "\($0.name)=\($0.destination)" }
        return lhsFormatted == rhsFormatted && lhs.excluded == rhs.excluded
    }
}

/// 방 PATH 및 bin 디렉터리 심링크 순수 플래너 (L3)
public enum PathPlanner {
    public static let toolbeltLimit = RoomWallPreset.toolbeltLimit

    /// 기본 POSIX 도구명 목록
    public static let standardPosixNames: [String] = [
        "cat", "cp", "date", "echo", "env", "false", "ls", "mkdir", "mv",
        "pwd", "rm", "sh", "sleep", "test", "true"
    ]

    /// 에이전트 CLI 가 필요로 하는 시스템 도우미 목록 (예: claude -> security)
    public static let agentHelpers: [String: [String]] = [
        "claude": ["security"]
    ]

    /// 방 벽 스펙과 사용 가능한 도구 딕셔너리(`[toolName: binaryPath]`)를 받아 bin 계획을 수립한다.
    public static func plan(
        walls: RoomWalls,
        availableTools: [String: String],
        posixNames: [String] = standardPosixNames,
        selfCLIName: String = "agent-room-terminal"
    ) -> PathPlan {
        switch walls.executables {
        case .hostPath:
            return PathPlan(links: [], excluded: [])

        case .allowList(let toolbelt):
            var links: [(name: String, destination: String)] = []
            var excluded: [String] = []

            appendBaseLinks(
                availableTools: availableTools,
                posixNames: posixNames,
                selfCLIName: selfCLIName,
                links: &links,
                excluded: &excluded
            )

            appendToolbeltLinks(
                toolbelt: toolbelt,
                availableTools: availableTools,
                posixNames: posixNames,
                selfCLIName: selfCLIName,
                links: &links,
                excluded: &excluded
            )

            appendHelperLinks(
                availableTools: availableTools,
                links: &links
            )

            return PathPlan(links: links, excluded: excluded)
        }
    }

    private static func appendBaseLinks(
        availableTools: [String: String],
        posixNames: [String],
        selfCLIName: String,
        links: inout [(name: String, destination: String)],
        excluded: inout [String]
    ) {
        for name in posixNames {
            guard let dest = availableTools[name] else { continue }
            links.append((name, dest))
        }

        if let dest = availableTools[selfCLIName] {
            links.append((selfCLIName, dest))
        } else if !excluded.contains(selfCLIName) {
            excluded.append(selfCLIName)
        }
    }

    private static func appendToolbeltLinks(
        toolbelt: [String],
        availableTools: [String: String],
        posixNames: [String],
        selfCLIName: String,
        links: inout [(name: String, destination: String)],
        excluded: inout [String]
    ) {
        var linkedCount = 0
        for name in toolbelt {
            guard name != selfCLIName, !posixNames.contains(name) else { continue }
            guard let dest = availableTools[name] else {
                if !excluded.contains(name) { excluded.append(name) }
                continue
            }
            guard linkedCount < toolbeltLimit else { continue }
            guard !links.contains(where: { $0.name == name }) else { continue }
            links.append((name, dest))
            linkedCount += 1
        }
    }

    private static func appendHelperLinks(
        availableTools: [String: String],
        links: inout [(name: String, destination: String)]
    ) {
        for (tool, helpers) in agentHelpers {
            guard availableTools[tool] != nil || links.contains(where: { $0.name == tool }) else { continue }
            for helper in helpers {
                guard let dest = availableTools[helper] else { continue }
                guard !links.contains(where: { $0.name == helper }) else { continue }
                links.append((helper, dest))
            }
        }
    }

    /// 설계도 writePaths 의 `/**` 꼬리를 떼고, 상대경로는 작업 디렉터리(worktree) 기준으로 편다.
    /// workdir 이 없으면 방 폴더 기준이다(실측 2026-09-05: 방 폴더 기준으로 풀면 worktree 쓰기가 전부 막힌다).
    public static func resolvedWritePaths(
        roomPath: String,
        workdir: String? = nil,
        writePaths: [String]
    ) -> [String] {
        let base = (workdir?.isEmpty == false ? workdir : nil) ?? roomPath
        return writePaths.map { raw in
            let trimmed = raw.replacingOccurrences(of: "/**", with: "")
            if trimmed.hasPrefix("/") { return trimmed }
            return (base as NSString).appendingPathComponent(trimmed)
        }
    }

    /// Antigravity CLI(agy) 의 홈 밑 상태 폴더 이름. 세션 DB·bin/agentapi 가 여기 쓰인다.
    public static let agyStateDirectory = ".gemini"

    /// SwiftPM 이 홈 밑에 쓰는 캐시·보안 폴더. open 프리셋(코드 작업 방)에서만 연다.
    public static let swiftPMHomeDirectories = RoomWalls.swiftPMHomeDirectories

    /// open 프리셋에서 컴파일·커밋이 되게 하는 쓰기 예외 — SwiftPM 홈 캐시와 workdir 의 git 저장소.
    /// toolbelt·readOnly 는 빈 배열(실측 2026-09-05: 캐시 쓰기 거부로 `swift build` 불가, bare 저장소 거부로 커밋 불가).
    public static func buildToolchainStatePaths(
        preset: RoomWallPreset,
        workdir: String?,
        homeDirectory: String
    ) -> [String] {
        guard preset == .open else { return [] }
        let home = homeDirectory as NSString
        var paths = swiftPMHomeDirectories.map { home.appendingPathComponent($0) }
        if let gitDir = gitRepositoryWritePath(workdir: workdir) {
            paths.append(gitDir)
        }
        return paths
    }

    /// 에이전트 CLI 가 자기 세션·자격증명을 쓰는 홈 밑 폴더. 그 도구가 방에 링크될 때만 연다.
    /// 홈 전체 쓰기 차단은 유지되고 이 폴더들만 예외다(실측 2026-09-03: HOME 쓰기 불가 → claude 세션 기록 실패).
    public static func agentStatePaths(agentTools: [String], homeDirectory: String) -> [String] {
        var paths: [String] = []
        for name in agentTools {
            guard let tool = AgentTool(rawValue: name) else { continue }
            paths.append(contentsOf: RoomWalls.agentStatePaths(tool: tool, homeDirectory: homeDirectory))
        }
        return paths
    }

    /// workdir 의 git 저장소 쓰기 경로. `.git` 이 디렉터리면 그 자체, worktree(`.git` 파일의
    /// `gitdir: <bare>/worktrees/<name>`)면 공용 저장소(`<bare>`) — objects·refs·worktree 메타가 모두 그 밑이다.
    public static func gitRepositoryWritePath(
        workdir: String?,
        fileManager: FileManager = .default
    ) -> String? {
        guard let workdir, !workdir.isEmpty else { return nil }
        let dotGit = (workdir as NSString).appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: dotGit, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue { return dotGit }
        let text: String
        do {
            text = try String(contentsOfFile: dotGit, encoding: .utf8)
        } catch {
            return nil
        }
        return gitCommonDirectory(fromGitFile: text, workdir: workdir)
    }

    /// `.git` 파일 본문(`gitdir: …`)에서 공용 저장소 경로를 푼다. 순수 함수 — 테스트용.
    public static func gitCommonDirectory(fromGitFile text: String, workdir: String) -> String? {
        let prefix = "gitdir:"
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        guard line.hasPrefix(prefix) else { return nil }
        var target = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        if !target.hasPrefix("/") {
            target = (workdir as NSString).appendingPathComponent(target)
        }
        let standardized = (target as NSString).standardizingPath
        let components = (standardized as NSString).pathComponents
        guard let index = components.lastIndex(of: "worktrees"), index > 0 else {
            return standardized
        }
        return NSString.path(withComponents: Array(components[..<index]))
    }

    /// `.git` 파일 본문(`gitdir: …`)에서 worktree 전용 gitdir 경로를 푼다. (예: `<bare>/worktrees/<name>`)
    public static func gitWorktreeDirectory(fromGitFile text: String, workdir: String) -> String? {
        let prefix = "gitdir:"
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        guard line.hasPrefix(prefix) else { return nil }
        var target = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        if !target.hasPrefix("/") {
            target = (workdir as NSString).appendingPathComponent(target)
        }
        return (target as NSString).standardizingPath
    }

    /// workdir 의 git 저장소 구조를 해석하여 dotGit 파일/디렉터리, worktree 전용 gitdir, 공용 bare gitdir 을 일괄 반환한다.
    public static func resolveGitDirectories(
        workdir: String?,
        fileManager: FileManager = .default
    ) -> (dotGitPath: String, worktreeGitDir: String?, commonGitDir: String)? {
        guard let workdir, !workdir.isEmpty else { return nil }
        let stdWorkdir = (workdir as NSString).standardizingPath
        let dotGit = (stdWorkdir as NSString).appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: dotGit, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue {
            return (dotGitPath: dotGit, worktreeGitDir: nil, commonGitDir: dotGit)
        }
        guard let text = try? String(contentsOfFile: dotGit, encoding: .utf8) else {
            return nil
        }
        let worktreeDir = gitWorktreeDirectory(fromGitFile: text, workdir: stdWorkdir)
        let commonDir = gitCommonDirectory(fromGitFile: text, workdir: stdWorkdir) ?? dotGit
        return (dotGitPath: dotGit, worktreeGitDir: worktreeDir, commonGitDir: commonDir)
    }
}
