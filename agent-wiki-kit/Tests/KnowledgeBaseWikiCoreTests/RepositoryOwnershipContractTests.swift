import Foundation
import KnowledgeBaseWikiCore
import Testing
import CommandKit

@Suite struct RepositoryIdentityContractTests {
    @Test func equivalentRemoteFormsShareCanonicalRepoID() throws {
        let scp = try RepositoryIdentity.normalize(remoteURL: "git@GitHub.com:OpenAI/example.git")
        let ssh = try RepositoryIdentity.normalize(remoteURL: "ssh://git@github.com/OpenAI/example.git")
        let https = try RepositoryIdentity.normalize(remoteURL: "https://github.com/OpenAI/example.git/")

        #expect(scp == "github.com/OpenAI/example")
        #expect(ssh == scp)
        #expect(https == scp)
        #expect(RepositoryIdentity.repoID(normalizedRemote: scp)
                == RepositoryIdentity.repoID(normalizedRemote: https))
    }

    @Test func fleetCollapsesWorktreeAliasesByRepoID() throws {
        let normalized = try RepositoryIdentity.normalize(remoteURL: "git@example.test:team/repo.git")
        let id = RepositoryIdentity.repoID(normalizedRemote: normalized)
        let fleet = FleetRegistry(worlds: [
            FleetWorldEntry(
                name: "repo-main", rootPath: "/workspace/main/.wiki", kind: .repo,
                gitRemote: "git@example.test:team/repo.git", repoId: id,
                normalizedGitRemote: normalized, worktreePaths: ["/workspace/main/.wiki"]),
            FleetWorldEntry(
                name: "repo-feature", rootPath: "/workspace/feature/.wiki", kind: .repo,
                gitRemote: "https://example.test/team/repo.git", repoId: id,
                normalizedGitRemote: normalized, worktreePaths: ["/workspace/feature/.wiki"]),
        ])

        #expect(fleet.canonicalRepositories.count == 1)
        #expect(fleet.canonicalRepositories[0].repoId == id)
        #expect(fleet.canonicalRepositories[0].worktreePaths.count == 2)
    }

    @Test func explicitlyOpenedWorktreeKeepsCanonicalOwnerAndExactExecutionState() throws {
        let fixture = try TemporaryGitLedger("worktree-context")
        _ = try fixture.store.publish(
            author: "owner", title: "Tracked owner knowledge", type: "decision", body: "canonical")
        _ = try fixture.commitAll("track repository knowledge")
        let feature = try fixture.addWorktree(named: "feature-context")
        defer {
            try? FileManager.default.removeItem(at: feature)
            fixture.remove()
        }
        try FileManager.default.createDirectory(
            at: feature.appendingPathComponent("apps/example"), withIntermediateDirectories: true)
        try "feature\n".write(
            to: feature.appendingPathComponent("feature.txt"), atomically: true, encoding: .utf8)
        _ = try fixture.git(["add", "--all"], cwd: feature)
        _ = try fixture.git(["commit", "-m", "feature execution head"], cwd: feature)

        let mainIdentity = try fixture.identity()
        let featureIdentity = try GitRepositoryInspector.inspect(
            cwd: feature.appendingPathComponent("apps/example").path)
        let config = LedgerConfig(
            worlds: [LedgerWorld(name: "canonical-owner", rootPath: fixture.worldRoot.path)],
            currentWorld: "canonical-owner")
        let context = try #require(RepositoryContext.resolve(
            cwd: feature.appendingPathComponent("apps/example").path, config: config))

        #expect(featureIdentity.repoId == mainIdentity.repoId)
        #expect(featureIdentity.worktreePath == feature.path)
        #expect(featureIdentity.currentBranch == "feature-context")
        #expect(featureIdentity.sourceCommit != mainIdentity.sourceCommit)
        #expect(context.identity == featureIdentity)
        #expect(context.world.rootPath == feature.appendingPathComponent(".wiki").path)
        #expect(context.world.name.hasPrefix("canonical-owner · "))

        let summary = RepositorySummaryContract(
            identity: context.identity, store: LedgerStore(root: URL(fileURLWithPath: context.world.rootPath)))
        #expect(summary.repository.id == mainIdentity.repoId)
        #expect(summary.stateMirror.worktreePath == feature.path)
        #expect(summary.repository.branch == "feature-context")
        #expect(summary.stateMirror.branch == "feature-context")
        #expect(summary.stateMirror.sourceCommit == featureIdentity.sourceCommit)
    }

    @Test func launchContextHonorsExplicitPathBeforeRegisteredFallbacks() {
        let path = RepositoryLaunchContext.explicitPath(
            arguments: ["--repository-path", "/worktree/explicit"],
            environment: [RepositoryLaunchContext.environmentKey: "/worktree/environment"],
            bundledSourceDirectory: "/worktree/bundle",
            currentDirectory: "/worktree/cwd")
        #expect(path == "/worktree/explicit")
        #expect(RepositoryLaunchContext.explicitPath(
            arguments: [],
            environment: [RepositoryLaunchContext.environmentKey: "/worktree/environment"],
            bundledSourceDirectory: "/worktree/bundle",
            currentDirectory: "/worktree/cwd") == "/worktree/environment")
    }

    @Test func launchContextIgnoresBundledSASourceButKeepsExplicitFlags() {
        // SASourceDirectory (any path) must not pin Dock-launched GUI.
        #expect(RepositoryLaunchContext.explicitPath(
            arguments: [],
            environment: [:],
            bundledSourceDirectory: "/tmp/swift-fix-monlith-test-paths/apps/knowledge-base-wiki-swift",
            currentDirectory: "/Users/me/not-a-git-repo") == nil)
        #expect(RepositoryLaunchContext.explicitPath(
            arguments: [],
            environment: [:],
            bundledSourceDirectory: "/Users/me/WORKSPACE/apps/swift-app-mono/.worktrees/ship/apps/knowledge-base-wiki-swift",
            currentDirectory: "/Users/me/not-a-git-repo") == nil)
        #expect(RepositoryLaunchContext.explicitPath(
            arguments: [],
            environment: [:],
            bundledSourceDirectory: "/Users/me/durable/apps/knowledge-base-wiki-swift",
            currentDirectory: "/Users/me/not-a-git-repo") == nil)

        // Explicit CLI / env still honor paths (tests · one-shot).
        #expect(RepositoryLaunchContext.explicitPath(
            arguments: ["--repository-path", "/tmp/explicit-repo"],
            environment: [:],
            bundledSourceDirectory: "/Users/me/durable/apps/knowledge-base-wiki-swift",
            currentDirectory: "/Users/me") == "/tmp/explicit-repo")
        #expect(RepositoryLaunchContext.explicitPath(
            arguments: [],
            environment: [RepositoryLaunchContext.environmentKey: "/private/tmp/env-repo"],
            bundledSourceDirectory: "/Users/me/durable/apps/knowledge-base-wiki-swift",
            currentDirectory: "/Users/me") == "/private/tmp/env-repo")

        #expect(RepositoryLaunchContext.isEphemeralPath("/tmp/swift-x"))
        #expect(RepositoryLaunchContext.isEphemeralPath("/private/tmp/swift-x"))
        #expect(RepositoryLaunchContext.isEphemeralPath("/var/folders/xx/T/x"))
        #expect(RepositoryLaunchContext.isEphemeralPath(
            "/Users/me/apps/swift-app-mono/.worktrees/agent-wiki-ship/apps/x"))
        #expect(!RepositoryLaunchContext.isEphemeralPath(
            "/Users/me/Documents/WORK/WORKSPACE/apps/swift-app-mono/main"))
    }
}

@Suite struct RepositorySummaryContractTests {
    @Test func taskListAndSummaryExposeVersionedReadOnlyJSON() throws {
        let (store, root) = temporaryStore("summary")
        defer { try? FileManager.default.removeItem(at: root) }
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let task = try store.publish(
            author: "owner", title: "Ship contract", type: "task", body: "Implement", now: t0)
        _ = try store.publish(author: "owner", title: "Delegate", type: "handoff", body: "위임 → agent:codex", now: t0.addingTimeInterval(10), extras: LedgerPublishExtras(cites: [.init(id: task.id, rel: "delegates")]))
        _ = try store.publish(
            author: "owner", title: "Decision", type: "decision", body: "Repository owns knowledge",
            now: t0.addingTimeInterval(20))

        let graph = LedgerTaskGraph(objects: store.scan())
        let taskContract = RepositoryTaskListContract(
            graph: graph, repoId: "repo-test", generatedAt: t0.addingTimeInterval(30))
        #expect(taskContract.schemaVersion == "knowledge-base-wiki.task-list.v1")
        #expect(taskContract.summary.total == 1)
        #expect(taskContract.summary.delegated == 1)
        #expect(taskContract.summary.items[0].assignee == "agent:codex")
        #expect(taskContract.summary.items[0].updatedAt == t0.addingTimeInterval(10))

        let identity = try fixtureIdentity(commit: String(repeating: "a", count: 40))
        let summary = RepositorySummaryContract(
            identity: identity, store: store, generatedAt: t0.addingTimeInterval(30))
        #expect(summary.schemaVersion == "knowledge-base-wiki.repository-summary.v1")
        #expect(summary.repository.id == identity.repoId)
        #expect(summary.repository.remote == identity.normalizedRemote)
        #expect(summary.tasks.delegated == 1)
        #expect(summary.knowledge.total == 1)
        #expect(summary.knowledge.recentDecisions.count == 1)
        #expect(summary.promotion.promoted == 0)
        #expect(summary.stateMirror.currentRepository == identity.repoId)
        #expect(summary.stateMirror.taskOpenCount == 1)
        #expect(summary.integrity.status == .healthy)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = String(decoding: try encoder.encode(summary), as: UTF8.self)
        #expect(json.contains("\"sourceUpdatedAt\""))
        #expect(json.contains("\"integrity\""))
        #expect(json.contains("\"promotion\""))
        #expect(json.contains("\"items\""))
    }
}

@Suite struct RepositoryPromotionContractTests {
    @Test func previewThenPublishCreatesPromotesCitationAndBidirectionalReceipt() throws {
        let sourceRepository = try PromotionGitRepositoryFixture("promotion-source")
        let sourceStore = sourceRepository.store
        let sourceRoot = sourceRepository.worldRoot
        let (targetStore, targetRoot) = temporaryStore("promotion-target")
        defer {
            sourceRepository.remove()
            try? FileManager.default.removeItem(at: targetRoot)
        }
        let now = Date(timeIntervalSince1970: 1_700_100_000)
        let source = try sourceStore.publish(author: "owner", title: "Reusable decision", type: "decision", body: "Use the repository contract.", now: now, extras: LedgerPublishExtras(tags: ["architecture"]))
        _ = try sourceRepository.commitAll("add promotion source")
        let repository = try sourceRepository.identity()
        let targetWorld = LedgerWorld(name: "gujo-wiki", rootPath: targetRoot.path)

        let preview = try PromotionService.preview(
            sourceStore: sourceStore, source: source, repository: repository,
            targetWorld: targetWorld, promotedBy: "agent:codex")
        #expect(preview.schemaVersion == "knowledge-base-wiki.promotion-preview.v2")
        #expect(preview.sourceKind == "repository")
        #expect(preview.sourceRepoId == repository.repoId)
        #expect(preview.sourceObjectId == source.id)
        #expect(preview.sourceCommit == repository.sourceCommit)
        #expect(preview.promotesCitation.rel == "promotes")

        let result = try PromotionService.publish(PromotionPublishRequest(
            sourceStore: sourceStore,
            targetStore: targetStore,
            source: source,
            repository: repository,
            targetWorld: targetWorld,
            promotedBy: "agent:codex",
            confirmationToken: preview.confirmationToken,
            now: now.addingTimeInterval(1)))
        #expect(result.receipt.sourceRepoId == repository.repoId)
        #expect(result.receipt.sourceObjectId == source.id)
        #expect(result.receipt.sourceCommit == repository.sourceCommit)

        let promoted = targetStore.scan().first { $0.id == result.promotedObjectId }
        #expect(promoted?.cites.contains { $0.id == source.id && $0.rel == "promotes" } == true)
        #expect(sourceStore.scan().contains { $0.id == result.sourceReceiptObjectId })
        #expect(targetStore.scan().contains { $0.id == result.targetReceiptObjectId })
        #expect(sourceStore.verify().isEmpty)
        #expect(targetStore.verify().isEmpty)

        let peers = [
            LedgerWorld(name: "repo", rootPath: sourceRoot.path),
            targetWorld,
        ]
        #expect(PromotionVerifier.verify(
            store: sourceStore, peerWorlds: peers, currentRepository: repository).isEmpty)
        #expect(PromotionVerifier.verify(store: targetStore, peerWorlds: peers).isEmpty)

        let retry = try PromotionService.publish(PromotionPublishRequest(
            sourceStore: sourceStore,
            targetStore: targetStore,
            source: source,
            repository: repository,
            targetWorld: targetWorld,
            promotedBy: "agent:codex",
            confirmationToken: preview.confirmationToken,
            now: now.addingTimeInterval(2)))
        #expect(retry.deduplicated)
        #expect(retry.promotedObjectId == result.promotedObjectId)
        #expect(sourceStore.scan().count == 2)
        #expect(targetStore.scan().count == 2)

        // verify must detect a missing cross-world endpoint, not silently exempt it.
        try removeObject(result.promotedObjectId, from: targetRoot)
        let broken = PromotionVerifier.verify(
            store: sourceStore, peerWorlds: peers, currentRepository: repository)
        #expect(broken.contains { $0.problem.contains("promotion target object 누락") })
    }

    @Test func publishRejectsUnconfirmedPreview() throws {
        let sourceRepository = try PromotionGitRepositoryFixture("promotion-reject-source")
        let sourceStore = sourceRepository.store
        let (targetStore, targetRoot) = temporaryStore("promotion-reject-target")
        defer {
            sourceRepository.remove()
            try? FileManager.default.removeItem(at: targetRoot)
        }
        let source = try sourceStore.publish(author: "owner", title: "Source", body: "Body")
        _ = try sourceRepository.commitAll("add source")
        let repository = try sourceRepository.identity()
        let targetWorld = LedgerWorld(name: "gujo-wiki", rootPath: targetRoot.path)

        #expect(throws: PromotionError.confirmationMismatch) {
            try PromotionService.publish(PromotionPublishRequest(
                sourceStore: sourceStore, targetStore: targetStore, source: source,
                repository: repository, targetWorld: targetWorld, promotedBy: "agent",
                confirmationToken: "not-the-preview-token"))
        }
        #expect(targetStore.scan().isEmpty)
    }

    @Test func previewRejectsUncommittedRepositoryObject() throws {
        let sourceRepository = try PromotionGitRepositoryFixture("promotion-uncommitted")
        let (_, targetRoot) = temporaryStore("promotion-uncommitted-target")
        defer {
            sourceRepository.remove()
            try? FileManager.default.removeItem(at: targetRoot)
        }
        let source = try sourceRepository.store.publish(
            author: "owner", title: "Uncommitted", body: "not in HEAD")
        let repository = try sourceRepository.identity()

        do {
            _ = try PromotionService.preview(
                sourceStore: sourceRepository.store,
                source: source,
                repository: repository,
                targetWorld: LedgerWorld(name: "gujo-wiki", rootPath: targetRoot.path),
                promotedBy: "agent")
            Issue.record("uncommitted repository object must fail closed")
        } catch let error as PromotionError {
            guard case .sourceNotAtCommit(.objectMissing) = error else {
                Issue.record("unexpected error: \(error)")
                return
            }
        }
    }

    @Test func previewRejectsStaleCommitBeforeObjectWasAdded() throws {
        let sourceRepository = try PromotionGitRepositoryFixture("promotion-stale")
        let (_, targetRoot) = temporaryStore("promotion-stale-target")
        defer {
            sourceRepository.remove()
            try? FileManager.default.removeItem(at: targetRoot)
        }
        let staleCommit = try sourceRepository.head()
        let source = try sourceRepository.store.publish(
            author: "owner", title: "Later", body: "added after stale commit")
        _ = try sourceRepository.commitAll("add later source")
        let staleIdentity = try sourceRepository.identity(commit: staleCommit)

        do {
            _ = try PromotionService.preview(
                sourceStore: sourceRepository.store,
                source: source,
                repository: staleIdentity,
                targetWorld: LedgerWorld(name: "gujo-wiki", rootPath: targetRoot.path),
                promotedBy: "agent")
            Issue.record("stale commit must fail closed")
        } catch let error as PromotionError {
            guard case .sourceNotAtCommit(.objectMissing) = error else {
                Issue.record("unexpected error: \(error)")
                return
            }
        }
    }

    @Test func previewRejectsUnknownSourceCommit() throws {
        let sourceRepository = try PromotionGitRepositoryFixture("promotion-wrong-commit")
        let (_, targetRoot) = temporaryStore("promotion-wrong-commit-target")
        defer {
            sourceRepository.remove()
            try? FileManager.default.removeItem(at: targetRoot)
        }
        let source = try sourceRepository.store.publish(
            author: "owner", title: "Committed", body: "known source")
        _ = try sourceRepository.commitAll("add known source")
        let wrongIdentity = try sourceRepository.identity(commit: String(repeating: "f", count: 40))

        do {
            _ = try PromotionService.preview(
                sourceStore: sourceRepository.store,
                source: source,
                repository: wrongIdentity,
                targetWorld: LedgerWorld(name: "gujo-wiki", rootPath: targetRoot.path),
                promotedBy: "agent")
            Issue.record("unknown source commit must fail closed")
        } catch let error as PromotionError {
            guard case .sourceNotAtCommit(.commitUnavailable) = error else {
                Issue.record("unexpected error: \(error)")
                return
            }
        }
    }

    @Test func previewAndPublishShareExactContentGateAndPublishRechecks() throws {
        let sourceRepository = try PromotionGitRepositoryFixture("promotion-exact-content")
        let (targetStore, targetRoot) = temporaryStore("promotion-exact-content-target")
        defer {
            sourceRepository.remove()
            try? FileManager.default.removeItem(at: targetRoot)
        }
        let committed = try sourceRepository.store.publish(
            author: "owner", title: "Committed", body: "original bytes")
        _ = try sourceRepository.commitAll("add exact source")
        let repository = try sourceRepository.identity()
        let targetWorld = LedgerWorld(name: "gujo-wiki", rootPath: targetRoot.path)
        let preview = try PromotionService.preview(
            sourceStore: sourceRepository.store,
            source: committed,
            repository: repository,
            targetWorld: targetWorld,
            promotedBy: "agent")

        let objectURL = try sourceRepository.objectURL(id: committed.id)
        let committedText = try String(contentsOf: objectURL, encoding: .utf8)
        try committedText.replacingOccurrences(of: "original bytes", with: "changed bytes")
            .write(to: objectURL, atomically: true, encoding: .utf8)
        let changed = try #require(sourceRepository.store.scan().first { $0.id == committed.id })

        do {
            _ = try PromotionService.preview(
                sourceStore: sourceRepository.store,
                source: changed,
                repository: repository,
                targetWorld: targetWorld,
                promotedBy: "agent")
            Issue.record("GUI/CLI preview path must reject content divergence")
        } catch let error as PromotionError {
            guard case .sourceNotAtCommit(.contentMismatch) = error else {
                Issue.record("unexpected preview error: \(error)")
                return
            }
        }

        do {
            _ = try PromotionService.publish(PromotionPublishRequest(
                sourceStore: sourceRepository.store,
                targetStore: targetStore,
                source: changed,
                repository: repository,
                targetWorld: targetWorld,
                promotedBy: "agent",
                confirmationToken: preview.confirmationToken))
            Issue.record("publish must recheck the shared exact-content gate")
        } catch let error as PromotionError {
            guard case .sourceNotAtCommit(.contentMismatch) = error else {
                Issue.record("unexpected publish error: \(error)")
                return
            }
        }
        #expect(targetStore.scan().isEmpty)
    }

    @Test func verifierRechecksReceiptSourceObjectAtExactCommit() throws {
        let sourceRepository = try PromotionGitRepositoryFixture("promotion-verifier")
        let (targetStore, targetRoot) = temporaryStore("promotion-verifier-target")
        defer {
            sourceRepository.remove()
            try? FileManager.default.removeItem(at: targetRoot)
        }
        let commitBeforeSource = try sourceRepository.head()
        let source = try sourceRepository.store.publish(
            author: "owner", title: "Source", body: "committed later")
        _ = try sourceRepository.commitAll("add source after receipt commit")
        let repository = try sourceRepository.identity()
        let promoted = try targetStore.publish(author: "agent", title: source.title, type: source.effectiveType, body: source.body, extras: LedgerPublishExtras(cites: [.init(id: source.id, rel: "promotes")]))
        let receipt = PromotionReceipt(PromotionReceipt.Draft(
            sourceKind: "repository",
            sourceRepoId: repository.repoId,
            sourceCommit: commitBeforeSource,
            sourceRemote: repository.normalizedRemote,
            sourceWorldName: nil,
            sourceObjectId: source.id,
            sourceWorldRoot: sourceRepository.worldRoot.path,
            targetWorld: "gujo-wiki",
            targetWorldRoot: targetRoot.path,
            targetObjectId: promoted.id,
            promotedAt: Date(),
            promotedBy: "agent"))
        let body = try receipt.json()
        _ = try sourceRepository.store.publish(author: "agent", title: "source receipt", type: "promotion-receipt", body: body, extras: LedgerPublishExtras(cites: [.init(id: source.id, rel: "receipts")]))
        _ = try targetStore.publish(author: "agent", title: "target receipt", type: "promotion-receipt", body: body, extras: LedgerPublishExtras(cites: [
                .init(id: source.id, rel: "promotes"),
                .init(id: promoted.id, rel: "receipts"),
            ]))

        let peers = [
            LedgerWorld(name: "repo", rootPath: sourceRepository.worldRoot.path),
            LedgerWorld(name: "gujo-wiki", rootPath: targetRoot.path),
        ]
        let violations = PromotionVerifier.verify(store: targetStore, peerWorlds: peers)
        #expect(violations.contains { $0.problem.contains("sourceCommit containment") })
    }

    @Test func v1ReceiptDecodesWithDefaultSourceKindRepository() throws {
        // v1 receipt JSON (sourceKind/sourceWorldName 없음)
        let v1ReceiptJSON = """
        {
          "schemaVersion": "knowledge-base-wiki.promotion-receipt.v1",
          "sourceRepoId": "repo-sha256-abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
          "sourceObjectId": "test-source-id",
          "sourceCommit": "a1b2c3d4",
          "sourceRemote": "git@example.com:test/repo.git",
          "sourceWorldRoot": "/workspace/main/.wiki",
          "targetWorld": "gujo",
          "targetWorldRoot": "/Users/test/gujo-wiki",
          "targetObjectId": "target-object-id",
          "promotedAt": "2026-08-11T10:00:00Z",
          "promotedBy": "test-user"
        }
        """

        guard let receipt = PromotionReceipt.decode(body: v1ReceiptJSON) else {
            Issue.record("v1 receipt should decode successfully")
            return
        }

        #expect(receipt.schemaVersion == "knowledge-base-wiki.promotion-receipt.v2")
        #expect(receipt.sourceKind == "repository")
        #expect(receipt.sourceRepoId == "repo-sha256-abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890")
        #expect(receipt.sourceWorldName == nil)
        #expect(receipt.sourceObjectId == "test-source-id")
        #expect(receipt.targetWorld == "gujo")
    }
}

/// 개인·실험 world(git repo가 아닌 `.wiki`) 승격 — repoId/commit 대신 world 이름 +
/// content-addressing 이 출처 증명이다. `person-yun-jeonghan` 처럼 git remote가 없는
/// world 에서도 preview→publish→양방향 영수증이 실제 gujo 원장을 건드리지 않고
/// 임시 픽스처만으로 동작해야 한다.
@Suite struct WorldPromotionContractTests {
    @Test func previewThenPublishRecordsWorldProvenanceWithoutRepositoryFields() throws {
        let (sourceStore, sourceRoot) = temporaryStore("personal-source")
        let (targetStore, targetRoot) = temporaryStore("personal-target")
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: targetRoot)
        }
        let now = Date(timeIntervalSince1970: 1_700_200_000)
        let source = try sourceStore.publish(author: "human", title: "검증된 개인 메모", type: "decision", body: "개인 world에서 검증한 뒤 승격.", now: now, extras: LedgerPublishExtras(tags: ["architecture"]))
        let targetWorld = LedgerWorld(name: "gujo-wiki", rootPath: targetRoot.path)

        let preview = try PromotionService.preview(
            sourceStore: sourceStore, source: source, repository: nil,
            sourceWorldName: "person-yun-jeonghan", targetWorld: targetWorld, promotedBy: "human")
        #expect(preview.sourceKind == "world")
        #expect(preview.sourceWorldName == "person-yun-jeonghan")
        #expect(preview.sourceRepoId == nil)
        #expect(preview.sourceCommit == nil)
        #expect(preview.sourceRemote == nil)
        #expect(preview.sourceObjectId == source.id)

        let result = try PromotionService.publish(PromotionPublishRequest(
            sourceStore: sourceStore, targetStore: targetStore, source: source,
            repository: nil, sourceWorldName: "person-yun-jeonghan",
            targetWorld: targetWorld, promotedBy: "human",
            confirmationToken: preview.confirmationToken, now: now.addingTimeInterval(1)))
        #expect(result.receipt.sourceKind == "world")
        #expect(result.receipt.sourceWorldName == "person-yun-jeonghan")
        #expect(result.receipt.sourceRepoId == nil)
        #expect(result.receipt.sourceCommit == nil)
        #expect(result.receipt.sourceObjectId == source.id)

        let promoted = targetStore.scan().first { $0.id == result.promotedObjectId }
        #expect(promoted?.cites.contains { $0.id == source.id && $0.rel == "promotes" } == true)
        #expect(promoted?.origin == "kbw-world://person-yun-jeonghan/objects/\(source.id)")
        #expect(sourceStore.scan().contains { $0.id == result.sourceReceiptObjectId })
        #expect(targetStore.scan().contains { $0.id == result.targetReceiptObjectId })
        #expect(sourceStore.verify().isEmpty)
        #expect(targetStore.verify().isEmpty)

        let peers = [
            LedgerWorld(name: "person-yun-jeonghan", rootPath: sourceRoot.path),
            targetWorld,
        ]
        #expect(PromotionVerifier.verify(store: sourceStore, peerWorlds: peers).isEmpty)
        #expect(PromotionVerifier.verify(store: targetStore, peerWorlds: peers).isEmpty)

        // 재승격은 같은 객체+같은 원본 world 로 dedup 되어야 한다(commit 개념이 없으므로).
        let retry = try PromotionService.publish(PromotionPublishRequest(
            sourceStore: sourceStore, targetStore: targetStore, source: source,
            repository: nil, sourceWorldName: "person-yun-jeonghan",
            targetWorld: targetWorld, promotedBy: "human",
            confirmationToken: preview.confirmationToken, now: now.addingTimeInterval(2)))
        #expect(retry.deduplicated)
        #expect(retry.promotedObjectId == result.promotedObjectId)
    }

    @Test func previewRejectsMissingRepositoryAndSourceWorldName() throws {
        let (sourceStore, sourceRoot) = temporaryStore("personal-no-provenance")
        let (_, targetRoot) = temporaryStore("personal-no-provenance-target")
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: targetRoot)
        }
        let source = try sourceStore.publish(author: "human", title: "무출처", body: "repository도 world도 없음")

        #expect(throws: PromotionError.sourceWorldNameRequired) {
            try PromotionService.preview(
                sourceStore: sourceStore, source: source, repository: nil, sourceWorldName: nil,
                targetWorld: LedgerWorld(name: "gujo-wiki", rootPath: targetRoot.path),
                promotedBy: "human")
        }
    }

    @Test func publishRejectsUnconfirmedWorldPreview() throws {
        let (sourceStore, sourceRoot) = temporaryStore("personal-unconfirmed")
        let (targetStore, targetRoot) = temporaryStore("personal-unconfirmed-target")
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: targetRoot)
        }
        let source = try sourceStore.publish(author: "human", title: "미확인", body: "confirm 없이 시도")
        let targetWorld = LedgerWorld(name: "gujo-wiki", rootPath: targetRoot.path)

        #expect(throws: PromotionError.confirmationMismatch) {
            try PromotionService.publish(PromotionPublishRequest(
                sourceStore: sourceStore, targetStore: targetStore, source: source,
                repository: nil, sourceWorldName: "person-yun-jeonghan",
                targetWorld: targetWorld, promotedBy: "human",
                confirmationToken: "not-the-preview-token"))
        }
        #expect(targetStore.scan().isEmpty)
    }
}

private func temporaryStore(_ label: String) -> (LedgerStore, URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kbw-\(label)-\(UUID().uuidString)")
    return (LedgerStore(root: root), root)
}

private func fixtureIdentity(commit: String) throws -> RepositoryIdentity {
    try RepositoryIdentity(
        remoteURL: "git@example.test:knowledge/repository.git",
        worktreePath: "/workspace/repository",
        gitCommonDirectory: "/workspace/repository.git",
        currentBranch: "feature/contract",
        defaultBranch: "main",
        sourceCommit: commit)
}

private final class TemporaryGitLedger {
    let repositoryRoot: URL
    let worldRoot: URL
    let store: LedgerStore

    init(_ label: String) throws {
        repositoryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("kbw-git-\(label)-\(UUID().uuidString)", isDirectory: true)
        worldRoot = repositoryRoot.appendingPathComponent(".wiki", isDirectory: true)
        store = LedgerStore(root: worldRoot)
        try FileManager.default.createDirectory(at: repositoryRoot, withIntermediateDirectories: true)
        _ = try git(["init", "-b", "main"])
        _ = try git(["config", "user.name", "KBW Tests"])
        _ = try git(["config", "user.email", "kbw-tests@example.test"])
        _ = try git(["remote", "add", "origin", "git@example.test:knowledge/temporary.git"])
        try "fixture\n".write(
            to: repositoryRoot.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8)
        _ = try commitAll("initial commit")
    }

    func remove() {
        try? FileManager.default.removeItem(at: repositoryRoot)
    }

    func head() throws -> String {
        try git(["rev-parse", "HEAD"])
    }

    func commitAll(_ message: String) throws -> String {
        _ = try git(["add", "--all"])
        _ = try git(["commit", "-m", message])
        return try head()
    }

    func identity(commit: String? = nil) throws -> RepositoryIdentity {
        let inspected = try GitRepositoryInspector.inspect(cwd: repositoryRoot.path)
        guard let commit else { return inspected }
        return try RepositoryIdentity(
            remoteName: inspected.remoteName,
            remoteURL: inspected.remoteURL,
            worktreePath: inspected.worktreePath,
            gitCommonDirectory: inspected.gitCommonDirectory,
            currentBranch: inspected.currentBranch,
            defaultBranch: inspected.defaultBranch,
            sourceCommit: commit)
    }

    func objectURL(id: String) throws -> URL {
        guard let enumerator = FileManager.default.enumerator(
            at: worldRoot.appendingPathComponent("objects"),
            includingPropertiesForKeys: nil
        ) else { throw TemporaryGitLedgerError("objects directory missing") }
        for case let url as URL in enumerator where url.lastPathComponent == "\(id).md" {
            return url
        }
        throw TemporaryGitLedgerError("object file missing: \(id)")
    }

    func addWorktree(named branch: String) throws -> URL {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("kbw-worktree-\(branch)-\(UUID().uuidString)", isDirectory: true)
        _ = try git(["worktree", "add", "-b", branch, path.path])
        return path
    }

    func git(_ arguments: [String], cwd: URL? = nil) throws -> String {
        let result = CommandKitSync.run(
            "/usr/bin/env",
            ["git", "-C", (cwd ?? repositoryRoot).path] + arguments,
            timeout: 30
        )
        let text = (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.ok else {
            throw TemporaryGitLedgerError("git \(arguments.joined(separator: " ")): \(text)")
        }
        return text
    }
}

private struct TemporaryGitLedgerError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func removeObject(_ id: String, from root: URL) throws {
    guard let enumerator = FileManager.default.enumerator(
        at: root.appendingPathComponent("objects"),
        includingPropertiesForKeys: nil
    ) else { return }
    for case let url as URL in enumerator where url.lastPathComponent == "\(id).md" {
        try FileManager.default.removeItem(at: url)
        return
    }
}
