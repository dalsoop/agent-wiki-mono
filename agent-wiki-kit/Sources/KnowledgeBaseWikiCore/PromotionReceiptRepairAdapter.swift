import Foundation

public struct PromotionReceiptRepairItem: Codable, Sendable, Equatable {
    public enum DefectKind: String, Codable, Sendable {
        case missingInSource = "missing_in_source"
        case missingInTarget = "missing_in_target"
        case missingBoth = "missing_both"
    }

    public enum Status: String, Codable, Sendable {
        case dryRun = "dry_run"
        case repaired = "repaired"
        case unrepairable = "unrepairable"
    }

    public let receiptId: String?
    public let sourceObjectId: String
    public let targetObjectId: String?
    public let sourceWorldRoot: String
    public let targetWorldRoot: String
    public let defectKind: DefectKind
    public let status: Status
    public let destinationWorld: String?
    public let repairedObjectId: String?
    public let detail: String

    public init(
        receiptId: String?,
        sourceObjectId: String,
        targetObjectId: String?,
        sourceWorldRoot: String,
        targetWorldRoot: String,
        defectKind: DefectKind,
        status: Status,
        destinationWorld: String?,
        repairedObjectId: String? = nil,
        detail: String
    ) {
        self.receiptId = receiptId
        self.sourceObjectId = sourceObjectId
        self.targetObjectId = targetObjectId
        self.sourceWorldRoot = sourceWorldRoot
        self.targetWorldRoot = targetWorldRoot
        self.defectKind = defectKind
        self.status = status
        self.destinationWorld = destinationWorld
        self.repairedObjectId = repairedObjectId
        self.detail = detail
    }
}

public struct PromotionReceiptRepairReport: Codable, Sendable, Equatable {
    public let world: String
    public let isApplied: Bool
    public let items: [PromotionReceiptRepairItem]
    public let filesToCommit: [String]

    public init(world: String, isApplied: Bool, items: [PromotionReceiptRepairItem], filesToCommit: [String] = []) {
        self.world = world
        self.isApplied = isApplied
        self.items = items
        self.filesToCommit = filesToCommit
    }
}

public enum PromotionReceiptRepairService {
    public static func repair(
        store: LedgerStore,
        worldName: String,
        peerWorlds: [LedgerWorld],
        apply: Bool,
        author: String,
        cwd: String = FileManager.default.currentDirectoryPath
    ) throws -> PromotionReceiptRepairReport {
        let resolvedPeerWorlds = RepositoryWorldResolution.resolve(worlds: peerWorlds, cwd: cwd)
        let (storesByRoot, worldRootsByName) = buildStoresMap(store: store, peerWorlds: resolvedPeerWorlds)
        var items: [PromotionReceiptRepairItem] = []
        var filesToCommit: [String] = []
        var processedReceiptBodies = Set<String>()

        // 1. 단방향 누락 복구 항목 검사
        let localReceipts = store.scan().filter { $0.effectiveType == "promotion-receipt" }
        for object in localReceipts {
            guard !processedReceiptBodies.contains(object.body) else { continue }
            processedReceiptBodies.insert(object.body)
            guard let (item, committedFile) = try inspectAndRepair(
                object: object,
                storesByRoot: storesByRoot,
                worldRootsByName: worldRootsByName,
                peerWorlds: resolvedPeerWorlds,
                apply: apply,
                author: author,
                cwd: cwd
            ) else { continue }
            items.append(item)
            if let committedFile {
                filesToCommit.append(committedFile)
            }
        }

        // 2. 양쪽 모두 누락된 항목 검사
        let missingBothItems = inspectMissingBoth(
            store: store,
            localReceipts: localReceipts,
            storesByRoot: storesByRoot,
            peerWorlds: resolvedPeerWorlds,
            alreadyFound: items
        )
        items.append(contentsOf: missingBothItems)

        return PromotionReceiptRepairReport(world: worldName, isApplied: apply, items: items, filesToCommit: filesToCommit)
    }

    private static func buildStoresMap(
        store: LedgerStore,
        peerWorlds: [LedgerWorld]
    ) -> ([String: LedgerStore], [String: String]) {
        let localRoot = PromotionVerifier.canonical(store.root.path)
        var storesByRoot: [String: LedgerStore] = [localRoot: store]
        var worldRootsByName: [String: String] = [:]
        for world in peerWorlds {
            let root = PromotionVerifier.canonical(world.rootPath)
            storesByRoot[root] = LedgerStore(root: URL(fileURLWithPath: root))
            worldRootsByName[world.name] = root
        }
        return (storesByRoot, worldRootsByName)
    }

    private static func resolveSourceStore(
        receipt: PromotionReceipt,
        storesByRoot: [String: LedgerStore],
        peerWorlds: [LedgerWorld],
        cwd: String
    ) -> LedgerStore? {
        if let repoId = receipt.sourceRepoId {
            for world in peerWorlds {
                let insp = GitRepositoryInspector.inspect(worldRoot: world.rootPath)
                if insp?.repoId == repoId {
                    let root = PromotionVerifier.canonical(world.rootPath)
                    return storesByRoot[root] ?? LedgerStore(root: URL(fileURLWithPath: world.rootPath))
                }
            }
        }
        let resolvedSourceRoot: String
        if RepositoryWorldResolution.isRepositoryWorld(rootPath: receipt.sourceWorldRoot) {
            resolvedSourceRoot = RepositoryWorldResolution.resolve(
                world: LedgerWorld(name: "", rootPath: receipt.sourceWorldRoot), cwd: cwd).rootPath
        } else {
            resolvedSourceRoot = receipt.sourceWorldRoot
        }
        let sourceRoot = PromotionVerifier.canonical(resolvedSourceRoot)
        if let direct = storesByRoot[sourceRoot] { return direct }
        if let existing = PromotionVerifier.existingStore(root: sourceRoot) { return existing }
        for world in peerWorlds {
            guard receipt.sourceRepoId != nil else { continue }
            let insp = GitRepositoryInspector.inspect(worldRoot: world.rootPath)
            if insp?.repoId == receipt.sourceRepoId {
                return storesByRoot[PromotionVerifier.canonical(world.rootPath)]
                    ?? LedgerStore(root: URL(fileURLWithPath: world.rootPath))
            }
        }
        return PromotionVerifier.storeHoldingObject(receipt.sourceObjectId, in: peerWorlds)
    }

    private static func resolveTargetStore(
        receipt: PromotionReceipt,
        storesByRoot: [String: LedgerStore],
        worldRootsByName: [String: String]
    ) -> LedgerStore? {
        let targetRoot = PromotionVerifier.canonical(receipt.targetWorldRoot)
        if let direct = storesByRoot[targetRoot] { return direct }
        if let mapped = worldRootsByName[receipt.targetWorld], let store = storesByRoot[mapped] {
            return store
        }
        return PromotionVerifier.existingStore(root: targetRoot)
    }

    private static func inspectAndRepair(
        object: LedgerObject,
        storesByRoot: [String: LedgerStore],
        worldRootsByName: [String: String],
        peerWorlds: [LedgerWorld],
        apply: Bool,
        author: String,
        cwd: String
    ) throws -> (item: PromotionReceiptRepairItem, committedFile: String?)? {
        guard let receipt = PromotionReceipt.decode(body: object.body) else { return nil }
        guard let sourceStore = resolveSourceStore(
            receipt: receipt, storesByRoot: storesByRoot, peerWorlds: peerWorlds, cwd: cwd
        ) else { return nil }
        guard let targetStore = resolveTargetStore(
            receipt: receipt, storesByRoot: storesByRoot, worldRootsByName: worldRootsByName
        ) else { return nil }

        let sourceObjects = sourceStore.scan()
        let targetObjects = targetStore.scan()
        let hasSource = sourceObjects.contains { $0.effectiveType == "promotion-receipt" && $0.body == object.body }
        let hasTarget = targetObjects.contains { $0.effectiveType == "promotion-receipt" && $0.body == object.body }

        if hasTarget && !hasSource {
            return try repairMissingSource(
                object: object, receipt: receipt, sourceStore: sourceStore, apply: apply, author: author, cwd: cwd
            )
        }
        if hasSource && !hasTarget {
            return try repairMissingTarget(
                object: object, receipt: receipt, targetStore: targetStore, sourceObjects: sourceObjects, apply: apply, author: author, cwd: cwd
            )
        }
        return nil
    }

    private static func repairMissingSource(
        object: LedgerObject,
        receipt: PromotionReceipt,
        sourceStore: LedgerStore,
        apply: Bool,
        author: String,
        cwd: String
    ) throws -> (item: PromotionReceiptRepairItem, committedFile: String?) {
        let dest = receipt.sourceWorldName ?? sourceStore.root.path
        if !apply {
            return (PromotionReceiptRepairItem(
                receiptId: object.id,
                sourceObjectId: receipt.sourceObjectId,
                targetObjectId: receipt.targetObjectId,
                sourceWorldRoot: receipt.sourceWorldRoot,
                targetWorldRoot: receipt.targetWorldRoot,
                defectKind: .missingInSource,
                status: .dryRun,
                destinationWorld: dest,
                repairedObjectId: nil,
                detail: "원본 world에 영수증 누락 (dry-run, --apply로 복구 가능)"
            ), nil)
        }
        try RepositoryWorldResolution.validateWrite(rootPath: sourceStore.root.path, cwd: cwd)
        let pubAuthor = receipt.promotedBy.isEmpty ? author : receipt.promotedBy
        let published = try sourceStore.publish(
            author: pubAuthor,
            title: "프로모션 링크: \(String(receipt.sourceObjectId.prefix(12))) → \(receipt.targetWorld)",
            type: "promotion-receipt",
            body: object.body,
            now: receipt.promotedAt,
            extras: LedgerPublishExtras(cites: [
                .init(id: receipt.sourceObjectId, rel: "receipts"),
                .init(id: receipt.targetObjectId, rel: "promoted-as"),
            ]))
        let committedFile = sourceStore.objectPath(for: published)
        return (PromotionReceiptRepairItem(
            receiptId: object.id,
            sourceObjectId: receipt.sourceObjectId,
            targetObjectId: receipt.targetObjectId,
            sourceWorldRoot: receipt.sourceWorldRoot,
            targetWorldRoot: receipt.targetWorldRoot,
            defectKind: .missingInSource,
            status: .repaired,
            destinationWorld: dest,
            repairedObjectId: published.id,
            detail: "원본 world에 영수증 복제 완료"
        ), committedFile)
    }

    private static func repairMissingTarget(
        object: LedgerObject,
        receipt: PromotionReceipt,
        targetStore: LedgerStore,
        sourceObjects: [LedgerObject],
        apply: Bool,
        author: String,
        cwd: String
    ) throws -> (item: PromotionReceiptRepairItem, committedFile: String?) {
        let dest = receipt.targetWorld
        if !apply {
            return (PromotionReceiptRepairItem(
                receiptId: object.id,
                sourceObjectId: receipt.sourceObjectId,
                targetObjectId: receipt.targetObjectId,
                sourceWorldRoot: receipt.sourceWorldRoot,
                targetWorldRoot: receipt.targetWorldRoot,
                defectKind: .missingInTarget,
                status: .dryRun,
                destinationWorld: dest,
                repairedObjectId: nil,
                detail: "대상 world에 영수증 누락 (dry-run, --apply로 복구 가능)"
            ), nil)
        }
        try RepositoryWorldResolution.validateWrite(rootPath: targetStore.root.path, cwd: cwd)
        let sourceObj = sourceObjects.first(where: { $0.id == receipt.sourceObjectId })
        let title = "프로모션 영수증: \(sourceObj?.title ?? String(receipt.sourceObjectId.prefix(12)))"
        let pubAuthor = receipt.promotedBy.isEmpty ? author : receipt.promotedBy
        let published = try targetStore.publish(
            author: pubAuthor,
            title: title,
            type: "promotion-receipt",
            body: object.body,
            now: receipt.promotedAt,
            extras: LedgerPublishExtras(cites: [
                .init(id: receipt.sourceObjectId, rel: "promotes"),
                .init(id: receipt.targetObjectId, rel: "receipts"),
            ]))
        let committedFile = targetStore.objectPath(for: published)
        return (PromotionReceiptRepairItem(
            receiptId: object.id,
            sourceObjectId: receipt.sourceObjectId,
            targetObjectId: receipt.targetObjectId,
            sourceWorldRoot: receipt.sourceWorldRoot,
            targetWorldRoot: receipt.targetWorldRoot,
            defectKind: .missingInTarget,
            status: .repaired,
            destinationWorld: dest,
            repairedObjectId: published.id,
            detail: "대상 world에 영수증 복제 완료"
        ), committedFile)
    }

    private static func inspectMissingBoth(
        store: LedgerStore,
        localReceipts: [LedgerObject],
        storesByRoot: [String: LedgerStore],
        peerWorlds: [LedgerWorld],
        alreadyFound: [PromotionReceiptRepairItem]
    ) -> [PromotionReceiptRepairItem] {
        let candidateObjects = store.scan().filter { $0.effectiveType != "promotion-receipt" }
        return candidateObjects.flatMap { object in
            inspectMissingBothForObject(
                object: object,
                storePath: store.root.path,
                localReceipts: localReceipts,
                storesByRoot: storesByRoot,
                peerWorlds: peerWorlds,
                alreadyFound: alreadyFound
            )
        }
    }

    private static func inspectMissingBothForObject(
        object: LedgerObject,
        storePath: String,
        localReceipts: [LedgerObject],
        storesByRoot: [String: LedgerStore],
        peerWorlds: [LedgerWorld],
        alreadyFound: [PromotionReceiptRepairItem]
    ) -> [PromotionReceiptRepairItem] {
        let candidateCites = object.cites.filter { $0.rel == "promotes" }
        return candidateCites.compactMap { cite in
            missingBothItem(
                sourceId: cite.id,
                targetId: object.id,
                storePath: storePath,
                localReceipts: localReceipts,
                storesByRoot: storesByRoot,
                peerWorlds: peerWorlds,
                alreadyFound: alreadyFound
            )
        }
    }

    private static func missingBothItem(
        sourceId: String,
        targetId: String,
        storePath: String,
        localReceipts: [LedgerObject],
        storesByRoot: [String: LedgerStore],
        peerWorlds: [LedgerWorld],
        alreadyFound: [PromotionReceiptRepairItem]
    ) -> PromotionReceiptRepairItem? {
        guard !alreadyFound.contains(where: { $0.sourceObjectId == sourceId && $0.targetObjectId == targetId }) else {
            return nil
        }
        guard !hasMatchingReceipt(sourceId: sourceId, targetId: targetId, receipts: localReceipts) else {
            return nil
        }
        guard !hasPeerReceipt(sourceId: sourceId, targetId: targetId, storesByRoot: storesByRoot, peerWorlds: peerWorlds) else {
            return nil
        }
        return PromotionReceiptRepairItem(
            receiptId: nil,
            sourceObjectId: sourceId,
            targetObjectId: targetId,
            sourceWorldRoot: storePath,
            targetWorldRoot: storePath,
            defectKind: .missingBoth,
            status: .unrepairable,
            destinationWorld: nil,
            repairedObjectId: nil,
            detail: "양쪽 원장 모두에 영수증이 없어 복구 불가 (수동 확인 필요)"
        )
    }

    private static func hasMatchingReceipt(
        sourceId: String,
        targetId: String,
        receipts: [LedgerObject]
    ) -> Bool {
        receipts.contains { receiptObj in
            guard let r = PromotionReceipt.decode(body: receiptObj.body) else { return false }
            return r.sourceObjectId == sourceId && r.targetObjectId == targetId
        }
    }

    private static func hasPeerReceipt(
        sourceId: String,
        targetId: String,
        storesByRoot: [String: LedgerStore],
        peerWorlds: [LedgerWorld]
    ) -> Bool {
        for peer in peerWorlds {
            let pStore = storesByRoot[PromotionVerifier.canonical(peer.rootPath)]
                ?? LedgerStore(root: URL(fileURLWithPath: peer.rootPath))
            if hasMatchingReceipt(sourceId: sourceId, targetId: targetId, receipts: pStore.scan()) {
                return true
            }
        }
        return false
    }
}
