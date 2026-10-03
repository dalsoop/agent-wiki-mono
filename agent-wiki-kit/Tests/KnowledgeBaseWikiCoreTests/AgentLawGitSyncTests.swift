import Foundation
import Testing
import WikiLedgerKit

@testable import KnowledgeBaseWikiCore

/// git 정본 동기화(T5) 시험 — 공포 직후 커밋, 커밋 대기, `sync` 의 pull 합집합·push, 덧붙이기 위반 멈춤, 제외 경로.
/// 근거: docs/business-rules.md "원장 구성"·"공포·개정·폐지·원상회복", 결정 0007.
/// 임시 디렉터리의 git 저장소와 임시 bare 원격만 쓴다(네트워크 없음).
@Suite(.serialized) struct AgentLawGitSyncTests {
    static let git = LawGitRunner.live

    @discardableResult
    static func git(_ arguments: [String], _ directory: URL) -> LawGitRunner.Output {
        git(arguments, in: directory, timeout: 30)
    }

    static func temporary(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.resolvingSymlinksInPath()
    }

    static func configureIdentity(_ dir: URL) {
        git(["config", "user.email", "t@example.com"], dir)
        git(["config", "user.name", "t"], dir)
        git(["config", "commit.gpgsign", "false"], dir)
    }

    /// 저장소 하나(맨 위 = `dir`)에 원장 셋을 둔다.
    struct Clone {
        let dir: URL
        var file: BoundLedgerFile {
            func path(_ name: String) -> String { dir.appendingPathComponent(name).path }
            return BoundLedgerFile(
                worlds: [
                    BoundWorld(name: "agent-law", rootPath: path("law"), key: "law"),
                    BoundWorld(name: "agent-law-person-a", rootPath: path("person-a"), layer: "tenant",
                               parent: "agent-law", key: "person-a"),
                    BoundWorld(name: "agent-law-tenant-b", rootPath: path("tenant-b"), layer: "tenant",
                               parent: "agent-law", key: "tenant-b"),
                ],
                currentWorld: "agent-law", devices: ["mac"], currentDevice: "mac")
        }

        func target(_ name: String = "agent-law") -> LawLedgerTarget {
            let catalog = WorldBindingCatalog(worlds: file.effectiveWorlds)
            return LawLedgerTarget(
                worldName: name, root: URL(fileURLWithPath: catalog.world(named: name)!.rootPath),
                catalog: catalog, registeredDevices: ["mac"], currentDevice: "mac")
        }

        func commitCount() -> Int {
            Int(AgentLawGitSyncTests.git(["rev-list", "--count", "HEAD"], dir).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }

        func headFiles() -> [String] {
            AgentLawGitSyncTests.git(["show", "--name-only", "--format=", "HEAD"], dir).stdout
                .split(separator: "\n").map(String.init)
        }

        func headSubject() -> String {
            AgentLawGitSyncTests.git(["log", "-1", "--format=%s"], dir).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func sync(lock: TimeInterval = 5) -> Result<LawSyncOutcome, LawSyncError> {
            LawGitSync(ledgerRoot: target().root, lockTimeout: lock).sync()
        }
    }

    /// 빈 bare 원격 + 그 원격을 origin 으로 둔 작업본.
    static func repository(remote: URL? = nil) throws -> (clone: Clone, remote: URL) {
        let base = try temporary("agent-law-git")
        let bare = remote ?? base.appendingPathComponent("remote.git")
        if remote == nil { git(["init", "-q", "--bare", "-b", "main", bare.path], base) }
        let work = base.appendingPathComponent("agent-law")
        git(["init", "-q", "-b", "main", work.path], base)
        configureIdentity(work)
        git(["remote", "add", "origin", bare.path], work)
        return (Clone(dir: work), bare)
    }

    static let agent = LawActor(
        author: "agent:claude@mac", kind: .agent, device: "mac", runtime: "claude-code",
        model: "claude-opus-5-5", effort: "high")

    static func draft(_ title: String, body: String = "본문", repeals: String? = nil, batch: String? = nil) -> LawDraft {
        LawDraft(actor: agent, title: title, batch: batch, repeals: repeals, body: body)
    }

    // MARK: - 공포 직후 커밋

    @Test func enactCommitsExactlyThatRecordFile() throws {
        let (clone, _) = try Self.repository()
        defer { try? FileManager.default.removeItem(at: clone.dir.deletingLastPathComponent()) }
        let law = clone.target()
        // 남의 작업 파일(같은 원장의 미커밋 파일)은 공포 커밋에 섞이면 안 된다.
        let stray = law.root.appendingPathComponent("notes.txt")
        try FileManager.default.createDirectory(at: law.root, withIntermediateDirectories: true)
        try "stray".write(to: stray, atomically: true, encoding: .utf8)

        let stored = try LawEnactService.enact(Self.draft("첫 기록"), target: law)
        #expect(clone.commitCount() == 1)
        let path = try #require(LawGitRepository.locate(ledgerRoot: law.root)?.relativePath(
            law.store.objectURL(id: stored.id, promulgated: stored.record.promulgated)))
        #expect(clone.headFiles() == [path])
        #expect(clone.headSubject() == "\(stored.id) 첫 기록")
        #expect(Self.git(["status", "--porcelain"], clone.dir).stdout.contains("notes.txt"))

        // 테넌트 원장 공포도 같은 저장소에 한 건 = 한 커밋.
        let tenant = try LawEnactService.enact(Self.draft("테넌트 기록"), target: clone.target("agent-law-person-a"))
        #expect(clone.commitCount() == 2)
        #expect(clone.headSubject() == "\(tenant.id) 테넌트 기록")
        #expect(clone.headFiles().first?.hasPrefix("person-a/objects/") == true)
    }

    @Test func idempotentEnactAddsNoCommitAndNoPending() throws {
        let (clone, _) = try Self.repository()
        defer { try? FileManager.default.removeItem(at: clone.dir.deletingLastPathComponent()) }
        let law = clone.target()
        let now = Date()
        let first = try LawEnactService.enact(Self.draft("같은 기록"), target: law, now: now)
        let again = try law.store.enact(Self.draft("같은 기록"), now: now, context: LawEnactService.context(index: LawEnactService.scope(of: law)))
        #expect(first.id == again.id)
        #expect(LawGitCommit.commit([again], ledgerRoot: law.root, lockTimeout: 1) != .skipped)
        #expect(clone.commitCount() == 1)
        #expect(LawGitRepository.locate(ledgerRoot: law.root)?.markedPending().isEmpty == true)
    }

    @Test func restoreCommitsEachRecordSeparately() throws {
        let (clone, _) = try Self.repository()
        defer { try? FileManager.default.removeItem(at: clone.dir.deletingLastPathComponent()) }
        let law = clone.target()
        try LawEnactService.enact(Self.draft("하나", batch: "b1"), target: law)
        try LawEnactService.enact(Self.draft("둘", batch: "b1"), target: law)
        #expect(clone.commitCount() == 2)
        let restored = try LawEnactService.restore(batch: "b1", actor: Self.agent, target: law)
        #expect(restored.count == 2)
        #expect(clone.commitCount() == 4)
        #expect(clone.headFiles().count == 1)
    }

    @Test func nonRepositoryRootIsSkipped() throws {
        let dir = try Self.temporary("agent-law-plain")
        defer { try? FileManager.default.removeItem(at: dir) }
        let clone = Clone(dir: dir)
        let stored = try LawEnactService.enact(Self.draft("git 밖"), target: clone.target())
        #expect(LawGitCommit.commit([stored], ledgerRoot: clone.target().root) == .skipped)
        #expect(LawStore(root: clone.target().root).scan().count == 1)
        if case .failure(.notARepository) = clone.sync() {} else { Issue.record("git 밖 sync 는 notARepository") }
    }

    /// 원장 루트가 저장소 맨 위·바로 아래가 아니면(엉뚱한 상위 저장소) 커밋하지 않는다.
    @Test func unrelatedAncestorRepositoryIsSkipped() throws {
        let base = try Self.temporary("agent-law-ancestor")
        defer { try? FileManager.default.removeItem(at: base) }
        Self.git(["init", "-q", "-b", "main", base.path], base)
        Self.configureIdentity(base)
        let clone = Clone(dir: base.appendingPathComponent("deep/agent-law"))
        let stored = try LawEnactService.enact(Self.draft("깊은 곳"), target: clone.target())
        #expect(LawGitCommit.commit([stored], ledgerRoot: clone.target().root) == .skipped)
        #expect(!Self.git(["rev-parse", "--verify", "-q", "HEAD"], base).ok)
    }

    // MARK: - 잠금 경합 → 커밋 대기 → sync

    @Test func lockContentionLeavesPendingAndSyncCommitsIt() throws {
        let (clone, remote) = try Self.repository()
        defer { try? FileManager.default.removeItem(at: clone.dir.deletingLastPathComponent()) }
        let law = clone.target()
        let stored = try law.store.enact(Self.draft("잠금 경합"))
        let repository = try #require(LawGitRepository.locate(ledgerRoot: law.root))
        let held = try #require(repository.acquireLock(timeout: 1))

        let outcome = LawGitCommit.commit([stored], ledgerRoot: law.root, lockTimeout: 0.2)
        guard case .pending = outcome else { Issue.record("잠금 경합이면 커밋 대기: \(outcome)"); return }
        #expect(repository.markedPending().count == 1)
        #expect(repository.pendingCount() == 1)
        #expect(!Self.git(["rev-parse", "--verify", "-q", "HEAD"], clone.dir).ok)
        // 잠금을 쥔 동안 sync 도 상한에서 멈춘다.
        if case .failure(.lockTimeout) = clone.sync(lock: 0.2) {} else { Issue.record("sync 도 잠금 대기 상한") }
        held.release()

        let result = clone.sync()
        guard case .success(let synced) = result else { Issue.record("sync 실패: \(result)"); return }
        #expect(synced.committedPending == 1)
        #expect(synced.pushed)
        #expect(repository.markedPending().isEmpty)
        #expect(repository.pendingCount() == 0)
        let log = Self.git(["log", "--format=%s", "main"], remote).stdout
        #expect(log.contains("\(stored.id) 잠금 경합"))
        let display = LawGitSync(ledgerRoot: law.root).display()
        #expect(display.isRepository && display.pending == 0 && display.pushed == true && display.lastSync != nil)
    }

    // MARK: - 두 복제본 합집합

    @Test func twoClonesConvergeOnFileUnion() throws {
        let (first, remote) = try Self.repository()
        defer { try? FileManager.default.removeItem(at: first.dir.deletingLastPathComponent()) }
        let a = try LawEnactService.enact(Self.draft("A 기기"), target: first.target())
        guard case .success(let firstPush) = first.sync() else { Issue.record("A sync 실패"); return }
        #expect(firstPush.pushed && firstPush.received == 0)

        let (second, _) = try Self.repository(remote: remote)
        defer { try? FileManager.default.removeItem(at: second.dir.deletingLastPathComponent()) }
        let b = try LawEnactService.enact(Self.draft("B 기기"), target: second.target("agent-law-tenant-b"))
        let secondResult = second.sync()
        guard case .success(let secondSync) = secondResult else { Issue.record("B sync 실패: \(secondResult)"); return }
        #expect(secondSync.received == 1)
        #expect(secondSync.pushed)

        guard case .success(let back) = first.sync() else { Issue.record("A 재동기화 실패"); return }
        #expect(back.received == 1)
        for clone in [first, second] {
            let ids = Set(LawStore(root: clone.target().root).scan().map(\.id))
                .union(LawStore(root: clone.target("agent-law-tenant-b").root).scan().map(\.id))
            #expect(ids == [a.id, b.id])
        }
    }

    @Test func samePathDifferentBytesStopsWithoutMerging() throws {
        let (first, remote) = try Self.repository()
        defer { try? FileManager.default.removeItem(at: first.dir.deletingLastPathComponent()) }
        let (second, _) = try Self.repository(remote: remote)
        defer { try? FileManager.default.removeItem(at: second.dir.deletingLastPathComponent()) }
        let path = "law/objects/2026/10/\(String(repeating: "a", count: 64)).md"
        for (clone, bytes) in [(first, "first"), (second, "second")] {
            let url = clone.dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: url, atomically: true, encoding: .utf8)
        }
        guard case .success = first.sync() else { Issue.record("A sync 실패"); return }
        let result = second.sync()
        guard case .failure(.divergentRecords(let paths)) = result else {
            Issue.record("같은 경로 다른 바이트면 멈춰야 함: \(result)"); return
        }
        #expect(paths == [path])
        // 합치지 않았다: 원격 끝이 HEAD 의 조상이 아니고, push 도 하지 않았다.
        #expect(!Self.git(["merge-base", "--is-ancestor", "origin/main", "HEAD"], second.dir).ok)
        #expect(!Self.git(["log", "--format=%H", "main"], remote).stdout
            .contains(Self.git(["rev-parse", "HEAD"], second.dir).stdout.trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(try String(contentsOf: second.dir.appendingPathComponent(path), encoding: .utf8) == "second")
        #expect(LawGitSync(ledgerRoot: second.target().root).lastState()?.error?.contains(path) == true)
    }

    // MARK: - 제외 경로

    @Test func syncIgnoresExhibitsStateAndSessions() throws {
        let (clone, _) = try Self.repository()
        defer { try? FileManager.default.removeItem(at: clone.dir.deletingLastPathComponent()) }
        let law = clone.target()
        try LawEnactService.enact(Self.draft("기록"), target: law)
        _ = try law.store.putExhibit(Data("원자료".utf8))
        for name in ["state/index.db", "sessions/s.json"] {
            let url = law.root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
        guard case .success = clone.sync() else { Issue.record("sync 실패"); return }
        #expect(Self.git(["status", "--porcelain", "--untracked-files=all"], clone.dir).stdout.isEmpty)
        let tracked = Self.git(["ls-files"], clone.dir).stdout
        #expect(!tracked.contains("exhibits/") && !tracked.contains("state/") && !tracked.contains("sessions/"))
        #expect(tracked.contains(".gitignore"))
        // 두 번째 sync 는 .gitignore 를 다시 커밋하지 않는다.
        let count = clone.commitCount()
        guard case .success = clone.sync() else { Issue.record("두 번째 sync 실패"); return }
        #expect(clone.commitCount() == count)
    }

    @Test func commitMessageIsIdAndOneLineTitle() {
        #expect(LawGitCommit.message(id: "abc", title: "줄\n바꿈") == "abc 줄 바꿈")
        #expect(LawGitCommit.message(id: "abc", title: nil) == "abc")
    }

    @Test func lockSecondsDefaultAndOverride() {
        #expect(LawGitRepository.lockSeconds(environment: [:]) == 30)
        #expect(LawGitRepository.lockSeconds(environment: ["AGENT_LAW_COMMIT_LOCK_SECONDS": "5"]) == 5)
        #expect(LawGitRepository.lockSeconds(environment: ["AGENT_LAW_COMMIT_LOCK_SECONDS": "x"]) == 30)
    }
}
