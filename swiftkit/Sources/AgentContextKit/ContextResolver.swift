import Foundation
import AgentSessionKit
import StateRootKit

/// 세션의 `cwd` 만으로 **어떤 지침 md 가 주입됐는지**를 탐색 규칙으로 재구성한다.
///
/// 이게 훅 없이 가는 근거다. 세 런타임의 md 탐색은 전부 결정적이라, 세션 로그에 남는
/// `cwd` 하나면 파일 **목록**은 과거 세션까지 100% 복원된다. 복원 안 되는 건 그 시점의
/// **내용**뿐이고, 그건 `SnapshotStore` 가 따로 맡는다.
///
/// 재구성이지 관측이 아니다 — 결과는 항상 `reconstructed*` provenance 로 나간다.
/// 유일한 예외가 Codex 로, 주입 원문이 로그에 있어 `InjectionEvidence` 가 덮어쓴다.
public struct ContextResolver: Sendable {
    /// 홈 디렉터리. 테스트가 가짜 홈을 주입한다.
    public let home: String
    /// 탐색을 멈출 상한 디렉터리들. 기본은 홈과 루트.
    private let stopDirs: Set<String>

    public init(home: String = StateRootKit.root) {
        self.home = home
        self.stopDirs = ["/"]
    }

    /// 런타임별 규칙 묶음.
    struct Rules {
        /// 홈에 있는 전역 지침 파일(있는 것만).
        let globals: [String]
        /// 디렉터리마다 찾을 파일 이름. 배열 순서가 곧 우선순위.
        let perDirNames: [String]
        /// 주입본을 로그에서 관측할 수 있는 런타임인가.
        let injectionObservable: Bool
    }

    /// 이 맥에 그 런타임이 설치돼 있나 — 홈에 자기 디렉터리를 만들었는지로 본다.
    ///
    /// 제품으로 남의 맥에서 도는 이상, 없는 런타임을 있는 것처럼 다루면 안 된다.
    /// Codex·Grok 이 없는 맥에서 `~/.codex/AGENTS.md` 를 찾아 헛돌거나, 더 나쁘게는
    /// "주입 지침 0건" 을 사실처럼 보고하게 된다.
    public func isInstalled(_ tool: AgentTool, fm: FileManager = .default) -> Bool {
        var isDir: ObjCBool = false
        // Antigravity 는 `~/.agy` 가 아니라 Gemini 계열 경로에 데이터를 둔다.
        let dir = tool == .agy ? home + "/.gemini/antigravity-cli"
                               : home + "/." + tool.rawValue
        return fm.fileExists(atPath: dir, isDirectory: &isDir) && isDir.boolValue
    }

    /// 이 맥에서 실제로 쓰이는 런타임만.
    public func installedTools(fm: FileManager = .default) -> Set<AgentTool> {
        Set(AgentTool.allCases.filter { isInstalled($0, fm: fm) })
    }

    func rules(for tool: AgentTool) -> Rules {
        switch tool {
        case .claude:
            // 전역 CLAUDE.md + cwd 상향 CLAUDE.md 체인. `.claude/CLAUDE.md` 도 프로젝트 층으로 친다.
            // 주입본은 세션 jsonl 에 남지 않는다(2026-08-04 전수 확인) → observable=false.
            return Rules(
                globals: [home + "/.claude/CLAUDE.md"],
                perDirNames: ["CLAUDE.md", "CLAUDE.local.md", ".claude/CLAUDE.md"],
                injectionObservable: false
            )
        case .codex:
            // 전역 ~/.codex/AGENTS.md + repo/하위 AGENTS.md. override 는 완전 대체라 같은 층에서 함께 잡고
            // 표시만 구분한다(대체 판정까지 하면 이 앱이 Codex 정책을 복제하게 된다).
            return Rules(
                globals: [home + "/.codex/AGENTS.md"],
                perDirNames: ["AGENTS.override.md", "AGENTS.md"],
                injectionObservable: true
            )
        case .grok:
            return Rules(
                globals: [home + "/.grok/AGENTS.md", home + "/.codex/AGENTS.md"],
                perDirNames: ["AGENTS.override.md", "AGENTS.md"],
                injectionObservable: false
            )
        case .agy:
            // Antigravity 는 Gemini 계열이라 GEMINI.md 규약을 따른다. 주입본이 전사본
            // blob 에 어떻게 남는지 아직 전수 확인 전이라 observable=false 로 둔다.
            return Rules(
                globals: [home + "/.gemini/GEMINI.md", home + "/.gemini/AGENTS.md"],
                perDirNames: ["AGENTS.md", "GEMINI.md"],
                injectionObservable: false
            )
        case .opencode:
            return Rules(
                globals: [home + "/.opencode/AGENTS.md"],
                perDirNames: ["AGENTS.md"],
                injectionObservable: false
            )
        case .cursor:
            return Rules(
                globals: [home + "/.cursor/AGENTS.md"],
                perDirNames: ["AGENTS.md"],
                injectionObservable: false
            )
        }
    }

    public func injectionObservable(_ tool: AgentTool) -> Bool { rules(for: tool).injectionObservable }

    /// `cwd` 에서 주입 스택을 재구성한다. 반환 순서 = 로드 순서(전역 → 상위 → cwd → memory).
    public func resolve(tool: AgentTool, cwd: String, fm: FileManager = .default) -> [InjectedDoc] {
        let r = rules(for: tool)
        var out: [InjectedDoc] = []
        var seen = Set<String>()

        func add(_ path: String, layer: String, importedBy: String? = nil) {
            let norm = (path as NSString).standardizingPath
            guard !seen.contains(norm) else { return }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: norm, isDirectory: &isDir), !isDir.boolValue else { return }
            seen.insert(norm)
            // attributesOfItem / resourceValues 는 xattr·FileProvider 경로를 탈 수 있어
            // 동기화 볼륨에서 getxattr 에 수십 초 멈춘다. 크기는 lstat 만.
            let bytes = Self.byteSize(norm)
            let text: String?
            do {
                text = try String(contentsOfFile: norm, encoding: .utf8)
            } catch {
                text = nil
            }
            out.append(InjectedDoc(
                path: norm, layer: layer, provenance: .reconstructedCurrent,
                bytes: bytes, approxTokens: text.map(TokenEstimate.approxTokens),
                importedBy: importedBy
            ))
            // `@import` 는 트랜스클루전이라 주입 스택의 일부다. 한 단계만 따라간다 —
            // 무한 재귀 방지가 목적이 아니라(seen 이 막는다) 깊은 체인은 md-lineage 의 일이라서다.
            if let text, importedBy == nil {
                for imp in MarkdownImports.paths(in: text, relativeTo: (norm as NSString).deletingLastPathComponent) {
                    add(imp, layer: "import", importedBy: norm)
                }
            }
        }

        for g in r.globals { add(g, layer: "global") }

        // cwd 상향 체인을 루트 방향으로 모은 뒤 **뒤집어서** 얕은 곳부터 넣는다
        // (얕은 규칙이 먼저 로드되고 깊은 규칙이 이긴다 — 세 런타임 공통).
        var chain: [String] = []
        var dir = (cwd as NSString).standardizingPath
        while !dir.isEmpty, dir != "/", !stopDirs.contains(dir) {
            chain.append(dir)
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir { break }
            dir = parent
        }
        for d in chain.reversed() {
            let layer = (d == (cwd as NSString).standardizingPath) ? "dir" : "ancestor"
            for name in r.perDirNames { add(d + "/" + name, layer: layer) }
        }

        // Claude auto-memory 는 프로젝트 슬러그 기준으로 매 세션 주입된다.
        if tool == .claude, let dir = ClaudeProjectSlug.resolveMemoryDir(forCwd: cwd, home: home, fm: fm) {
            add(dir + "/MEMORY.md", layer: "memory")
            // MEMORY.md 는 색인일 뿐이고 개별 메모도 같이 회수된다. 색인만 세면
            // 실제 주입량이 과소평가된다.
            for name in (try? fm.contentsOfDirectory(atPath: dir))?.sorted() ?? []
            where name.hasSuffix(".md") && name != "MEMORY.md" {
                add(dir + "/" + name, layer: "memory")
            }
        }
        return out
    }

    /// 표준 cwd 상향 walk 에 **안 걸리지만** 레포 정본으로 보이는 지침.
    ///
    /// bare + worktree mono 실측: 세션 cwd 가 `…/swift-app-mono/.bare` 이면 상향 체인은
    /// `.bare` → `swift-app-mono` → … 이고, 정본 `main/CLAUDE.md` 는 **sibling worktree**
    /// 라서 walk 에 안 잡힌다. Claude 규칙상 sibling 은 주입 대상이 아니므로 이 목록은
    /// "머리에 있다"가 아니라 **"머리에 없을 수 있는 레포 정본(사각)"** 이다.
    public func injectBlindSpots(
        tool: AgentTool, cwd: String, already: Set<String> = [], fm: FileManager = .default
    ) -> [InjectedDoc] {
        guard tool == .claude else { return [] }
        let normCwd = (cwd as NSString).standardizingPath
        guard (normCwd as NSString).lastPathComponent == ".bare" else { return [] }

        var out: [InjectedDoc] = []
        let candidates = [
            // sibling main worktree (이 모노의 정본 지침 위치)
            (normCwd as NSString).deletingLastPathComponent + "/main/CLAUDE.md",
            (normCwd as NSString).deletingLastPathComponent + "/main/AGENTS.md",
        ]
        for path in candidates {
            let norm = (path as NSString).standardizingPath
            guard !already.contains(norm) else { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: norm, isDirectory: &isDir), !isDir.boolValue else { continue }
            let bytes = Self.byteSize(norm)
            let text: String?
            do {
                text = try String(contentsOfFile: norm, encoding: .utf8)
            } catch {
                text = nil
            }
            out.append(InjectedDoc(
                path: norm,
                layer: "worktree-main",
                provenance: .reconstructedCurrent,
                bytes: bytes,
                approxTokens: text.map(TokenEstimate.approxTokens),
                importedBy: nil,
                missing: false
            ))
        }
        return out
    }

    /// xattr 없이 파일 크기만. GUI 가 `attributesOfItem` getxattr 에 고착되던 경로.
    private static func byteSize(_ path: String) -> Int? {
        var st = stat()
        let ok = path.withCString { lstat($0, &st) == 0 }
        guard ok, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        return Int(st.st_size)
    }
}

/// Claude Code 가 프로젝트 상태를 저장할 때 쓰는 경로 슬러그.
///
/// 규칙: 절대경로에서 `[A-Za-z0-9-]` 가 아닌 문자를 전부 `-` 로 바꾼다. 그래서 `.bare` 로
/// 끝나는 bare 레포는 `…-mono--bare` 처럼 대시가 겹치고, 한글 경로는 통째로 대시가 된다
/// (`-Users-jeonghan-Documents-WORK-------------` 실측 확인).
public enum ClaudeProjectSlug {
    public static func slug(_ absPath: String) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-")
        return String((absPath as NSString).standardizingPath.map { allowed.contains($0) ? $0 : "-" })
    }

    public static func projectDir(forCwd cwd: String, home: String = StateRootKit.root) -> String {
        home + "/.claude/projects/" + slug(cwd)
    }

    public static func memoryDir(forCwd cwd: String, home: String = StateRootKit.root) -> String {
        projectDir(forCwd: cwd, home: home) + "/memory"
    }

    /// 실재하는 memory 디렉터리를 찾는다 — cwd 부터 위로 올라가며 첫 히트.
    ///
    /// 왜 cwd 슬러그 하나로 안 되나 — Claude 는 memory 를 **cwd 가 아니라 프로젝트 루트**
    /// 기준으로 잡는다. 실측: cwd 가 `…/swift-app-mono/.bare` 인 세션의 memory 는
    /// `…-apps-swift-app-mono/memory` 에 있다(`--bare` 슬러그에는 없다). 규칙을 추측해
    /// 박아 넣는 대신 위로 올라가며 실재를 확인한다.
    public static func resolveMemoryDir(
        forCwd cwd: String, home: String = StateRootKit.root, fm: FileManager = .default
    ) -> String? {
        var dir = (cwd as NSString).standardizingPath
        while !dir.isEmpty, dir != "/" {
            let candidate = memoryDir(forCwd: dir, home: home)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue { return candidate }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir { break }
            dir = parent
        }
        return nil
    }
}

/// 마크다운 트랜스클루전(`@path/to/file.md`) 추출.
///
/// Claude Code·Codex 가 공유하는 문법이다. 코드펜스 안은 예시일 뿐이라 건너뛴다 —
/// 안 그러면 "이런 식으로 쓴다" 는 문서가 자기가 인용한 파일을 주입한 걸로 잡힌다.
public enum MarkdownImports {
    public static func paths(in text: String, relativeTo baseDir: String) -> [String] {
        var out: [String] = []
        var inFence = false
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") { inFence.toggle(); continue }
            if inFence { continue }
            guard line.hasPrefix("@") else { continue }
            let token = String(line.dropFirst()).components(separatedBy: .whitespaces).first ?? ""
            guard !token.isEmpty, token.hasSuffix(".md") else { continue }
            if token.hasPrefix("/") {
                out.append(token)
            } else if token.hasPrefix("~/") {
                out.append(StateRootKit.path(String(token.dropFirst(2))))
            } else {
                out.append(baseDir + "/" + token)
            }
        }
        return out
    }
}

/// 토큰 수 **추정**. 정확한 토크나이저가 아니다 — 문서 간 상대 비교와 예산 감각용이다.
///
/// 바이트/4 를 쓰지 않는 이유: 한글은 UTF-8 3바이트라 그 공식이 2배 넘게 부풀린다.
/// 문자 종류로 나눠 센다(ASCII ≈ 4자/토큰, 그 외 ≈ 1.5자/토큰).
public enum TokenEstimate {
    public static func approxTokens(_ text: String) -> Int {
        var ascii = 0
        var wide = 0
        for scalar in text.unicodeScalars {
            if scalar.isASCII { ascii += 1 } else { wide += 1 }
        }
        return Int((Double(ascii) / 4.0) + (Double(wide) / 1.5))
    }
}
