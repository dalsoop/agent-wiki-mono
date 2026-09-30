import Foundation
import Testing
import CommandKit
@testable import KnowledgeBaseWikiCore

@Suite struct RepositoryWorldResolutionTests {
    final class BareWorktreeFixture {
        let tempRoot: URL
        let bareDir: URL
        let mainWorktree: URL
        let featWorktree: URL
        let outsideDir: URL
        let repoName = "test-repo"

        init() throws {
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("kbw-bare-wt-\(UUID().uuidString)", isDirectory: true)
            tempRoot = base
            bareDir = base.appendingPathComponent(".bare", isDirectory: true)
            let worktreesDir = base.appendingPathComponent(".worktrees", isDirectory: true)
            mainWorktree = worktreesDir.appendingPathComponent("main", isDirectory: true)
            featWorktree = worktreesDir.appendingPathComponent("feat", isDirectory: true)
            outsideDir = base.appendingPathComponent("outside", isDirectory: true)

            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)

            // 1. git init --bare
            _ = try Self.runGit(["init", "--bare", bareDir.path], cwd: base.path)
            _ = try Self.runGit(["config", "user.name", "Test User"], cwd: bareDir.path)
            _ = try Self.runGit(["config", "user.email", "test@example.com"], cwd: bareDir.path)

            // 2. Initial commit through a temp clone
            let initClone = base.appendingPathComponent("init-clone", isDirectory: true)
            _ = try Self.runGit(["clone", bareDir.path, initClone.path], cwd: base.path)
            _ = try Self.runGit(["config", "user.name", "Test User"], cwd: initClone.path)
            _ = try Self.runGit(["config", "user.email", "test@example.com"], cwd: initClone.path)
            try "initial\n".write(to: initClone.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
            _ = try Self.runGit(["add", "."], cwd: initClone.path)
            _ = try Self.runGit(["commit", "-m", "initial commit"], cwd: initClone.path)
            _ = try Self.runGit(["branch", "-M", "main"], cwd: initClone.path)
            _ = try Self.runGit(["push", "origin", "main"], cwd: initClone.path)
            try FileManager.default.removeItem(at: initClone)

            // 3. Set remote origin for bare repo so repoId can be derived
            _ = try Self.runGit(["remote", "add", "origin", "git@example.test:org/test-repo.git"], cwd: bareDir.path)

            // 4. Create worktrees: main and feat
            _ = try Self.runGit(["worktree", "add", mainWorktree.path, "main"], cwd: bareDir.path)
            _ = try Self.runGit(["worktree", "add", "-b", "feat", featWorktree.path], cwd: bareDir.path)

            _ = try Self.runGit(["config", "user.name", "Test User"], cwd: mainWorktree.path)
            _ = try Self.runGit(["config", "user.email", "test@example.com"], cwd: mainWorktree.path)
            _ = try Self.runGit(["config", "user.name", "Test User"], cwd: featWorktree.path)
            _ = try Self.runGit(["config", "user.email", "test@example.com"], cwd: featWorktree.path)

            // 5. Create .wiki directories in worktrees
            try FileManager.default.createDirectory(at: mainWorktree.appendingPathComponent(".wiki/objects"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: featWorktree.appendingPathComponent(".wiki/objects"), withIntermediateDirectories: true)
        }

        func tearDown() {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        func head(cwd: String) throws -> String {
            let res = try Self.runGit(["rev-parse", "HEAD"], cwd: cwd)
            return res.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        static func runGit(_ arguments: [String], cwd: String) throws -> String {
            let result = CommandKitSync.run(
                "/usr/bin/env",
                ["git", "-C", cwd] + arguments,
                timeout: 30
            )
            let text = (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            guard result.ok else {
                throw GenericError("git \(arguments.joined(separator: " ")) in \(cwd): \(text)")
            }
            return text
        }
    }

    struct GenericError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    @Test func cwdInFeatWorktreeResolvesToFeatWiki() throws {
        let fixture = try BareWorktreeFixture()
        defer { fixture.tearDown() }

        let mainWikiPath = fixture.mainWorktree.appendingPathComponent(".wiki").path
        let featWikiPath = fixture.featWorktree.appendingPathComponent(".wiki").path
        let registeredWorld = LedgerWorld(name: fixture.repoName, rootPath: mainWikiPath)

        // 1. Direct RepositoryWorldResolution.resolve
        let resolved = RepositoryWorldResolution.resolve(world: registeredWorld, cwd: fixture.featWorktree.path)
        #expect(resolved.rootPath == featWikiPath)

        // 2. LedgerConfig.resolveWorld
        let config = LedgerConfig(rootPath: fixture.bareDir.path, worlds: [registeredWorld])
        let configResolved = config.resolveWorld(cwd: fixture.featWorktree.path, explicitWorld: fixture.repoName)
        #expect(configResolved?.rootPath == featWikiPath)
    }

    @Test func cwdOutsideRepositoryUsesMainAndRefusesWrite() throws {
        let fixture = try BareWorktreeFixture()
        defer { fixture.tearDown() }

        let mainWikiPath = fixture.mainWorktree.appendingPathComponent(".wiki").path
        let registeredWorld = LedgerWorld(name: fixture.repoName, rootPath: mainWikiPath)

        // 1. Path stays registered path (main slot)
        let resolved = RepositoryWorldResolution.resolve(world: registeredWorld, cwd: fixture.outsideDir.path)
        #expect(resolved.rootPath == mainWikiPath)

        // 2. Write check refused
        let writeDenial = RepositoryWorldResolution.checkWriteDenial(world: resolved, cwd: fixture.outsideDir.path)
        #expect(writeDenial == RepositoryWorldResolution.writeRefusalReason)

        #expect(throws: RepositoryWorldWriteError.self) {
            try RepositoryWorldResolution.validateWrite(world: resolved, cwd: fixture.outsideDir.path)
        }
    }

    @Test func cwdInMainSlotRefusesWriteAndAllowsRead() throws {
        let fixture = try BareWorktreeFixture()
        defer { fixture.tearDown() }

        let mainWikiPath = fixture.mainWorktree.appendingPathComponent(".wiki").path
        let registeredWorld = LedgerWorld(name: fixture.repoName, rootPath: mainWikiPath)

        let resolved = RepositoryWorldResolution.resolve(world: registeredWorld, cwd: fixture.mainWorktree.path)
        #expect(resolved.rootPath == mainWikiPath)

        // 1. Write refused
        let mainWriteDenial = RepositoryWorldResolution.checkWriteDenial(world: resolved, cwd: fixture.mainWorktree.path)
        #expect(mainWriteDenial == RepositoryWorldResolution.writeRefusalReason)

        #expect(throws: RepositoryWorldWriteError.self) {
            try RepositoryWorldResolution.validateWrite(world: resolved, cwd: fixture.mainWorktree.path)
        }

        // 2. Read allowed
        let mainStore = LedgerStore(root: URL(fileURLWithPath: resolved.rootPath))
        let objects = mainStore.scan()
        #expect(objects.isEmpty)
    }

    @Test func repairReceiptsApplyWithCwdInFeatRepairsInFeatAndLeavesMainUntouched() throws {
        let fixture = try BareWorktreeFixture()
        defer { fixture.tearDown() }

        let targetDir = fixture.tempRoot.appendingPathComponent("gujo-wiki", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDir.appendingPathComponent("objects"), withIntermediateDirectories: true)
        let targetStore = LedgerStore(root: targetDir)
        let targetWorld = LedgerWorld(name: "gujo-wiki", rootPath: targetDir.path)

        // feat/.wiki에 원본 객체 발행 (sourceStore)
        let featWikiURL = fixture.featWorktree.appendingPathComponent(".wiki")
        let featStore = LedgerStore(root: featWikiURL)
        let sourceObj = try featStore.publish(
            author: "bob", title: "피처 지식", type: "concept", body: "피처 본문")

        // targetStore에 승격 객체 발행
        let promotedObj = try targetStore.publish(
            author: "bob", title: "피처 지식", type: "concept", body: "피처 본문",
            extras: LedgerPublishExtras(cites: [.init(id: sourceObj.id, rel: "promotes")]))

        let sourceCommit = try fixture.head(cwd: fixture.featWorktree.path)
        let featIdentity = try GitRepositoryInspector.inspect(cwd: fixture.featWorktree.path)

        let mainWikiPath = fixture.mainWorktree.appendingPathComponent(".wiki").path
        let receiptDraft = PromotionReceipt.Draft(
            sourceKind: "repository",
            sourceRepoId: featIdentity.repoId,
            sourceCommit: sourceCommit,
            sourceObjectId: sourceObj.id,
            sourceWorldRoot: mainWikiPath, // 원래 영수증에 main/.wiki로 잡혀 있었던 상황 재현
            targetWorld: targetWorld.name,
            targetWorldRoot: targetStore.root.standardizedFileURL.path,
            targetObjectId: promotedObj.id,
            promotedAt: Date(),
            promotedBy: "bob"
        )
        let receipt = PromotionReceipt(receiptDraft)
        let receiptBody = try receipt.json()

        // targetStore에만 영수증 발행 (sourceStore 누락)
        _ = try targetStore.publish(
            author: "bob",
            title: "프로모션 영수증",
            type: "promotion-receipt",
            body: receiptBody,
            extras: LedgerPublishExtras(cites: [
                .init(id: sourceObj.id, rel: "promotes"),
                .init(id: promotedObj.id, rel: "receipts"),
            ]))

        // 등록된 world 목록에는 main/.wiki로 등록되어 있음
        let registeredRepoWorld = LedgerWorld(name: fixture.repoName, rootPath: mainWikiPath)
        let peerWorlds = [targetWorld, registeredRepoWorld]

        // repair 실행: cwd=featWorktree, apply=true
        let report = try PromotionReceiptRepairService.repair(
            store: targetStore,
            worldName: targetWorld.name,
            peerWorlds: peerWorlds,
            apply: true,
            author: "operator",
            cwd: fixture.featWorktree.path)

        #expect(report.isApplied)
        #expect(report.items.count == 1)
        #expect(report.items[0].status == .repaired)
        #expect(report.items[0].defectKind == .missingInSource)

        // 결과에 커밋해야 할 파일 목록(쓴 경로)이 포함됨
        #expect(!report.filesToCommit.isEmpty)
        #expect(report.filesToCommit.allSatisfy { $0.contains(fixture.featWorktree.appendingPathComponent(".wiki").path) })

        // feat/.wiki에 영수증 파일 생성 확인
        let featReceipts = featStore.scan().filter { $0.effectiveType == "promotion-receipt" }
        #expect(featReceipts.count == 1)

        // main/.wiki는 무변경 (영수증 파일 없음)
        let mainWikiURL = fixture.mainWorktree.appendingPathComponent(".wiki")
        let mainStoreAfter = LedgerStore(root: mainWikiURL)
        let mainReceipts = mainStoreAfter.scan().filter { $0.effectiveType == "promotion-receipt" }
        #expect(mainReceipts.isEmpty)
    }
}
