import Foundation

/// ledger 3 파일 파서 — 파서 정본은 이것 하나다(docs/standards.md "agent-law (ledger 3)").
/// `serialize()` 의 역. 저장된 `id`·`sha256` 은 따로 돌려주고, 무결성 판정(재해시)은 감사가 한다.
public enum LawRecordParser {

    public struct Parsed: Sendable, Equatable {
        public let storedID: String
        public let storedSHA256: String
        public let record: LawRecord
        /// `cost:` 줄이 있었지만 읽지 못한 이유(cost 는 코어 밖이라 기록은 그대로 읽힌다). 없으면 nil.
        public let costDecodeError: LawCostDecodeError?
    }

    static let singleKeys: Set<String> = [
        "ledger", "id", "promulgated", "author", "sha256", "author-kind", "device", "runtime",
        "runtime-version", "model", "effort", "app", "app-version", "speaker", "title", "type",
        "origin", "batch", "tags", "amends", "repeals", "source", "cost",
    ]

    /// ledger 3 파일이 아니거나 필수 필드(`ledger: 3`, `id`, `promulgated`, `author`, `sha256`)가 없거나
    /// 같은 단일 필드가 두 번 나오면 nil.
    public static func parse(_ text: String) -> Parsed? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first == "---", let closing = lines.dropFirst().firstIndex(of: "---") else { return nil }

        var fields: [String: String] = [:]
        var cites: [LawCite] = []
        var exhibits: [String] = []
        var amendsAlso: [String] = []
        var unknown: [String] = []
        for line in lines[1..<closing] {
            guard let colon = line.firstIndex(of: ":") else {
                if !line.trimmingCharacters(in: .whitespaces).isEmpty { unknown.append(line) }
                continue
            }
            let key = String(line[..<colon])
            var value = Substring(line[line.index(after: colon)...])
            if value.first == " " { value = value.dropFirst() }
            let v = String(value)
            switch key {
            case "cites":
                let parts = v.split(separator: " ", maxSplits: 1).map(String.init)
                guard let id = parts.first, parts.count == 2 else { return nil }
                cites.append(LawCite(id: id, rel: parts[1]))
            case "exhibit":
                exhibits.append(v)
            case "amends-also":
                amendsAlso.append(v)
            default:
                if singleKeys.contains(key) {
                    guard fields[key] == nil else { return nil }
                    fields[key] = v
                } else {
                    unknown.append(line)
                }
            }
        }
        guard fields["ledger"] == String(LawRecord.ledgerVersion),
              let id = fields["id"], !id.isEmpty,
              let promulgatedRaw = fields["promulgated"], let promulgated = LawTime.parse(promulgatedRaw),
              let author = fields["author"], !author.isEmpty,
              let sha = fields["sha256"] else { return nil }

        var tags: [String] = []
        if let raw = fields["tags"] {
            guard raw.hasPrefix("["), raw.hasSuffix("]") else { return nil }
            let inner = raw.dropFirst().dropLast()
            tags = inner.isEmpty ? [] : inner.components(separatedBy: ", ")
        }
        var cost: LawCost?
        var costDecodeError: LawCostDecodeError?
        if let raw = fields["cost"] {
            switch LawCost.decode(jsonLine: raw) {
            case .success(let decoded): cost = decoded
            case .failure(let error): costDecodeError = error
            }
        }

        let body = lines[(closing + 1)...].joined(separator: "\n")
        let authorship = LawAuthorship(
            authorKind: fields["author-kind"], device: fields["device"], runtime: fields["runtime"],
            runtimeVersion: fields["runtime-version"], model: fields["model"], effort: fields["effort"],
            app: fields["app"], appVersion: fields["app-version"], speaker: fields["speaker"])
        let relations = LawRelations(
            cites: cites, exhibits: exhibits, amends: fields["amends"], amendsAlso: amendsAlso,
            repeals: fields["repeals"])
        let record = LawRecord(
            promulgated: promulgated, author: author, authorship: authorship,
            title: fields["title"], type: fields["type"], origin: fields["origin"], batch: fields["batch"],
            tags: tags, relations: relations, source: fields["source"], unknownFields: unknown,
            body: body, cost: cost)
        return Parsed(storedID: id, storedSHA256: sha, record: record, costDecodeError: costDecodeError)
    }

    /// 파일 머리 필드에서 `ledger:` 값만 빠르게 본다(ledger 1·2·3 분기용). 없으면 nil.
    public static func ledgerVersion(of text: String) -> Int? {
        for line in text.split(separator: "\n", maxSplits: 4, omittingEmptySubsequences: false).dropFirst() {
            if line.hasPrefix("ledger: ") { return Int(line.dropFirst(8)) }
            if line == "---" { break }
        }
        return nil
    }
}
