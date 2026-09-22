import Foundation
import KnowledgeBaseWikiCore
import LocalizationKit

public struct WorldAwarePublishCopy: Sendable {
    public var needBody: String
    public var missingRef: @Sendable (String) -> String
    public var unknownOption: @Sendable (String) -> String
    public var missingCite: @Sendable (String) -> String

    public init(
        needBody: String,
        missingRef: @escaping @Sendable (String) -> String,
        unknownOption: @escaping @Sendable (String) -> String,
        missingCite: @escaping @Sendable (String) -> String
    ) {
        self.needBody = needBody
        self.missingRef = missingRef
        self.unknownOption = unknownOption
        self.missingCite = missingCite
    }

    public static let koreanHardcoded = WorldAwarePublishCopy(
        needBody: "stdin 으로 본문을 주세요 (철회 발행만 본문 생략 가능)",
        missingRef: { "없는 객체 참조: \($0)" },
        unknownOption: { "모르는 옵션: \($0)" },
        missingCite: { "없는 객체 참조: \($0)" })

    public static func fromLocalization() -> WorldAwarePublishCopy {
        WorldAwarePublishCopy(
            needBody: CLILocalization.string("CommandPublish.needBody"),
            missingRef: { CLILocalization.format("CommandPublish.missingRef", $0) },
            unknownOption: { CLILocalization.format("CommandWorld.unknownOption", $0) },
            missingCite: { "없는 객체 참조: \($0)" })
    }
}

public func objectsByWorld(catalog: WorldBindingCatalog) -> [String: Set<String>] {
    var map: [String: Set<String>] = [:]
    for world in catalog.worlds {
        let store = LedgerStore(root: URL(fileURLWithPath: world.rootPath))
        map[world.name] = Set(store.scan().map(\.id))
    }
    return map
}

public func enforceCiteGate(
    currentWorld: String,
    arguments: [String],
    catalog: WorldBindingCatalog,
    missingCite: (String) -> String = { "없는 객체 참조: \($0)" }
) {
    let ids = WorldPublishCiteIDs.extract(from: arguments)
    guard !ids.isEmpty else { return }
    let located = objectsByWorld(catalog: catalog)
    for id in ids {
        guard let citedWorld = WorldCiteGate.locateWorld(containing: id, objectsByWorld: located) else {
            fail(missingCite(id))
        }
        if let denial = WorldCiteGate.evaluate(
            currentWorld: currentWorld,
            citedID: id,
            citedWorld: citedWorld,
            catalog: catalog)
        {
            fail(denial.message)
        }
    }
}

public func scopedObjectIDs(currentWorld: String, catalog: WorldBindingCatalog) -> Set<String> {
    let scope = WorldSearchScope.names(current: currentWorld, catalog: catalog)
    var ids: Set<String> = []
    for world in catalog.worlds where scope.contains(world.name) {
        let store = LedgerStore(root: URL(fileURLWithPath: world.rootPath))
        ids.formUnion(store.scan().map(\.id))
    }
    return ids
}

public func runWorldAwarePublish(
    store: LedgerStore,
    worldName: String,
    author: String,
    arguments: [String],
    catalog: WorldBindingCatalog,
    copy: WorldAwarePublishCopy = .fromLocalization()
) {
    enforceCiteGate(
        currentWorld: worldName, arguments: arguments, catalog: catalog, missingCite: copy.missingCite)
    let cites = WorldPublishCiteIDs.extract(from: arguments)
    let currentIDs = Set(store.scan().map(\.id))
    let needsScopedLookup = cites.contains { !currentIDs.contains($0) }
    if !needsScopedLookup {
        runPublish(store: store, author: author, arguments: arguments)
        return
    }
    runScopedPublish(
        store: store, worldName: worldName, catalog: catalog, author: author,
        arguments: arguments, copy: copy)
}

private func applyScopedSceneEvidenceLink(
    fields: inout WorldScopedPublishFields,
    body: inout String,
    store: LedgerStore
) {
    guard fields.typeField == PublishCompleteness.sceneEvidenceType || fields.ofDecision != nil else { return }
    guard let decisionID = fields.ofDecision else {
        fail("scene-evidence 발행에는 --of <decision-id> 가 필요합니다")
    }
    if fields.typeField == nil { fields.typeField = PublishCompleteness.sceneEvidenceType }
    guard fields.typeField == PublishCompleteness.sceneEvidenceType else {
        fail("--of 는 --kind scene-evidence 발행 전용입니다 (지금 type: \(fields.typeField ?? "없음"))")
    }
    switch PublishCompleteness.sceneEvidenceLink(of: decisionID, objects: store.scan()) {
    case .success(let cite):
        if !fields.cites.contains(cite) { fields.cites.append(cite) }
        body = PublishCompleteness.sceneEvidenceBody(of: decisionID, body: body)
    case .failure(let failure):
        fail(failure.message)
    }
    if let failure = PublishCompleteness.validateSceneEvidence(cites: fields.cites) {
        fail(failure.message)
    }
}

private func runScopedPublish(
    store: LedgerStore,
    worldName: String,
    catalog: WorldBindingCatalog,
    author: String,
    arguments: [String],
    copy: WorldAwarePublishCopy
) {
    var fields = WorldScopedPublishArgs.parse(arguments)
    if let unknown = fields.unknownOption {
        fail(copy.unknownOption(unknown))
    }
    var body = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || fields.retracts != nil else {
        fail(copy.needBody)
    }
    applyScopedSceneEvidenceLink(fields: &fields, body: &body, store: store)
    let allowed = scopedObjectIDs(currentWorld: worldName, catalog: catalog)
    for ref in ([fields.supersedes, fields.retracts].compactMap { $0 } + fields.cites.map(\.id))
    where !allowed.contains(ref) {
        fail(copy.missingRef(ref))
    }
    do {
        let object = try store.publish(
            author: author,
            title: fields.title,
            type: fields.typeField,
            body: body,
            extras: LedgerPublishExtras(
                cites: fields.cites,
                observes: fields.observes,
                supersedes: fields.supersedes,
                retracts: fields.retracts,
                origin: fields.origin,
                tags: fields.tags + fields.aliases.map { "alias:" + $0 }))
        syncIndexAfterWrite(store)
        print(object.id) // allow:debug
    } catch {
        fail("\(error)")
    }
}
