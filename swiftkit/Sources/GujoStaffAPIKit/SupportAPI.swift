import Foundation
import GujoAuthKit

/// `/api/support/staff/*` — inquiries · reports.
public struct SupportAPI: Sendable {
    let client: GujoStaffAPIClient
    private var root: String { GujoStaffRoutes.support }

    public var inquiries: Inquiries { Inquiries(client: client, root: root + "/inquiries") }

    /// 지원 통계·보고서(서버 주도 형태).
    public func reports(period: String? = nil) async throws -> JSONObject {
        var query: [String: String] = [:]
        if let period { query["period"] = period }
        return try await client.call("GET", root + "/reports", query: query, requires: .inquiriesRead)
    }

    public struct Inquiries: Sendable {
        let client: GujoStaffAPIClient
        let root: String

        public func index(status: String? = nil, page: Int? = nil) async throws -> Page<Inquiry> {
            var query = pageQuery(page)
            if let status { query["status"] = status }
            return try await client.call("GET", root, query: query, requires: .inquiriesRead)
        }

        public func show(_ id: Int) async throws -> Inquiry {
            try await client.call("GET", "\(root)/\(id)", requires: .inquiriesRead, as: Single<Inquiry>.self).data
        }

        public func messages(_ id: Int) async throws -> Page<InquiryMessage> {
            try await client.call("GET", "\(root)/\(id)/messages", requires: .inquiriesRead)
        }

        public func reply(_ id: Int, _ draft: InquiryMessageDraft) async throws -> InquiryMessage {
            try await client.call(
                "POST", "\(root)/\(id)/messages", body: draft, requires: .inquiriesWrite,
                as: Single<InquiryMessage>.self).data
        }

        public func close(_ id: Int) async throws -> Inquiry {
            try await client.call(
                "POST", "\(root)/\(id)/close", requires: .inquiriesWrite, as: Single<Inquiry>.self).data
        }

        public func reopen(_ id: Int) async throws -> Inquiry {
            try await client.call(
                "POST", "\(root)/\(id)/reopen", requires: .inquiriesWrite, as: Single<Inquiry>.self).data
        }
    }
}
