import Foundation

public struct WorldFlagParse: Equatable, Sendable {
    public var positionals: [String]
    public var layer: String?
    public var parent: String?
    public var display: String?
    public var unknownOption: String?

    public init(
        positionals: [String] = [],
        layer: String? = nil,
        parent: String? = nil,
        display: String? = nil,
        unknownOption: String? = nil
    ) {
        self.positionals = positionals
        self.layer = layer
        self.parent = parent
        self.display = display
        self.unknownOption = unknownOption
    }
}

public enum WorldCLIFlags {
    public static func parse(_ raw: [String]) -> WorldFlagParse {
        var parsed = WorldFlagParse()
        var index = 0
        while index < raw.count {
            let token = raw[index]
            if token == "--layer", index + 1 < raw.count {
                parsed.layer = raw[index + 1]
                index += 2
                continue
            }
            if token == "--parent", index + 1 < raw.count {
                parsed.parent = raw[index + 1]
                index += 2
                continue
            }
            if token == "--display", index + 1 < raw.count {
                parsed.display = raw[index + 1]
                index += 2
                continue
            }
            if token.hasPrefix("--") {
                parsed.unknownOption = token
                return parsed
            }
            parsed.positionals.append(token)
            index += 1
        }
        return parsed
    }
}

public enum WorldPublishCiteIDs {
    public static func extract(from arguments: [String]) -> [String] {
        var ids: [String] = []
        var rest = Array(arguments.dropFirst())
        while let index = rest.firstIndex(where: { $0.hasPrefix("--") }) {
            let flag = rest[index]
            if flag == "--allow-unclassified" {
                rest.removeSubrange(index..<(index + 1))
                continue
            }
            guard rest.count > index + 1 else { break }
            var consumed = 2
            if flag == "--cite" {
                ids.append(rest[index + 1])
                if rest.count > index + 2, !rest[index + 2].hasPrefix("--") {
                    consumed = 3
                }
            }
            rest.removeSubrange(index..<(index + consumed))
        }
        return ids
    }
}

public struct WorldScopedSearchParse: Equatable, Sendable {
    public var queryText: String
    public var domainFilter: String?
    public var kindFilter: String?
    public var knowledgeFilter: String?
    public var limit: Int
    public var asJSON: Bool

    public init(
        queryText: String = "",
        domainFilter: String? = nil,
        kindFilter: String? = nil,
        knowledgeFilter: String? = nil,
        limit: Int = 8,
        asJSON: Bool = false
    ) {
        self.queryText = queryText
        self.domainFilter = domainFilter
        self.kindFilter = kindFilter
        self.knowledgeFilter = knowledgeFilter
        self.limit = limit
        self.asJSON = asJSON
    }
}

public enum WorldScopedSearchArgs {
    public static func parse(_ arguments: [String]) -> WorldScopedSearchParse {
        var query: [String] = []
        var parsed = WorldScopedSearchParse()
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--domain": index += 1; parsed.domainFilter = arguments[index]
            case "--kind": index += 1; parsed.kindFilter = arguments[index]
            case "--knowledge": index += 1; parsed.knowledgeFilter = arguments[index]
            case "--limit": index += 1; parsed.limit = Int(arguments[index]) ?? 8
            case "--json": parsed.asJSON = true
            default: query.append(arguments[index])
            }
            index += 1
        }
        parsed.queryText = query.joined(separator: " ")
        return parsed
    }
}

public struct WorldScopedPublishFields: Equatable, Sendable {
    public var title: String?
    public var typeField: String?
    public var origin: String?
    public var tags: [String]
    public var aliases: [String]
    public var cites: [LedgerObject.Cite]
    public var observes: [String]
    public var supersedes: String?
    public var retracts: String?
    /// scene-evidence 역링크 대상 결정 객체 id (`--of`).
    public var ofDecision: String?
    public var unknownOption: String?

    public init(
        title: String? = nil,
        typeField: String? = nil,
        origin: String? = nil,
        tags: [String] = [],
        aliases: [String] = [],
        cites: [LedgerObject.Cite] = [],
        observes: [String] = [],
        supersedes: String? = nil,
        retracts: String? = nil,
        ofDecision: String? = nil,
        unknownOption: String? = nil
    ) {
        self.title = title
        self.typeField = typeField
        self.origin = origin
        self.tags = tags
        self.aliases = aliases
        self.cites = cites
        self.observes = observes
        self.supersedes = supersedes
        self.retracts = retracts
        self.ofDecision = ofDecision
        self.unknownOption = unknownOption
    }
}

public enum WorldScopedPublishArgs {
    public static func parse(_ arguments: [String]) -> WorldScopedPublishFields {
        var fields = WorldScopedPublishFields()
        var rest = Array(arguments.dropFirst())
        while let index = rest.firstIndex(where: { $0.hasPrefix("--") }) {
            let flag = rest[index]
            if flag == "--allow-unclassified" {
                rest.removeSubrange(index..<(index + 1))
                continue
            }
            guard rest.count > index + 1 else { return fields }
            let value = rest[index + 1]
            var consumed = 2
            switch flag {
            case "--title": fields.title = value
            case "--type": fields.typeField = value
            case "--origin": fields.origin = value
            case "--tag": fields.tags.append(value)
            case "--alias": fields.aliases.append(value)
            case "--observes": fields.observes.append(value)
            case "--supersedes": fields.supersedes = value
            case "--retracts": fields.retracts = value
            case "--of": fields.ofDecision = value
            case "--batch": break
            case "--kind":
                // `--kind scene-evidence` 는 3축 분류 kind 가 아니라 객체 종류다(--type 과 동의).
                if value == PublishCompleteness.sceneEvidenceType { fields.typeField = value }
            case "--domain", "--knowledge", "--classification-reason": break
            case "--cite":
                if rest.count > index + 2, !rest[index + 2].hasPrefix("--") {
                    fields.cites.append(.init(id: value, rel: rest[index + 2]))
                    consumed = 3
                } else {
                    fields.cites.append(.init(id: value, rel: "cites"))
                }
            default:
                fields.unknownOption = flag
                return fields
            }
            rest.removeSubrange(index..<(index + consumed))
        }
        return fields
    }
}
