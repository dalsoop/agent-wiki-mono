import Foundation
import KnowledgeBaseWikiCore

// 원장 설정 — `world add <이름> --key <k> --root <경로> [--parent <이름>] [--predecessor <이름>]`,
// `world tenant-map <테넌트> <원장>`, `world device register <키>`, `world dream-device <키>`,
// `world storage [--endpoint <url>] [--bucket <b>] [--region <r>]`(R2 주소, 비밀 아님. 키는 키체인).
// 규칙은 `WorldMutation.adding`·`LedgerThreeConfigMutation` 이 판정하고, 저장은 `WorldBoundIO`(BoundLedgerFile) 하나.
// 근거: docs/contracts.md "agent-law 명령 (ledger 3)", docs/business-rules.md "원장 구성".

let worldLedgerUsage = """
사용법: world add <이름> --key <k> --root <경로> [--parent <이름>] [--predecessor <이름>] [--display <이름>]
       world tenant-map <테넌트> <원장>
       world device register <키>
       world dream-device <키>
       world storage [--endpoint <url>] [--bucket <b>] [--region <r>]
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
            arguments, skip: 2, valued: ["--endpoint", "--bucket", "--region"],
            flags: ["--json", "-j"], usage: worldLedgerUsage)
        guard options.positionals.isEmpty else { usageFail(worldLedgerUsage) }
        var settings = file.lawStorage ?? LawStorageSettings()
        if let endpoint = options.value("--endpoint") { settings.endpoint = endpoint }
        if let bucket = options.value("--bucket") { settings.bucket = bucket }
        if let region = options.value("--region") { settings.region = region }
        file.lawStorage = settings
        WorldBoundIO.save(file)
        print("storage endpoint=\(settings.resolvedEndpoint)  bucket=\(settings.resolvedBucket)  region=\(settings.resolvedRegion)") // allow:debug
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

/// ledger 3 원장 등록. `--parent` 가 있으면 층은 tenant(상위는 remoteShared 여야 한다).
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
