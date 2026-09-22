import FileBrowserKit
import Foundation

/// 위키 층(개념·엔티티·색인)을 Google OKF v0.1 번들로 렌더한다.
/// 예약 파일: index.md(색인 + 전체 목록), log.md(체크포인트 이력).
public enum OKFExporter {
    public static func export(objects: [LedgerObject], heads: [LedgerObject], to outRoot: URL) throws -> String {
        func slug(_ title: String) -> String {
            let base = title.precomposedStringWithCanonicalMapping
                .replacingOccurrences(of: "개념: ", with: "")
                .replacingOccurrences(of: "엔티티: ", with: "")
            let allowed = base.map { char -> Character in
                char.isLetter || char.isNumber ? char : "-"
            }
            return String(allowed).split(separator: "-").joined(separator: "-").lowercased()
        }
        func yamlEscape(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        var pathOf: [String: String] = [:]
        var exports: [(object: LedgerObject, path: String, okfType: String)] = []
        for head in heads {
            switch head.effectiveType {
            case "concept":
                let path = "concepts/\(slug(head.title ?? head.id)).md"
                pathOf[head.id] = path
                exports.append((head, path, "Concept"))
            case "entity":
                let path = "entities/\(slug(head.title ?? head.id)).md"
                pathOf[head.id] = path
                exports.append((head, path, "Entity"))
            default: continue
            }
        }
        for (object, path, okfType) in exports {
            let url = outRoot.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var lines = ["---", "type: \(okfType)"]
            if let title = object.title {
                lines.append("title: \(yamlEscape(title.precomposedStringWithCanonicalMapping))")
            }
            lines.append("timestamp: \(LedgerObject.iso.string(from: object.published))")
            if !object.tags.isEmpty {
                lines.append("tags: [\(object.tags.joined(separator: ", "))]")
            }
            lines.append("resource: memo-citation-ledger://\(object.id)")
            lines.append("---")
            var body = object.body
            let linked = object.cites.compactMap { cite -> String? in
                guard let target = pathOf[cite.id] else { return nil }
                let citedTitle = heads.first { $0.id == cite.id }?.title ?? cite.id
                return "- [\(citedTitle.precomposedStringWithCanonicalMapping)](/\(target)) (\(cite.rel))"
            }
            if !linked.isEmpty {
                body += "\n\n## 관련 개념\n\n" + linked.joined(separator: "\n")
            }
            try Data((lines.joined(separator: "\n") + "\n" + body + "\n").utf8).write(to: url)
            // slug() 가 NFC 로 정규화해도 `appendingPathComponent` 가 syscall 직전에
            // 다시 NFD 로 되돌린다 — Foundation 경로 API 로는 NFC 파일명을 만들 수
            // 없다(실측 확인). 번들을 zip·git 으로 옮기면 리눅스에서 자소분리로
            // 보이므로, 쓴 직후 POSIX rename(2) 로 디스크 바이트를 NFC 로 고친다.
            // 실패하면 nil 을 돌려주고 넘어간다 — 파일 내용은 이미 정상이다.
            _ = HangulNFCFilename.renameToNFC(url)
        }
        var index = "# 색인\n\n"
        if let indexObject = heads.first(where: { $0.effectiveType == "index" }) {
            index += indexObject.body + "\n\n"
        }
        index += "## 전체 목록\n\n"
        for (object, path, _) in exports.sorted(by: { $0.path < $1.path }) {
            index += "- [\((object.title ?? object.id).precomposedStringWithCanonicalMapping)](/\(path))\n"
        }
        try Data(index.utf8).write(to: outRoot.appendingPathComponent("index.md"))
        var log = "# 변경 이력 (체크포인트)\n\n"
        for checkpoint in objects.filter({ $0.effectiveType == "checkpoint" }).sorted(by: { ($0.published, $0.id) > ($1.published, $1.id) }) {
            log += "- \(LedgerObject.iso.string(from: checkpoint.published)) — \((checkpoint.title ?? "").precomposedStringWithCanonicalMapping)\n"
        }
        try Data(log.utf8).write(to: outRoot.appendingPathComponent("log.md"))
        let concepts = exports.filter { $0.okfType == "Concept" }.count
        let entities = exports.filter { $0.okfType == "Entity" }.count
        return "OKF 번들: \(outRoot.path) — 개념 \(concepts), 엔티티 \(entities), index.md, log.md"
    }
}
