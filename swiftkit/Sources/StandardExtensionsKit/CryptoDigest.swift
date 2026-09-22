import Foundation
#if canImport(CryptoKit)
import CryptoKit
#elseif canImport(Crypto)
import Crypto
#endif

extension Data {
    /// 16진수 소문자 문자열로 변환한다.
    @inlinable
    public var hexEncodedString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// SHA256 해시를 계산하여 16진수 소문자 문자열로 반환한다.
    @inlinable
    public var sha256Hex: String {
        #if canImport(CryptoKit) || canImport(Crypto)
        let digest = SHA256.hash(data: self)
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        return ""
        #endif
    }
}

extension String {
    /// UTF-8 바이트의 SHA256 해시를 계산하여 16진수 소문자 문자열로 반환한다.
    @inlinable
    public var sha256Hex: String {
        Data(utf8).sha256Hex
    }
}
