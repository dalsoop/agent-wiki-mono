import Foundation
import GujoAuthKit

/// `/api/support/staff/*` — core 계약 docs/contracts/gujo-staff-auth-v1.md §5(문의 목록·상세·답변·닫기·재오픈·첨부 링크).
public struct SupportAPI: Sendable {
    let client: GujoStaffAPIClient
    private var root: String { GujoStaffRoutes.support }

    public var inquiries: Inquiries { Inquiries(client: client, root: root + "/inquiries") }

    public struct Inquiries: Sendable {
        let client: GujoStaffAPIClient
        let root: String

        /// 목록. `status` 는 open·answered·closed·all, `limit` 는 1…200(서버 기본 50).
        public func index(status: String? = nil, limit: Int? = nil) async throws -> Page<InquirySummary> {
            var query: [String: String] = [:]
            if let status { query["status"] = status }
            if let limit { query["limit"] = String(limit) }
            return try await client.call("GET", root, query: query, requires: .inquiriesRead)
        }

        public func show(_ id: Int) async throws -> InquiryDetail {
            try await client.call("GET", "\(root)/\(id)", requires: .inquiriesRead, as: Single<InquiryDetail>.self).data
        }

        /// 스태프 답변. 서버는 답변이 붙은 문의 상세를 돌려준다.
        public func reply(_ id: Int, _ draft: InquiryMessageDraft) async throws -> InquiryDetail {
            try await client.call(
                "POST", "\(root)/\(id)/messages", body: draft, requires: .inquiriesWrite,
                as: Single<InquiryDetail>.self).data
        }

        public func close(_ id: Int) async throws -> InquiryDetail {
            try await client.call(
                "POST", "\(root)/\(id)/close", requires: .inquiriesWrite, as: Single<InquiryDetail>.self).data
        }

        public func reopen(_ id: Int) async throws -> InquiryDetail {
            try await client.call(
                "POST", "\(root)/\(id)/reopen", requires: .inquiriesWrite, as: Single<InquiryDetail>.self).data
        }

        /// 첨부 다운로드 링크(§5.3). 받은 `url` 은 `expiresAt` 까지만 유효하고 **Authorization 없이** GET 한다.
        public func attachmentLink(_ id: Int, attachment attachmentId: Int) async throws -> InquiryAttachmentLink {
            try await client.call(
                "GET", "\(root)/\(id)/attachments/\(attachmentId)", requires: .inquiriesRead,
                as: Single<InquiryAttachmentLink>.self).data
        }
    }
}
