import Foundation

/// 파일 기반 원장(KBW `.wiki/objects/` 등)에서 id 를 조회한다.
/// forge(refs/meta/forge 사이드 ref) 가 KBW 위키 결정을 교차 cite 할 때, 그 대상이
/// 실제 존재하는 발행물인지(= dangling 아님) 확인하는 데 쓴다.
///
/// forge 자신의 저장소는 git ref 라 파일이 아니므로 이 유틸이 아니라 MetaLedger.find 를 쓴다.
/// 이 유틸은 오직 "작업 트리에 objects/ 파일로 풀린 원장"(KBW world) 대상이다.
public enum LedgerLookup {

    /// `<objectsDir>` 아래(연/월 샤딩 무관) `<id>.md` 파일이 있으면 그 URL, 없으면 nil.
    /// id 접두어가 아니라 **완전 일치**만 — 교차 cite 는 정확한 content-address 를 요구한다.
    public static func objectURL(id: String, inObjectsDir objectsDir: URL) -> URL? {
        let needle = "\(id).md"
        guard let e = FileManager.default.enumerator(
            at: objectsDir, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in e where url.lastPathComponent == needle {
            return url
        }
        return nil
    }

    /// `<objectsDir>` 에 id 가 존재하는가.
    public static func exists(id: String, inObjectsDir objectsDir: URL) -> Bool {
        objectURL(id: id, inObjectsDir: objectsDir) != nil
    }

    /// 교차 cite 대상의 **현재 상태** — 존재만이 아니라 철회·개정됐는지까지.
    /// 파일 원장을 훑어 다른 객체가 이 id 를 `retracts:`/`supersedes:` 하는지 본다.
    /// (append-only 라 원본 파일은 남지만, 나중에 철회/개정 객체가 발행됐을 수 있다.)
    public static func status(id: String, inObjectsDir objectsDir: URL) -> Status {
        guard exists(id: id, inObjectsDir: objectsDir) else { return .missing }
        guard let e = FileManager.default.enumerator(
            at: objectsDir, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]) else { return .head }
        for case let url as URL in e where url.pathExtension == "md" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            // frontmatter 구간(첫 --- 과 닫는 --- 사이)만 훑는다 — 본문의 우연한 매치 방지.
            guard lines.first == "---",
                let close = lines.dropFirst().firstIndex(of: "---") else { continue }
            for line in lines[1..<close] {
                if line.hasPrefix("supersedes:"),
                    line.dropFirst("supersedes:".count).trimmingCharacters(in: .whitespaces) == id {
                    return .superseded(by: objectID(of: url))
                }
                if line.hasPrefix("retracts:"),
                    line.dropFirst("retracts:".count).trimmingCharacters(in: .whitespaces) == id {
                    return .retracted(by: objectID(of: url))
                }
            }
        }
        return .head
    }

    private static func objectID(of url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    /// 파일 원장 객체의 현재 상태.
    public enum Status: Equatable {
        case head                    // 존재 + 최신(철회·개정 안 됨)
        case superseded(by: String)  // 다른 객체가 개정함
        case retracted(by: String)   // 다른 객체가 철회함
        case missing                 // 원장에 없음(dangling)
    }
}
