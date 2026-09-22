import Foundation
import ContentAddressedAssetKit
import StateRootKit

public struct TenantDocumentVault: Sendable {
    public let tenantID: String
    public let rootDirectory: URL

    public init(tenantID: String, rootDirectory: URL? = nil) {
        self.tenantID = tenantID
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let tenantRoot = StateRootKit.tenantStateRoot(tenant: tenantID)
            self.rootDirectory = URL(fileURLWithPath: tenantRoot).appendingPathComponent("documents")
        }
    }

    public var objectsDirectory: URL {
        rootDirectory.appendingPathComponent("objects")
    }

    public var recordsFileURL: URL {
        rootDirectory.appendingPathComponent("records.json")
    }

    public func store(
        fileURL: URL,
        kind: TenantDocumentKind,
        issuedAt: Date = Date(),
        validityDays: Int? = nil
    ) throws -> TenantDocumentRecord {
        if !FileManager.default.fileExists(atPath: rootDirectory.path) {
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        }

        let store = AssetStore(rootDirectory: objectsDirectory)
        let asset = try store.store(fileURL: fileURL)

        let days = validityDays ?? kind.defaultValidityDays
        let expiresAt: Date?
        if let days {
            expiresAt = Calendar.current.date(byAdding: .day, value: days, to: issuedAt)
        } else {
            expiresAt = nil
        }

        let record = TenantDocumentRecord(
            id: UUID().uuidString,
            tenantID: tenantID,
            kind: kind,
            assetHash: asset.hash,
            originalName: asset.originalName,
            sizeBytes: asset.sizeBytes,
            issuedAt: issuedAt,
            expiresAt: expiresAt
        )

        var records = try allRecords()
        records.append(record)
        try saveRecords(records)

        return record
    }

    public func latestRecord(for kind: TenantDocumentKind) throws -> TenantDocumentRecord? {
        let records = try allRecords()
        return records
            .filter { $0.kind == kind }
            .sorted(by: { $0.issuedAt < $1.issuedAt })
            .last
    }

    public func allRecords() throws -> [TenantDocumentRecord] {
        guard FileManager.default.fileExists(atPath: recordsFileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: recordsFileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([TenantDocumentRecord].self, from: data)
    }

    public func validRecords() throws -> [TenantDocumentRecord] {
        try allRecords().filter { !$0.isExpired }
    }

    public func assetURL(for record: TenantDocumentRecord) -> URL? {
        let store = AssetStore(rootDirectory: objectsDirectory)
        return store.lookup(hash: record.assetHash)
    }

    private func saveRecords(_ records: [TenantDocumentRecord]) throws {
        if !FileManager.default.fileExists(atPath: rootDirectory.path) {
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(records)
        try data.write(to: recordsFileURL, options: .atomic)
    }
}
