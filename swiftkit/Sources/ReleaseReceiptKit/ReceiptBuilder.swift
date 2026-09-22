import Foundation

/// Errors that can occur when building or writing a ReleaseReceipt.
public enum ReceiptBuilderError: Error, LocalizedError, Equatable, Sendable {
    case missingRequiredField(String)
    case fileNotFound(URL)
    case writeFailed(URL, String)

    public var errorDescription: String? {
        switch self {
        case .missingRequiredField(let field):
            return "ReceiptBuilder error: missing required field '\(field)'."
        case .fileNotFound(let url):
            return "Artifact file for receipt not found at: \(url.path)"
        case .writeFailed(let url, let reason):
            return "Failed to atomically write receipt to \(url.path): \(reason)"
        }
    }
}

/// Fluent builder and file writer for creating and storing ReleaseReceipts.
public struct ReceiptBuilder: Sendable {
    public var schema: String = ReleaseReceipt.defaultSchema
    public var appSlug: String?
    public var bundleID: String?
    public var version: String?
    public var buildNumber: Int?
    public var artifact: ArtifactReceipt?
    public var notary: NotaryReceipt?
    public var sparkle: SparkleReceipt?
    public var createdAt: Date?

    public init() {}

    // MARK: - Fluent Setters

    public func setSchema(_ schema: String) -> ReceiptBuilder {
        var copy = self
        copy.schema = schema
        return copy
    }

    public func setAppSlug(_ appSlug: String) -> ReceiptBuilder {
        var copy = self
        copy.appSlug = appSlug
        return copy
    }

    public func setBundleID(_ bundleID: String) -> ReceiptBuilder {
        var copy = self
        copy.bundleID = bundleID
        return copy
    }

    public func setVersion(_ version: String) -> ReceiptBuilder {
        var copy = self
        copy.version = version
        return copy
    }

    public func setBuildNumber(_ buildNumber: Int?) -> ReceiptBuilder {
        var copy = self
        copy.buildNumber = buildNumber
        return copy
    }

    public func setArtifact(_ artifact: ArtifactReceipt) -> ReceiptBuilder {
        var copy = self
        copy.artifact = artifact
        return copy
    }

    public func setArtifact(
        filename: String,
        sha256: String,
        sizeBytes: Int64,
        contentType: String
    ) -> ReceiptBuilder {
        setArtifact(
            ArtifactReceipt(
                filename: filename,
                sha256: sha256,
                sizeBytes: sizeBytes,
                contentType: contentType
            )
        )
    }

    /// Automatically computes SHA-256 and byte size from the file at `fileURL`.
    public func setArtifact(
        from fileURL: URL,
        contentType: String? = nil,
        filename: String? = nil
    ) throws -> ReceiptBuilder {
        let standardizedURL = fileURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardizedURL.path) else {
            throw ReceiptBuilderError.fileNotFound(standardizedURL)
        }

        let (sha256Hex, sizeBytes) = try ReceiptVerifier.computeSHA256(for: standardizedURL)
        let resolvedFilename = filename ?? standardizedURL.lastPathComponent
        let resolvedContentType = contentType ?? Self.inferContentType(for: standardizedURL)

        return setArtifact(
            ArtifactReceipt(
                filename: resolvedFilename,
                sha256: sha256Hex,
                sizeBytes: sizeBytes,
                contentType: resolvedContentType
            )
        )
    }

    public func setNotary(_ notary: NotaryReceipt) -> ReceiptBuilder {
        var copy = self
        copy.notary = notary
        return copy
    }

    public func setNotary(
        submissionID: String,
        notarizedAt: Date = Date(),
        teamID: String? = nil
    ) -> ReceiptBuilder {
        setNotary(
            NotaryReceipt(
                submissionID: submissionID,
                notarizedAt: notarizedAt,
                teamID: teamID
            )
        )
    }

    public func setSparkle(_ sparkle: SparkleReceipt?) -> ReceiptBuilder {
        var copy = self
        copy.sparkle = sparkle
        return copy
    }

    public func setSparkle(ed25519Signature: String?) -> ReceiptBuilder {
        setSparkle(SparkleReceipt(ed25519Signature: ed25519Signature))
    }

    public func setCreatedAt(_ date: Date) -> ReceiptBuilder {
        var copy = self
        copy.createdAt = date
        return copy
    }

    // MARK: - Build

    public func build() throws -> ReleaseReceipt {
        guard let appSlug = appSlug, !appSlug.isEmpty else {
            throw ReceiptBuilderError.missingRequiredField("appSlug")
        }
        guard let bundleID = bundleID, !bundleID.isEmpty else {
            throw ReceiptBuilderError.missingRequiredField("bundleID")
        }
        guard let version = version, !version.isEmpty else {
            throw ReceiptBuilderError.missingRequiredField("version")
        }
        guard let artifact = artifact else {
            throw ReceiptBuilderError.missingRequiredField("artifact")
        }
        guard let notary = notary else {
            throw ReceiptBuilderError.missingRequiredField("notary")
        }

        return ReleaseReceipt(
            schema: schema,
            appSlug: appSlug,
            bundleID: bundleID,
            version: version,
            buildNumber: buildNumber,
            artifact: artifact,
            notary: notary,
            sparkle: sparkle,
            createdAt: createdAt ?? Date()
        )
    }

    /// Builds the `ReleaseReceipt` and atomically writes it to `destinationURL`.
    @discardableResult
    public func buildAndWrite(
        to destinationURL: URL,
        atomically: Bool = true
    ) throws -> ReleaseReceipt {
        let receipt = try build()
        try Self.write(receipt: receipt, to: destinationURL, atomically: atomically)
        return receipt
    }

    // MARK: - Atomic File Writing Helpers

    /// Atomically writes a ReleaseReceipt to a JSON file on disk.
    public static func write(
        receipt: ReleaseReceipt,
        to destinationURL: URL,
        atomically: Bool = true
    ) throws {
        let parentDir = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            do {
                try FileManager.default.createDirectory(
                    at: parentDir,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                throw ReceiptBuilderError.writeFailed(
                    destinationURL,
                    "Failed to create directory at \(parentDir.path): \(error.localizedDescription)"
                )
            }
        }

        let data: Data
        do {
            data = try receipt.toJSONData()
        } catch {
            throw ReceiptBuilderError.writeFailed(
                destinationURL,
                "JSON encoding error: \(error.localizedDescription)"
            )
        }

        do {
            let writeOptions: Data.WritingOptions = atomically ? .atomic : []
            try data.write(to: destinationURL, options: writeOptions)
        } catch {
            throw ReceiptBuilderError.writeFailed(
                destinationURL,
                error.localizedDescription
            )
        }
    }

    /// Convenience wrapper for atomic writes.
    public static func writeAtomically(
        receipt: ReleaseReceipt,
        to destinationURL: URL
    ) throws {
        try write(receipt: receipt, to: destinationURL, atomically: true)
    }



    // MARK: - Utilities

    /// Infers standard MIME content type from file extension.
    public static func inferContentType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "zip":
            return "application/zip"
        case "dmg":
            return "application/x-apple-diskimage"
        case "pkg":
            return "application/x-newton-compatible-pkg"
        case "gz", "tgz":
            return "application/gzip"
        case "json":
            return "application/json"
        default:
            return "application/octet-stream"
        }
    }
}
