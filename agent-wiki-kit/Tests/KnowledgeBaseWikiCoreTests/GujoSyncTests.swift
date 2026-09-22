import Foundation
import Testing
@testable import KnowledgeBaseWikiCore

/// gujo 전송로 계약. 핵심은 **뒤처짐이 관측 가능한가** — 이전 전송로(syncthing)는
/// 그게 안 보여서 몇 주간 죽은 줄 몰랐다.
@Suite struct GujoSyncTests {
    /// 임시 git 저장소(seed 역할 bare + 작업본) 한 벌.
    private func makeRepoPair() throws -> (work: URL, seed: URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("gujo-test-\(UUID().uuidString)")
        let seed = base.appendingPathComponent("seed.git")
        let work = base.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        _ = GujoSync.run("git", ["init", "-q", "--bare", "-b", "main", seed.path], cwd: nil)
        _ = GujoSync.run("git", ["init", "-q", "-b", "main", work.path], cwd: nil)
        for (key, value) in ["user.email": "t@example.com", "user.name": "t"] {
            _ = GujoSync.run("git", ["-C", work.path, "config", key, value], cwd: nil)
        }
        try FileManager.default.createDirectory(
            at: work.appendingPathComponent("objects/2026/07"), withIntermediateDirectories: true)
        try "seed object".write(
            to: work.appendingPathComponent("objects/2026/07/a.md"), atomically: true, encoding: .utf8)
        _ = GujoSync.run("git", ["-C", work.path, "add", "-A"], cwd: nil)
        _ = GujoSync.run("git", ["-C", work.path, "commit", "-q", "-m", "init"], cwd: nil)
        _ = GujoSync.run("git", ["-C", work.path, "remote", "add", "origin", seed.path], cwd: nil)
        _ = GujoSync.run("git", ["-C", work.path, "push", "-q", "-u", "origin", "main"], cwd: nil)
        return (work, seed)
    }

    @Test func statusReportsCleanRepository() throws {
        let (work, _) = try makeRepoPair()
        defer { try? FileManager.default.removeItem(at: work.deletingLastPathComponent()) }
        let state = GujoSync(root: work).status()
        #expect(state.isRepository)
        #expect(state.ahead == 0)
        #expect(state.behind == 0)
        #expect(state.dirty == 0)
        #expect(state.needsAttention == false)
    }

    @Test func nonRepositoryIsFlaggedRatherThanCrashing() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gujo-plain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let state = GujoSync(root: dir).status()
        #expect(state.isRepository == false)
        #expect(state.needsAttention)
    }

    /// 로컬에서 발행하면 ahead 로 **보여야** 한다 — 이게 안 보이면 또 조용히 뒤처진다.
    @Test func localPublishShowsAsAhead() throws {
        let (work, _) = try makeRepoPair()
        defer { try? FileManager.default.removeItem(at: work.deletingLastPathComponent()) }
        try "new object".write(
            to: work.appendingPathComponent("objects/2026/07/b.md"), atomically: true, encoding: .utf8)
        _ = GujoSync.run("git", ["-C", work.path, "add", "-A"], cwd: nil)
        _ = GujoSync.run("git", ["-C", work.path, "commit", "-q", "-m", "publish"], cwd: nil)

        let state = GujoSync(root: work).status()
        #expect(state.ahead == 1)
        #expect(state.needsAttention)
    }

    @Test func uncommittedWorkShowsAsDirty() throws {
        let (work, _) = try makeRepoPair()
        defer { try? FileManager.default.removeItem(at: work.deletingLastPathComponent()) }
        try "loose".write(
            to: work.appendingPathComponent("objects/2026/07/c.md"), atomically: true, encoding: .utf8)
        #expect(GujoSync(root: work).status().dirty == 1)
    }

    @Test func syncPushesLocalCommitsToSeed() throws {
        let (work, seed) = try makeRepoPair()
        defer { try? FileManager.default.removeItem(at: work.deletingLastPathComponent()) }
        try "pushed".write(
            to: work.appendingPathComponent("objects/2026/07/d.md"), atomically: true, encoding: .utf8)
        _ = GujoSync.run("git", ["-C", work.path, "add", "-A"], cwd: nil)
        _ = GujoSync.run("git", ["-C", work.path, "commit", "-q", "-m", "d"], cwd: nil)

        let sync = GujoSync(root: work)
        let result = sync.sync()
        guard case .success(let outcome) = result else {
            Issue.record("sync 실패: \(result)"); return
        }
        #expect(outcome.pushed)
        #expect(sync.status().ahead == 0)
        // seed 가 실제로 받았는지 — 커밋 수로 확인
        let seedLog = GujoSync.run("git", ["-C", seed.path, "rev-list", "--count", "main"], cwd: nil)
        #expect(seedLog.out == "2")
    }

    @Test func syncStampsLastSyncTime() throws {
        let (work, _) = try makeRepoPair()
        defer { try? FileManager.default.removeItem(at: work.deletingLastPathComponent()) }
        let sync = GujoSync(root: work)
        #expect(sync.loadLastSync() == nil)
        _ = sync.sync()
        let stamped = sync.loadLastSync()
        #expect(stamped != nil)
        if let stamped { #expect(abs(stamped.timeIntervalSinceNow) < 60) }
    }

    /// 피어는 **pull-only** — 추가하면 push url 이 막혀 있어야 한다.
    @Test func addedPeerHasPushDisabled() throws {
        let (work, seed) = try makeRepoPair()
        defer { try? FileManager.default.removeItem(at: work.deletingLastPathComponent()) }
        let sync = GujoSync(root: work)
        guard case .success = sync.addPeer(name: "mac2", url: seed.path) else {
            Issue.record("피어 추가 실패"); return
        }
        let pushURL = GujoSync.run(
            "git", ["-C", work.path, "remote", "get-url", "--push", "mac2"], cwd: nil)
        #expect(pushURL.out == "DISABLED_pull_only_mesh")
        #expect(sync.peers().contains { $0.name == "mac2" })
    }

    @Test func originIsNotTreatedAsPeer() throws {
        let (work, _) = try makeRepoPair()
        defer { try? FileManager.default.removeItem(at: work.deletingLastPathComponent()) }
        let sync = GujoSync(root: work)
        #expect(sync.peers().isEmpty)
        if case .success = sync.removePeer(name: "origin") {
            Issue.record("origin 을 피어로 지워선 안 된다")
        }
    }

    /// 피어 sync 는 fetch·merge 만 하고 push 하지 않는다.
    @Test func peerSyncMergesWithoutPushing() throws {
        let (work, seed) = try makeRepoPair()
        defer { try? FileManager.default.removeItem(at: work.deletingLastPathComponent()) }
        let sync = GujoSync(root: work)
        _ = sync.addPeer(name: "mac2", url: seed.path)
        let result = sync.sync(peer: "mac2")
        guard case .success(let outcome) = result else {
            Issue.record("피어 sync 실패: \(result)"); return
        }
        #expect(outcome.pushed == false)
        #expect(outcome.fetched == ["mac2"])
    }

    @Test func blobCountIgnoresMissingDirectory() throws {
        let (work, _) = try makeRepoPair()
        defer { try? FileManager.default.removeItem(at: work.deletingLastPathComponent()) }
        #expect(GujoSync(root: work).countBlobs() == 0)

        let blobs = work.appendingPathComponent("blobs/ab")
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        try "x".write(to: blobs.appendingPathComponent("abcdef"), atomically: true, encoding: .utf8)
        #expect(GujoSync(root: work).countBlobs() == 1)
    }
}
