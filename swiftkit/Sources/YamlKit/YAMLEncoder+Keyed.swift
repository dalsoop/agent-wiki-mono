import Foundation

final class YAMLKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let impl: _YAMLEncoderImpl
    var pairs: [(key: YAMLNode, value: YAMLNode)] = []
    var codingPath: [CodingKey] { impl.codingPath }

    init(impl: _YAMLEncoderImpl) {
        self.impl = impl
    }

    func encodeNil(forKey key: Key) throws {
        pairs.append((.scalar(raw: key.stringValue, plain: false), .null))
        flush()
    }

    func encode(_ value: Bool, forKey key: Key) throws { append(key, .scalar(raw: value ? "true" : "false", plain: true)) }
    func encode(_ value: Int, forKey key: Key) throws { append(key, .scalar(raw: String(value), plain: true)) }
    func encode(_ value: Int8, forKey key: Key) throws { append(key, .scalar(raw: String(value), plain: true)) }
    func encode(_ value: Int16, forKey key: Key) throws { append(key, .scalar(raw: String(value), plain: true)) }
    func encode(_ value: Int32, forKey key: Key) throws { append(key, .scalar(raw: String(value), plain: true)) }
    func encode(_ value: Int64, forKey key: Key) throws { append(key, .scalar(raw: String(value), plain: true)) }
    func encode(_ value: UInt, forKey key: Key) throws { append(key, .scalar(raw: String(value), plain: true)) }
    func encode(_ value: UInt8, forKey key: Key) throws { append(key, .scalar(raw: String(value), plain: true)) }
    func encode(_ value: UInt16, forKey key: Key) throws { append(key, .scalar(raw: String(value), plain: true)) }
    func encode(_ value: UInt32, forKey key: Key) throws { append(key, .scalar(raw: String(value), plain: true)) }
    func encode(_ value: UInt64, forKey key: Key) throws { append(key, .scalar(raw: String(value), plain: true)) }
    func encode(_ value: Float, forKey key: Key) throws { append(key, .scalar(raw: NumberFormatter.scalar.doubleString(Double(value)), plain: true)) }
    func encode(_ value: Double, forKey key: Key) throws { append(key, .scalar(raw: NumberFormatter.scalar.doubleString(value), plain: true)) }
    func encode(_ value: String, forKey key: Key) throws { append(key, .scalar(raw: value, plain: false)) }

    func encode<T>(_ value: T, forKey key: Key) throws where T: Encodable {
        let sub = _YAMLEncoderImpl(codingPath: impl.codingPath + [key], dateStrategy: impl.dateStrategy, dataStrategy: impl.dataStrategy, userInfo: impl.userInfo)
        try sub.boxInto(value)
        append(key, sub.value)
    }

    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        let sub = _YAMLEncoderImpl(codingPath: impl.codingPath + [key], dateStrategy: impl.dateStrategy, dataStrategy: impl.dataStrategy, userInfo: impl.userInfo)
        let container = sub.container(keyedBy: NestedKey.self)
        append(key, sub.value)
        return container
    }

    func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        let sub = _YAMLEncoderImpl(codingPath: impl.codingPath + [key], dateStrategy: impl.dateStrategy, dataStrategy: impl.dataStrategy, userInfo: impl.userInfo)
        let container = sub.unkeyedContainer()
        append(key, sub.value)
        return container
    }

    func superEncoder() -> Encoder { impl }
    func superEncoder(forKey key: Key) -> Encoder {
        let sub = _YAMLEncoderImpl(codingPath: impl.codingPath + [key], dateStrategy: impl.dateStrategy, dataStrategy: impl.dataStrategy, userInfo: impl.userInfo)
        append(key, sub.value)
        return sub
    }

    private func append(_ key: Key, _ node: YAMLNode) {
        pairs.append((.scalar(raw: key.stringValue, plain: false), node))
        flush()
    }

    /// 컨테이너 결과를 부모 impl.value 에 반영.
    private func flush() {
        impl.value = .mapping(pairs)
    }
}
