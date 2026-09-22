import Foundation

final class YAMLSingleValueDecodingContainer: SingleValueDecodingContainer {
    let impl: _YAMLDecoderImpl
    var codingPath: [CodingKey] { impl.codingPath }

    init(impl: _YAMLDecoderImpl) {
        self.impl = impl
    }

    func decodeNil() -> Bool { impl.node.isNull }
    func decode(_ type: Bool.Type) throws -> Bool { try impl.decodeBool() }
    func decode(_ type: Int.Type) throws -> Int { try impl.decodeInt() }
    func decode(_ type: Int8.Type) throws -> Int8 { try impl.decodeInt8() }
    func decode(_ type: Int16.Type) throws -> Int16 { try impl.decodeInt16() }
    func decode(_ type: Int32.Type) throws -> Int32 { try impl.decodeInt32() }
    func decode(_ type: Int64.Type) throws -> Int64 { try impl.decodeInt64() }
    func decode(_ type: UInt.Type) throws -> UInt { try impl.decodeUInt() }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try impl.decodeUInt8() }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try impl.decodeUInt16() }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try impl.decodeUInt32() }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try impl.decodeUInt64() }
    func decode(_ type: Float.Type) throws -> Float { try impl.decodeFloat() }
    func decode(_ type: Double.Type) throws -> Double { try impl.decodeDouble() }
    func decode(_ type: String.Type) throws -> String { try impl.decodeString() }

    func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        if T.self == Date.self, let v = try impl.decodeDate() as? T { return v }
        if T.self == Data.self, let v = try impl.decodeData() as? T { return v }
        if T.self == URL.self {
            let s = try impl.decodeString()
            guard let url = URL(string: s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "잘못된 URL — \(s)"))
            }
            if let v = url as? T { return v }
        }
        return try T.init(from: impl)
    }

    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        try impl.container(keyedBy: NestedKey.self)
    }

    func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        try impl.unkeyedContainer()
    }
}
