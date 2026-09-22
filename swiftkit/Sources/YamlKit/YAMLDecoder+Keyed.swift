import Foundation

final class YAMLKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    var pairs: [(key: YAMLNode, value: YAMLNode)]
    let impl: _YAMLDecoderImpl
    var codingPath: [CodingKey] { impl.codingPath }

    lazy var allKeys: [Key] = {
        pairs.compactMap { Key(stringValue: $0.key.stringKey()) }
    }()

    init(pairs: [(key: YAMLNode, value: YAMLNode)], impl: _YAMLDecoderImpl) {
        self.pairs = pairs
        self.impl = impl
    }

    private func child(for key: Key) -> _YAMLDecoderImpl? {
        guard let pair = pairs.first(where: { $0.key.stringKey() == key.stringValue }) else { return nil }
        return impl.child(for: key, node: pair.value)
    }

    func contains(_ key: Key) -> Bool {
        pairs.contains { $0.key.stringKey() == key.stringValue }
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        guard let dec = child(for: key) else { return true }
        return dec.node.isNull
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try require(key).decodeBool() }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try require(key).decodeInt() }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try require(key).decodeInt8() }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try require(key).decodeInt16() }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try require(key).decodeInt32() }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try require(key).decodeInt64() }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try require(key).decodeUInt() }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try require(key).decodeUInt8() }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try require(key).decodeUInt16() }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try require(key).decodeUInt32() }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try require(key).decodeUInt64() }
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try require(key).decodeFloat() }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try require(key).decodeDouble() }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try require(key).decodeString() }

    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {
        let dec = try require(key)
        if T.self == Date.self, let v = try dec.decodeDate() as? T { return v }
        if T.self == Data.self, let v = try dec.decodeData() as? T { return v }
        if T.self == URL.self {
            let s = try dec.decodeString()
            guard let url = URL(string: s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "잘못된 URL — \(s)"))
            }
            if let v = url as? T { return v }
        }
        return try T.init(from: dec)
    }

    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        try require(key).container(keyedBy: NestedKey.self)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        try require(key).unkeyedContainer()
    }

    func superDecoder() throws -> Decoder { impl }
    func superDecoder(forKey key: Key) throws -> Decoder {
        child(for: key) ?? impl.child(for: key, node: .null)
    }

    private func require(_ key: Key) throws -> _YAMLDecoderImpl {
        guard let dec = child(for: key) else {
            throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "키 없음 — \(key.stringValue)"))
        }
        return dec
    }
}
