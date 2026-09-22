import Foundation

// MARK: - 스칼라 디코딩 보조

extension _YAMLDecoderImpl {
    func decodeBool() throws -> Bool {
        if case let .scalar(raw, _) = node {
            switch raw {
            case "true", "True", "TRUE", "yes", "Yes", "YES", "on", "On", "ON": return true
            case "false", "False", "FALSE", "no", "No", "NO", "off", "Off", "OFF": return false
            default:
                throw DecodingError.typeMismatch(Bool.self, .init(codingPath: codingPath, debugDescription: "불이 아님 — \(raw)"))
            }
        }
        throw DecodingError.typeMismatch(Bool.self, .init(codingPath: codingPath, debugDescription: "불이 아님 — \(node)"))
    }

    func decodeString() throws -> String {
        if case let .scalar(raw, _) = node { return raw }
        if node.isNull { return "" }
        // 매핑/시퀀스를 문자열로 요구하면 에러.
        throw DecodingError.typeMismatch(String.self, .init(codingPath: codingPath, debugDescription: "문자열이 아님 — \(node)"))
    }

    func decodeInt() throws -> Int {
        guard let raw = scalarRaw else { throw notNumber(Int.self) }
        if let v = parseInt(raw) { return v }
        // 실수 형태면 truncate.
        if let d = Double(raw) { return Int(d) }
        throw notNumber(Int.self)
    }
    func decodeInt8() throws -> Int8 { Int8(try decodeInt()) }
    func decodeInt16() throws -> Int16 { Int16(try decodeInt()) }
    func decodeInt32() throws -> Int32 { Int32(try decodeInt()) }
    func decodeInt64() throws -> Int64 { Int64(try decodeInt()) }
    func decodeUInt() throws -> UInt {
        guard let raw = scalarRaw else { throw notNumber(UInt.self) }
        if let v = Int(raw) { return UInt(v) }
        throw notNumber(UInt.self)
    }
    func decodeUInt8() throws -> UInt8 { UInt8(try decodeUInt()) }
    func decodeUInt16() throws -> UInt16 { UInt16(try decodeUInt()) }
    func decodeUInt32() throws -> UInt32 { UInt32(try decodeUInt()) }
    func decodeUInt64() throws -> UInt64 { UInt64(try decodeUInt()) }
    func decodeFloat() throws -> Float { Float(try decodeDouble()) }
    func decodeDouble() throws -> Double {
        guard let raw = scalarRaw else { throw notNumber(Double.self) }
        switch raw {
        case ".inf", ".Inf", ".INF", "+.inf": return .infinity
        case "-.inf", "-.Inf", "-.INF": return -.infinity
        case ".nan", ".NaN", ".NAN": return .nan
        default: break
        }
        if let v = Double(raw) { return v }
        throw notNumber(Double.self)
    }

    func decodeDate() throws -> Date {
        guard let raw = scalarRaw else {
            throw DecodingError.typeMismatch(Date.self, .init(codingPath: codingPath, debugDescription: "날짜가 아님"))
        }
        switch dateStrategy {
        case .deferredToDate:
            if let ts = Double(raw) { return Date(timeIntervalSince1970: ts) }
            // ISO 형태도 폴백으로 받아들인다.
            return try parseFlexibleDate(raw)
        case .iso8601:
            return try parseFlexibleDate(raw)
        case .formatted(let formatter):
            guard let d = formatter.date(from: raw) else {
                throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "날짜 파싱 실패 — \(raw)"))
            }
            return d
        }
    }

    func decodeData() throws -> Data {
        guard let raw = scalarRaw else {
            throw DecodingError.typeMismatch(Data.self, .init(codingPath: codingPath, debugDescription: "데이터가 아님"))
        }
        switch dataStrategy {
        case .base64, .deferredToData:
            guard let d = Data(base64Encoded: raw) else {
                throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "base64 디코딩 실패"))
            }
            return d
        }
    }

    private var scalarRaw: String? {
        if case let .scalar(raw, _) = node { return raw }
        return nil
    }

    private func parseInt(_ raw: String) -> Int? {
        let trimmed = raw.hasPrefix("+") ? String(raw.dropFirst()) : raw
        if trimmed.hasPrefix("0x"), let v = UInt64(trimmed.dropFirst(2), radix: 16) { return Int(exactly: v) }
        if trimmed.hasPrefix("0o"), let v = UInt64(trimmed.dropFirst(2), radix: 8) { return Int(exactly: v) }
        if trimmed.hasPrefix("0b"), let v = UInt64(trimmed.dropFirst(2), radix: 2) { return Int(exactly: v) }
        return Int(trimmed)
    }

    private func parseFlexibleDate(_ raw: String) throws -> Date {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }
        // 일부 포매터 폴백.
        let alt = DateFormatter()
        alt.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX", "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd"] {
            alt.dateFormat = fmt
            if let d = alt.date(from: raw) { return d }
        }
        throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "날짜 파싱 실패 — \(raw)"))
    }

    private func notNumber<T>(_ type: T.Type) -> DecodingError {
        DecodingError.typeMismatch(type, .init(codingPath: codingPath, debugDescription: "숫자가 아님 — \(node)"))
    }
}
