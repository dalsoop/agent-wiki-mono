#if canImport(CryptoKit)
import CryptoKit
import Foundation

/// RFC 6238 TOTP — Bitwarden 항목의 totp 시드(otpauth:// URI 또는 bare base32)로
/// 현재 코드를 만든다. 외부 의존 없음.
public enum TOTPGenerator {
    public struct Config: Sendable, Equatable {
        public var secret: Data
        public var digits: Int
        public var period: Int
        public var algorithm: Algorithm
        public enum Algorithm: String, Sendable { case sha1 = "SHA1", sha256 = "SHA256", sha512 = "SHA512" }
    }

    /// otpauth:// URI 또는 bare base32 시드를 파싱. steam:// 등 비표준은 nil.
    public static func parse(_ seed: String) -> Config? {
        let trimmed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("otpauth://") {
            guard let comp = URLComponents(string: trimmed) else { return nil }
            var secret: Data?
            var digits = 6, period = 30
            var algo = Config.Algorithm.sha1
            for q in comp.queryItems ?? [] {
                switch q.name.lowercased() {
                case "secret": secret = q.value.flatMap(base32Decode)
                case "digits": digits = q.value.flatMap(Int.init) ?? 6
                case "period": period = q.value.flatMap(Int.init) ?? 30
                case "algorithm": algo = q.value.flatMap { Config.Algorithm(rawValue: $0.uppercased()) } ?? .sha1
                default: break
                }
            }
            guard let s = secret, !s.isEmpty else { return nil }
            return Config(secret: s, digits: digits, period: period, algorithm: algo)
        }
        guard let s = base32Decode(trimmed), !s.isEmpty else { return nil }
        return Config(secret: s, digits: 6, period: 30, algorithm: .sha1)
    }

    /// 주어진 시각의 코드.
    public static func code(_ config: Config, at date: Date = Date()) -> String {
        let counter = UInt64(date.timeIntervalSince1970) / UInt64(max(config.period, 1))
        var big = counter.bigEndian
        let msg = Data(bytes: &big, count: 8)
        let key = SymmetricKey(data: config.secret)
        let mac: Data
        switch config.algorithm {
        case .sha1:   mac = Data(HMAC<Insecure.SHA1>.authenticationCode(for: msg, using: key))
        case .sha256: mac = Data(HMAC<SHA256>.authenticationCode(for: msg, using: key))
        case .sha512: mac = Data(HMAC<SHA512>.authenticationCode(for: msg, using: key))
        }
        let offset = Int(mac[mac.count - 1] & 0x0f)
        let bin = (UInt32(mac[offset] & 0x7f) << 24)
            | (UInt32(mac[offset + 1]) << 16)
            | (UInt32(mac[offset + 2]) << 8)
            | UInt32(mac[offset + 3])
        let mod = UInt32(pow(10, Double(config.digits)))
        return String(format: "%0\(config.digits)d", bin % mod)
    }

    /// 현재 주기에서 남은 초.
    public static func secondsRemaining(_ config: Config, at date: Date = Date()) -> Int {
        let p = max(config.period, 1)
        return p - Int(date.timeIntervalSince1970) % p
    }

    /// RFC 4648 base32 (패딩·공백·소문자 관대).
    static func base32Decode(_ input: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var lookup = [Character: UInt8]()
        for (i, ch) in alphabet.enumerated() { lookup[ch] = UInt8(i) }
        var bits = 0, value = 0
        var out = Data()
        for raw in input.uppercased() where raw != "=" && raw != " " && raw != "-" {
            guard let v = lookup[raw] else { return nil }
            value = (value << 5) | Int(v)
            bits += 5
            if bits >= 8 {
                out.append(UInt8((value >> (bits - 8)) & 0xff))
                bits -= 8
            }
        }
        return out
    }
}
#endif
