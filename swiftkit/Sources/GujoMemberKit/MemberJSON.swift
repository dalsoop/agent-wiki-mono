import Foundation

/// 스태프 고객 JSON 공통 디코더 — `/api/commerce/staff/customers` 와
/// `/api/support/staff` 가 섞어 보내는 Int/String id · ISO-8601 시각을 한 곳에서 받는다.
public enum MemberJSON {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(decodeDate)
        return decoder
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Int 또는 String 으로 오는 식별자를 문자열로 정규화한다.
    public static func decodeIdentifier<K: CodingKey>(_ container: KeyedDecodingContainer<K>, key: K) throws -> String {
        if let value = decodeOptionalIdentifier(container, key: key) {
            return value
        }
        throw DecodingError.keyNotFound(
            key,
            DecodingError.Context(codingPath: container.codingPath, debugDescription: "member id missing")
        )
    }

    public static func decodeOptionalIdentifier<K: CodingKey>(_ container: KeyedDecodingContainer<K>, key: K) -> String? {
        guard container.contains(key) else { return nil }
        do {
            return try container.decode(FlexibleIdentifier.self, forKey: key).normalized
        } catch {
            return nil
        }
    }

    public static func decodeDate(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        if let date = numericDate(container) { return date }
        let raw = try container.decode(String.self)
        guard let date = parseISO8601(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "unrecognized date: \(raw)")
        }
        return date
    }

    private static func numericDate(_ container: SingleValueDecodingContainer) -> Date? {
        do {
            return Date(timeIntervalSince1970: try container.decode(TimeInterval.self))
        } catch {
            do {
                return Date(timeIntervalSince1970: TimeInterval(try container.decode(Int.self)))
            } catch {
                return nil
            }
        }
    }

    public static func parseISO8601(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: trimmed) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: trimmed)
    }
}

/// Int 또는 String 식별자. `try?` 타입 프로브 대신 한 번의 디코드로 받는다.
struct FlexibleIdentifier: Decodable {
    var normalized: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            normalized = nil
            return
        }
        do {
            normalized = String(try container.decode(Int.self))
            return
        } catch {
            let raw = try container.decode(String.self).trimmingCharacters(in: .whitespacesAndNewlines)
            normalized = raw.isEmpty ? nil : raw
        }
    }
}
