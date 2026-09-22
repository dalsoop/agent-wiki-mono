import Foundation
import GujoAuthKit

/// `/api/commerce/staff/*` — customers · products · orders · subscriptions · events.
public struct CommerceAPI: Sendable {
    let client: GujoStaffAPIClient
    private var root: String { GujoStaffRoutes.commerce }

    public var customers: Customers { Customers(client: client, root: root + "/customers") }
    public var orders: Orders { Orders(client: client, root: root + "/orders") }
    public var subscriptions: Subscriptions { Subscriptions(client: client, root: root + "/subscriptions") }

    /// 상품 목록. 읽기 전용 ability 가 계약에 없어 로컬 검사는 하지 않고 서버 판정에 맡긴다.
    public func products(page: Int? = nil) async throws -> Page<Product> {
        try await client.call("GET", root + "/products", query: pageQuery(page), requires: nil)
    }

    /// 커머스 이벤트 스트림(서버 주도 형태).
    public func events(since: Date? = nil, page: Int? = nil) async throws -> Page<JSONValue> {
        var query = pageQuery(page)
        if let since { query["since"] = ISO8601DateFormatter().string(from: since) }
        return try await client.call("GET", root + "/events", query: query, requires: .ordersRead)
    }

    public struct Customers: Sendable {
        let client: GujoStaffAPIClient
        let root: String

        public func index(search: String? = nil, page: Int? = nil) async throws -> Page<Customer> {
            var query = pageQuery(page)
            if let search, !search.isEmpty { query["q"] = search }
            return try await client.call("GET", root, query: query, requires: .customersRead)
        }

        public func show(_ id: Int) async throws -> Customer {
            try await client.call("GET", "\(root)/\(id)", requires: .customersRead, as: Single<Customer>.self).data
        }

        public func create(_ draft: CustomerDraft) async throws -> Customer {
            try await client.call(
                "POST", root, body: draft, requires: .customersWrite, as: Single<Customer>.self).data
        }

        public func update(_ id: Int, _ draft: CustomerDraft) async throws -> Customer {
            try await client.call(
                "PATCH", "\(root)/\(id)", body: draft, requires: .customersWrite, as: Single<Customer>.self).data
        }

        public func devices(_ id: Int) async throws -> Page<CustomerDevice> {
            try await client.call("GET", "\(root)/\(id)/devices", requires: .customersRead)
        }

        public func invoices(_ id: Int, page: Int? = nil) async throws -> Page<Invoice> {
            try await client.call("GET", "\(root)/\(id)/invoices", query: pageQuery(page), requires: .invoicesRead)
        }

        public func creditNotes(_ id: Int, page: Int? = nil) async throws -> Page<CreditNote> {
            try await client.call(
                "GET", "\(root)/\(id)/credit-notes", query: pageQuery(page), requires: .invoicesRead)
        }

        public func createCreditNote(_ id: Int, _ draft: CreditNoteDraft) async throws -> CreditNote {
            try await client.call(
                "POST", "\(root)/\(id)/credit-notes", body: draft, requires: .creditNotesWrite,
                as: Single<CreditNote>.self).data
        }

        public func creditBalance(_ id: Int) async throws -> CreditBalance {
            try await client.call(
                "GET", "\(root)/\(id)/credit-balance", requires: .invoicesRead, as: Single<CreditBalance>.self).data
        }

        public func devicesRevoke(_ id: Int, deviceId: Int) async throws {
            _ = try await client.call(
                "POST", "\(root)/\(id)/devices/\(deviceId)/revoke", requires: .devicesRevoke, as: Empty.self)
        }

        public func entitlementsGrant(_ id: Int, _ change: EntitlementChange) async throws {
            _ = try await client.call(
                "POST", "\(root)/\(id)/entitlements/grant", body: change, requires: .entitlementsGrant,
                as: Empty.self)
        }

        public func entitlementsRevoke(_ id: Int, _ change: EntitlementChange) async throws {
            _ = try await client.call(
                "POST", "\(root)/\(id)/entitlements/revoke", body: change, requires: .entitlementsRevoke,
                as: Empty.self)
        }
    }

    public struct Orders: Sendable {
        let client: GujoStaffAPIClient
        let root: String

        public func show(_ id: Int) async throws -> Order {
            try await client.call("GET", "\(root)/\(id)", requires: .ordersRead, as: Single<Order>.self).data
        }

        public func cancel(_ id: Int, reason: String? = nil) async throws -> Order {
            try await client.call(
                "POST", "\(root)/\(id)/cancel", body: RefundRequest(reason: reason), requires: .ordersCancel,
                as: Single<Order>.self).data
        }

        public func refund(_ id: Int, _ request: RefundRequest = RefundRequest()) async throws -> Order {
            try await client.call(
                "POST", "\(root)/\(id)/refund", body: request, requires: .ordersRefund,
                as: Single<Order>.self).data
        }
    }

    public struct Subscriptions: Sendable {
        let client: GujoStaffAPIClient
        let root: String

        public func grant(_ grant: SubscriptionGrant) async throws -> Subscription {
            try await client.call(
                "POST", "\(root)/grant", body: grant, requires: .subscriptionsWrite,
                as: Single<Subscription>.self).data
        }

        public func cancel(_ id: Int, reason: String? = nil) async throws -> Subscription {
            try await client.call(
                "POST", "\(root)/\(id)/cancel", body: RefundRequest(reason: reason),
                requires: .subscriptionsWrite, as: Single<Subscription>.self).data
        }

        public func refund(_ id: Int, _ request: RefundRequest = RefundRequest()) async throws -> Subscription {
            try await client.call(
                "POST", "\(root)/\(id)/refund", body: request, requires: .subscriptionsRefund,
                as: Single<Subscription>.self).data
        }
    }
}

func pageQuery(_ page: Int?) -> [String: String] {
    guard let page else { return [:] }
    return ["page": String(page)]
}
