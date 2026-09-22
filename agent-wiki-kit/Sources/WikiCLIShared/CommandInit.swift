import Foundation
import KnowledgeBaseWikiCore
import LocalizationKit

/// init — 원장 스캐폴드(AGENTS.md·역할 정의) + 세계관 등록.
public func runInit(arguments: [String]) -> Never {
    guard arguments.count >= 2 else { fail(usage) }
    if CLIArgv.isHelpToken(arguments[1]) {
        print("사용법: agent-wiki init <원장 경로>")  // allow:debug — CLI 사용법 stdout
        exit(0)
    }
    let url = URL(fileURLWithPath: (arguments[1] as NSString).expandingTildeInPath)
    ensureLedgerRoot(at: url)
    writeLedgerConvention(to: url)
    let roles = bundledAgentRoleDefinitions()
    installAgentRoles(roles, under: url)
    registerWorld(root: url, roleCount: roles.count)
    exit(0)
}

/// 원장 뿌리(objects/) — append-only 규약의 물리 표준 위치.
func ensureLedgerRoot(at url: URL) {
    do {
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent("objects"), withIntermediateDirectories: true)
    } catch {
        fail("objects 디렉터리 생성 실패: \(error.localizedDescription)")
    }
}

/// 원장 규약 AGENTS.md — 어떤 러너든 읽는 표준 위치. 이미 있으면 건드리지 않는다.
func writeLedgerConvention(to url: URL) {
    let agentsMD = url.appendingPathComponent("AGENTS.md")
    guard !FileManager.default.fileExists(atPath: agentsMD.path) else { return }
    do {
        try Data("""
        # AGENTS.md — agent-wiki 원장 규약

        이 폴더는 append-only 인용 원장이다(SPEC 7조). 파일을 직접 만들거나 고치지 마라 —
        모든 발행은 `agent-wiki --as <네이름> publish ...` CLI 로만 한다.
        수정·삭제 연산은 없다: 고침 = `--supersedes`, 철회 = `--retracts`.

        ## 관계 어휘 (Argdown 표준)
        - `supports` 재현/동일 취지 — 대상의 지지도가 오르고 신선도가 리셋된다
        - `contradicts` 반박 — 지우지 않고 나란히 남는다
        - `undercuts` 논증 자체의 결함 지적

        ## 도메인
        - 지식/사실: 근거는 반드시 `--origin <url>` 을 단다. 반감기 90일.
        - 창작(소설 등): 설정이 근거다. 반감기 365일 — 낡음은 오류가 아니라 "돌아볼 때" 신호.

        ## 작업 묶음
        여러 발행을 한 작업으로 묶으려면 시작 시 `batch new` 로 id 를 받고
        `MEMO_LEDGER_BATCH` 로 물려라 — 사람이 묶음째 되돌릴 수 있다.
        """.utf8).write(to: agentsMD)
    } catch {
        fail("AGENTS.md 쓰기 실패: \(error.localizedDescription)")
    }
}

/// 번들 리소스의 초기 역할 템플릿(이름, 정의) — 이름순.
func bundledAgentRoleDefinitions() -> [(String, String)] {
    (ResourceBundle.named("AgentWikiKit_WikiCLIShared").urls(
        forResourcesWithExtension: "md", subdirectory: "agents") ?? [])
        .compactMap { url -> (String, String)? in
            let text: String
            do {
                text = try String(contentsOf: url, encoding: .utf8)
            } catch {
                fail("역할 템플릿 읽기 실패(\(url.lastPathComponent)): \(error.localizedDescription)")
            }
            return (url.deletingPathExtension().lastPathComponent, text)
        }
        .sorted { $0.0 < $1.0 }
}

/// 저장소 담당 역할 — 엔진 중립 .agents/roles. 없는 것만 쓴다(멱등).
func installAgentRoles(_ roles: [(String, String)], under url: URL) {
    let fm = FileManager.default
    let agentsDir = RepositoryAgentRoleStore(
        repositoryRoot: RepositoryAgentRoleStore.repositoryRoot(forWorldRoot: url)).rolesDirectory
    do {
        try fm.createDirectory(at: agentsDir, withIntermediateDirectories: true)
    } catch {
        fail("역할 디렉터리 생성 실패: \(error.localizedDescription)")
    }
    for (name, definition) in roles {
        let defURL = agentsDir.appendingPathComponent("\(name).md")
        guard !fm.fileExists(atPath: defURL.path) else { continue }
        do {
            try Data(definition.utf8).write(to: defURL)
        } catch {
            fail("역할 정의 쓰기 실패(\(name)): \(error.localizedDescription)")
        }
    }
}

/// 세계관 등록 — config worlds 에 없으면 추가하고 current 로 지정.
func registerWorld(root url: URL, roleCount: Int) {
    do {
        var config = LedgerConfig.load()
        var worlds = config.effectiveWorlds
        if let index = worlds.firstIndex(where: { $0.rootPath == url.path }) {
            config.currentWorld = worlds[index].name
        } else {
            let name = url.lastPathComponent
            worlds.append(LedgerWorld(name: name, rootPath: url.path))
            config.currentWorld = name
        }
        config.worlds = worlds
        try config.save()
        print("원장 루트: \(url.path)  (AGENTS.md + .agents/roles 역할 \(roleCount)개)")  // allow:debug — CLI 결과 stdout
    } catch {
        fail("설정 저장 실패: \(error.localizedDescription)")
    }
}
