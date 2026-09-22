import Foundation
import SessionKit

/// 네 툴의 세션 저장소를 하나의 목록으로 합친다.
public struct SessionIndex: Sendable {
    let grok: GrokSessionReader
    let claude: ClaudeSessionReader
    let codex: CodexSessionReader
    let agy: AntigravitySessionReader

    public init(
        grok: GrokSessionReader = .init(),
        claude: ClaudeSessionReader = .init(),
        codex: CodexSessionReader = .init(),
        agy: AntigravitySessionReader = .init()
    ) {
        self.grok = grok
        self.claude = claude
        self.codex = codex
        self.agy = agy
    }

    /// 설치돼 있고 세션이 실제로 있는 툴만 훑는다.
    public func discover(tools: Set<AgentTool> = Set(AgentTool.allCases), limitPerTool: Int = 500) -> [SessionRef] {
        var out: [SessionRef] = []
        if tools.contains(.grok)   { out += grok.discover(limit: limitPerTool) }
        if tools.contains(.claude) { out += claude.discover(limit: limitPerTool) }
        if tools.contains(.codex)  { out += codex.discover(limit: limitPerTool) }
        if tools.contains(.agy)    { out += agy.discover(limit: limitPerTool) }
        return out.sorted { $0.lastActive > $1.lastActive }
    }

    /// 특정 작업 디렉터리에서 돌던 세션만. 워크트리 하위도 같은 프로젝트로 친다.
    public func discover(cwd: String, tools: Set<AgentTool> = Set(AgentTool.allCases)) -> [SessionRef] {
        discover(tools: tools).filter { Self.isSameProject($0.cwd, cwd) }
    }

    /// 두 경로가 같은 프로젝트인가. 한쪽이 다른 쪽의 하위(워크트리 등)여도 같게 본다.
    ///
    /// bare + worktree 구조(`<repo>/.bare`, `<repo>/.worktrees/<name>`)도 같은 저장소로
    /// 인식한다 — `.bare` 에서 시작된 세션이 프로젝트 필터에 안 걸리던 원인(실측 2026-08-14).
    ///
    /// 이미 훑어둔 목록을 다시 거를 때 쓴다 — 디스크를 두 번 훑지 않으려고 공개해 둔다.
    public static func isSameProject(_ a: String, _ b: String) -> Bool {
        let x = normalize(a), y = normalize(b)
        guard !x.isEmpty, !y.isEmpty, x != "/", y != "/" else { return false }
        if x == y || x.hasPrefix(y + "/") || y.hasPrefix(x + "/") { return true }
        let rx = repoRoot(x), ry = repoRoot(y)
        if rx != x || ry != y {
            return rx == ry || rx.hasPrefix(ry + "/") || ry.hasPrefix(rx + "/")
        }
        return false
    }

    /// bare/worktree 경로를 저장소 루트로 올린다.
    /// `<repo>/.bare` → `<repo>`, `<repo>/.worktrees/<name>` → `<repo>`.
    static func repoRoot(_ path: String) -> String {
        let ns = path as NSString
        if ns.lastPathComponent == ".bare" { return ns.deletingLastPathComponent }
        let parent = ns.deletingLastPathComponent
        if (parent as NSString).lastPathComponent == ".worktrees" {
            return (parent as NSString).deletingLastPathComponent
        }
        return path
    }

    /// id 로 세션 하나를 찾는다. 접두사도 받되 **모호하면 실패**한다 —
    /// 실측에서 8자 접두사가 겹치는 세션이 있었다(`019f9e58-5214…` vs `019f9e58-40f7…`).
    /// 조용히 엉뚱한 세션을 인수인계하는 것보다 못 찾았다고 하는 게 낫다.
    ///
    /// 각 리더의 `findPrefix(id:limit:2)` 를 호출해 전체 discover 풀스캔을 건너뛴다.
    /// 같은 툴 내 접두사 충돌도 감지한다(limit 2 → 2개 이상이면 ambiguous).
    public func find(id: String) throws -> SessionRef {
        var matches: [SessionRef] = []
        matches += claude.findPrefix(id: id, limit: 2)
        matches += codex.findPrefix(id: id, limit: 2)
        matches += grok.findPrefix(id: id, limit: 2)
        matches += agy.findPrefix(id: id, limit: 2)
        if let exact = matches.first(where: { $0.id == id }) { return exact }
        switch matches.count {
        case 0: throw LookupError.notFound(id)
        case 1: return matches[0]
        default: throw LookupError.ambiguous(id, matches.map(\.id))
        }
    }

    public enum LookupError: Error, CustomStringConvertible {
        case notFound(String)
        case ambiguous(String, [String])

        public var description: String {
            switch self {
            case .notFound(let id):
                return "세션을 찾을 수 없다: \(id)"
            case .ambiguous(let id, let ids):
                return "접두사 '\(id)' 가 \(ids.count)개 세션에 걸린다 — 전체 id 로 지정할 것:\n"
                    + ids.prefix(5).map { "  " + $0 }.joined(separator: "\n")
            }
        }
    }

    /// - Parameter window: 읽을 구간. 기본은 머리+꼬리만 — 큰 세션에서 체감이 크다.
    ///   드리프트 감지처럼 빠짐없이 봐야 하면 `.full`.
    /// - Parameter recoverIfEmpty: 창이 비면 `.full` 로 재시도할지. 팩 생성 기본은 true.
    ///   **health/`doctor` 는 false 로 둔다** — 빈 창이 초대형 세션 전체 재파싱(수분)을
    ///   촉발해 health 가 42초·3분이 됐던 원인(2026-07-29 실측).
    public func digest(
        _ ref: SessionRef,
        window: DigestWindow = .standard,
        recoverIfEmpty: Bool = true
    ) -> SessionDigest {
        let d = rawDigest(ref, window: window)
        // **바이트 창이 굶는 경우가 있다.** codex 세션은 줄이 몇 백 개뿐인데 한 줄이 2MB 씩
        // 되기도 한다(이미지). 그러면 꼬리 8MB 안에 온전한 줄이 8개밖에 안 들어오고, 그
        // 8개가 하필 메타데이터면 팩이 **통째로 빈다**(실측: 228MB·811줄 세션에서 지시 0개).
        // 창은 크기를 줄이려는 최적화지 내용을 버리는 규칙이 아니므로, 빈손이면 다시 읽는다.
        guard recoverIfEmpty, window.isTruncating, d.userMessages.isEmpty, d.commands.isEmpty else { return d }
        return rawDigest(ref, window: .full)
    }

    private func rawDigest(_ ref: SessionRef, window: DigestWindow) -> SessionDigest {
        switch ref.tool {
        case .grok:   return grok.digest(ref, window: window)
        case .claude: return claude.digest(ref, window: window)
        case .codex:  return codex.digest(ref, window: window)
        case .agy:    return agy.digest(ref, window: window)
        case .opencode, .cursor:
            return SessionDigest(ref: ref)
        }
    }

    static func normalize(_ path: String) -> String {
        var p = (path as NSString).standardizingPath
        while p.count > 1, p.hasSuffix("/") { p.removeLast() }
        return p
    }
}

/// 팩 생성 시점의 실제 저장소 상태. 세션 로그에는 없는 **현재** 사실이라 따로 수집한다.
///
/// 이 repo 는 bare + worktree 구조라 세션이 돌던 cwd(`.worktrees/foo`)가 이미 사라졌을 수
/// 있다. 인수자가 "어디서 이어야 하는가"를 판단하려면 이 정보가 필요하다.
public struct GitSnapshot: Sendable, Equatable {
    public var root: String
    public var branch: String
    public var head: String
    public var dirtyFiles: [String]
    /// cwd 가 실제로 존재하는지. false 면 인수자는 워크트리부터 되살려야 한다.
    public var cwdExists: Bool

    public init(root: String, branch: String, head: String, dirtyFiles: [String], cwdExists: Bool) {
        self.root = root
        self.branch = branch
        self.head = head
        self.dirtyFiles = dirtyFiles
        self.cwdExists = cwdExists
    }

    public static func capture(cwd: String) -> GitSnapshot? {
        let exists = FileManager.default.fileExists(atPath: cwd)
        guard exists else {
            return GitSnapshot(root: cwd, branch: "", head: "", dirtyFiles: [], cwdExists: false)
        }
        guard let root = git(cwd, "rev-parse", "--show-toplevel"), !root.isEmpty else { return nil }
        let branch = git(cwd, "rev-parse", "--abbrev-ref", "HEAD") ?? ""
        let head = git(cwd, "log", "-1", "--oneline") ?? ""
        let status = git(cwd, "status", "--porcelain") ?? ""
        let dirty = status.split(separator: "\n").map(String.init)
        return GitSnapshot(root: root, branch: branch, head: head, dirtyFiles: dirty, cwdExists: true)
    }

    /// git 은 UI 를 막는 자리에서 불린다 — 짧게 끊는다. 실패하면 팩에서 저장소 절이
    /// 빠질 뿐이라 치명적이지 않다.
    static func git(_ cwd: String, _ args: String...) -> String? {
        Shell.capture(["/usr/bin/env", "git"] + args, cwd: cwd, timeout: 5)
    }
}
