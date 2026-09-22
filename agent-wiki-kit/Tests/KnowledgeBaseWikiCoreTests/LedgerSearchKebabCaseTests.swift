import Foundation
import Testing

@testable import KnowledgeBaseWikiCore

/// kebab-case 질의가 FTS5 문법 오류로 죽지 않는다는 계약.
///
/// 회귀 대상: `ftsTerms` 가 토큰을 bareword 로 넘겨서 `agent-vault*` 가 FTS5 문법
/// 오류가 됐고, 오류가 삼켜져 **"결과 없음"** 으로 보였다. 원장에 분명히 있는
/// `agent-vault` · `k3s-prod` · `gujo-swift` 가 전부 0건이었다.
///
/// 이 Mac 의 명명 규칙이 kebab-case 강제라(앱·CLI·호스트 전부) 가장 자주 치는
/// 질의 계열이 통째로 죽어 있었다. 빈 결과는 "원장에 지식이 없다" 와 구분되지
/// 않아서, 에이전트가 있는 지식을 없다고 판단하고 헛짚었다(실제 사고 2026-08-04).
@Suite struct LedgerSearchKebabCaseTests {
    private func makeWorld(title: String, body: String) throws -> (root: URL, id: String) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kbw-kebab-\(UUID())", isDirectory: true)
        let store = LedgerStore(root: root)
        let object = try store.publish(author: "test", title: title, type: "concept", body: body)
        let index = LedgerIndex(root: root)
        _ = index.sync(objectsDir: root.appendingPathComponent("objects"))
        return (root, object.id)
    }

    @Test func hyphenatedQueryFindsObject() throws {
        let world = try makeWorld(
            title: "근거: agent-vault 위임 경로",
            body: "k3s-prod 에서 gujo-swift 가 카드를 받는다.")
        defer { try? FileManager.default.removeItem(at: world.root) }
        let index = LedgerIndex(root: world.root)

        // 제목의 kebab-case 이름
        #expect(index.search("agent-vault").contains { $0.id == world.id })
        // 본문의 kebab-case 이름
        #expect(index.search("k3s-prod").contains { $0.id == world.id })
        #expect(index.search("gujo-swift").contains { $0.id == world.id })
    }

    @Test func otherReservedCharactersDoNotThrow() throws {
        let world = try makeWorld(title: "근거: 예약문자 질의", body: "본문")
        defer { try? FileManager.default.removeItem(at: world.root) }
        let index = LedgerIndex(root: world.root)

        // FTS5 예약문자가 섞여도 크래시·예외 없이 빈 결과로 끝나야 한다.
        for q in ["a:b", "c(d)", "e*f", "\"quoted\"", "x^y", "-", "--"] {
            let res = index.search(q)
            let ids = index.searchAllIDs(q)
            #expect(res.isEmpty)
            #expect(ids.isEmpty)
        }
    }

    @Test func mixedKoreanAndKebabStillWorks() throws {
        let world = try makeWorld(
            title: "근거: agent-vault 카드 위임",
            body: "카드 위임은 grant 로 한다.")
        defer { try? FileManager.default.removeItem(at: world.root) }
        let index = LedgerIndex(root: world.root)

        #expect(index.search("agent-vault 카드").contains { $0.id == world.id })
    }
}
