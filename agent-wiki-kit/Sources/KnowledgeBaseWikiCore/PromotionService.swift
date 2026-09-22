import CryptoKit
import Foundation

/// 승격 출처의 두 형태. repo world 는 git commit 에 정확히 봉인해 증명하고, world(개인·
/// 비repo) world 는 그 자체가 content-addressed 원장이라는 사실로 증명한다(id=sha256(본문),
/// `LedgerStore.scan()`이 그 일치를 이미 검증). 두 증명 방식은 서로 다르다 — repo 가 아닌
/// world 를 repo 인 척 `sourceRepoId`/`sourceCommit` 를 비워서 채우면 영수증이 거짓을
/// 말하게 된다. 그래서 receipt/preview 필드는 `sourceKind` 로 갈라 실제로 있는 값만 채운다.
public enum PromotionSourceEndpoint: Sendable, Equatable {
    case repository(RepositoryIdentity)
    case world(name: String)

    public var kind: String {
        switch self {
        case .repository: return "repository"
        case .world: return "world"
        }
    }
}

public struct PromotionReceipt: Codable, Sendable, Equatable {
    public static let schemaVersion = "knowledge-base-wiki.promotion-receipt.v2"

    public let schemaVersion: String
    /// "repository" | "world" — 아래 provenance 필드 중 어느 쪽이 채워지는지의 판별자.
    public let sourceKind: String
    public let sourceRepoId: String?
    public let sourceCommit: String?
    public let sourceRemote: String?
    /// world 출처(비repo)일 때의 논리 world 이름. repo 출처는 repoId 가 이미 정본이라 nil.
    public let sourceWorldName: String?
    public let sourceObjectId: String
    public let sourceWorldRoot: String
    public let targetWorld: String
    public let targetWorldRoot: String
    public let targetObjectId: String
    public let promotedAt: Date
    public let promotedBy: String

    public struct Draft: Sendable, Equatable {
        public var sourceKind: String
        public var sourceRepoId: String?
        public var sourceCommit: String?
        public var sourceRemote: String?
        public var sourceWorldName: String?
        public var sourceObjectId: String
        public var sourceWorldRoot: String
        public var targetWorld: String
        public var targetWorldRoot: String
        public var targetObjectId: String
        public var promotedAt: Date
        public var promotedBy: String

        public init(
            sourceKind: String,
            sourceRepoId: String? = nil,
            sourceCommit: String? = nil,
            sourceRemote: String? = nil,
            sourceWorldName: String? = nil,
            sourceObjectId: String,
            sourceWorldRoot: String,
            targetWorld: String,
            targetWorldRoot: String,
            targetObjectId: String,
            promotedAt: Date,
            promotedBy: String
        ) {
            self.sourceKind = sourceKind
            self.sourceRepoId = sourceRepoId
            self.sourceCommit = sourceCommit
            self.sourceRemote = sourceRemote
            self.sourceWorldName = sourceWorldName
            self.sourceObjectId = sourceObjectId
            self.sourceWorldRoot = sourceWorldRoot
            self.targetWorld = targetWorld
            self.targetWorldRoot = targetWorldRoot
            self.targetObjectId = targetObjectId
            self.promotedAt = promotedAt
            self.promotedBy = promotedBy
        }
    }

    public init(_ draft: Draft) {
        self.schemaVersion = Self.schemaVersion
        self.sourceKind = draft.sourceKind
        self.sourceRepoId = draft.sourceRepoId
        self.sourceCommit = draft.sourceCommit
        self.sourceRemote = draft.sourceRemote
        self.sourceWorldName = draft.sourceWorldName
        self.sourceObjectId = draft.sourceObjectId
        self.sourceWorldRoot = draft.sourceWorldRoot
        self.targetWorld = draft.targetWorld
        self.targetWorldRoot = draft.targetWorldRoot
        self.targetObjectId = draft.targetObjectId
        self.promotedAt = draft.promotedAt
        self.promotedBy = draft.promotedBy
    }

    /// v1 호환 디코더: sourceKind가 없으면 "repository" 기본값 사용(v1 receipt는 전부 repo 출처)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // v1 호환: sourceKind가 없으면 기본값 "repository" 사용
        self.sourceKind = (try? container.decode(String.self, forKey: .sourceKind)) ?? "repository"
        self.sourceRepoId = try container.decodeIfPresent(String.self, forKey: .sourceRepoId)
        self.sourceCommit = try container.decodeIfPresent(String.self, forKey: .sourceCommit)
        self.sourceRemote = try container.decodeIfPresent(String.self, forKey: .sourceRemote)
        self.sourceWorldName = try container.decodeIfPresent(String.self, forKey: .sourceWorldName)
        self.sourceObjectId = try container.decode(String.self, forKey: .sourceObjectId)
        self.sourceWorldRoot = try container.decode(String.self, forKey: .sourceWorldRoot)
        self.targetWorld = try container.decode(String.self, forKey: .targetWorld)
        self.targetWorldRoot = try container.decode(String.self, forKey: .targetWorldRoot)
        self.targetObjectId = try container.decode(String.self, forKey: .targetObjectId)
        self.promotedAt = try container.decode(Date.self, forKey: .promotedAt)
        self.promotedBy = try container.decode(String.self, forKey: .promotedBy)

        // v1→v2 자동 승격: schemaVersion 필드는 항상 v2로 통일
        self.schemaVersion = Self.schemaVersion
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, sourceKind, sourceRepoId, sourceCommit, sourceRemote
        case sourceWorldName, sourceObjectId, sourceWorldRoot, targetWorld
        case targetWorldRoot, targetObjectId, promotedAt, promotedBy
    }

    public func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    public static func decode(body: String) -> PromotionReceipt? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = body.data(using: .utf8),
              let receipt = try? decoder.decode(PromotionReceipt.self, from: data) else { return nil }

        // v1 또는 v2 schemaVersion 허용 (v1은 자동으로 v2로 승격됨)
        let v1 = "knowledge-base-wiki.promotion-receipt.v1"
        let v2 = "knowledge-base-wiki.promotion-receipt.v2"
        guard receipt.schemaVersion == v1 || receipt.schemaVersion == v2 else { return nil }

        return receipt
    }
}

public struct PromotionPreview: Codable, Sendable, Equatable {
    public static let schemaVersion = "knowledge-base-wiki.promotion-preview.v2"

    public let schemaVersion: String
    public let sourceKind: String
    public let sourceRepoId: String?
    public let sourceCommit: String?
    public let sourceRemote: String?
    public let sourceWorldName: String?
    public let sourceObjectId: String
    public let sourceTitle: String
    public let sourceType: String?
    public let targetWorld: String
    public let targetWorldRoot: String
    public let promotesCitation: LedgerCitationContract
    public let confirmationToken: String
    public let publishRequires: String
}

public struct LedgerCitationContract: Codable, Sendable, Equatable {
    public let id: String
    public let rel: String
}

public struct PromotionResult: Codable, Sendable, Equatable {
    public static let schemaVersion = "knowledge-base-wiki.promotion-result.v1"

    public let schemaVersion: String
    public let promotedObjectId: String
    public let targetReceiptObjectId: String
    public let sourceReceiptObjectId: String
    public let receipt: PromotionReceipt
    public let deduplicated: Bool
}

public enum PromotionSourceCommitFailure: Sendable, Equatable, CustomStringConvertible {
    case worldOutsideRepository
    case commitUnavailable
    case objectMissing
    case malformedObject
    case contentMismatch

    public var description: String {
        switch self {
        case .worldOutsideRepository:
            return "선택한 원장 world가 repository checkout 밖에 있습니다"
        case .commitUnavailable:
            return "sourceCommit을 이 저장소에서 찾을 수 없습니다"
        case .objectMissing:
            return "sourceCommit에 원장 객체가 없습니다 — .wiki/objects를 먼저 커밋하세요"
        case .malformedObject:
            return "sourceCommit의 원장 객체가 손상되어 내용을 증명할 수 없습니다"
        case .contentMismatch:
            return "현재 원장 객체와 sourceCommit의 객체 내용이 다릅니다 — 정확한 commit을 다시 선택하세요"
        }
    }
}

public enum PromotionError: Error, CustomStringConvertible, Equatable {
    case sourceNotFound(String)
    case sourceIsReceipt
    case sourceNotAtCommit(PromotionSourceCommitFailure)
    case sourceWorldNameRequired
    case sameWorld
    case confirmationMismatch
    case malformedReceipt

    public var description: String {
        switch self {
        case .sourceNotFound(let id): return "프로모션 원본 객체를 찾을 수 없음: \(id)"
        case .sourceIsReceipt: return "프로모션 영수증 자체는 다시 프로모션할 수 없음"
        case .sourceNotAtCommit(let reason):
            return "프로모션 원본의 exact sourceCommit provenance 검증 실패: \(reason)"
        case .sourceWorldNameRequired:
            return "repo가 아닌 world에서 승격하려면 sourceWorldName이 필요함"
        case .sameWorld: return "repo 원장과 공유 원장은 서로 달라야 함"
        case .confirmationMismatch: return "preview 확인 토큰 불일치 — preview를 다시 실행하세요"
        case .malformedReceipt: return "프로모션 영수증 JSON 생성 실패"
        }
    }
}

public struct PromotionPublishRequest: Sendable {
    public var sourceStore: LedgerStore
    public var targetStore: LedgerStore
    public var source: LedgerObject
    public var repository: RepositoryIdentity? = nil
    public var sourceWorldName: String? = nil
    public var targetWorld: LedgerWorld
    public var promotedBy: String
    public var confirmationToken: String
    public var now: Date = Date()

    public init(
        sourceStore: LedgerStore,
        targetStore: LedgerStore,
        source: LedgerObject,
        repository: RepositoryIdentity? = nil,
        sourceWorldName: String? = nil,
        targetWorld: LedgerWorld,
        promotedBy: String,
        confirmationToken: String,
        now: Date = Date()
    ) {
        self.sourceStore = sourceStore
        self.targetStore = targetStore
        self.source = source
        self.repository = repository
        self.sourceWorldName = sourceWorldName
        self.targetWorld = targetWorld
        self.promotedBy = promotedBy
        self.confirmationToken = confirmationToken
        self.now = now
    }
}

/// Explicit preview -> confirmed publish. All writes use LedgerStore.publish, preserving
/// append-only/content-addressed ledger semantics.
///
/// `repository`/`sourceWorldName` 는 상호배타적인 한 값을 실어 나르는 두 개의 옵셔널
/// 파라미터다 — 진짜 대안은 `PromotionSourceEndpoint` 이지만, 기존 repo 호출부
/// (`repository: identity`, non-optional)를 한 글자도 안 건드리고 얹기 위해 이 형태를
/// 유지한다. `repository`가 있으면 그걸 쓰고, 없으면 `sourceWorldName`을 요구한다.
public enum PromotionService {
    public static func preview(
        sourceStore: LedgerStore,
        source: LedgerObject,
        repository: RepositoryIdentity?,
        sourceWorldName: String? = nil,
        targetWorld: LedgerWorld,
        promotedBy: String
    ) throws -> PromotionPreview {
        let endpoint = try resolveEndpoint(repository: repository, sourceWorldName: sourceWorldName)
        try validateSource(sourceStore: sourceStore, source: source, endpoint: endpoint)
        let targetRoot = URL(fileURLWithPath: targetWorld.rootPath).standardizedFileURL.path
        let (repoId, commit, remote, worldName) = fields(of: endpoint)
        let tuple = [
            PromotionPreview.schemaVersion,
            endpoint.kind,
            repoId ?? "", commit ?? "", remote ?? "", worldName ?? "",
            source.id,
            targetWorld.name,
            targetRoot,
            promotedBy,
        ].joined(separator: "\n")
        let token = SHA256.hash(data: Data(tuple.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return PromotionPreview(
            schemaVersion: PromotionPreview.schemaVersion,
            sourceKind: endpoint.kind,
            sourceRepoId: repoId,
            sourceCommit: commit,
            sourceRemote: remote,
            sourceWorldName: worldName,
            sourceObjectId: source.id,
            sourceTitle: source.title ?? "(제목 없음)",
            sourceType: source.effectiveType,
            targetWorld: targetWorld.name,
            targetWorldRoot: targetRoot,
            promotesCitation: LedgerCitationContract(id: source.id, rel: "promotes"),
            confirmationToken: token,
            publishRequires: "promotion publish \(source.id) --to gujo --confirm --json")
    }

    /// 하위호환 — 축을 직접 나열하는 옛 호출부(wiki-ui·CLI)도 그대로 컴파일된다.
    /// 새 코드는 `PromotionPublishRequest` 를 구성해 넘긴다. 둘 다 같은 경로에 쓴다.
    public static func publish(
        sourceStore: LedgerStore,
        targetStore: LedgerStore,
        source: LedgerObject,
        repository: RepositoryIdentity? = nil,
        sourceWorldName: String? = nil,
        targetWorld: LedgerWorld,
        promotedBy: String,
        confirmationToken: String,
        now: Date = Date()
    ) throws -> PromotionResult {
        try publish(PromotionPublishRequest(
            sourceStore: sourceStore,
            targetStore: targetStore,
            source: source,
            repository: repository,
            sourceWorldName: sourceWorldName,
            targetWorld: targetWorld,
            promotedBy: promotedBy,
            confirmationToken: confirmationToken,
            now: now))
    }

    public static func publish(_ request: PromotionPublishRequest) throws -> PromotionResult {
        let sourceStore = request.sourceStore
        let targetStore = request.targetStore
        let source = request.source
        let repository = request.repository
        let sourceWorldName = request.sourceWorldName
        let targetWorld = request.targetWorld
        let promotedBy = request.promotedBy
        let confirmationToken = request.confirmationToken
        let now = request.now
        guard sourceStore.root.standardizedFileURL != targetStore.root.standardizedFileURL else {
            throw PromotionError.sameWorld
        }
        let endpoint = try resolveEndpoint(repository: repository, sourceWorldName: sourceWorldName)
        let preview = try preview(
            sourceStore: sourceStore, source: source, repository: repository,
            sourceWorldName: sourceWorldName, targetWorld: targetWorld, promotedBy: promotedBy)
        guard preview.confirmationToken == confirmationToken else {
            throw PromotionError.confirmationMismatch
        }
        let sourceWorldRoot = sourceStore.root.standardizedFileURL.path

        if let existing = existingReceipt(
            in: targetStore, sourceObjectId: source.id, sourceWorldRoot: sourceWorldRoot
        ) {
            let targetObjects = targetStore.scan()
            guard targetObjects.contains(where: { $0.id == existing.receipt.targetObjectId }) else {
                throw PromotionError.malformedReceipt
            }
            let sourceReceipt = try ensureSourceReceipt(
                existing.receipt, sourceStore: sourceStore, promotedBy: promotedBy, now: now)
            return PromotionResult(
                schemaVersion: PromotionResult.schemaVersion,
                promotedObjectId: existing.receipt.targetObjectId,
                targetReceiptObjectId: existing.object.id,
                sourceReceiptObjectId: sourceReceipt.id,
                receipt: existing.receipt,
                deduplicated: true)
        }

        let (repoId, commit, remote, worldName) = fields(of: endpoint)
        let origin: String
        switch endpoint {
        case .repository(let repo):
            origin = "kbw-repo://\(repo.repoId)/objects/\(source.id)?commit=\(repo.sourceCommit)"
        case .world(let name):
            origin = "kbw-world://\(name)/objects/\(source.id)"
        }
        let promoted = try targetStore.publish(
            author: promotedBy,
            title: source.title,
            type: source.effectiveType,
            body: source.body,
            now: now,
            extras: LedgerPublishExtras(
                cites: [.init(id: source.id, rel: "promotes")],
                origin: origin,
                tags: Array(Set(source.tags + ["promoted-from-repository"])).sorted()))
        let receipt = PromotionReceipt(PromotionReceipt.Draft(
            sourceKind: endpoint.kind,
            sourceRepoId: repoId,
            sourceCommit: commit,
            sourceRemote: remote,
            sourceWorldName: worldName,
            sourceObjectId: source.id,
            sourceWorldRoot: sourceWorldRoot,
            targetWorld: targetWorld.name,
            targetWorldRoot: targetStore.root.standardizedFileURL.path,
            targetObjectId: promoted.id,
            promotedAt: now,
            promotedBy: promotedBy))
        let body = try receipt.json()
        let targetReceipt = try targetStore.publish(
            author: promotedBy,
            title: "프로모션 영수증: \(source.title ?? String(source.id.prefix(12)))",
            type: "promotion-receipt",
            body: body,
            now: now,
            extras: LedgerPublishExtras(cites: [
                .init(id: source.id, rel: "promotes"),
                .init(id: promoted.id, rel: "receipts"),
            ]))
        let sourceReceipt = try ensureSourceReceipt(
            receipt, sourceStore: sourceStore, promotedBy: promotedBy, now: now)
        return PromotionResult(
            schemaVersion: PromotionResult.schemaVersion,
            promotedObjectId: promoted.id,
            targetReceiptObjectId: targetReceipt.id,
            sourceReceiptObjectId: sourceReceipt.id,
            receipt: receipt,
            deduplicated: false)
    }

    /// `repository`가 있으면 그 정체성을 쓰고, 없으면 `sourceWorldName`을 요구한다 — 둘 다
    /// 없는 호출은 "어디서 왔는지 모르는 승격"이라 봉쇄한다.
    private static func resolveEndpoint(
        repository: RepositoryIdentity?, sourceWorldName: String?
    ) throws -> PromotionSourceEndpoint {
        if let repository { return .repository(repository) }
        guard let sourceWorldName, !sourceWorldName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PromotionError.sourceWorldNameRequired
        }
        return .world(name: sourceWorldName)
    }

    private static func fields(
        of endpoint: PromotionSourceEndpoint
    ) -> (repoId: String?, commit: String?, remote: String?, worldName: String?) {
        switch endpoint {
        case .repository(let repo):
            return (repo.repoId, repo.sourceCommit, repo.normalizedRemote, nil)
        case .world(let name):
            return (nil, nil, nil, name)
        }
    }

    /// Single provenance gate used by preview, publish, GUI and CLI. It validates the local
    /// endpoint first, then — only for a repo endpoint — reads the exact object bytes from
    /// `repository.sourceCommit`. A world endpoint has no git history to pin to; its proof is
    /// that the object is content-addressed (`LedgerStore.scan()` already refuses an id that
    /// doesn't hash to its own body), so passing the two local checks above is the whole gate.
    public static func validateSource(
        sourceStore: LedgerStore,
        source: LedgerObject,
        endpoint: PromotionSourceEndpoint
    ) throws {
        guard source.effectiveType != "promotion-receipt" else {
            throw PromotionError.sourceIsReceipt
        }
        guard let storedSource = sourceStore.scan().first(where: { $0.id == source.id }) else {
            throw PromotionError.sourceNotFound(source.id)
        }
        // `Date` retains finer in-memory precision than the deterministic ledger timestamp.
        // Compare canonical stored bytes instead of synthesized Equatable so publish()'s return
        // value and scan()'s parsed value are treated as the same object, while a forged same-id
        // value still fails closed.
        guard storedSource.serialize() == source.serialize() else {
            throw PromotionError.sourceNotAtCommit(.contentMismatch)
        }
        if sourceStore.verify().contains(where: { $0.id == source.id }) {
            throw PromotionError.sourceNotAtCommit(.contentMismatch)
        }
        guard case .repository(let repository) = endpoint else { return }
        switch GitRepositoryInspector.provenance(
            object: storedSource,
            worldRoot: sourceStore.root,
            repository: repository,
            commit: repository.sourceCommit
        ) {
        case .exact:
            return
        case .worldOutsideWorktree:
            throw PromotionError.sourceNotAtCommit(.worldOutsideRepository)
        case .commitUnavailable:
            throw PromotionError.sourceNotAtCommit(.commitUnavailable)
        case .missingAtCommit:
            throw PromotionError.sourceNotAtCommit(.objectMissing)
        case .malformedAtCommit:
            throw PromotionError.sourceNotAtCommit(.malformedObject)
        case .mismatchedAtCommit:
            throw PromotionError.sourceNotAtCommit(.contentMismatch)
        }
    }

    private static func ensureSourceReceipt(
        _ receipt: PromotionReceipt,
        sourceStore: LedgerStore,
        promotedBy: String,
        now: Date
    ) throws -> LedgerObject {
        let body = try receipt.json()
        if let existing = sourceStore.scan().first(where: {
            $0.effectiveType == "promotion-receipt" && $0.body == body
        }) { return existing }
        return try sourceStore.publish(
            author: promotedBy,
            title: "프로모션 링크: \(String(receipt.sourceObjectId.prefix(12))) → \(receipt.targetWorld)",
            type: "promotion-receipt",
            body: body,
            now: now,
            extras: LedgerPublishExtras(cites: [
                .init(id: receipt.sourceObjectId, rel: "receipts"),
                .init(id: receipt.targetObjectId, rel: "promoted-as"),
            ]))
    }

    /// 중복 판정은 (원본 객체, 원본 world) 로 한다. repo 출처는 commit 이 달라도 content가
    /// 같으면 id 가 같으므로 이걸로 충분하고, world 출처는 애초에 commit 개념이 없다.
    private static func existingReceipt(
        in store: LedgerStore,
        sourceObjectId: String,
        sourceWorldRoot: String
    ) -> (object: LedgerObject, receipt: PromotionReceipt)? {
        for object in store.scan() where object.effectiveType == "promotion-receipt" {
            guard let receipt = PromotionReceipt.decode(body: object.body) else { continue }
            if receipt.sourceObjectId == sourceObjectId, receipt.sourceWorldRoot == sourceWorldRoot {
                return (object, receipt)
            }
        }
        return nil
    }
}

public enum PromotionVerifier {
    public static func verify(
        store: LedgerStore,
        peerWorlds: [LedgerWorld],
        currentRepository: RepositoryIdentity? = nil
    ) -> [LedgerStore.Violation] {
        // 원장 루트는 **실경로로 정규화해서** 키로 쓴다. 같은 디렉터리를 심볼릭 링크
        // 경로로도 부를 수 있어서(`…/main/.wiki` ↔ `…/.worktrees/main/.wiki`), 문자열
        // 그대로 키를 잡으면 있는 world 를 못 찾고 "source world 누락" 으로 오판한다.
        let localRoot = canonical(store.root.path)
        var storesByRoot: [String: LedgerStore] = [localRoot: store]
        var worldRootsByName: [String: String] = [:]
        for world in peerWorlds {
            let root = canonical(world.rootPath)
            storesByRoot[root] = LedgerStore(root: URL(fileURLWithPath: root))
            worldRootsByName[world.name] = root
        }
        var violations: [LedgerStore.Violation] = []
        let localReceipts = store.scan().filter { $0.effectiveType == "promotion-receipt" }
        for object in localReceipts {
            guard let receipt = PromotionReceipt.decode(body: object.body) else {
                violations.append(.init(id: object.id, problem: "promotion receipt JSON/schema 불일치"))
                continue
            }
            let sourceRoot = canonical(receipt.sourceWorldRoot)
            let targetRoot = canonical(receipt.targetWorldRoot)
            let sourceStore = storesByRoot[sourceRoot]
                ?? existingStore(root: sourceRoot)
                ?? peerWorlds.lazy.compactMap { world -> LedgerStore? in
                    guard receipt.sourceRepoId != nil,
                          GitRepositoryInspector.inspect(worldRoot: world.rootPath)?.repoId
                            == receipt.sourceRepoId else { return nil }
                    return LedgerStore(root: URL(fileURLWithPath: world.rootPath))
                }.first
            let targetStore = storesByRoot[targetRoot]
                ?? worldRootsByName[receipt.targetWorld].flatMap { storesByRoot[$0] }
                ?? existingStore(root: targetRoot)
            guard let sourceStore else {
                violations.append(.init(id: object.id, problem: "promotion source world 누락: \(receipt.sourceWorldRoot)"))
                continue
            }
            guard let targetStore else {
                violations.append(.init(id: object.id, problem: "promotion target world 누락: \(receipt.targetWorldRoot)"))
                continue
            }
            let sourceObjects = sourceStore.scan()
            let targetObjects = targetStore.scan()
            guard let source = sourceObjects.first(where: { $0.id == receipt.sourceObjectId }) else {
                violations.append(.init(id: object.id, problem: "promotion source object 누락: \(receipt.sourceObjectId)"))
                continue
            }
            guard let target = targetObjects.first(where: { $0.id == receipt.targetObjectId }) else {
                violations.append(.init(id: object.id, problem: "promotion target object 누락: \(receipt.targetObjectId)"))
                continue
            }
            if !target.cites.contains(where: {
                $0.id == receipt.sourceObjectId && $0.rel == "promotes"
            }) {
                violations.append(.init(id: target.id, problem: "promotes citation과 receipt 불일치"))
            }
            let sourceReceiptExists = sourceObjects.contains {
                $0.effectiveType == "promotion-receipt" && $0.body == object.body
            }
            let targetReceiptExists = targetObjects.contains {
                $0.effectiveType == "promotion-receipt" && $0.body == object.body
            }
            if !sourceReceiptExists || !targetReceiptExists {
                violations.append(.init(
                    id: object.id,
                    problem: "promotion bidirectional receipt 누락(source=\(sourceReceiptExists), target=\(targetReceiptExists))"))
            }
            guard receipt.sourceObjectId.isEmpty == false else {
                violations.append(.init(id: object.id, problem: "promotion immutable provenance 필드 누락"))
                continue
            }
            switch receipt.sourceKind {
            case "repository":
                guard let repoId = receipt.sourceRepoId, let commit = receipt.sourceCommit,
                      !repoId.isEmpty, !commit.isEmpty else {
                    violations.append(.init(id: object.id, problem: "promotion immutable provenance 필드 누락"))
                    continue
                }
                guard let receiptRepository = GitRepositoryInspector.inspect(
                    worldRoot: sourceStore.root.path
                ), receiptRepository.repoId == repoId else {
                    violations.append(.init(
                        id: object.id,
                        problem: "promotion source repository identity 검증 실패"))
                    continue
                }
                let provenance = GitRepositoryInspector.provenance(
                    object: source,
                    worldRoot: sourceStore.root,
                    repository: receiptRepository,
                    commit: commit)
                if provenance != .exact {
                    violations.append(.init(
                        id: object.id,
                        problem: "promotion sourceCommit containment 불일치: \(provenance)"))
                }
                if let currentRepository,
                   canonical(sourceStore.root.path) == localRoot,
                   currentRepository.repoId != repoId {
                    violations.append(.init(id: object.id, problem: "promotion sourceRepoId와 현재 repoId 불일치"))
                }
            case "world":
                guard let worldName = receipt.sourceWorldName, !worldName.isEmpty else {
                    violations.append(.init(id: object.id, problem: "promotion immutable provenance 필드 누락"))
                    continue
                }
                // world 출처는 git commit 이 없다 — 증명은 content-addressing이다. `source`가
                // 위에서 이미 sourceObjectId 로 조회됐다는 것 자체가 그 world 에 정확히 이
                // 바이트가 있다는 뜻이다(LedgerStore.scan()이 id=contentID 불일치를 걸러낸다).
                break
            default:
                violations.append(.init(id: object.id, problem: "promotion sourceKind 미상: \(receipt.sourceKind)"))
            }
        }
        return violations
    }


    /// 심볼릭 링크까지 푼 실경로. 링크 경로와 실경로가 같은 디렉터리를 가리키는데도
    /// 다른 문자열이라 비교가 어긋나는 걸 막는다(bare+worktree 배치에서 상시 발생).
    private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func existingStore(root: String) -> LedgerStore? {
        let objects = URL(fileURLWithPath: root).appendingPathComponent("objects").path
        guard FileManager.default.fileExists(atPath: objects) else { return nil }
        return LedgerStore(root: URL(fileURLWithPath: root))
    }
}
