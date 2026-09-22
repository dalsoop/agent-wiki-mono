import Foundation

/// `Encodable` → YAML 문자열. Yams `YAMLEncoder` 호출을 대체한다.
///
/// 구현 전략: Swift `Encoder` 프로토콜 컨테이너들로 `YAMLNode` 트리를 빌드한 뒤
/// `YAMLEmitter` 로 직렬화한다. 코더블 타입이 쓰는 인코딩 패턴(키드 컨테이너·
/// 단일값·비정형 컨테이너·날짜/데이터 전략)을 커버한다.
public struct YAMLEncoder {
    public var dateEncodingStrategy: DateEncodingStrategy = .deferredToDate
    public var dataEncodingStrategy: DataEncodingStrategy = .base64
    public var userInfo: [CodingUserInfoKey: Any] = [:]

    public init() {}

    public func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = _YAMLEncoderImpl(
            dateStrategy: dateEncodingStrategy,
            dataStrategy: dataEncodingStrategy,
            userInfo: userInfo
        )
        let node = try encoder.box(value)
        return YAMLEmitter(sortKeys: false).emit(node)
    }
}

public enum DateEncodingStrategy {
    /// Date → epoch(Double). 기본.
    case deferredToDate
    /// Date → "yyyy-MM-dd'T'HH:mm:ssZ".
    case iso8601
    /// Date → "yyyy-MM-dd".
    case formatted(DateFormatter)
}

public enum DataEncodingStrategy {
    case base64
    case deferredToData
}

/// 내부 Encoder 구현체. 컨테이너들이 공유해 올리는 박스.
final class _YAMLEncoderImpl: Encoder {
    var codingPath: [CodingKey]
    let dateStrategy: DateEncodingStrategy
    let dataStrategy: DataEncodingStrategy
    var userInfo: [CodingUserInfoKey: Any]

    /// 현재 인코딩 중인 값(node 조립 결과). 컨테이너가 채운다.
    var value: YAMLNode = .null

    init(
        codingPath: [CodingKey] = [],
        dateStrategy: DateEncodingStrategy,
        dataStrategy: DataEncodingStrategy,
        userInfo: [CodingUserInfoKey: Any]
    ) {
        self.codingPath = codingPath
        self.dateStrategy = dateStrategy
        self.dataStrategy = dataStrategy
        self.userInfo = userInfo
    }

    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
        let container = YAMLKeyedEncodingContainer<Key>(impl: self)
        value = .mapping([])
        return KeyedEncodingContainer(container)
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        let container = YAMLUnkeyedEncodingContainer(impl: self)
        value = .sequence([])
        return container
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        YAMLSingleValueEncodingContainer(impl: self)
    }

    /// 임의 Encodable을 node로 박싱 — 하위 엔코더를 새로 만들어 위임.
    func box(_ encodable: Encodable) throws -> YAMLNode {
        if let date = encodable as? Date {
            return try boxDate(date)
        }
        if let data = encodable as? Data {
            return try boxData(data)
        }
        if let url = encodable as? URL {
            return .scalar(raw: url.absoluteString, plain: false)
        }
        // 일반 Encodable — 스스로 인코딩하게 위임.
        let sub = _YAMLEncoderImpl(codingPath: codingPath, dateStrategy: dateStrategy, dataStrategy: dataStrategy, userInfo: userInfo)
        try encodable.encode(to: sub)
        return sub.value
    }

    private func boxDate(_ date: Date) throws -> YAMLNode {
        switch dateStrategy {
        case .deferredToDate:
            // epoch seconds(Double).
            let ts = date.timeIntervalSince1970
            return .scalar(raw: NumberFormatter.scalar.doubleString(ts), plain: true)
        case .iso8601:
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return .scalar(raw: f.string(from: date), plain: false)
        case .formatted(let formatter):
            return .scalar(raw: formatter.string(from: date), plain: false)
        }
    }

    private func boxData(_ data: Data) throws -> YAMLNode {
        switch dataStrategy {
        case .deferredToData:
            // 비정형 — base64로 직접.
            return .scalar(raw: data.base64EncodedString(), plain: false)
        case .base64:
            return .scalar(raw: data.base64EncodedString(), plain: false)
        }
    }
}
