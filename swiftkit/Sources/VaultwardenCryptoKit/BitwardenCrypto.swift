#if canImport(CryptoKit)
import CryptoKit
import Foundation
import CommonCrypto

/// Bitwarden 프로토콜 암호화 프리미티브.
///
/// - 마스터키: PBKDF2-SHA256(password, salt=lowercased email)
/// - 서버 인증 해시: PBKDF2(masterKey, salt=password, 1회)
/// - 키 스트레칭: HKDF-SHA256 expand(info: "enc"/"mac")
/// - EncString(type 2): "2.<iv b64>|<ct b64>|<mac b64>", AES-256-CBC + HMAC-SHA256(iv|ct)
public enum BitwardenCrypto {

    public enum CryptoError: Error, LocalizedError, Equatable {
        case unsupportedKdf(Int)
        case invalidEncString
        case unsupportedEncType(Int)
        case macMismatch
        case cipherFailure(Int32)

        public var errorDescription: String? {
            switch self {
            case .unsupportedKdf(let k): return "지원하지 않는 KDF(\(k)) — 이 계정은 Argon2id를 사용합니다. 웹 볼트에서 KDF를 PBKDF2로 바꾸면 로그인할 수 있습니다."
            case .invalidEncString: return "EncString 형식이 올바르지 않습니다"
            case .unsupportedEncType(let t): return "지원하지 않는 암호화 타입(\(t))"
            case .macMismatch: return "MAC 검증 실패 — 키가 맞지 않습니다"
            case .cipherFailure(let s): return "암복호화 실패 (status \(s))"
            }
        }
    }

    public struct KdfConfig: Sendable, Equatable {
        public let kdf: Int            // 0 = PBKDF2-SHA256, 1 = Argon2id
        public let iterations: Int
        public init(kdf: Int, iterations: Int) {
            self.kdf = kdf
            self.iterations = iterations
        }
    }

    /// enc 32바이트 + mac 32바이트 쌍.
    public struct SymmetricKeySet: Sendable, Equatable {
        public let enc: Data
        public let mac: Data
        public init(enc: Data, mac: Data) {
            self.enc = enc
            self.mac = mac
        }
        /// 64바이트 원본 (enc|mac). Keychain 보관용.
        public var raw: Data { enc + mac }
        public init?(raw: Data) {
            guard raw.count == 64 else { return nil }
            self.init(enc: raw.prefix(32), mac: raw.suffix(32))
        }
    }

    // MARK: - KDF

    public static func masterKey(password: String, email: String, kdf: KdfConfig) throws -> Data {
        guard kdf.kdf == 0 else { throw CryptoError.unsupportedKdf(kdf.kdf) }
        return pbkdf2(password: Data(password.utf8),
                      salt: Data(email.lowercased().trimmingCharacters(in: .whitespaces).utf8),
                      iterations: kdf.iterations)
    }

    /// 서버로 보내는 인증 해시 (base64).
    public static func masterPasswordHash(masterKey: Data, password: String) -> String {
        pbkdf2(password: masterKey, salt: Data(password.utf8), iterations: 1).base64EncodedString()
    }

    /// 마스터키를 HKDF로 스트레칭해 enc/mac 키셋을 만든다.
    public static func stretchedKey(masterKey: Data) -> SymmetricKeySet {
        let prk = SymmetricKey(data: masterKey)
        let enc = HKDF<SHA256>.expand(pseudoRandomKey: prk, info: Data("enc".utf8), outputByteCount: 32)
        let mac = HKDF<SHA256>.expand(pseudoRandomKey: prk, info: Data("mac".utf8), outputByteCount: 32)
        return SymmetricKeySet(enc: enc.withUnsafeBytes { Data($0) },
                               mac: mac.withUnsafeBytes { Data($0) })
    }

    static func pbkdf2(password: Data, salt: Data, iterations: Int) -> Data {
        var out = Data(count: 32)
        _ = out.withUnsafeMutableBytes { outPtr in
            password.withUnsafeBytes { pwPtr in
                salt.withUnsafeBytes { saltPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwPtr.baseAddress?.assumingMemoryBound(to: Int8.self), password.count,
                        saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                        outPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), 32)
                }
            }
        }
        return out
    }

    // MARK: - EncString

    public struct EncString: Sendable, Equatable {
        public let type: Int
        public let iv: Data
        public let data: Data
        public let mac: Data?

        public init(parse s: String) throws {
            guard let dot = s.firstIndex(of: ".") else { throw CryptoError.invalidEncString }
            guard let t = Int(s[..<dot]) else { throw CryptoError.invalidEncString }
            let parts = s[s.index(after: dot)...].split(separator: "|").map(String.init)
            guard parts.count >= 2,
                  let iv = Data(base64Encoded: parts[0]),
                  let data = Data(base64Encoded: parts[1]) else { throw CryptoError.invalidEncString }
            self.type = t
            self.iv = iv
            self.data = data
            self.mac = parts.count >= 3 ? Data(base64Encoded: parts[2]) : nil
        }

        public init(type: Int, iv: Data, data: Data, mac: Data?) {
            self.type = type
            self.iv = iv
            self.data = data
            self.mac = mac
        }

        public var serialized: String {
            var s = "\(type).\(iv.base64EncodedString())|\(data.base64EncodedString())"
            if let mac { s += "|\(mac.base64EncodedString())" }
            return s
        }
    }

    /// EncString 복호화. type 0(AES-CBC no MAC), 2(AES-CBC + HMAC) 지원.
    public static func decrypt(_ enc: EncString, key: SymmetricKeySet) throws -> Data {
        switch enc.type {
        case 2:
            guard let mac = enc.mac else { throw CryptoError.invalidEncString }
            let computed = HMAC<SHA256>.authenticationCode(for: enc.iv + enc.data,
                                                           using: SymmetricKey(data: key.mac))
            guard Data(computed) == mac else { throw CryptoError.macMismatch }
            return try aesCbc(kCCDecrypt, key: key.enc, iv: enc.iv, input: enc.data)
        case 0:
            return try aesCbc(kCCDecrypt, key: key.enc, iv: enc.iv, input: enc.data)
        default:
            throw CryptoError.unsupportedEncType(enc.type)
        }
    }

    public static func decryptString(_ s: String, key: SymmetricKeySet) throws -> String {
        let data = try decrypt(EncString(parse: s), key: key)
        return String(decoding: data, as: UTF8.self)
    }

    /// type 2 EncString으로 암호화.
    public static func encrypt(_ plaintext: Data, key: SymmetricKeySet) throws -> EncString {
        var iv = Data(count: 16)
        _ = iv.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let ct = try aesCbc(kCCEncrypt, key: key.enc, iv: iv, input: plaintext)
        let mac = HMAC<SHA256>.authenticationCode(for: iv + ct, using: SymmetricKey(data: key.mac))
        return EncString(type: 2, iv: iv, data: ct, mac: Data(mac))
    }

    public static func encryptString(_ s: String, key: SymmetricKeySet) throws -> String {
        try encrypt(Data(s.utf8), key: key).serialized
    }

    static func aesCbc(_ op: Int, key: Data, iv: Data, input: Data) throws -> Data {
        var out = Data(count: input.count + kCCBlockSizeAES128)
        var written = 0
        let status = out.withUnsafeMutableBytes { outPtr in
            key.withUnsafeBytes { keyPtr in
                iv.withUnsafeBytes { ivPtr in
                    input.withUnsafeBytes { inPtr in
                        CCCrypt(CCOperation(op), CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding),
                                keyPtr.baseAddress, key.count,
                                ivPtr.baseAddress,
                                inPtr.baseAddress, input.count,
                                outPtr.baseAddress, outPtr.count, &written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw CryptoError.cipherFailure(status) }
        return out.prefix(written)
    }
}
#endif
