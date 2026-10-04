import Foundation

/// 본문 머리 칸 — 유형별 추가 칸. 본문 첫 줄부터 빈 줄 전까지 `키: 값`.
/// 근거: docs/business-rules.md "본문 머리 칸". 키 목록과 파서는 여기 하나뿐이다.
public struct LawHeadFieldBlock: Sendable, Equatable {
    /// 받은 순서의 (키, 값).
    public let entries: [(key: String, value: String)]

    public init(entries: [(key: String, value: String)]) { self.entries = entries }

    public var keys: [String] { entries.map(\.key) }

    public subscript(key: String) -> String? {
        entries.first(where: { $0.key == key })?.value
    }

    public static let empty = LawHeadFieldBlock(entries: [])

    public static func == (lhs: LawHeadFieldBlock, rhs: LawHeadFieldBlock) -> Bool {
        lhs.entries.map { [$0.key, $0.value] } == rhs.entries.map { [$0.key, $0.value] }
    }
}

public enum LawHeadFieldError: Error, Equatable, CustomStringConvertible {
    case malformedLine(String)
    case keyNotAllowed(type: String, key: String)
    case duplicateKey(String)
    case missingKey(type: String, key: String)
    case emptyValue(String)
    case valueNotAllowed(key: String, value: String)

    public var description: String {
        switch self {
        case .malformedLine(let l): return "본문 머리 칸 형식 오류: \(l)"
        case .keyNotAllowed(let t, let k): return "유형 \(t) 에 허용되지 않은 머리 칸: \(k)"
        case .duplicateKey(let k): return "머리 칸 중복: \(k)"
        case .missingKey(let t, let k): return "유형 \(t) 의 머리 칸 \(k) 가 없음"
        case .emptyValue(let k): return "머리 칸 \(k) 가 비었음"
        case .valueNotAllowed(let k, let v): return "머리 칸 \(k) 의 값 \(v) 는 허용되지 않음"
        }
    }
}

public enum LawHeadFields {
    /// 유형별 허용 키(정의 순서). 이 표에 없는 유형은 머리 칸이 없다.
    public static let keysByType: [LawRecordType: [String]] = [
        .finding: ["subject", "certainty", "effective-from", "effective-until", "domain", "reason"],
        .ruling: ["level", "outcome"],
        .registration: ["repo", "status", "path"],
        .proposal: ["scope"],
        .redaction: ["target", "reason"],
        .evidence: ["session", "utterance-at", "runtime", "device"],
    ]

    /// 반드시 있어야 하는 키. `finding` 의 `reason` 은 비면 거부(business-rules), 나머지는
    /// 명령 계약(docs/contracts.md `finding`·`judgment register`)의 필수 인자와 결정의 성립 요소다.
    static let requiredKeysByType: [LawRecordType: [String]] = [
        .finding: ["subject", "certainty", "domain", "reason"],
        .ruling: ["level", "outcome"],
        .registration: ["repo", "status"],
    ]

    /// 값 집합이 정해진 키 — 값 집합은 LawVocabulary 의 열거형에서 온다.
    static func allowedValues(type: LawRecordType, key: String) -> Set<String>? {
        func raws<E: CaseIterable & RawRepresentable>(_: E.Type) -> Set<String> where E.RawValue == String {
            Set(E.allCases.map(\.rawValue))
        }
        switch (type, key) {
        case (.finding, "subject"): return raws(LawSubject.self)
        case (.finding, "certainty"): return raws(LawCertainty.self)
        case (.finding, "domain"): return raws(LawDomain.self)
        case (.ruling, "level"): return raws(LawRulingLevel.self)
        case (.ruling, "outcome"): return raws(LawRulingOutcome.self)
        case (.registration, "status"): return raws(LawRegistrationStatus.self)
        case (.evidence, "runtime"): return raws(LawRuntime.self)
        default: return nil
        }
    }

    /// 비울 수 있는 키(빈 값 허용).
    static let emptyAllowedKeys: Set<String> = ["effective-from", "effective-until", "path"]

    /// 본문의 머리 칸을 읽는다. 머리 칸이 없는 유형(지식 기록 등)과 모르는 유형은 빈 블록.
    /// 첫 줄이 `키: 값` 꼴(소문자·숫자·하이픈 키)이 아니면 머리 칸이 없는 것이다.
    /// 머리 칸 블록 안의 줄은 모두 허용 키의 `키: 값` 이어야 한다.
    public static func parse(body: String, type: String?) throws -> LawHeadFieldBlock {
        guard let type = type.flatMap(LawRecordType.init(rawValue:)),
              let allowed = keysByType[type] else { return .empty }
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first, splitKeyValue(first) != nil else {
            try checkRequired(type: type, entries: [])
            return .empty
        }
        var entries: [(key: String, value: String)] = []
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { break }
            guard let (key, value) = splitKeyValue(line) else { throw LawHeadFieldError.malformedLine(line) }
            guard allowed.contains(key) else { throw LawHeadFieldError.keyNotAllowed(type: type.rawValue, key: key) }
            guard !entries.contains(where: { $0.key == key }) else { throw LawHeadFieldError.duplicateKey(key) }
            if value.isEmpty, !emptyAllowedKeys.contains(key) { throw LawHeadFieldError.emptyValue(key) }
            if !value.isEmpty, let values = allowedValues(type: type, key: key), !values.contains(value) {
                throw LawHeadFieldError.valueNotAllowed(key: key, value: value)
            }
            entries.append((key, value))
        }
        try checkRequired(type: type, entries: entries)
        return LawHeadFieldBlock(entries: entries)
    }

    private static func checkRequired(type: LawRecordType, entries: [(key: String, value: String)]) throws {
        for key in requiredKeysByType[type] ?? [] where !entries.contains(where: { $0.key == key }) {
            throw LawHeadFieldError.missingKey(type: type.rawValue, key: key)
        }
    }

    /// `키: 값` 한 줄. 키는 소문자로 시작하는 소문자·숫자·하이픈.
    static func splitKeyValue(_ line: String) -> (String, String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = String(line[..<colon])
        guard let head = key.first, head.isLowercase, head.isASCII,
              key.allSatisfy(isKeyCharacter) else { return nil }
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    /// 머리 칸 키 글자 — ASCII 소문자, 숫자, 하이픈.
    static func isKeyCharacter(_ c: Character) -> Bool {
        let isASCIILowercase = c.isLowercase && c.isASCII
        guard !isASCIILowercase else { return true }
        return c.isNumber || c == "-"
    }
}
