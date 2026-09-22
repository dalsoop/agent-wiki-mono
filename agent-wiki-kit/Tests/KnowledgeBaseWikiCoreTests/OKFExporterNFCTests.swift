import CitationLedgerKit
import Darwin
import Foundation
import Testing

@testable import KnowledgeBaseWikiCore

/// OKF 번들 파일명이 디스크에 **NFC 바이트로** 떨어지는지 회귀 검증.
///
/// Foundation 으로는 이걸 검사할 수 없다. `contentsOfDirectory` 든 `URL` 이든
/// 파일명을 String 으로 돌려주는 순간 NFD 로 분해되고, Swift 의 `String ==` 는
/// 정규화 동등성으로 비교해서 NFC/NFD 를 같다고 판정한다. 그래서 `readdir(3)`
/// 로 raw 바이트를 직접 읽어 UTF-8 시퀀스를 비교한다.
@Suite struct OKFExportNFCTests {
    /// `readdir(3)` 로 디렉터리 엔트리의 파일명 raw 바이트를 그대로 읽는다.
    private func rawEntryNames(_ dir: URL) -> [[UInt8]] {
        guard let handle = opendir(dir.path) else { return [] }
        defer { closedir(handle) }
        var names: [[UInt8]] = []
        while let entry = readdir(handle) {
            var bytes: [UInt8] = []
            withUnsafeBytes(of: entry.pointee.d_name) { buffer in
                bytes.append(contentsOf: buffer.prefix(Int(entry.pointee.d_namlen)))
            }
            let name = String(decoding: bytes, as: UTF8.self)
            guard name != ".", name != ".." else { continue }
            names.append(bytes)
        }
        return names
    }

    @Test func exportedHangulFilenamesAreNFCOnDisk() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("okf-nfc-\(UUID())")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("okf-nfc-out-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: out) }

        let store = LedgerStore(root: root)
        _ = try store.publish(
            author: "wiki-maintainer", title: "개념: 한글파일명정규화", type: "concept", body: "내용")
        let objects = store.scan()
        _ = try OKFExporter.export(objects: objects, heads: store.heads(objects), to: out)

        let names = rawEntryNames(out.appendingPathComponent("concepts"))
        #expect(names.count == 1)

        let raw = try #require(names.first)
        let decoded = String(decoding: raw, as: UTF8.self)
        let nfc = Array(decoded.precomposedStringWithCanonicalMapping.utf8)

        // 실패하면 `HangulNFCFilename.renameToNFC` 호출이 빠진 것이다 —
        // `appendingPathComponent` 가 NFC 슬러그를 syscall 직전에 되돌린다.
        #expect(
            raw == nfc,
            """
            파일명이 디스크에 NFD 로 떨어졌다. \
            실제=\(raw.map { String(format: "%02x", $0) }.joined()) \
            기대=\(nfc.map { String(format: "%02x", $0) }.joined())
            """)
        #expect(decoded.contains("한글파일명정규화"))
    }
}
