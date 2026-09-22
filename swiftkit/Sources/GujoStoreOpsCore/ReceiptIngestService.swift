import Foundation
import ReleaseReceiptKit

/// release-receipt.json 검증 및 스토어 인제스트 서비스.
public struct ReceiptIngestService: Sendable {
    public init() {}

    /// 로컬 영수증 파일을 검증하고 ReleaseReceipt 인스턴스를 반환한다.
    public func validateReceipt(at fileURL: URL) throws -> ReleaseReceipt {
        let receipt: ReleaseReceipt
        do {
            receipt = try ReleaseReceipt.from(fileURL: fileURL)
        } catch {
            throw StoreOpsError.invalidReceipt("영수증 로드 실패: \(error.localizedDescription)")
        }

        // 1. SHA-256 검증
        guard receipt.artifact.isValidSHA256 else {
            throw StoreOpsError.invalidReceipt("SHA-256 체크섬 형식이 올바르지 않습니다 (\(receipt.artifact.sha256)). 64자리 16진수가 필요합니다.")
        }

        // 2. 파일 크기 검증
        guard receipt.artifact.sizeBytes > 0 else {
            throw StoreOpsError.invalidReceipt("아티팩트 파일 크기가 0 이하입니다 (\(receipt.artifact.sizeBytes)).")
        }

        // 3. Apple 공증 제출 ID 형식 검증
        let subID = receipt.notary.submissionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: subID) != nil else {
            throw StoreOpsError.invalidReceipt("공증 제출 ID가 UUID 형식이 아닙니다 (\(subID)).")
        }

        return receipt
    }

    /// 영수증을 검증하고 StoreOpsClient 를 통해 스토어로 인제스트한다.
    public func ingest(
        at fileURL: URL,
        overrideDownloadURL: URL? = nil,
        client: StoreOpsClient
    ) async throws -> ReceiptIngestResult {
        let receipt = try validateReceipt(at: fileURL)
        let data = try receipt.toJSONData()
        return try await client.ingestReceipt(receiptData: data, overrideDownloadURL: overrideDownloadURL)
    }
}
