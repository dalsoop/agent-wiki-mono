import Foundation

/// YAML 문자열/데이터 → `Decodable`. Yams `YAMLDecoder` 호출을 대체한다.
///
/// `decode(_:from:)` 은 `String` 과 `Data` 모두 받는다(Yams 호환 — 호출처가 둘 다 쓴다).
/// 내부적으로 `YAMLParser` 로 `YAMLNode` 를 만들고, Swift `Decoder` 프로토콜 컨테이너로
/// `Decodable` 타입에 채운다.
public struct YAMLDecoder {
    public var dateDecodingStrategy: DateDecodingStrategy = .deferredToDate
    public var dataDecodingStrategy: DataDecodingStrategy = .base64
    public var userInfo: [CodingUserInfoKey: Any] = [:]

    public init() {}

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let text = String(data: data, encoding: .utf8) ?? ""
        return try decode(type, from: text)
    }

    public func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        let node = try YAMLParser.parseNode(string)
        let decoder = _YAMLDecoderImpl(
            node: node,
            codingPath: [],
            dateStrategy: dateDecodingStrategy,
            dataStrategy: dataDecodingStrategy,
            userInfo: userInfo
        )
        return try type.init(from: decoder)
    }
}

public enum DateDecodingStrategy {
    /// epoch Double 로 해석. 기본.
    case deferredToDate
    /// ISO8601 문자열 파싱.
    case iso8601
    /// 커스텀 포매터.
    case formatted(DateFormatter)
}

public enum DataDecodingStrategy {
    case base64
    case deferredToData
}

/// 내부 Decoder 구현체. 현재 커서가 가리키는 `YAMLNode` 를 들고 다닌다.
final class _YAMLDecoderImpl: Decoder {
    let node: YAMLNode
    var codingPath: [CodingKey]
    let dateStrategy: DateDecodingStrategy
    let dataStrategy: DataDecodingStrategy
    var userInfo: [CodingUserInfoKey: Any]

    init(
        node: YAMLNode,
        codingPath: [CodingKey],
        dateStrategy: DateDecodingStrategy,
        dataStrategy: DataDecodingStrategy,
        userInfo: [CodingUserInfoKey: Any]
    ) {
        self.node = node
        self.codingPath = codingPath
        self.dateStrategy = dateStrategy
        self.dataStrategy = dataStrategy
        self.userInfo = userInfo
    }

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        guard case let .mapping(pairs) = node else {
            // 비어있는(null/스칼라) 문서를 빈 매핑으로 관대하게 해석할 수 있게.
            if node.isNull { return KeyedDecodingContainer(YAMLKeyedDecodingContainer<Key>(pairs: [], impl: self)) }
            throw DecodingError.typeMismatch([String: Any].self, .init(codingPath: codingPath, debugDescription: "매핑이 아님 — \(node)"))
        }
        return KeyedDecodingContainer(YAMLKeyedDecodingContainer<Key>(pairs: pairs, impl: self))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard case let .sequence(items) = node else {
            if node.isNull { return YAMLUnkeyedDecodingContainer(items: [], impl: self) }
            throw DecodingError.typeMismatch([Any].self, .init(codingPath: codingPath, debugDescription: "시퀀스가 아님 — \(node)"))
        }
        return YAMLUnkeyedDecodingContainer(items: items, impl: self)
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        YAMLSingleValueDecodingContainer(impl: self)
    }

    /// 자식 node 로 새 디코더.
    func child(for key: CodingKey, node child: YAMLNode) -> _YAMLDecoderImpl {
        _YAMLDecoderImpl(node: child, codingPath: codingPath + [key], dateStrategy: dateStrategy, dataStrategy: dataStrategy, userInfo: userInfo)
    }

    func child(at index: Int, node child: YAMLNode) -> _YAMLDecoderImpl {
        _YAMLDecoderImpl(node: child, codingPath: codingPath + [_YAMLIndexKey(index: index)], dateStrategy: dateStrategy, dataStrategy: dataStrategy, userInfo: userInfo)
    }
}

struct _YAMLIndexKey: CodingKey {
    var intValue: Int?
    var stringValue: String { String(intValue ?? 0) }
    init(index: Int) { intValue = index }
    init?(intValue: Int) { self.intValue = intValue }
    init?(stringValue: String) { intValue = Int(stringValue) }
}
