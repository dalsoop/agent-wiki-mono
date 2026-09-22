import Foundation
import Testing

@testable import KnowledgeBaseWikiCore

/// 봉인된 원문이 검색에 닿는다는 계약.
///
/// 원장은 원문을 blob 으로 봉인하지만(정본·불변), 그 내용은 어디에도 색인되지 않았다.
/// 그래서 "저장은 됐는데 아무도 못 찾는" 상태가 구조적으로 존재했다 — 실측
/// 2026-08-04: 텍스트 blob 8개 전부 검색 도달 0.
///
/// 객체는 사람이 쓴 해석이고 blob 은 날것이라, 원문에만 있는 표현(로그 한 줄,
/// 녹취 문장)은 객체 본문 어디에도 없다. 그걸 못 찾으면 원문을 보관한 의미가 없다.
@Suite struct BlobContentSearchTests {
    private func makeWorld() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kbw-blobfts-\(UUID())", isDirectory: true)
    }

    /// 객체에는 없고 원문에만 있는 말로 찾을 수 있어야 한다.
    @Test func textBlobContentIsSearchable() throws {
        let root = makeWorld()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try LedgerStore(root: root).publish(
            author: "test", title: "근거: 배포 회고", type: "evidence",
            body: "배포는 성공했다.")   // 아래 원문의 표현은 여기 없다
        let sha = try BlobStore(root: root).put(
            Data("=== run stdout ===\n압축 해제 실패 코드 137 · OOM killer\n".utf8))

        let index = LedgerIndex(root: root)
        _ = index.sync(objectsDir: root.appendingPathComponent("objects"))
        _ = index.syncBlobs(root: root)

        let hits = index.searchBlobs("OOM killer")
        #expect(hits.contains { $0.sha == sha })
        #expect(hits.first?.kind == "텍스트")
        #expect(!(hits.first?.snippet.isEmpty ?? true))
        // 객체 검색으로는 안 잡힌다 — 표를 나눠 두는 이유.
        #expect(index.search("OOM killer").isEmpty)
    }

    /// 바이너리 원본은 색인하지 않는다 — 본문이 없어 fts 만 부풀린다.
    @Test func binaryBlobIsRecordedButNotIndexed() throws {
        let root = makeWorld()
        defer { try? FileManager.default.removeItem(at: root) }
        // PNG 매직 바이트
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        png.append(Data(repeating: 0x00, count: 64))
        let sha = try BlobStore(root: root).put(png)

        let index = LedgerIndex(root: root)
        _ = index.syncBlobs(root: root)

        #expect(index.blobRowCount() == 1)       // 종류는 기록한다
        #expect(!index.ftsContains(id: sha))     // 내용은 색인하지 않는다
    }

    /// 새로 봉인한 원본은 다음 조회에서 저절로 색인돼야 한다(수동 rebuild 요구 금지).
    @Test func ensureFreshPicksUpNewBlobs() throws {
        let root = makeWorld()
        defer { try? FileManager.default.removeItem(at: root) }
        let objectsDir = root.appendingPathComponent("objects")
        _ = try LedgerStore(root: root).publish(
            author: "test", title: "근거: 기준선", type: "evidence", body: "본문")
        let index = LedgerIndex(root: root)
        index.ensureFresh(objectsDir: objectsDir)
        #expect(index.blobRowCount() == 0)

        let sha = try BlobStore(root: root).put(Data("나중에 봉인한 원문 · 격리검증토큰".utf8))
        #expect(index.blobIndexIsStale(root: root))

        index.ensureFresh(objectsDir: objectsDir)
        #expect(index.searchBlobs("격리검증토큰").contains { $0.sha == sha })
    }

    /// blob 행이 객체 색인율을 부풀리면 구조 진단이 거짓말을 한다.
    @Test func blobRowsDoNotInflateObjectCoverage() throws {
        let root = makeWorld()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try LedgerStore(root: root).publish(
            author: "test", title: "근거: 하나", type: "evidence", body: "본문")
        _ = try BlobStore(root: root).put(Data("원문 텍스트".utf8))

        let index = LedgerIndex(root: root)
        _ = index.sync(objectsDir: root.appendingPathComponent("objects"))
        _ = index.syncBlobs(root: root)

        #expect(index.ftsRowCount() == 2)         // 객체 1 + blob 1
        #expect(index.ftsObjectRowCount() == 1)   // 객체만
        let structure = LedgerStructure(root: root)
        let objectFTS = try #require(structure.edges.first { $0.id == "object-fts" })
        #expect(objectFTS.actual == 1)
        #expect(objectFTS.status == .satisfied)
    }
}
