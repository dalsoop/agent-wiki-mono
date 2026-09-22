import Foundation

final class YAMLSingleValueEncodingContainer: SingleValueEncodingContainer {
    let impl: _YAMLEncoderImpl
    var codingPath: [CodingKey] { impl.codingPath }

    init(impl: _YAMLEncoderImpl) {
        self.impl = impl
    }

    func encodeNil() throws { impl.value = .null }

    func encode(_ value: Bool) throws { impl.value = .scalar(raw: value ? "true" : "false", plain: true) }
    func encode(_ value: Int) throws { impl.value = .scalar(raw: String(value), plain: true) }
    func encode(_ value: Int8) throws { impl.value = .scalar(raw: String(value), plain: true) }
    func encode(_ value: Int16) throws { impl.value = .scalar(raw: String(value), plain: true) }
    func encode(_ value: Int32) throws { impl.value = .scalar(raw: String(value), plain: true) }
    func encode(_ value: Int64) throws { impl.value = .scalar(raw: String(value), plain: true) }
    func encode(_ value: UInt) throws { impl.value = .scalar(raw: String(value), plain: true) }
    func encode(_ value: UInt8) throws { impl.value = .scalar(raw: String(value), plain: true) }
    func encode(_ value: UInt16) throws { impl.value = .scalar(raw: String(value), plain: true) }
    func encode(_ value: UInt32) throws { impl.value = .scalar(raw: String(value), plain: true) }
    func encode(_ value: UInt64) throws { impl.value = .scalar(raw: String(value), plain: true) }
    func encode(_ value: Float) throws { impl.value = .scalar(raw: NumberFormatter.scalar.doubleString(Double(value)), plain: true) }
    func encode(_ value: Double) throws { impl.value = .scalar(raw: NumberFormatter.scalar.doubleString(value), plain: true) }
    func encode(_ value: String) throws { impl.value = .scalar(raw: value, plain: false) }

    func encode<T>(_ value: T) throws where T: Encodable {
        try impl.boxInto(value)
    }
}
