import Foundation
import MoneyLedgerStoreKit
import MoneyLedgerModels

/// 첨부파일 본체 저장소 — 복사·경로해석·삭제. 메타 행은 LedgerStore 가 소유한다.
/// GUI(드래그/파일선택)와 CLI(biz attach)가 같은 경로를 쓴다.
/// AttachmentRecord/AttachmentError 모델은 LedgerModels 로 옮겨갔고(Linux-portable),
/// AttachmentStore 만 LedgerContext 에 묶여 LedgerKit 에 남는다.
public struct AttachmentStore: Sendable {
    public let root: URL

    public init(context: LedgerContext) {
        self.root = context.databaseURL.deletingLastPathComponent()
            .appendingPathComponent("attachments", isDirectory: true)
    }

    public func directory(for record: AttachmentRecord) -> URL {
        root.appendingPathComponent(record.ownerKind.rawValue, isDirectory: true)
            .appendingPathComponent(record.ownerID, isDirectory: true)
    }

    public func fileURL(for record: AttachmentRecord) -> URL {
        directory(for: record).appendingPathComponent(record.fileName)
    }

    /// 원본 파일을 저장소로 복사하고 메타를 만든다(LedgerStore.insert(attachment:) 는 호출부 몫).
    public func importFile(
        ownerKind: AttachmentRecord.OwnerKind,
        ownerID: String,
        sourceURL: URL,
        originalName: String? = nil
    ) throws -> AttachmentRecord {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw AttachmentError.sourceMissing(sourceURL.path)
        }
        let ext = sourceURL.pathExtension.lowercased()
        let record = AttachmentRecord(
            ownerKind: ownerKind,
            ownerID: ownerID,
            fileName: ext.isEmpty ? UUID().uuidString.lowercased() : "\(UUID().uuidString.lowercased()).\(ext)",
            originalName: originalName ?? sourceURL.lastPathComponent
        )
        let destination = fileURL(for: record)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return record
    }

    public func removeFile(for record: AttachmentRecord) {
        try? FileManager.default.removeItem(at: fileURL(for: record))
    }
}
