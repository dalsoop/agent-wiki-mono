import Foundation
import GujoAuthKit

/// `/ops/v1/*` — health · packages · devices · install-jobs · runners · receipts · audit.
/// 옛 `auth.ops` 토큰 경로와 같은 라우트를 `gst_` 토큰으로 친다(계약 §3).
public struct OpsAPI: Sendable {
    let client: GujoStaffAPIClient
    private var root: String { GujoStaffRoutes.ops }

    public func health() async throws -> JSONObject {
        try await client.call("GET", root + "/health", requires: .opsHealth)
    }

    public var packages: Packages { Packages(client: client, root: root + "/packages") }
    public var devices: Devices { Devices(client: client, root: root + "/devices") }
    public var installJobs: InstallJobs { InstallJobs(client: client, root: root + "/install-jobs") }
    public var runners: Runners { Runners(client: client, root: root + "/runners") }

    public func receiptsIngest(_ payload: ReceiptIngest) async throws -> JSONObject {
        try await client.call("POST", root + "/receipts/ingest", body: payload, requires: .opsReceipts)
    }

    public func audit(page: Int? = nil) async throws -> Page<JSONValue> {
        try await client.call("GET", root + "/audit", query: pageQuery(page), requires: .opsAudit)
    }

    public struct Packages: Sendable {
        let client: GujoStaffAPIClient
        let root: String

        public func list(page: Int? = nil) async throws -> Page<OpsPackage> {
            try await client.call("GET", root, query: pageQuery(page), requires: .opsPackages)
        }

        public func publish(_ package: OpsPackagePublish) async throws -> OpsPackage {
            try await client.call(
                "POST", root, body: package, requires: .opsPackages, as: Single<OpsPackage>.self).data
        }
    }

    public struct Devices: Sendable {
        let client: GujoStaffAPIClient
        let root: String

        public func list(page: Int? = nil) async throws -> Page<OpsDevice> {
            try await client.call("GET", root, query: pageQuery(page), requires: .opsDevices)
        }

        public func show(_ id: Int) async throws -> OpsDevice {
            try await client.call("GET", "\(root)/\(id)", requires: .opsDevices, as: Single<OpsDevice>.self).data
        }

        public func create(_ draft: OpsDeviceDraft) async throws -> OpsDevice {
            try await client.call(
                "POST", root, body: draft, requires: .opsDevices, as: Single<OpsDevice>.self).data
        }

        public func update(_ id: Int, _ draft: OpsDeviceDraft) async throws -> OpsDevice {
            try await client.call(
                "PATCH", "\(root)/\(id)", body: draft, requires: .opsDevices, as: Single<OpsDevice>.self).data
        }

        public func delete(_ id: Int) async throws {
            _ = try await client.call("DELETE", "\(root)/\(id)", requires: .opsDevices, as: Empty.self)
        }
    }

    public struct InstallJobs: Sendable {
        let client: GujoStaffAPIClient
        let root: String

        public func list(page: Int? = nil) async throws -> Page<InstallJob> {
            try await client.call("GET", root, query: pageQuery(page), requires: .opsInstallJobs)
        }

        public func show(_ id: Int) async throws -> InstallJob {
            try await client.call("GET", "\(root)/\(id)", requires: .opsInstallJobs, as: Single<InstallJob>.self).data
        }

        public func create(_ draft: InstallJobDraft) async throws -> InstallJob {
            try await client.call(
                "POST", root, body: draft, requires: .opsInstallJobs, as: Single<InstallJob>.self).data
        }
    }

    public struct Runners: Sendable {
        let client: GujoStaffAPIClient
        let root: String

        public func list() async throws -> Page<Runner> {
            try await client.call("GET", root, requires: .opsRunners)
        }

        public func heartbeat(_ id: String, _ beat: RunnerHeartbeat) async throws {
            let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
            _ = try await client.call(
                "POST", "\(root)/\(encoded)/heartbeat", body: beat, requires: .opsRunners, as: Empty.self)
        }
    }
}
