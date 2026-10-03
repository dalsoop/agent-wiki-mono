import Foundation
import KnowledgeBaseWikiCore
import SwiftUI

// 위키 전용 모델 — 섹션 분할·include·정보상자·내부링크·둘러보기.
extension LedgerModel {
    /// 위키 내부 링크 — 제목(개념/엔티티/근거)으로 문서를 찾아 점프.
    /// 둘러보기 — 태그(분류)를 공유하는 형제 위키 문서 (자신 제외).
    func siblingWikiPages(of document: LedgerDocument, limit: Int = 12) -> [LedgerDocument] {
        let tags = Set(document.head.tags).subtracting(["entity"])
        guard !tags.isEmpty else { return [] }
        return wikiDocuments
            .filter { $0.id != document.id && !Set($0.head.tags).isDisjoint(with: tags) }
            .sorted { $0.title < $1.title }
            .prefix(limit).map { $0 }
    }

    /// 위키 본문을 섹션 블록으로 분할 — heading 마다 새 블록(앞부분은 서문 블록).
    struct WikiSection: Identifiable {
        let index: Int
        let heading: String?     // "## 등장 맥락" 원문 (서문이면 nil)
        let headingText: String  // "등장 맥락" (번호·마크 제거)
        let number: String       // "1" / "2.1" (전역 번호, 서문이면 "")
        let level: Int           // 1/2/3 (서문이면 0)
        let anchor: String       // "sec-N"
        let raw: String          // heading + 본문 원문 (편집 단위)
        let bodyWithoutHeading: String  // 렌더용 (heading 줄 제외)
        var id: Int { index }
    }

    func wikiSections(_ body: String) -> [WikiSection] {
        let stripped = strippedForSections(body)
        var sections: [WikiSection] = []
        var current: [String] = []
        var currentHeading: String?
        var idx = 0
        var counters = [0, 0, 0]
        var headingIdx = 0
        func flush() {
            let raw = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty && currentHeading == nil { return }
            var number = "", level = 0, headingText = "", anchor = ""
            if let h = currentHeading {
                let t = h.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("### ") { level = 3; headingText = String(t.dropFirst(4)) }
                else if t.hasPrefix("## ") { level = 2; headingText = String(t.dropFirst(3)) }
                else { level = 1; headingText = String(t.dropFirst(2)) }
                counters[level - 1] += 1
                for d in level..<3 { counters[d] = 0 }
                number = counters.prefix(level).filter { $0 > 0 }.map(String.init).joined(separator: ".")
                anchor = "sec-\(headingIdx)"; headingIdx += 1
            }
            let bodyOnly = currentHeading == nil ? raw
                : current.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            sections.append(WikiSection(index: idx, heading: currentHeading, headingText: headingText,
                                        number: number, level: level, anchor: anchor,
                                        raw: raw, bodyWithoutHeading: bodyOnly))
            idx += 1; current = []; currentHeading = nil
        }
        for line in stripped.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("# ") || t.hasPrefix("## ") || t.hasPrefix("### ") {
                flush()
                currentHeading = t
                current = [line]
            } else {
                current.append(line)
            }
        }
        flush()
        return sections
    }

    private func strippedForSections(_ body: String) -> String {
        var lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let first = lines.first, first.hasPrefix("개정 사유:") {
            lines.removeFirst()
            while let h = lines.first, h.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        }
        return lines.joined(separator: "\n")
    }

    /// 한 섹션만 편집 → 전체 본문 재조립 후 개정판 발행 (append-only 유지).
    func editWikiSection(_ document: LedgerDocument, index: Int, newRaw: String, reason: String) {
        var raws = wikiSections(document.head.body).map(\.raw)
        guard index < raws.count else { return }
        raws[index] = newRaw
        let body = "개정 사유: \(reason)\n\n" + raws.joined(separator: "\n\n")
        do {
            if isLedgerThreeWorld {
                _ = try performEdit(.amend(
                    target: document.head.id, title: document.head.title, body: body, cites: document.head.cites))
            } else {
                guard let store = legacyWritableStore() else { return }
                _ = try store.publish(
                    author: "human", title: document.head.title, type: document.head.effectiveType,
                    body: body, supersedes: document.head.id,
                    origin: document.head.origin, tags: document.head.tags)
            }
            refresh()
        } catch { errorMessage = "섹션 편집 실패: \(error)" }
    }

    /// 본문에서 정보상자(:::정보상자 … :::) 를 추출 — 우측 열에 렌더. (본문에서는 제거)
    struct Infobox { let title: String; let image: String?; let pairs: [(String, String)] }
    func extractInfobox(_ body: String) -> (box: Infobox?, bodyWithout: String) {
        var lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        var box: Infobox?
        var i = 0
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.hasPrefix(":::") && box == nil {
                let title = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var pairs: [(String, String)] = []
                var image: String?
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(":::") {
                    let row = lines[i].trimmingCharacters(in: .whitespaces)
                    let parts = row.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    if parts.count == 2 {
                        if parts[0] == "이미지" { image = parts[1] } else { pairs.append((parts[0], parts[1])) }
                    }
                    i += 1
                }
                box = Infobox(title: title.isEmpty ? "정보" : title, image: image, pairs: pairs)
                i += 1
                continue
            }
            out.append(lines[i]); i += 1
        }
        return (box, out.joined(separator: "\n"))
    }

    /// [include(제목)] transclusion — 대상 문서 본문을 끌어와 재귀 확장.
    /// openNAMU 방식 루프 방어: 순환(seen) + 깊이(max 3) + 총 확장수 상한.
    func expandIncludes(_ body: String, seen: Set<String> = [], depth: Int = 0) -> String {
        guard depth < 3 else { return body }
        let pattern = #"\[include\(([^)]+)\)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return body }
        let ns = body as NSString
        let matches = regex.matches(in: body, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return body }
        var result = body
        for match in matches.reversed() {
            // [include(제목, key=값, key2=값2)] — 첫 인자=제목, 나머지=매개변수(틀)
            let raw = ns.substring(with: match.range(at: 1))
            let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let title = parts.first ?? ""
            var params: [String: String] = [:]
            for arg in parts.dropFirst() {
                let kv = arg.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if kv.count == 2 { params[kv[0]] = kv[1] }
            }
            let full = match.range(at: 0)
            let replacement: String
            if seen.contains(title) {
                replacement = "> ⚠ include 순환 감지: \(title)"
            } else if let doc = wikiDocumentByTitle(title) {
                var inner = strippedForSections(doc.head.body)
                // 매개변수 치환: @key@ → 값 (틀 문서의 자리표시자)
                for (key, value) in params {
                    inner = inner.replacingOccurrences(of: "@\(key)@", with: value)
                }
                let expanded = expandIncludes(inner, seen: seen.union([title]), depth: depth + 1)
                replacement = "> ⊃ 포함: [[\(title)]]\n\n\(expanded)"
            } else {
                replacement = "> ⚠ 없는 문서 포함: [[\(title)]]"
            }
            result = (result as NSString).replacingCharacters(in: full, with: replacement)
        }
        return result
    }

    private func wikiDocumentByTitle(_ title: String) -> LedgerDocument? {
        let target = title.precomposedStringWithCanonicalMapping
        return wikiDocuments.first { d in
            let t = d.title.precomposedStringWithCanonicalMapping
            return t == target || t == "개념: \(target)" || t == "엔티티: \(target)"
        }
    }

    /// [[제목]] 이 실제 문서로 해석되는지 (없으면 빨간 링크).
    func wikiLinkExists(_ title: String) -> Bool {
        let target = title.precomposedStringWithCanonicalMapping
        return objects.contains { o in
            guard let t = o.title?.precomposedStringWithCanonicalMapping else { return false }
            return t == target || t == "개념: \(target)" || t == "엔티티: \(target)" || t == "근거: \(target)"
        }
    }

    func jumpToTitle(_ title: String) {
        let target = title.precomposedStringWithCanonicalMapping
        let candidates = objects.filter { object in
            guard let t = object.title?.precomposedStringWithCanonicalMapping else { return false }
            return t == target || t == "개념: \(target)" || t == "엔티티: \(target)" || t == "근거: \(target)"
        }
        if let hit = candidates.min(by: { ($0.published, $0.id) > ($1.published, $1.id) }) { jump(toObject: hit.id) }
    }
}
