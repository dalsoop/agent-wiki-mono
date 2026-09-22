import SingleInstanceKit
import AgentWikiLocalCore
import CitationLedgerKit
import AgentCLIKit
import Foundation
import KnowledgeBaseWikiCore
import AppScaffoldKit
import WikiCLIShared
import LocalizationKit

SingleInstanceCLI.autoGuard()

// Cloud Apps 게이트 — GUI 의 `.gujoManaged()` 와 대칭인 CLI 진입 한 줄.
GujoManaged.exitIfNotEntitledSync()

// agent-wiki-local — repo `.wiki/` 기본. `--world` 는 조회와 테넌트 층에 쓴다.

var arguments = Array(CommandLine.arguments.dropFirst())
let defaultAuthor = ProcessInfo.processInfo.environment["MEMO_LEDGER_AUTHOR"] ?? CitationActor.resolve()
let peeled = CLIArgv.peelLeadingGlobals(arguments, defaultAuthor: defaultAuthor)
var author = peeled.author
let worldOverride = peeled.world
arguments = peeled.rest

guard let command = arguments.first else { printLocalUsage(); exit(0) }

let localUsage = """
agent-wiki-local — repo .wiki/ 전용 CLI

사용법: agent-wiki-local <command> [options]

Local-only commands:
  task              작업그래프 (new|handoff|done|list|chain|bind|verify|adapter|capsule)
  repository        저장소 요약 (summary --json)
  repository-summary  저장소 요약 (--json)
  promotion         승격 (preview|publish)
  promote           승격 (preview|publish)
  world             세계관 (list|add|set-layer)

Shared commands:
  publish           객체 발행
  classify          분류
  capture           캡처
  show              객체 보기
  list              목록
  status            상태
  search / context  검색 / 컨텍스트
  path              인용 경로
  history           이력
  cited-by          피인용
  rollback          되돌리기
  policy            정책
  structure         구조
  verify            무결성 검증
  migrate           마이그레이션
  checkpoint        체크포인트
  distill           증류
  review            리뷰
  tick              틱
  backup            백업
  index             색인
  recent / changes  최근 변경
  discuss           토론
  learn / metrics   학습 / 메트릭
  rules             규칙
  diff              차이
  blob              블롭
  event             이벤트
  graph             그래프
  batch             배치 생성
  agent             에이전트
  init              초기화
  root              원장 경로
  app               앱 제어
  install           설치
  dual-entry        이중진입 진단
  hook              작성 훅
  capabilities      상호운용 계약
  version           버전
  help              이 도움말

전역 원장(gujo-wiki 등)은 agent-wiki (Studio) 를 쓰세요.
"""

func printLocalUsage() { print(localUsage) }

// 전역 선행 검증: 허용된 옵션 어휘
let allowedOptions: Set<String> = [
    "--access-key", "--agent", "--alias", "--all", "--allow-unclassified", "--apply", "--as", "--as-agent", "--attr",
    "--authored", "--batch", "--blob", "--bucket", "--canonical-task", "--checker", "--cite",
    "--classification-reason", "--comment", "--confirm", "--count", "--dispatch", "--domain",
    "--dry", "--endpoint", "--engine", "--event", "--exclude", "--exit-code", "--file", "--fleet",
    "--git-common-dir", "--help", "--here", "--ids", "--is-inside-work-tree", "--json", "--keep-daily",
    "--keep-monthly", "--keep-weekly", "--kind", "--knowledge", "--left-right", "--level", "--limit",
    "--max", "--model", "--name", "--name-only", "--no-edit", "--object", "--observes", "--occurred",
    "--open", "--origin", "--outcome", "--output-format", "--parent", "--path", "--peer", "--porcelain",
    "--probe", "--project", "--prune", "--push", "--query", "--quiet", "--reason", "--region", "--rel",
    "--remote", "--repository-path", "--retracts", "--root", "--rule", "--runtime-task", "--score",
    "--secret-key", "--short", "--show-toplevel", "--since", "--single", "--source", "--subject", "--summary",
    "--supersedes", "--tag", "--target-world", "--text", "--title", "--to", "--type", "--layer", "--verification",
    "--version", "--w", "--weight", "--workspace", "--world", "-h", "-j", "-V",
    "--no-studio-adopt",
]
let suppliedOptions = Set(arguments.filter { $0.hasPrefix("-") && $0 != "-" })
let unknownOptions = suppliedOptions.subtracting(allowedOptions)
if !unknownOptions.isEmpty {
    let names = unknownOptions.sorted().joined(separator: ", ")
    FileHandle.standardError.write(Data("error: unknown option(s): \(names)\nRun with --help for usage.\n".utf8))
    exit(64)
}

if command == "help" || command == "--help" || command == "-h" {
    printLocalUsage()
    exit(0)
}
if command == "version" || command == "--version" {
    print(LedgerVersion.current)
    try? DualEntry.writeInstallStamp(version: LedgerVersion.current)
    exit(0)
}
if command == "dual-entry" { runDualEntry(arguments: arguments); exit(0) }
if command == "capabilities" { runCapabilities(); exit(0) }
if command == "install" { runInstall(arguments: arguments); exit(0) }
if command == "skill-install" || command == "skill-uninstall" || command == "skill-status"
    || command == "skill" || command == "skills" {
    runSkillSurface(arguments: arguments); exit(0)
}
if command == "hook" {
    AuthoringHook.run()
    exit(0)
}
if command == "init" { runInit(arguments: arguments) }
if command == "world" { runWorld(arguments: arguments); exit(0) }

// cwd 기반 .wiki/ 자동 탐지. `--world` 가 있으면 등록된 world 를 연다.
let acceptsPathOverride: Bool
switch command {
case "repository", "repository-summary", "promotion", "promote":
    acceptsPathOverride = true
default:
    acceptsPathOverride = false
}
let pathOverride: String? = {
    guard acceptsPathOverride,
          let index = arguments.firstIndex(of: "--path"), index + 1 < arguments.count
    else { return nil }
    return (arguments[index + 1] as NSString).expandingTildeInPath
}()
let cwd = pathOverride ?? FileManager.default.currentDirectoryPath
let config = LedgerConfig.load()
let world: LedgerWorld
if let worldOverride {
    guard let resolved = config.resolveWorld(
        cwd: cwd, explicitWorld: worldOverride, tenantWikiWorld: nil)
    else {
        fail("없는 세계관: \(worldOverride)")
    }
    world = resolved
} else {
    guard let resolved = config.resolveWorld(
        cwd: cwd, explicitWorld: nil, tenantWikiWorld: nil)
    else {
        fail(
            CLILocalization.string("main.string-2")
            + CLILocalization.string("main.string-3")
            + CLILocalization.string("main.string-4")
        )
    }
    world = resolved
}
let root = URL(fileURLWithPath: world.rootPath)
let store = LedgerStore(root: root)
let repository = RepositoryContext.resolve(cwd: cwd, world: world)?.identity

func runAgentCLI(_ cliArgs: [String]) -> Never {
    let workspaceRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let app = AgentCLIApp(
        slug: "agent-wiki-local",
        workspaceRoot: workspaceRoot,
        domainContext: { "agent-wiki-local app" })
    let cli = AgentCLICommand(app: app)
    let exitCode = cli.runSync(cliArgs) ?? 64
    exit(exitCode)
}

switch command {
    // Local-only commands
    case "task": runTask(store: store, author: author, repository: repository, arguments: arguments)
    case "orchestration": runTask(
        store: store,
        author: author,
        repository: repository,
        arguments: ["task"] + Array(arguments.dropFirst()))
    case "repository-summary": runRepositorySummary(
        store: store, repository: repository, worlds: config.effectiveWorlds, arguments: arguments)
    case "repository": runRepository(
        store: store, repository: repository, worlds: config.effectiveWorlds, arguments: arguments)
    case "promote", "promotion": runPromotion(
        store: store, repository: repository, world: world,
        config: config, author: author, arguments: arguments,
        worldOverride: worldOverride)

    // Agent CLI
    case "agent":
        switch arguments.dropFirst().first {
        case "run", "sync", "evolve", "role":
            runAgentCommand(store: store, root: root, author: author, arguments: arguments)
            exit(0)
        default:
            runAgentCLI(Array(CommandLine.arguments.dropFirst()))
        }
    case "chat":
        runAgentCLI(Array(CommandLine.arguments.dropFirst()))

    // Shared commands (WikiCLIShared)
    case "root": print(root.path)
    case "batch": runBatchNew(arguments: arguments)
    case "publish":
        if let denial = WorldEnvLock.denial(
            environment: ProcessInfo.processInfo.environment,
            explicitWorld: worldOverride,
            isWrite: true)
        {
            fail(denial)
        }
        runWorldAwarePublish(
            store: store,
            worldName: world.name,
            author: author,
            arguments: arguments,
            catalog: loadWorldCatalog(current: world),
            copy: .koreanHardcoded)
    case "classify": runClassify(store: store, author: author, arguments: arguments)
    case "capture": runCapture(store: store, author: author, arguments: arguments)
    case "show": runShow(store: store, arguments: arguments)
    case "list": runList(store: store, arguments: arguments)
    case "status": runStatus(store: store, worldName: world.name, arguments: arguments)
    case "search", "context":
        runScopedSearchOrContext(
            command: command,
            store: store,
            worldName: world.name,
            arguments: arguments,
            catalog: loadWorldCatalog(current: world))
    case "path": runPath(store: store, arguments: arguments)
    case "history": runHistory(store: store, arguments: arguments)
    case "cited-by": runCitedBy(store: store, arguments: arguments)
    case "rollback": runRollback(store: store, author: author, arguments: arguments)
    case "policy": runPolicy(store: store, author: author, arguments: arguments)
    case "structure": runStructure(store: store, arguments: arguments)
    case "verify": runVerify(store: store, worlds: config.effectiveWorlds, repository: repository)
    case "migrate": runMigrate(store: store, arguments: arguments)
    case "checkpoint": runCheckpoint(store: store, author: author)
    case "distill": runDistill(store: store, root: root, arguments: arguments)
    case "review": runReview(store: store, author: author, arguments: arguments)
    case "tick": runTick(store: store, root: root, author: author, arguments: arguments)
    case "backup": runBackup(arguments: arguments)
    case "index": runIndex(store: store, root: root, arguments: arguments)
    case "recent", "changes": runRecent(store: store, arguments: arguments)
    case "discuss": runDiscuss(store: store, arguments: arguments)
    case "learn", "metrics": runLearn(store: store, root: root, arguments: arguments)
    case "rules": runRules(store: store, arguments: arguments)
    case "diff": runDiff(store: store, arguments: arguments)
    case "blob": runBlob(root: root, arguments: arguments)
    case "event": runEvent(root: root, author: author, arguments: arguments)
    case "graph": runGraph(store: store, root: root, arguments: arguments)
    case "app": runAppControl(arguments: arguments)

    default: fail(localUsage)
}
