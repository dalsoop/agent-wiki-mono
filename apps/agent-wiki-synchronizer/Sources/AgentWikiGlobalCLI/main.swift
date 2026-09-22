import SingleInstanceKit
import AgentWikiGlobalCore
import CitationLedgerKit
import AgentCLIKit
import Foundation
import KnowledgeBaseWikiCore
import AppScaffoldKit
import WikiCLIShared
import LocalizationKit

SingleInstanceCLI.autoGuard()

// Cloud Apps gate
GujoManaged.exitIfNotEntitledSync()

// agent-wiki-global — global-scope Agent Wiki CLI.
// No cwd auto-detection; defaults to gujo-wiki world.

var arguments = Array(CommandLine.arguments.dropFirst())
let defaultAuthor = ProcessInfo.processInfo.environment["MEMO_LEDGER_AUTHOR"] ?? CitationActor.resolve()
let peeled = CLIArgv.peelLeadingGlobals(arguments, defaultAuthor: defaultAuthor)
var author = peeled.author
let worldOverride = peeled.world
arguments = peeled.rest

guard let command = arguments.first else { fail(usage) }

// Option validation
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
    print(usage)
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
if command == "schedule" { runSchedule(arguments: arguments); exit(0) }
if command == "init" { runInit(arguments: arguments) }
if command == "world" || command == "worlds" { runWorld(arguments: arguments); exit(0) }

// multi-root control plane before single-world store open
if command == "gujo" { runGujo(arguments: arguments); exit(0) }
if command == "fleet" { runFleet(arguments: arguments); exit(0) }
if command == "pull" { runPull(arguments: arguments); exit(0) }
if command == "weight" { runWeight(arguments: arguments); exit(0) }

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

// World resolution: --world flag, default to gujo-wiki (NO cwd auto-detection)
let config = LedgerConfig.load()
let tenantWorld = TenantWikiBinding.activeWorldName()
guard let world = config.resolveWorld(
    cwd: cwd,
    explicitWorld: worldOverride ?? "gujo-wiki",
    tenantWikiWorld: tenantWorld
) else {
    fail(
        CLILocalization.string("main.string")
    )
}
let root = URL(fileURLWithPath: world.rootPath)
let store = LedgerStore(root: root)
let repository = RepositoryContext.resolve(cwd: cwd, world: world)?.identity


func runAgentCLI(_ cliArgs: [String]) -> Never {
    let workspaceRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let app = AgentCLIApp(
        slug: "agent-wiki-global",
        workspaceRoot: workspaceRoot,
        domainContext: { "agent-wiki-global app" }
    )
    let cli = AgentCLICommand(app: app)
    let exitCode = cli.runSync(cliArgs) ?? 64
    exit(exitCode)
}


switch command {
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
        catalog: loadWorldCatalog(),
        copy: .fromLocalization())
case "promotion", "promote":
    runPromotion(
        store: store,
        repository: repository,
        worldName: world.name,
        config: config,
        author: author,
        arguments: arguments,
        worldOverride: worldOverride)
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
        catalog: loadWorldCatalog(),
        copy: .fromLocalization(
            untitledKey: "CommandPull.untitled",
            searchEmptyKey: "CommandSearch.empty",
            contextEmptyKey: "CommandSearch.none"))
case "path": runPath(store: store, arguments: arguments)
case "history": runHistory(store: store, arguments: arguments)
case "cited-by": runCitedBy(store: store, arguments: arguments)
case "rollback": runRollback(store: store, author: author, arguments: arguments)
case "policy": runPolicy(store: store, author: author, arguments: arguments)
case "structure": runStructure(store: store, arguments: arguments)
case "verify": runVerify(store: store, worlds: config.effectiveWorlds, repository: repository)
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
case "run", "sync", "evolve", "role":
    runAgentCommand(store: store, root: root, author: author, arguments: ["agent", command] + Array(arguments.dropFirst()))
    exit(0)
case "migrate": runMigrate(store: store, arguments: arguments)
case "checkpoint": runCheckpoint(store: store, author: author)
case "okf-export": runOKFExport(store: store, arguments: arguments)
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
default: fail(usage)
}
