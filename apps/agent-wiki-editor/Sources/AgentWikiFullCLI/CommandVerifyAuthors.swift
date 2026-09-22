import Foundation
import KnowledgeBaseWikiCore
import CommandKit
import LocalizationKit

// author 감사 — KBW 를 "기록"에서 "증거"로.
//
// KBW 의 `author:` 는 자기신고라(누구나 --as 로 발행), forge 의 서버측 author 검증과
// 신뢰 등급이 달랐다. 이 감사는 그 간극을 git 커미터로 메운다: 각 객체를 원장에 처음
// 추가한 커밋의 **커미터**가 곧 진짜 행위자다. `author:`(논리적 actor)와 커미터(git
// 신원)는 네임스페이스가 달라, 원장 루트의 `authors.json`(커미터email → actor 매핑)으로
// 잇는다. 매핑이 있으면 verify 가 불일치를 위반으로 잡는다(없으면 이 감사는 건너뜀).
//
// 이는 forge REMOTE_USER↔author 바인딩의 KBW 아날로그다 — 다만 집행 시점이 push 훅이
// 아니라 verify(감사)이므로, 강제하려면 CI/pre-receive 에서 `verify` 를 게이트로 돌린다.

enum AuthorAudit {
    /// authors.json(커미터→actor 매핑)이 있으면 author↔커미터 감사 위반을 반환. 없으면 nil(감사 생략).
    /// 매핑은 **상속**된다 — 앱 `.wiki`에 없으면 상위 디렉터리의 `.wiki/authors.json`(repo 루트까지)을
    /// 쓴다. 모노레포에서 authors.json 을 루트에 한 번만 두면 모든 앱 `.wiki`가 물려받는다(중복 제거).
    static func run(root: URL, objects: [LedgerObject]) -> [LedgerStore.Violation]? {
        guard let map = resolveAuthorsMap(from: root) else { return nil }

        guard let committerByID = committerEmailByObjectID(root: root) else {
            return [LedgerStore.Violation(
                id: "authors.json", problem: CLILocalization.string("CommandVerifyAuthors.string"))]
        }

        var violations: [LedgerStore.Violation] = []
        var unverifiable = 0
        for object in objects where object.ledger >= 2 {  // content-addressed 만
            guard let email = committerByID[object.id] else { continue }
            guard let expected = map[email] else { unverifiable += 1; continue }
            if object.author != expected {
                violations.append(LedgerStore.Violation(
                    id: object.id,
                    problem: CLILocalization.format("CommandVerifyAuthors.string-2", object.author, email, expected)))
            }
        }
        if unverifiable > 0 {
            FileHandle.standardError.write(Data(
                CLILocalization.format("CommandVerifyAuthors.string-3", unverifiable).utf8))
        }
        return violations
    }

    /// 각 객체 파일을 원장에 **처음 추가한** 커밋의 커미터 email. objects/…/<id>.md → email.
    /// 커미터→actor 매핑을 상속 체인에서 찾는다 — 자기 `.wiki/authors.json` 우선,
    /// 없으면 상위 디렉터리의 `.wiki/authors.json`(repo 루트 = `.git` 있는 곳까지). 가까운 것이 이긴다.
    static func resolveAuthorsMap(from root: URL) -> [String: String]? {
        let fm = FileManager.default
        var candidates = [root.appendingPathComponent("authors.json")]  // 자기 .wiki
        var dir = root.deletingLastPathComponent()  // .wiki 를 담은 디렉터리
        while true {
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }  // 파일시스템 루트
            candidates.append(parent.appendingPathComponent(".wiki/authors.json"))
            if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) { break }  // dir 가 git 루트
            dir = parent
        }
        for url in candidates {
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode([String: String].self, from: data)
            } catch {
                _ = error
            }
        }
        return nil
    }

    private static func committerEmailByObjectID(root: URL) -> [String: String]? {
        // git 저장소인지 확인(아니면 감사 불가). cwd=root 로 두면 /var↔/private/var 심링크 무관.
        guard git(["rev-parse", "--show-toplevel"], cwd: root) != nil else { return nil }
        // pathspec 은 cwd(=root) 기준으로 해석되므로 "objects" 면 <root>/objects 를 정확히 가리킨다.
        // \x01 로 커밋 경계를 표시하고, --name-only 로 그 커밋이 추가한 파일을 잇는다.
        // 출력 경로는 리포 루트 기준이지만 basename 만 쓰므로 접두어는 무관하다.
        guard let log = git(
            ["log", "--diff-filter=A", "--name-only", "--format=\u{01}%ce", "--", "objects"],
            cwd: root) else { return nil }
        // log 는 최신→과거 순 → 같은 파일이 여러 번 나오면 계속 덮어써 마지막(가장 과거)
        // 값이 남는다 = 그 객체를 처음 추가한 커밋의 커미터.
        var email = ""
        var byID: [String: String] = [:]
        for line in log.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("\u{01}") { email = String(line.dropFirst()); continue }
            guard line.hasSuffix(".md") else { continue }
            let id = (String(line) as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
            byID[id] = email
        }
        return byID
    }

    private static func git(_ args: [String], cwd: URL) -> String? {
        let result = CommandKitSync.run(
            "/usr/bin/env",
            ["git", "-C", cwd.path] + args,
            timeout: 30
        )
        guard result.ok else { return nil }
        return result.stdout
    }
}

