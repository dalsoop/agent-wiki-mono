import Foundation

/// 순수 Swift YAML 모듈. 외부 SPM 패키지(Yams) 의존 없이, swift-app-mono 4개 앱이
/// 다루는 YAML(프론트매터·설정·매니페스트·코덱 직렬화)을 파싱·직렬화한다.
///
/// YAML 1.1/1.2 풀스펙이 목표가 아니다 — 사용처가 실제로 다루는 범위를 커버한다:
/// 블록 매핑·시퀀스, 플로우 컬렉션 `[]` `{}`, 중첩 구조, 따옴표/따옴표없음 스칼라,
/// 정수/실수/불/null 해석, 줄 끝 주석 `#`. round-trip(직렬화→역직렬화 동치)이 기준이다.
public enum YamlKit {
    /// YAML 문자열을 파싱해 `Any?`(String/Int/Double/Bool/NSNull/Array/Dictionary)로 돌려준다.
    /// Yams의 `Yams.load(yaml:)` 호출을 대체한다.
    public static func load(yaml: String) throws -> Any? {
        try YAMLParser.parse(yaml)
    }

    /// `Any`(String/Int/Double/Bool/NSNull/Array/Dictionary)를 YAML 문자열로 직렬화한다.
    /// Yams의 `Yams.dump(object:allowUnicode:sortKeys:)` 호출을 대체한다.
    public static func dump(
        object: Any,
        allowUnicode: Bool = true,
        sortKeys: Bool = false
    ) throws -> String {
        let node = try NodeConverter.makeNode(from: object)
        var emitter = YAMLEmitter(sortKeys: sortKeys)
        return emitter.emit(node) + "\n"
    }
}

/// 파서가 만들고 이미터/인코더/디코더가 공유하는 내부 표현.
///
/// `scalar`는 원문 표면을 그대로 들고, 해석(resolution)은 값이 필요한 쪽(`any()`/디코더)에서
/// 지연 수행한다 — 따옴표로 "123"을 쓴 스칼라가 정수로 잘못 바뀌지 않는다.
indirect enum YAMLNode {
    /// - Parameters:
      ///   - raw: 따옴표를 벗긴 스칼라 원문.
    ///   - plain: 따옴표 없는 plain 스칼라였는가(정수/불/null 자동 해석 대상).
    case scalar(raw: String, plain: Bool)
    case sequence([YAMLNode])
    /// 매핑 — 키는 항상 스칼라로 정규화한다. 순서를 보존한다(직렬화·round-trip용).
    case mapping([(key: YAMLNode, value: YAMLNode)])
    case null

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

extension YAMLNode {
    /// 디코더/`load`가 스칼라를 Swift 값으로 해석할 때 쓴다.
    /// plain 스칼라만 정수/불/null/실수로 해석하고, 따옴표 스칼라는 문자열로 둔다.
    func any() -> Any? {
        switch self {
        case .null:
            return NSNull()
        case let .scalar(raw, plain):
            return ScalarResolver.resolve(raw: raw, plain: plain)
        case let .sequence(items):
            return items.map { $0.any() as Any }
        case let .mapping(pairs):
            var dict: [String: Any] = [:]
            for (key, value) in pairs {
                dict[key.stringKey()] = value.any() as Any
            }
            return dict
        }
    }

    /// 매핑 키를 문자열로 정규화. 키는 항상 스칼라로 들어온다고 가정한다.
    func stringKey() -> String {
        switch self {
        case let .scalar(raw, _): return raw
        case .null: return "null"
        case .sequence, .mapping: return ""
        }
    }
}

/// `dump`가 받은 `Any`를 `YAMLNode`로 바꾼다.
enum NodeConverter {
    static func makeNode(from value: Any?) throws -> YAMLNode {
        guard let value else { return .null }
        switch value {
        case is NSNull:
            return .null
        case let string as String:
            return .scalar(raw: string, plain: false)
        case let bool as Bool:
            return .scalar(raw: bool ? "true" : "false", plain: true)
        case let int as Int:
            return .scalar(raw: String(int), plain: true)
        case let int64 as Int64:
            return .scalar(raw: String(int64), plain: true)
        case let uint64 as UInt64:
            return .scalar(raw: String(uint64), plain: true)
        case let double as Double:
            return .scalar(raw: NumberFormatter.scalar.doubleString(double), plain: true)
        case let number as NSNumber:
            // Bool/Int/Double 분기 — CFBoolean 여부로 진위를 판별한다.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .scalar(raw: number.boolValue ? "true" : "false", plain: true)
            }
            let d = number.doubleValue
            if d.rounded() == d, abs(d) < 1e15 {
                return .scalar(raw: String(number.intValue), plain: true)
            }
            return .scalar(raw: NumberFormatter.scalar.doubleString(d), plain: true)
        case let array as [Any]:
            return .sequence(try array.map { try makeNode(from: $0) })
        case let dict as [String: Any]:
            return .mapping(try dict.map { (key: .scalar(raw: $0.key, plain: false), value: try makeNode(from: $0.value)) })
        case let hashable as [AnyHashable: Any]:
            // 딕셔너리 키가 비-문자일 수 있다 — 문자열로 정규화.
            return .mapping(try hashable.map {
                (key: .scalar(raw: String(describing: $0.key), plain: false), value: try makeNode(from: $0.value))
            })
        default:
            throw YamlKitError.unsupportedType(String(describing: type(of: value)))
        }
    }
}

enum YamlKitError: Error, CustomStringConvertible {
    case unsupportedType(String)
    case parserError(String)

    var description: String {
        switch self {
        case let .unsupportedType(type): "YamlKit: 지원하지 않는 타입 — \(type)"
        case let .parserError(message): "YamlKit: 파싱 실패 — \(message)"
        }
    }
}
