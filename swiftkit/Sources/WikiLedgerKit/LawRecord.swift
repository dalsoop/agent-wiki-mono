import CryptoKit
import Foundation

// ledger 3 기록 형식(직렬화·정체성)의 정본.
// 근거: docs/business-rules.md "기록 정체성과 표기", docs/standards.md "agent-law (ledger 3)".
// 엔진과 다른 앱은 이 타입을 쓴다. 필드 순서·표기를 바꾸면 기존 기록 전부가 감사에서 "코어 변조"가 된다.

/// 내용 주소 해시 — 64자 소문자 16진수 sha256. citationledgerkit `CitationLedger.sha256Hex` 와 같은 결과.
public enum LawHash {
    public static func sha256Hex(_ string: String) -> String { sha256Hex(Data(string.utf8)) }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 64자 소문자 16진수인가.
    public static func isContentID(_ s: String) -> Bool {
        s.utf8.count == 64 && s.allSatisfy { $0.isHexDigit && ($0.isNumber || $0.isLowercase) }
    }
}

/// 공포일 — ms 정밀 ISO8601 UTC(`2026-10-04T01:02:03.456Z`).
public enum LawTime {
    nonisolated(unsafe) static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public static func format(_ date: Date) -> String { formatter.string(from: date) }

    public static func parse(_ string: String) -> Date? { formatter.date(from: string) }

    /// ms 아래를 버린 시각 — 저장 표기와 같은 값.
    public static func truncatedToMilliseconds(_ date: Date) -> Date {
        parse(format(date)) ?? date
    }
}

/// `cites: <id> <rel>` 한 줄.
public struct LawCite: Sendable, Equatable, Hashable, Codable {
    public let id: String
    public let rel: String

    public init(id: String, rel: String = LawRelation.cites.rawValue) {
        self.id = id
        self.rel = rel
    }
}

/// 코어 밖 비용 기록 — 토큰 수·읽은 객체 수·세션 id. 바꿔도 id 가 변하지 않는다.
public struct LawCost: Sendable, Equatable, Codable {
    public var tokensIn: Int?
    public var tokensOut: Int?
    public var objectsRead: Int?
    public var session: String?

    public init(tokensIn: Int? = nil, tokensOut: Int? = nil, objectsRead: Int? = nil, session: String? = nil) {
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
        self.objectsRead = objectsRead
        self.session = session
    }

    public var isEmpty: Bool { tokensIn == nil && tokensOut == nil && objectsRead == nil && session == nil }

    /// `{json}` 한 줄 — 키 순서 고정(tokensIn, tokensOut, objectsRead, session), 값 없는 키는 생략.
    public var jsonLine: String? {
        var parts: [String] = []
        if let tokensIn { parts.append("\"tokensIn\":\(tokensIn)") }
        if let tokensOut { parts.append("\"tokensOut\":\(tokensOut)") }
        if let objectsRead { parts.append("\"objectsRead\":\(objectsRead)") }
        if let session, !session.isEmpty {
            let escaped = session.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            parts.append("\"session\":\"\(escaped)\"")
        }
        return parts.isEmpty ? nil : "{" + parts.joined(separator: ",") + "}"
    }

    public init?(jsonLine: String) {
        guard let data = jsonLine.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        func int(_ k: String) -> Int? { (obj[k] as? NSNumber)?.intValue }
        self.init(tokensIn: int("tokensIn"), tokensOut: int("tokensOut"),
                  objectsRead: int("objectsRead"), session: obj["session"] as? String)
        if isEmpty { return nil }
    }
}

/// ledger 3 기록 한 건(값). 필드는 저장 표기 그대로의 문자열이다 — 값 검증은 엔진의 공포 경로가 한다.
public struct LawRecord: Sendable, Equatable {
    public static let ledgerVersion = 3

    public var ledger: Int
    public var promulgated: Date
    public var author: String
    public var authorKind: String?
    public var device: String?
    public var runtime: String?
    public var runtimeVersion: String?
    public var model: String?
    public var effort: String?
    public var app: String?
    public var appVersion: String?
    public var speaker: String?
    public var title: String?
    public var type: String?
    public var origin: String?
    public var batch: String?
    public var tags: [String]
    public var cites: [LawCite]
    /// 증거물 sha256 들(`exhibit:` 줄마다 하나).
    public var exhibits: [String]
    public var amends: String?
    public var amendsAlso: [String]
    public var repeals: String?
    /// `source:` JSON 한 줄(원문 그대로).
    public var source: String?
    /// 모르는 필드 — 받은 순서의 원래 줄. 코어 맨 뒤에 그대로 둔다.
    public var unknownFields: [String]
    public var body: String
    /// 코어 밖.
    public var cost: LawCost?

    public init(
        ledger: Int = LawRecord.ledgerVersion,
        promulgated: Date,
        author: String,
        authorKind: String? = nil,
        device: String? = nil,
        runtime: String? = nil,
        runtimeVersion: String? = nil,
        model: String? = nil,
        effort: String? = nil,
        app: String? = nil,
        appVersion: String? = nil,
        speaker: String? = nil,
        title: String? = nil,
        type: String? = nil,
        origin: String? = nil,
        batch: String? = nil,
        tags: [String] = [],
        cites: [LawCite] = [],
        exhibits: [String] = [],
        amends: String? = nil,
        amendsAlso: [String] = [],
        repeals: String? = nil,
        source: String? = nil,
        unknownFields: [String] = [],
        body: String,
        cost: LawCost? = nil
    ) {
        self.ledger = ledger
        self.promulgated = promulgated
        self.author = author
        self.authorKind = authorKind
        self.device = device
        self.runtime = runtime
        self.runtimeVersion = runtimeVersion
        self.model = model
        self.effort = effort
        self.app = app
        self.appVersion = appVersion
        self.speaker = speaker
        self.title = title
        self.type = type
        self.origin = origin
        self.batch = batch
        self.tags = tags
        self.cites = cites
        self.exhibits = exhibits
        self.amends = amends
        self.amendsAlso = amendsAlso
        self.repeals = repeals
        self.source = source
        self.unknownFields = unknownFields
        self.body = body
        self.cost = cost
    }

    /// 새 기록의 표기 정규화 — 제목·태그 NFC, 본문은 그대로. 공포 경로가 id 계산 전에 부른다.
    public func nfcNormalized() -> LawRecord {
        var copy = self
        copy.title = title?.precomposedStringWithCanonicalMapping
        copy.tags = tags.map(\.precomposedStringWithCanonicalMapping)
        return copy
    }

    /// 개정·폐지 관계로 대체하는 모든 id(`amends` + `amends-also`).
    public var allAmends: [String] { (amends.map { [$0] } ?? []) + amendsAlso }

    /// 개정·원상회복·폐지 기록인가.
    public var amendsOrRepeals: Bool { amends != nil || !amendsAlso.isEmpty || repeals != nil }

    /// 코어 줄 — 순서: ledger, promulgated, author, author-kind, device, runtime, runtime-version, model,
    /// effort, app, app-version, speaker, title, type, origin, batch, tags, 각 cites, 각 exhibit, amends,
    /// 각 amends-also, repeals, source, 모르는 필드. 값 없는 필드는 줄을 쓰지 않는다.
    public func coreLines() -> [String] {
        var lines = ["ledger: \(ledger)", "promulgated: \(LawTime.format(promulgated))", "author: \(author)"]
        func add(_ key: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            lines.append("\(key): \(value)")
        }
        add("author-kind", authorKind)
        add("device", device)
        add("runtime", runtime)
        add("runtime-version", runtimeVersion)
        add("model", model)
        add("effort", effort)
        add("app", app)
        add("app-version", appVersion)
        add("speaker", speaker)
        add("title", title)
        add("type", type)
        add("origin", origin)
        add("batch", batch)
        if !tags.isEmpty { lines.append("tags: [\(tags.joined(separator: ", "))]") }
        for cite in cites { lines.append("cites: \(cite.id) \(cite.rel)") }
        for exhibit in exhibits { lines.append("exhibit: \(exhibit)") }
        add("amends", amends)
        for also in amendsAlso { lines.append("amends-also: \(also)") }
        add("repeals", repeals)
        add("source", source)
        lines.append(contentsOf: unknownFields)
        return lines
    }

    /// 해시 대상 — 코어 줄을 `\n` 으로 잇고 `\n---\n` + 본문.
    public func canonicalCore() -> String {
        coreLines().joined(separator: "\n") + "\n---\n" + body
    }

    /// id = sha256(canonicalCore).
    public func contentID() -> String { LawHash.sha256Hex(canonicalCore()) }

    /// 본문 해시(`sha256:` 줄).
    public var bodySHA256: String { LawHash.sha256Hex(body) }

    /// 파일 표기 — `---`, 머리 필드(ledger, id, promulgated, author, sha256, 나머지 코어, cost), `---`, 본문.
    /// `id` 를 주지 않으면 contentID() 를 쓴다(파싱한 기록의 저장된 id 를 그대로 다시 쓸 때만 준다).
    public func serialize(id: String? = nil) -> String {
        let core = coreLines()
        var lines = ["---", core[0], "id: \(id ?? contentID())", core[1], core[2], "sha256: \(bodySHA256)"]
        lines.append(contentsOf: core.dropFirst(3))
        if let json = cost?.jsonLine { lines.append("cost: \(json)") }
        lines.append("---")
        return lines.joined(separator: "\n") + "\n" + body
    }
}
