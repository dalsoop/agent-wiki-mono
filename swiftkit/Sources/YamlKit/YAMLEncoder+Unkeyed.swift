import Foundation

final class YAMLUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    let impl: _YAMLEncoderImpl
    var items: [YAMLNode] = []
    var codingPath: [CodingKey] { impl.codingPath }
    var count: Int { items.count }

    init(impl: _YAMLEncoderImpl) {
        self.impl = impl
    }

    private func append(_ node: YAMLNode) {
        items.append(node)
        impl.value = .sequence(items)
    }

    func encodeNil() throws { append(.null) }
    func encode(_ value: Bool) throws { append(.scalar(raw: value ? "true" : "false", plain: true)) }
    func encode(_ value: Int) throws { append(.scalar(raw: String(value), plain: true)) }
    func encode(_ value: Int8) throws { append(.scalar(raw: String(value), plain: true)) }
    func encode(_ value: Int16) throws { append(.scalar(raw: String(value), plain: true)) }
    func encode(_ value: Int32) throws { append(.scalar(raw: String(value), plain: true)) }
    func encode(_ value: Int64) throws { append(.scalar(raw: String(value), plain: true)) }
    func encode(_ value: UInt) throws { append(.scalar(raw: String(value), plain: true)) }
    func encode(_ value: UInt8) throws { append(.scalar(raw: String(value), plain: true)) }
    func encode(_ value: UInt16) throws { append(.scalar(raw: String(value), plain: true)) }
    func encode(_ value: UInt32) throws { append(.scalar(raw: String(value), plain: true)) }
    func encode(_ value: UInt64) throws { append(.scalar(raw: String(value), plain: true)) }
    func encode(_ value: Float) throws { append(.scalar(raw: NumberFormatter.scalar.doubleString(Double(value)), plain: true)) }
    func encode(_ value: Double) throws { append(.scalar(raw: NumberFormatter.scalar.doubleString(value), plain: true)) }
    func encode(_ value: String) throws { append(.scalar(raw: value, plain: false)) }

    func encode<T>(_ value: T) throws where T: Encodable {
        let sub = _YAMLEncoderImpl(codingPath: impl.codingPath, dateStrategy: impl.dateStrategy, dataStrategy: impl.dataStrategy, userInfo: impl.userInfo)
        try sub.boxInto(value)
        append(sub.value)
    }

    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        let sub = _YAMLEncoderImpl(codingPath: impl.codingPath, dateStrategy: impl.dateStrategy, dataStrategy: impl.dataStrategy, userInfo: impl.userInfo)
        let container = sub.container(keyedBy: NestedKey.self)
        append(sub.value)
        return container
    }

    func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let sub = _YAMLEncoderImpl(codingPath: impl.codingPath, dateStrategy: impl.dateStrategy, dataStrategy: impl.dataStrategy, userInfo: impl.userInfo)
        let container = sub.unkeyedContainer()
        append(sub.value)
        return container
    }

    func superEncoder() -> Encoder { impl }
}
