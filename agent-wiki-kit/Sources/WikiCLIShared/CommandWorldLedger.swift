import Foundation
import KnowledgeBaseWikiCore

// 원장 설정 — `world add <이름> --key <k> --root <경로> [--parent <이름>] [--predecessor <이름>]`,
// `world tenant-map <테넌트> <원장>`, `world device register <키>`, `world dream-device <키>`,
// `world storage [--endpoint <url>] [--bucket <b>] [--region <r>] [--credential-source bitwarden:<item id>|none]`
// (R2 주소·키 출처, 비밀 아님. 키 값은 키체인 또는 Bitwarden 항목에만. 엔드포인트 기본값 없음. 결정 0009),
// `world ai dream|arbiters|show`(드리밍 AI·중재자 후보. 모델 이름은 소스에 두지 않고 여기서만 설정).
// 규칙은 `WorldMutation.adding`·`LedgerThreeConfigMutation` 이 판정하고, 저장은 `WorldBoundIO`(BoundLedgerFile) 하나.
// 근거: docs/contracts.md "agent-law 명령 (ledger 3)", docs/business-rules.md "원장 구성".

let worldLedgerUsage = """
사용법: world add <이름> --key <k> --root <경로> [--layer <층>] [--parent <이름>] [--predecessor <이름>] [--display <이름>]
       world tenant-map <테넌트> <원장>
       world device register <키>
       world dream-device <키>
       world storage [--endpoint <url>] [--bucket <b>] [--region <r>] [--credential-source bitwarden:<item id>|none]
       world ai dream --runtime <r> --model <m> [--effort <e>]
       world ai arbiters --add <runtime>:<model>[:<effort>]... | --clear
       world ai show [--json]
"""

/// 두 CLI 의 `world` 분기가 먼저 부른다. ledger 3 원장 설정이면 처리하고 true.
public func runWorldLedgerSubcommand(file: inout BoundLedgerFile, arguments: [String]) -> Bool {
    let sub = arguments.count >= 2 ? arguments[1] : ""
    let rest = Array(arguments.dropFirst(2))
    switch sub {
    case "add":
        guard rest.contains(where: { ["--key", "--root", "--predecessor"].contains($0) }) else { return false }
        applyLedgerWorldAdd(file: &file, arguments: arguments)
    case "tenant-map":
        guard rest.count == 2 else { usageFail(worldLedgerUsage) }
        file = mutationResult(LedgerThreeConfigMutation.settingTenantMap(in: file, tenant: rest[0], world: rest[1]))
        WorldBoundIO.save(file)
        print("tenant \(rest[0]) → \(rest[1])") // allow:debug
    case "device":
        guard rest.count == 2, rest[0] == "register" else { usageFail(worldLedgerUsage) }
        file = mutationResult(LedgerThreeConfigMutation.registeringDevice(in: file, key: rest[1]))
        WorldBoundIO.save(file)
        print("device \(rest[1]) registered (this device)") // allow:debug
    case "dream-device":
        guard rest.count == 1 else { usageFail(worldLedgerUsage) }
        file = mutationResult(LedgerThreeConfigMutation.settingDreamDevice(in: file, key: rest[0]))
        WorldBoundIO.save(file)
        print("dream device \(rest[0])") // allow:debug
    case "storage":
        let options = LawOptions.parse(
            arguments, skip: 2, valued: ["--endpoint", "--bucket", "--region", "--credential-source"],
            flags: ["--json", "-j"], usage: worldLedgerUsage)
        guard options.positionals.isEmpty else { usageFail(worldLedgerUsage) }
        var settings = file.lawStorage ?? LawStorageSettings()
        if let endpoint = options.value("--endpoint") { settings.endpoint = endpoint }
        if let bucket = options.value("--bucket") { settings.bucket = bucket }
        if let region = options.value("--region") { settings.region = region }
        if let source = options.value("--credential-source") {
            switch LawR2CredentialSource.settingValue(forOption: source) {
            case .success(let reference): settings.credentialSource = reference
            case .failure(let error): usageFail("\(error)\n\(worldLedgerUsage)")
            }
        }
        file.lawStorage = settings
        WorldBoundIO.save(file)
        print("storage endpoint=\(settings.resolvedEndpoint ?? "(미설정)")  bucket=\(settings.resolvedBucket)  region=\(settings.resolvedRegion)  credentials=\(settings.resolvedCredentialSource)") // allow:debug
    case "ai":
        runWorldAI(file: &file, arguments: arguments)
    default:
        return false
    }
    return true
}

private func mutationResult(_ result: Result<BoundLedgerFile, WorldMutationFailure>) -> BoundLedgerFile {
    switch result {
    case .success(let next): return next
    case .failure(let failure): fail(failure.message)
    }
}

/// ledger 3 원장 등록. 층은 `--layer`(공유 원장은 `remoteShared`)로 기록하고, `--parent` 만 있으면 tenant(상위는 remoteShared 여야 한다).
private func applyLedgerWorldAdd(file: inout BoundLedgerFile, arguments: [String]) {
    let options = LawOptions.parse(
        arguments, skip: 2,
        valued: ["--key", "--root", "--parent", "--predecessor", "--layer", "--display"],
        flags: ["--json", "-j"], usage: worldLedgerUsage)
    guard options.positionals.count == 1 || options.positionals.count == 2 else { usageFail(worldLedgerUsage) }
    let name = options.positionals[0]
    guard let rawRoot = options.value("--root") ?? (options.positionals.count == 2 ? options.positionals[1] : nil) else {
        usageFail(worldLedgerUsage)
    }
    let root = (rawRoot as NSString).expandingTildeInPath
    let parent = options.value("--parent")
    let layer = options.value("--layer") ?? (parent != nil ? WikiWorldLayer.tenant.rawValue : nil)
    let next = mutationResult(WorldMutation.adding(
        to: file, name: name, path: root, layer: layer, parent: parent, display: options.value("--display"),
        key: options.value("--key"), predecessor: options.value("--predecessor")))
    do {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: root).appendingPathComponent("objects"), withIntermediateDirectories: true)
    } catch {
        fail("objects 디렉터리 생성 실패: \(error.localizedDescription)")
    }
    file = next
    WorldBoundIO.save(file)
    let added = WorldBindingCatalog(worlds: file.effectiveWorlds).world(named: name)
    print("world \(name)  key=\(added?.key ?? "-")  root=\(root)" // allow:debug
        + (added?.parent.map { "  parent=\($0)" } ?? "") + (added?.predecessor.map { "  predecessor=\($0)" } ?? ""))
}

/// `world ai` — 드리밍 AI(`dream`)와 중재자 후보(`court.arbiters`). 실행 도구 이름은 지원 CLI 목록으로 해석한다.
/// 설정이 없으면 `dream run` 은 안내와 함께 1, `court hear` 는 중재자 없음으로 대법원 회부.
private func runWorldAI(file: inout BoundLedgerFile, arguments: [String]) {
    let action = arguments.count >= 3 ? arguments[2] : "show"
    switch action {
    case "dream":
        let options = LawOptions.parse(
            arguments, skip: 3, valued: ["--runtime", "--model", "--effort"], flags: ["--json", "-j"],
            usage: worldLedgerUsage)
        guard options.positionals.isEmpty, let runtime = options.value("--runtime"),
              let model = options.value("--model")
        else { usageFail(worldLedgerUsage) }
        file = mutationResult(LawAIConfigMutation.settingDream(
            in: file, runtime: runtime, model: model, effort: options.value("--effort")))
        WorldBoundIO.save(file)
        print("dream ai \(file.dream?.runnerLabel ?? "-")") // allow:debug
    case "arbiters":
        let options = LawOptions.parse(
            arguments, skip: 3, valued: ["--add"], flags: ["--clear", "--json", "-j"], usage: worldLedgerUsage)
        let adds = options.all("--add")
        // `--add` 와 `--clear` 중 정확히 하나(빈 `--add` 목록 == `--clear` 있음).
        guard options.positionals.isEmpty, adds.isEmpty == options.has("--clear") else { usageFail(worldLedgerUsage) }
        file = options.has("--clear")
            ? LawAIConfigMutation.clearingArbiters(in: file)
            : mutationResult(LawAIConfigMutation.addingArbiters(in: file, specs: adds))
        WorldBoundIO.save(file)
        let list = (file.court?.resolvedArbiters ?? []).map(\.label)
        print("arbiters \(list.isEmpty ? "(없음 — 항소심은 대법원 회부)" : list.joined(separator: ", "))") // allow:debug
    case "show":
        let options = LawOptions.parse(arguments, skip: 3, valued: [], flags: ["--json", "-j"], usage: worldLedgerUsage)
        guard options.positionals.isEmpty else { usageFail(worldLedgerUsage) }
        let dream = file.dream?.ai
        let arbiters = file.court?.resolvedArbiters ?? []
        if options.has("--json") {
            struct Pick: Encodable { let runtime: String; let model: String; let effort: String? }
            struct Envelope: Encodable { let ok: Bool; let dream: Pick?; let arbiters: [Pick] }
            printJSON(Envelope(
                ok: true,
                dream: dream.map { Pick(runtime: $0.cli.rawValue, model: $0.model, effort: $0.effort) },
                arbiters: arbiters.map { Pick(runtime: $0.cli.rawValue, model: $0.model, effort: $0.effort) }))
        } else {
            print("dream     \(dream?.label ?? "(미설정) — \(LawDreamSettings.missingAIGuidance)")") // allow:debug
            print("arbiters  \(arbiters.isEmpty ? "(없음 — 항소심은 대법원 회부)" : arbiters.map(\.label).joined(separator: ", "))") // allow:debug
        }
    default:
        usageFail(worldLedgerUsage)
    }
}
