import Foundation

final class YAMLUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    var items: [YAMLNode]
    let impl: _YAMLDecoderImpl
    var codingPath: [CodingKey] { impl.codingPath }
    var currentIndex: Int = 0
    var count: Int? { items.count }
    var isAtEnd: Bool { currentIndex >= items.count }

    init(items: [YAMLNode], impl: _YAMLDecoderImpl) {
        self.items = items
        self.impl = impl
    }

    private func current() throws -> _YAMLDecoderImpl {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(Any.self, .init(codingPath: codingPath, debugDescription: "시퀀스 끝"))
        }
        return impl.child(at: currentIndex, node: items[currentIndex])
    }

    private func advance<T>(_ decode: (_YAMLDecoderImpl) throws -> T) throws -> T {
        let dec = try current()
        let v = try decode(dec)
        currentIndex += 1
        return v
    }

    func decodeNil() throws -> Bool {
        if isAtEnd { return true }
        let isNull = items[currentIndex].isNull
        if isNull { currentIndex += 1 }
        return isNull
    }
    func decode(_ type: Bool.Type) throws -> Bool { try advance { try $0.decodeBool() } }
    func decode(_ type: Int.Type) throws -> Int { try advance { try $0.decodeInt() } }
    func decode(_ type: Int8.Type) throws -> Int8 { try advance { try $0.decodeInt8() } }
    func decode(_ type: Int16.Type) throws -> Int16 { try advance { try $0.decodeInt16() } }
    func decode(_ type: Int32.Type) throws -> Int32 { try advance { try $0.decodeInt32() } }
    func decode(_ type: Int64.Type) throws -> Int64 { try advance { try $0.decodeInt64() } }
    func decode(_ type: UInt.Type) throws -> UInt { try advance { try $0.decodeUInt() } }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try advance { try $0.decodeUInt8() } }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try advance { try $0.decodeUInt16() } }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try advance { try $0.decodeUInt32() } }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try advance { try $0.decodeUInt64() } }
    func decode(_ type: Float.Type) throws -> Float { try advance { try $0.decodeFloat() } }
    func decode(_ type: Double.Type) throws -> Double { try advance { try $0.decodeDouble() } }
    func decode(_ type: String.Type) throws -> String { try advance { try $0.decodeString() } }

    func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        let dec = try current()
        currentIndex += 1
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

    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        try advance { try $0.container(keyedBy: NestedKey.self) }
    }

    func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        try advance { try $0.unkeyedContainer() }
    }

    func superDecoder() throws -> Decoder {
        try advance { $0 }
    }
}
