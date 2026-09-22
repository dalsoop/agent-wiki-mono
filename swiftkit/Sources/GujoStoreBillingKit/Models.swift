import Foundation

/// 배포 패키지 (Android APK 등). 서버 Package 리소스.
public struct OpsPackage: Sendable, Equatable, Identifiable, Codable {
    public var id: String { packageName }
    public let packageName: String
    public let displayName: String
    public let summary: String
    public let platform: String
    public let versionName: String?
    public let versionCode: Int?
    public let installURL: URL?
    public let artifactURL: URL?
    public let sizeBytes: Int64?
    public let status: String
    public let priceUsdCents: Int?
    public let accessDurationDays: Int?

    public init(
        packageName: String,
        displayName: String,
        summary: String = "",
        platform: String = "android",
        versionName: String? = nil,
        versionCode: Int? = nil,
        installURL: URL? = nil,
        artifactURL: URL? = nil,
        sizeBytes: Int64? = nil,
        status: String = "published",
        priceUsdCents: Int? = nil,
        accessDurationDays: Int? = nil
    ) {
        self.packageName = packageName
        self.displayName = displayName
        self.summary = summary
        self.platform = platform
        self.versionName = versionName
        self.versionCode = versionCode
        self.installURL = installURL
        self.artifactURL = artifactURL
        self.sizeBytes = sizeBytes
        self.status = status
        self.priceUsdCents = priceUsdCents
        self.accessDurationDays = accessDurationDays
    }
}

/// 관리 대상 기기.
public struct OpsDevice: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let label: String
    public let platform: String
    public let serial: String?
    public let state: String
    public let lastSeenAt: Date?

    public init(
        id: String,
        label: String,
        platform: String = "android",
        serial: String? = nil,
        state: String = "unknown",
        lastSeenAt: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.platform = platform
        self.serial = serial
        self.state = state
        self.lastSeenAt = lastSeenAt
    }

    public var isReady: Bool { state == "ready" || state == "device" }
}

public enum InstallJobStatus: String, Sendable, Codable, Equatable {
    case queued, claimed, running, succeeded, failed, cancelled
}

/// 서버 소유 설치 지시. Mac runner 가 claim/report.
public struct InstallJob: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let packageName: String
    public let deviceId: String
    public let status: InstallJobStatus
    public let createdBy: String?
    public let error: String?

    public init(
        id: String,
        packageName: String,
        deviceId: String,
        status: InstallJobStatus,
        createdBy: String? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.packageName = packageName
        self.deviceId = deviceId
        self.status = status
        self.createdBy = createdBy
        self.error = error
    }
}

public struct OpsHealth: Sendable, Equatable {
    public let ok: Bool
    public let service: String
    public let catalogBridge: String?
    /// `configured` | `unconfigured` | nil (구버전 서버)
    public let catalogPublish: String?
    /// `required` | `open` | nil — Bearer STORE_OPS_TOKEN 필요 여부
    public let opsAuth: String?
    public let runnersOnline: Int?

    public init(
        ok: Bool,
        service: String,
        catalogBridge: String? = nil,
        catalogPublish: String? = nil,
        opsAuth: String? = nil,
        runnersOnline: Int? = nil
    ) {
        self.ok = ok
        self.service = service
        self.catalogBridge = catalogBridge
        self.catalogPublish = catalogPublish
        self.opsAuth = opsAuth
        self.runnersOnline = runnersOnline
    }
}

/// Mac adb runner 하트비트 상태.
public struct OpsRunner: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let host: String
    public let label: String?
    public let status: String
    public let online: Bool
    public let adbReadyCount: Int
    public let lastSeenAt: String?

    public init(
        id: String,
        host: String,
        label: String? = nil,
        status: String = "offline",
        online: Bool = false,
        adbReadyCount: Int = 0,
        lastSeenAt: String? = nil
    ) {
        self.id = id
        self.host = host
        self.label = label
        self.status = status
        self.online = online
        self.adbReadyCount = adbReadyCount
        self.lastSeenAt = lastSeenAt
    }
}

public enum StoreOpsError: Error, LocalizedError, Equatable {
    case http(Int)
    case decode(String)
    case empty
    case network(String)
    case notImplemented(String)
    case invalidReceipt(String)

    public var errorDescription: String? {
        switch self {
        case .http(let c): return "HTTP \(c)"
        case .decode(let m): return "decode: \(m)"
        case .empty: return "empty response"
        case .network(let m): return m
        case .notImplemented(let m): return "not implemented: \(m)"
        case .invalidReceipt(let m): return "invalid receipt: \(m)"
        }
    }
}

/// release-receipt.json 인제스트 결과 모델.
public struct ReceiptIngestResult: Codable, Sendable, Equatable {
    public let ok: Bool
    public let storeProductId: Int
    public let gujoProductId: Int?
    public let bundleId: String?
    public let version: String
    public let releaseId: Int
    public let isActive: Bool
    public let artifactSha256: String?
    public let artifactSize: Int64?
    public let notarySubmissionId: String?
    public let externalDownloadUrl: String?
    public let readinessScore: Int
    public let purchasable: Bool
    public let summary: String

    public init(
        ok: Bool,
        storeProductId: Int,
        gujoProductId: Int? = nil,
        bundleId: String? = nil,
        version: String,
        releaseId: Int,
        isActive: Bool,
        artifactSha256: String? = nil,
        artifactSize: Int64? = nil,
        notarySubmissionId: String? = nil,
        externalDownloadUrl: String? = nil,
        readinessScore: Int,
        purchasable: Bool,
        summary: String
    ) {
        self.ok = ok
        self.storeProductId = storeProductId
        self.gujoProductId = gujoProductId
        self.bundleId = bundleId
        self.version = version
        self.releaseId = releaseId
        self.isActive = isActive
        self.artifactSha256 = artifactSha256
        self.artifactSize = artifactSize
        self.notarySubmissionId = notarySubmissionId
        self.externalDownloadUrl = externalDownloadUrl
        self.readinessScore = readinessScore
        self.purchasable = purchasable
        self.summary = summary
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case storeProductId = "store_product_id"
        case gujoProductId = "gujo_product_id"
        case bundleId = "bundle_id"
        case version
        case releaseId = "release_id"
        case isActive = "is_active"
        case artifactSha256 = "artifact_sha256"
        case artifactSize = "artifact_size"
        case notarySubmissionId = "notary_submission_id"
        case externalDownloadUrl = "external_download_url"
        case readinessScore = "readiness_score"
        case purchasable
        case summary
    }
}
