import Foundation
import CryptoKit

/// Errors that can occur during receipt verification.
public enum ReceiptVerificationError: Error, LocalizedError, Equatable, Sendable {
    case fileNotFound(URL)
    case sizeMismatch(expected: Int64, actual: Int64)
    case hashMismatch(expected: String, actual: String)
    case invalidReceiptHashFormat(String)
    case ioError(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Artifact file does not exist at: \(url.path)"
        case .sizeMismatch(let expected, let actual):
            return "Artifact size mismatch: expected \(expected) bytes, but got \(actual) bytes"
        case .hashMismatch(let expected, let actual):
            return "Artifact SHA-256 hash mismatch: expected \(expected), but computed \(actual)"
        case .invalidReceiptHashFormat(let hash):
            return "Receipt artifact SHA-256 hash has invalid format: '\(hash)'. Expected 64-char hex string."
        case .ioError(let message):
            return "Artifact I/O error: \(message)"
        }
    }
}

/// Detailed result of artifact verification against a ReleaseReceipt.
public struct ReceiptVerificationResult: Sendable, Equatable {
    public let isValid: Bool
    public let artifactURL: URL
    public let computedSHA256: String
    public let computedSizeBytes: Int64
    public let verifiedAt: Date
    public let errors: [ReceiptVerificationError]

    public init(
        isValid: Bool,
        artifactURL: URL,
        computedSHA256: String,
        computedSizeBytes: Int64,
        verifiedAt: Date = Date(),
        errors: [ReceiptVerificationError] = []
    ) {
        self.isValid = isValid
        self.artifactURL = artifactURL
        self.computedSHA256 = computedSHA256
        self.computedSizeBytes = computedSizeBytes
        self.verifiedAt = verifiedAt
        self.errors = errors
    }
}

/// Offline integrity verifier for release artifacts against their ReleaseReceipt.
public struct ReceiptVerifier: Sendable {
    public let bufferSize: Int

    public static let defaultBufferSize = 1024 * 1024 // 1 MB buffer

    public init(bufferSize: Int = ReceiptVerifier.defaultBufferSize) {
        self.bufferSize = max(4096, bufferSize)
    }

    public static let shared = ReceiptVerifier()

    /// Verifies the artifact at `artifactURL` against `receipt`.
    ///
    /// - Parameters:
    ///   - receipt: The release receipt containing expected checksum and metadata.
    ///   - artifactURL: Local file URL of the artifact to verify.
    ///   - strict: When true (default), throws the first encountered `ReceiptVerificationError`.
    ///             When false, returns a result containing all detected issues.
    /// - Returns: A `ReceiptVerificationResult` detailing the verification outcome.
    @discardableResult
    public func verify(
        receipt: ReleaseReceipt,
        artifactURL: URL,
        strict: Bool = true
    ) throws -> ReceiptVerificationResult {
        var detectedErrors: [ReceiptVerificationError] = []
        let standardizedURL = artifactURL.standardizedFileURL

        // 1. File existence check
        guard FileManager.default.fileExists(atPath: standardizedURL.path) else {
            let error = ReceiptVerificationError.fileNotFound(standardizedURL)
            if strict { throw error }
            return ReceiptVerificationResult(
                isValid: false,
                artifactURL: standardizedURL,
                computedSHA256: "",
                computedSizeBytes: 0,
                verifiedAt: Date(),
                errors: [error]
            )
        }

        // 2. Receipt hash format check
        if !receipt.artifact.isValidSHA256 {
            let error = ReceiptVerificationError.invalidReceiptHashFormat(receipt.artifact.sha256)
            if strict { throw error }
            detectedErrors.append(error)
        }

        // 3. File size check
        let actualSize = try checkFileSize(
            url: standardizedURL,
            expectedSize: receipt.artifact.sizeBytes,
            strict: strict,
            errors: &detectedErrors
        )

        // 4 & 5. Checksum verification
        let computedSHA256 = try checkHash(
            url: standardizedURL,
            expectedSHA256: receipt.artifact.sha256,
            strict: strict,
            errors: &detectedErrors
        )

        return ReceiptVerificationResult(
            isValid: detectedErrors.isEmpty,
            artifactURL: standardizedURL,
            computedSHA256: computedSHA256,
            computedSizeBytes: max(0, actualSize),
            verifiedAt: Date(),
            errors: detectedErrors
        )
    }

    private func checkFileSize(
        url: URL,
        expectedSize: Int64,
        strict: Bool,
        errors: inout [ReceiptVerificationError]
    ) throws -> Int64 {
        let actualSize: Int64
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let fileSizeNumber = attrs[.size] as? NSNumber else {
                throw ReceiptVerificationError.ioError("Could not retrieve file size attribute")
            }
            actualSize = fileSizeNumber.int64Value
        } catch let error as ReceiptVerificationError {
            if strict { throw error }
            errors.append(error)
            return -1
        } catch {
            let ioErr = ReceiptVerificationError.ioError("Failed to inspect file attributes: \(error.localizedDescription)")
            if strict { throw ioErr }
            errors.append(ioErr)
            return -1
        }

        if actualSize >= 0 && actualSize != expectedSize {
            let sizeErr = ReceiptVerificationError.sizeMismatch(
                expected: expectedSize,
                actual: actualSize
            )
            if strict { throw sizeErr }
            errors.append(sizeErr)
        }
        return actualSize
    }

    private func checkHash(
        url: URL,
        expectedSHA256: String,
        strict: Bool,
        errors: inout [ReceiptVerificationError]
    ) throws -> String {
        let computedSHA256: String
        do {
            let streamResult = try Self.computeSHA256(for: url, bufferSize: bufferSize)
            computedSHA256 = streamResult.sha256
        } catch let error as ReceiptVerificationError {
            if strict { throw error }
            errors.append(error)
            return ""
        } catch {
            let ioErr = ReceiptVerificationError.ioError("Failed reading file content: \(error.localizedDescription)")
            if strict { throw ioErr }
            errors.append(ioErr)
            return ""
        }

        let expectedNormalized = expectedSHA256.lowercased()
        if !computedSHA256.isEmpty && computedSHA256.lowercased() != expectedNormalized {
            let hashErr = ReceiptVerificationError.hashMismatch(
                expected: expectedNormalized,
                actual: computedSHA256.lowercased()
            )
            if strict { throw hashErr }
            errors.append(hashErr)
        }
        return computedSHA256
    }

    /// Convenience static method forwarding to the shared instance in strict mode.
    @discardableResult
    public static func verify(
        receipt: ReleaseReceipt,
        artifactURL: URL
    ) throws -> ReceiptVerificationResult {
        try shared.verify(receipt: receipt, artifactURL: artifactURL, strict: true)
    }

    /// Computes the SHA-256 checksum and total byte count of a file using streaming reads.
    public static func computeSHA256(
        for fileURL: URL,
        bufferSize: Int = ReceiptVerifier.defaultBufferSize
    ) throws -> (sha256: String, sizeBytes: Int64) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ReceiptVerificationError.fileNotFound(fileURL)
        }

        guard let handle = FileHandle(forReadingAtPath: fileURL.path) else {
            throw ReceiptVerificationError.ioError("Failed to open file handle for: \(fileURL.path)")
        }
        defer {
            do {
                try handle.close()
            } catch {
                fputs("ReceiptVerifier: handle.close failed: \(error)\n", stderr)
            }
        }

        var hasher = SHA256()
        var totalBytes: Int64 = 0
        let chunkSize = max(4096, bufferSize)

        while true {
            let chunk: Data
            do {
                if #available(macOS 10.15.4, iOS 13.4, *) {
                    guard let data = try handle.read(upToCount: chunkSize), !data.isEmpty else {
                        break
                    }
                    chunk = data
                } else {
                    chunk = handle.readData(ofLength: chunkSize)
                    if chunk.isEmpty { break }
                }
            } catch {
                throw ReceiptVerificationError.ioError("Read error at byte offset \(totalBytes): \(error.localizedDescription)")
            }

            hasher.update(data: chunk)
            totalBytes += Int64(chunk.count)
        }

        let digest = hasher.finalize()
        let sha256Hex = digest.map { String(format: "%02x", $0) }.joined()

        return (sha256Hex, totalBytes)
    }
}
