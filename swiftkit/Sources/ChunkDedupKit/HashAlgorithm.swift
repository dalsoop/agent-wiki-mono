import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Supported cryptographic hash algorithms for deduplication block hashing.
public enum HashAlgorithm: String, Sendable, Codable, CaseIterable {
    case sha256 = "sha256"
    case blake3 = "blake3"

    /// Computes hash digest for given data.
    public func hash(data: Data) -> Data {
        switch self {
        case .sha256:
            #if canImport(CryptoKit)
            let digest = SHA256.hash(data: data)
            return Data(digest)
            #else
            // Fallback for non-Apple platforms without CryptoKit
            return BLAKE3.hash(data: data)
            #endif
        case .blake3:
            return BLAKE3.hash(data: data)
        }
    }

    /// Computes lowercase hex-encoded string of hash digest.
    public func hexHash(data: Data) -> String {
        switch self {
        case .sha256:
            #if canImport(CryptoKit)
            let digest = SHA256.hash(data: data)
            return digest.map { String(format: "%02x", $0) }.joined()
            #else
            return BLAKE3.hexHash(data: data)
            #endif
        case .blake3:
            return BLAKE3.hexHash(data: data)
        }
    }
}
