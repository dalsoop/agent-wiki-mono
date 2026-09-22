import Foundation

public enum Base62: Sendable {
    private static let charset = [UInt8]("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8)

    @inline(__always)
    private static func decodeDigit(_ b: UInt8) -> UInt8? {
        switch b {
        case 48...57: return b - 48
        case 65...90: return b - 55
        case 97...122: return b - 61
        default: return nil
        }
    }

    public static func encode(_ value: UInt64) -> String {
        if value == 0 { return "0" }
        var v = value, buf: [UInt8] = []
        buf.reserveCapacity(11)
        while v > 0 { buf.append(charset[Int(v % 62)]); v /= 62 }
        return String(decoding: buf.reversed(), as: UTF8.self)
    }

    public static func decode(_ string: String) -> UInt64? {
        guard !string.isEmpty else { return nil }
        var result: UInt64 = 0
        for b in string.utf8 {
            guard let d = decodeDigit(b) else { return nil }
            let (m, o1) = result.multipliedReportingOverflow(by: 62)
            let (a, o2) = m.addingReportingOverflow(UInt64(d))
            if o1 || o2 { return nil }
            result = a
        }
        return result
    }

    public static func encode(_ data: Data) -> String {
        let zeros = data.prefix(while: { $0 == 0 }).count
        var digits: [UInt8] = []
        for byte in data.dropFirst(zeros) {
            var carry = Int(byte)
            for i in 0..<digits.count {
                let acc = Int(digits[i]) << 8 + carry
                digits[i] = UInt8(acc % 62); carry = acc / 62
            }
            while carry > 0 { digits.append(UInt8(carry % 62)); carry /= 62 }
        }
        return String(repeating: "0", count: zeros) + String(decoding: digits.reversed().map { charset[Int($0)] }, as: UTF8.self)
    }

    public static func decode(_ string: String) -> Data? {
        let utf8 = Array(string.utf8), zeros = utf8.prefix(while: { $0 == 48 }).count
        var bytes: [UInt8] = []
        for b in utf8.dropFirst(zeros) {
            guard let d = decodeDigit(b) else { return nil }
            var carry = Int(d)
            for i in 0..<bytes.count {
                let acc = Int(bytes[i]) * 62 + carry
                bytes[i] = UInt8(acc & 0xFF); carry = acc >> 8
            }
            while carry > 0 { bytes.append(UInt8(carry & 0xFF)); carry >>= 8 }
        }
        return Data(repeating: 0, count: zeros) + bytes.reversed()
    }
}
