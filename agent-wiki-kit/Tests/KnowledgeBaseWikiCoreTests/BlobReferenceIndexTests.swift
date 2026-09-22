import Foundation
import Testing

@testable import KnowledgeBaseWikiCore

/// 객체 → 원본 역참조 계약.
///
/// 원장은 원본을 두 형태로 가리킨다 — 수집물의 `source.blob`(객체당 하나)과, 문서가
/// 본문에 적는 sha(그림 여러 장). 색인이 **본문 쪽을 안 읽어서** 그 참조들이 없는
/// 것처럼 보였고, 같은 정의를 쓰던 `blob gc` 가 산 원본을 회수 대상으로 삼았다
/// (실측 2026-08-04: 26개 12.2 MB).
///
/// 고침은 데이터 이관이 아니라 **읽는 쪽**이다. 64자 hex 는 모호하지 않고 실재하는
/// blob 집합과 대조하므로 오탐이 없으며, `source.blob` 은 단수라 그림 여러 장을 안은
/// 문서를 애초에 담지 못한다.
@Suite struct BlobReferenceIndexTests {
    private func makeWorld() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kbw-blobrefs-\(UUID())", isDirectory: true)
    }

    private func freshIndex(_ root: URL) -> LedgerIndex {
        let index = LedgerIndex(root: root)
        index.ensureFresh(objectsDir: root.appendingPathComponent("objects"))
        return index
    }

    /// 본문에 적힌 sha 도 역참조로 잡힌다.
    @Test func bodyMentionIsIndexedAsReference() throws {
        let root = makeWorld()
        defer { try? FileManager.default.removeItem(at: root) }
        let sha = try BlobStore(root: root).put(Data("그림 바이트".utf8))
        let object = try LedgerStore(root: root).publish(
            author: "test", title: "플레이북: 그림 인용", type: "playbook",
            body: "절차 2단계 [그림1 blob: \(sha)] 를 참고한다.")

        let refs = freshIndex(root).objectsReferencing(blob: sha)
        #expect(refs.count == 1)
        #expect(refs.first?.object == object.id)
        #expect(refs.first?.via == "body")
    }

    /// 한 객체가 원본 여러 개를 인용할 수 있다 — `source.blob` 단수로는 못 담는 형태.
    @Test func oneObjectCanReferenceManyBlobs() throws {
        let root = makeWorld()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BlobStore(root: root)
        let a = try store.put(Data("그림 하나".utf8))
        let b = try store.put(Data("그림 둘".utf8))
        let c = try store.put(Data("그림 셋".utf8))
        _ = try LedgerStore(root: root).publish(
            author: "test", title: "플레이북: 그림 셋", type: "playbook",
            body: "[1 \(a)] [2 \(b)] [3 \(c)]")

        let index = freshIndex(root)
        for sha in [a, b, c] {
            #expect(index.objectsReferencing(blob: sha).count == 1, "\(sha.prefix(8)) 미도달")
        }
        #expect(index.referencedBlobSHAs().count == 3)
    }

    /// typed 와 body 를 구분해서 센다 — 성격이 다른 참조라 화면이 섞으면 안 된다.
    @Test func typedAndBodyAreCountedSeparately() throws {
        let root = makeWorld()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BlobStore(root: root)
        let captured = try store.put(Data("수집 원문".utf8))
        let figure = try store.put(Data("문서 그림".utf8))

        var provenance = Provenance()
        provenance.blob = captured
        let ledger = LedgerStore(root: root)
        _ = try ledger.publish(author: "test", title: "근거: 수집물", type: "evidence", body: "수집했다.", extras: LedgerPublishExtras(source: provenance))
        _ = try ledger.publish(author: "test", title: "플레이북: 그림", type: "playbook",
                               body: "[그림 \(figure)]")

        let counts = freshIndex(root).blobRefCounts()
        #expect(counts.typed == 1)
        #expect(counts.body == 1)
    }

    /// 아무도 안 가리키는 원본만 gc 도달 집합에서 빠진다.
    @Test func unreferencedBlobIsTheOnlyGCCandidate() throws {
        let root = makeWorld()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BlobStore(root: root)
        let kept = try store.put(Data("문서가 안는 원본".utf8))
        let orphan = try store.put(Data("아무도 안 가리키는 원본".utf8))
        _ = try LedgerStore(root: root).publish(
            author: "test", title: "플레이북: 유지", type: "playbook", body: "[\(kept)]")

        let reachable = freshIndex(root).referencedBlobSHAs()
        #expect(reachable.contains(kept))
        #expect(!reachable.contains(orphan))
    }

    /// sha 접두어로도 찾을 수 있어야 한다 — 전체 sha 를 요구해 "참조 없음"으로
    /// 오독하게 만든 게 실제 오진의 원인이었다.
    @Test func prefixResolvesToFullSHA() throws {
        let root = makeWorld()
        defer { try? FileManager.default.removeItem(at: root) }
        let sha = try BlobStore(root: root).put(Data("접두어 시험".utf8))
        _ = try LedgerStore(root: root).publish(
            author: "test", title: "플레이북: 접두어", type: "playbook", body: "[\(sha)]")

        let index = freshIndex(root)
        #expect(index.resolveBlobSHA(String(sha.prefix(8))) == sha)
        #expect(index.resolveBlobSHA("없는접두어00") == nil)
    }
}
