import Foundation
import Testing

@testable import KnowledgeBaseWikiCore

/// 심볼릭 링크로 부른 world 도 봉쇄(containment) 검사를 통과해야 한다는 계약.
///
/// 실사고(2026-08-04): `verify` 가 프로모션 영수증 하나를
/// `containment 불일치: worldOutsideWorktree` 로 계속 위반 처리했다. 변조가 아니라
/// **경로 표기 차이**였다 — git 의 `rev-parse --show-toplevel` 은 실경로를 주는데
/// world 는 심볼릭 링크 경로로 등록돼 있어서 접두어 비교가 어긋났다.
///
/// 이 Mac 의 bare+worktree 배치가 상시 그 형태다(`…/repo/main` → `…/repo/.worktrees/main`).
/// 즉 repo world 를 거친 프로모션은 **구조적으로 전부** 위반으로 떴고, 그 상시 빨간불이
/// verify 를 무시하게 만든다. 봉쇄는 "같은 디렉터리인가"를 물어야지 "같은 문자열인가"가
/// 아니다.
@Suite struct PromotionSymlinkContainmentTests {
    /// 링크 경로로 부른 world 는 실경로와 같은 판정을 받아야 한다.
    @Test func symlinkedWorldRootIsStillContained() throws {
        let fixture = try PromotionGitRepositoryFixture("symlink")
        defer { fixture.remove() }

        let object = try fixture.store.publish(
            author: "test", title: "근거: 심볼릭 링크 봉쇄", type: "concept", body: "본문")
        let commit = try fixture.commitAll("publish object")
        let identity = try fixture.identity(commit: commit)

        // 저장본을 다시 읽는다 — `publish()` 반환값은 in-memory Date 가 원장 타임스탬프보다
        // 정밀해서 커밋된 바이트와 안 맞는다(PromotionService 의 같은 주석 참조).
        let stored = try #require(fixture.store.scan().first { $0.id == object.id })

        // 실경로로는 원래도 통과했다 — 기준선.
        #expect(
            GitRepositoryInspector.provenance(
                object: stored, worldRoot: fixture.worldRoot,
                repository: identity, commit: commit) == .exact)

        // 같은 디렉터리를 심볼릭 링크로 부른다.
        let link = FileManager.default.temporaryDirectory
            .appendingPathComponent("kbw-symlink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.repositoryRoot)
        defer { try? FileManager.default.removeItem(at: link) }

        let linkedWorldRoot = link.appendingPathComponent(".wiki", isDirectory: true)
        #expect(
            GitRepositoryInspector.provenance(
                object: stored, worldRoot: linkedWorldRoot,
                repository: identity, commit: commit) == .exact)
        #expect(
            GitRepositoryInspector.contains(
                object: stored, worldRoot: linkedWorldRoot,
                repository: identity, commit: commit) == true)
    }

    /// 링크를 풀었다고 해서 진짜 바깥 world 까지 통과시키면 안 된다(fail-closed 유지).
    @Test func genuinelyOutsideWorldStillFails() throws {
        let fixture = try PromotionGitRepositoryFixture("outside")
        defer { fixture.remove() }

        let object = try fixture.store.publish(
            author: "test", title: "근거: 바깥 world", type: "concept", body: "본문")
        let commit = try fixture.commitAll("publish object")
        let identity = try fixture.identity(commit: commit)

        let stored = try #require(fixture.store.scan().first { $0.id == object.id })
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("kbw-outside-\(UUID().uuidString)", isDirectory: true)
        #expect(
            GitRepositoryInspector.provenance(
                object: stored, worldRoot: outside,
                repository: identity, commit: commit) == .worldOutsideWorktree)
    }
}
