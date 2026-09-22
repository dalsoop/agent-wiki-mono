import Foundation

/// Small JSON tree for daemon envelopes and event payloads. Avoids type-erased `Any`.
public enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public subscript(key: String) -> JSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    public var string: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var bool: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    public var int: Int? {
        switch self {
        case .int(let value):
            return value
        case .double(let value):
            return Int(value)
        default:
            return nil
        }
    }

    public var double: Double? {
        switch self {
        case .double(let value):
            return value
        case .int(let value):
            return Double(value)
        default:
            return nil
        }
    }

    public var array: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    public var object: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let value = Self.decode(Bool.self, container) {
            self = .bool(value)
            return
        }
        if let value = Self.decode(Int.self, container) {
            self = .int(value)
            return
        }
        if let value = Self.decode(Double.self, container) {
            self = .double(value)
            return
        }
        if let value = Self.decode(String.self, container) {
            self = .string(value)
            return
        }
        if let value = Self.decode([JSONValue].self, container) {
            self = .array(value)
            return
        }
        if let value = Self.decode([String: JSONValue].self, container) {
            self = .object(value)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "unsupported JSON value"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        _ container: SingleValueDecodingContainer
    ) -> T? {
        do {
            return try container.decode(type)
        } catch {
            return nil
        }
    }
}
