import CitationLedgerKit
import Foundation
import KnowledgeBaseWikiCore
import SelfTestKit
import LocalizationKit
import CommandKit

func runWorld(arguments: [String]) {
    var config = LedgerConfig.load()
    switch arguments.count >= 2 ? arguments[1] : "list" {
    case "list":
        let items = WikiWorldPresentation.listItems(
            worlds: config.effectiveWorlds,
            selectedName: config.current?.name
        )
        if arguments.contains("--json") {
            printJSON(items)
        } else if items.isEmpty {
            print(CLILocalization.string("CommandWorld.print"))
        } else {
            print(WikiWorldPresentation.plainText(items: items))
        }
    case "use":
        guard arguments.count >= 3 else { fail(usage) }
        guard config.effectiveWorlds.contains(where: { $0.name == arguments[2] }) else {
            fail("없는 세계관: \(arguments[2])")
        }
        config.worlds = config.effectiveWorlds
        config.currentWorld = arguments[2]
        try? config.save()
        print(CLILocalization.format("CommandWorld.print-2", arguments[2]))
    case "add":
        guard arguments.count >= 4, !arguments[2].hasPrefix("--"), !arguments[3].hasPrefix("--")
        else { fail(usage) }
        let path = (arguments[3] as NSString).expandingTildeInPath
        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path).appendingPathComponent("objects"),
                withIntermediateDirectories: true)
        } catch {
            fail("objects 디렉터리 생성 실패: \(error.localizedDescription)")
        }
        // `--display <이름>` — 사람용 표시 이름. 없으면 slug 그대로(기존 재등록은 기존 값 유지).
        let display: String? = {
            guard let index = arguments.firstIndex(of: "--display"), arguments.count > index + 1
            else { return nil }
            return arguments[index + 1]
        }()
        var worlds = config.effectiveWorlds
        let previousDisplay = worlds.first { $0.name == arguments[2] }?.display
        worlds.removeAll { $0.name == arguments[2] }
        worlds.append(LedgerWorld(name: arguments[2], rootPath: path, display: display ?? previousDisplay))
        config.worlds = worlds
        try? config.save()
        print(CLILocalization.format("CommandWorld.print-3", arguments[2], path))
    case "rm":
        // `add` 의 짝 — closing-door 규칙이 잡은 형태(쌓는 문만 있고 닫는 문이 없음).
        // 실측 2026-08-11: world add test-personal 이 오염됐는데 되돌릴 CLI 가 없어
        // ~/.memo-citation-ledger/config.json 을 손으로 고쳤다.
        // 디렉터리(객체·블롭)는 **건드리지 않는다** — world 정의만 config 에서 뺀다.
        // 객체를 지워야 하면 직접 rm -rf. current 였으면 gujo-wiki 로 돌아간다.
        guard arguments.count >= 3 else { fail(usage) }
        let name = arguments[2]
        var worlds = config.effectiveWorlds
        let before = worlds.count
        worlds.removeAll { $0.name == name }
        guard worlds.count < before else { fail("없는 세계관: \(name)") }
        config.worlds = worlds
        if config.current?.name == name {
            config.currentWorld = config.effectiveWorlds.first(where: {
                $0.name == "gujo-wiki"
            })?.name ?? config.effectiveWorlds.first?.name
        }
        try? config.save()
        let cur = config.current?.name ?? "없음"
        print(CLILocalization.format("CommandWorld.print-4", name, cur))
    case "init-repo":
        // repo 안에 `.wiki/` 원장을 만든다 = 그 repo(GitLab 프로젝트)의 world.
        // 접근권한은 그 repo 멤버십이 집행(앱은 auth 0). objects/ 만 커밋, state·blobs 는 파생물이라 gitignore.
        // 대상 결정 (변수 함정 주의):
        //   init-repo <경로>   → 그 경로 (모노레포에서 앱별 .wiki: `init-repo apps/foo`)
        //   init-repo --here   → 현재 디렉터리 (앱 안에서 그 앱의 .wiki)
        //   init-repo          → repoRoot(.git 위로 탐색) = repo 루트 .wiki
        // 경로는 항상 **절대경로로 저장**한다 — world 설정이 cwd 바뀌어도 유효하도록.
        let fm = FileManager.default
        let explicitPath = arguments.dropFirst(2).first { !$0.hasPrefix("--") }
        let rawBase: String
        if arguments.contains("--here") {
            rawBase = fm.currentDirectoryPath
        } else if let explicitPath {
            rawBase = (explicitPath as NSString).expandingTildeInPath
        } else {
            rawBase = repoRoot(from: fm.currentDirectoryPath) ?? fm.currentDirectoryPath
        }
        let base = URL(fileURLWithPath: rawBase).standardizedFileURL.path
        let wiki = (base as NSString).appendingPathComponent(".wiki")
        do {
            try fm.createDirectory(atPath: (wiki as NSString).appendingPathComponent("objects"),
                                   withIntermediateDirectories: true)
            let gitignore = (wiki as NSString).appendingPathComponent(".gitignore")
            if !fm.fileExists(atPath: gitignore) {
                try "# 파생물(재생성 가능) — objects/ 만 커밋한다\nstate/\nblobs/\nindex.db\n"
                    .write(toFile: gitignore, atomically: true, encoding: .utf8)
            }
            // authors.json 스캐폴드 — 커미터 email → actor 바인딩(author 검증용, verify 가 대조).
            // 현재 git user.email 을 신원 SSOT(CitationActor)로 매핑해 미리 채운다. 이미 있으면 안 건드림.
            // **상속**: 상위 .wiki(예: repo 루트)에 authors.json 이 있으면 앱별로 중복 생성하지 않는다
            // — 모노레포에서 루트 한 곳만 두고 모든 앱 .wiki 가 물려받게(변수 한 곳 관리).
            let authorsPath = (wiki as NSString).appendingPathComponent("authors.json")
            if fm.fileExists(atPath: authorsPath) {
                // 이미 있음 — 안 건드림
            } else if AuthorAudit.resolveAuthorsMap(from: URL(fileURLWithPath: wiki)) != nil {
                print(CLILocalization.string("CommandWorld.print-5"))
            } else {
                let email = gitConfigEmail(cwd: base)
                let actor = CitationActor.resolve()
                let map: [String: String] = email.isEmpty ? [:] : [email: actor]
                let data = try JSONSerialization.data(
                    withJSONObject: map, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: URL(fileURLWithPath: authorsPath))
                let hint = email.isEmpty
                    ? "(git user.email 없음 — 커미터→actor 매핑을 직접 채워라)"
                    : "\(email) → \(actor)  (다른 커미터가 있으면 추가하라)"
                print(CLILocalization.format("CommandWorld.print-6", hint))
            }
        } catch { fail("\(error)") }
        let name = (base as NSString).lastPathComponent
        var worlds = config.effectiveWorlds
        worlds.removeAll { $0.name == name || $0.rootPath == wiki }
        worlds.append(LedgerWorld(name: name, rootPath: wiki))
        config.worlds = worlds
        try? config.save()   // currentWorld 는 안 바꿈 — cwd 로 자동 해소되니까
        print(CLILocalization.format("CommandWorld.print-7", name, wiki))
        print(CLILocalization.string("CommandWorld.print-8"))
    case "self-test":
        SelfTestRunner.run(WorldSelfTest(), json: arguments.contains("--json") || arguments.contains("-j"))
    default: fail(usage)
    }
}

/// cwd 에서 상위로 `.git` 을 찾아 repo 루트를 반환(없으면 nil).
private func repoRoot(from start: String) -> String? {
    let fm = FileManager.default
    var dir = URL(fileURLWithPath: start).standardizedFileURL
    while true {
        if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) { return dir.path }
        let parent = dir.deletingLastPathComponent()
        if parent.path == dir.path { return nil }
        dir = parent
    }
}

/// `git config user.email` (repo 기준). 없으면 빈 문자열. 워치독으로 매달림 방지.
private func gitConfigEmail(cwd: String) -> String {
    let safeResult = SafeProcessRunner.run(
        "/usr/bin/env",
        ["git", "-C", cwd, "config", "user.email"],
        timeout: 10
    )
    return safeResult.trimmedStdout
}

func runOKFExport(store: LedgerStore, arguments: [String]) {
    guard arguments.count >= 2 else { fail(usage) }
    let outRoot = URL(fileURLWithPath: (arguments[1] as NSString).expandingTildeInPath)
    let objects = store.scan()
    do {
        print(try OKFExporter.export(objects: objects, heads: store.heads(objects), to: outRoot))
    } catch {
        fail("\(error)")
    }
}

