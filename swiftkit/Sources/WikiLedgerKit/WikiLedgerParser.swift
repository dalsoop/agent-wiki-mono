import Foundation
import GraphEngineKit

/// 원장 객체 파일(`objects/**/*.md`)을 read-only 로 파싱.
///
/// frontmatter 는 평 scalar `key: value` 와 반복 키(`cite:` 여러 줄)뿐이라 YAML
/// 라이브러리 없이 줄 단위 파싱(외부 의존성 0). 본문 `[[wikilink]]` 는 보조 엣지.
public enum WikiLedgerParser {

    public struct ParsedObject: Sendable {
        public let node: WikiNode
        public let edges: [WikiEdge]
    }

    public static func parse(url: URL, relativePath: String) -> ParsedObject? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(raw: raw, relativePath: relativePath)
    }

    public static func parse(raw: String, relativePath: String) -> ParsedObject? {
        let (frontmatter, body) = splitFrontmatter(raw)
        guard let frontmatter, let id = frontmatter["id"]?.trimmingCharacters(in: .whitespaces),
              !id.isEmpty else { return nil }

        let lines = frontmatterLinesBlock(raw)
        let rawType = (frontmatter["type"]?.trimmingCharacters(in: .whitespaces)) ?? ""
        let title = frontmatter["title"]?.trimmingCharacters(in: .whitespaces) ?? "(untitled)"
        // type 이 비었거나 unknown 이면 title 접두("결정:"/"개념:"/"근거:"...)에서 추론(#7/#41).
        let type = (rawType.isEmpty || rawType == "unknown") ? Self.inferType(from: title) : rawType
        let node = WikiNode(
            id: id,
            type: type,
            author: frontmatter["author"]?.trimmingCharacters(in: .whitespaces) ?? "unknown",
            published: frontmatter["published"]?.trimmingCharacters(in: .whitespaces) ?? "",
            title: title,
            path: relativePath
        )

        var edges: [WikiEdge] = []
        for line in lines {
            guard let (key, value) = splitKeyValue(line) else { continue }
            switch key {
            case "cite":
                let parts = value.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard let target = parts.first, !target.isEmpty else { continue }
                let rel = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : nil
                edges.append(WikiEdge(from: id, to: String(target), kind: .cite, relation: rel))
            case "supersedes", "retracts", "observes", "batch":
                let to = value.trimmingCharacters(in: .whitespaces)
                guard !to.isEmpty, let k = WikiEdgeKind(rawValue: key) else { continue }
                edges.append(WikiEdge(from: id, to: to, kind: k))
            default:
                break
            }
        }
        edges.append(contentsOf: bodyWikilinks(body: body, from: id))
        edges.append(contentsOf: instanceOfEdges(body: body, from: id))
        return ParsedObject(node: node, edges: edges)
    }

    // MARK: - type 추론

    /// title 접두어에서 type 추론(원장 객체들이 type 필드 없이 title 앞 접두로 종류 표시).
    static func inferType(from title: String) -> String {
        let lower = title.lowercased()
        let pairs: [(String, String)] = [
            ("결정:", "decision"), ("개념:", "concept"), ("엔티티:", "entity"),
            ("근거:", "evidence"), ("run:", "run"), ("선별:", "screening"),
            ("분류:", "classification"), ("체크포인트:", "checkpoint"),
            ("관찰:", "observation"), ("상충:", "contradiction"), ("개정:", "evaluation"),
            ("폐기:", "retraction"), ("재현:", "note"), ("플레이북", "playbook"),
            ("note:", "note"),
        ]
        for (prefix, t) in pairs where lower.hasPrefix(prefix) { return t }
        return "unknown"
    }

    // MARK: - frontmatter

    static func splitFrontmatter(_ raw: String) -> (frontmatter: [String: String]?, body: String) {
        var lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return (nil, raw)
        }
        lines.removeFirst()
        var fm: [String: String] = [:]
        var bodyStart = lines.count
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { bodyStart = i + 1; break }
            if let (k, v) = splitKeyValue(line) { fm[k] = v }
        }
        return (fm, lines[bodyStart...].joined(separator: "\n"))
    }

    static func frontmatterLinesBlock(_ raw: String) -> [String] {
        var lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else { return [] }
        lines.removeFirst()
        var out: [String] = []
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            out.append(line)
        }
        return out
    }

    static func splitKeyValue(_ line: String) -> (String, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        var value = trimmed[trimmed.index(after: colon)...]
        if value.first == " " { value = value.dropFirst() }
        return (key, String(value))
    }

    static func bodyWikilinks(body: String, from: String) -> [WikiEdge] {
        var edges: [WikiEdge] = []
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]\n]+)\]\]"#) else { return [] }
        let range = NSRange(body.startIndex..., in: body)
        for m in regex.matches(in: body, range: range) {
            guard let r = Range(m.range(at: 1), in: body) else { continue }
            let raw = String(body[r]).trimmingCharacters(in: .whitespaces)
            let target = raw.split(whereSeparator: { $0 == "(" || $0 == "|" }).first
                .map { String($0).trimmingCharacters(in: .whitespaces) } ?? raw
            if target.isEmpty { continue }
            edges.append(WikiEdge(from: from, to: target, kind: .wikilink))
        }
        return edges
    }

    static func instanceOfEdges(body: String, from: String) -> [WikiEdge] {
        var edges: [WikiEdge] = []
        for line in body.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.lowercased().hasPrefix("instance-of") else { continue }
            let rest = s.dropFirst("instance-of".count)
            let target = rest.split(separator: ":", maxSplits: 1).last?
                .trimmingCharacters(in: .whitespaces)
                .split(whereSeparator: { $0 == " " }).first
                .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "[]")) }
            if let target, !target.isEmpty {
                edges.append(WikiEdge(from: from, to: target, kind: .instanceOf))
            }
        }
        return edges
    }
}

/// 원장 루트를 훑어 파싱 + alias 해상으로 그래프를 빌드. 위키 도메인 인덱스.
public enum WikiLedgerIndex {

    /// `objects/**/*.md` 전체 파싱 → `[[wikilink]]` alias 를 title→id 로 해상 → 그래프.
    public static func buildGraph(root: URL) -> Graph<WikiNode, WikiEdge> {
        let objectsRoot = root.appendingPathComponent("objects")
        var nodes: [WikiNode] = []
        var rawEdges: [WikiEdge] = []
        for url in DirectoryFingerprint.files(root: objectsRoot, fileExtension: "md") {
            let rel = relative(path: url, root: root)
            guard let p = WikiLedgerParser.parse(url: url, relativePath: rel) else { continue }
            nodes.append(p.node)
            rawEdges.append(contentsOf: p.edges)
        }
        // alias 해상: wikilink 의 target(타이틀/alias)을 id 로. frontmatter id 면 그대로.
        // 같은 title 이 여러 객체면 첫 것으로 흡수.
        let titleToID = Dictionary(
            nodes.map { ($0.title.lowercased(), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        let nodeIDs = Set(nodes.map(\.id))
        let edges = rawEdges.map { e -> WikiEdge in
            if nodeIDs.contains(e.to) { return e }
            if let resolved = titleToID[e.to.lowercased()] {
                return WikiEdge(from: e.from, to: resolved, kindRaw: e.kind, relation: e.relation)
            }
            return e // dangling: 대상 노드 없음(순회에서 무시)
        }
        return Graph(nodes: nodes, edges: edges)
    }

    /// 진단용 파일 수.
    public static func objectFileCount(root: URL) -> Int {
        DirectoryFingerprint.files(root: root.appendingPathComponent("objects"), fileExtension: "md").count
    }

    static func relative(path: URL, root: URL) -> String {
        let p = path.path, r = root.path
        if p.hasPrefix(r) { return String(p.dropFirst(r.count).drop(while: { $0 == "/" })) }
        return path.lastPathComponent
    }
}
