import Foundation

public enum PhotoLedgerError: Error, Sendable, Equatable, CustomStringConvertible {
    case unavailable(String)
    case failed(String)

    public var description: String {
        switch self {
        case .unavailable(let path): return "ledger unavailable: \(path)"
        case .failed(let detail): return detail
        }
    }
}

public struct LedgerSessionRef: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var blobCount: Int
    /// 세션 종류(photo-origin-ledger OriginSession.kind 의 문자열). 구형 원장 JSON엔 없다.
    public var kind: String?
    /// 세션 원본 루트 상대경로. 구형 원장 JSON엔 없다.
    public var originRel: String?

    public init(id: String, label: String, blobCount: Int,
                kind: String? = nil, originRel: String? = nil) {
        self.id = id
        self.label = label
        self.blobCount = blobCount
        self.kind = kind
        self.originRel = originRel
    }
}

public struct LedgerBlobRef: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sessionId: String
    public var name: String
    public var rel: String
    /// 촬영 시각 ISO8601(원장이 기록했을 때만). 구형 원장 JSON엔 없다.
    public var capturedAt: String?

    public init(id: String, sessionId: String, name: String, rel: String,
                capturedAt: String? = nil) {
        self.id = id
        self.sessionId = sessionId
        self.name = name
        self.rel = rel
        self.capturedAt = capturedAt
    }
}

public struct LedgerHealth: Codable, Sendable, Equatable {
    public var shareMounted: Bool
    public var sessionCount: Int
    public var blobCount: Int
    public var onboardingComplete: Bool

    public init(
        shareMounted: Bool,
        sessionCount: Int,
        blobCount: Int,
        onboardingComplete: Bool
    ) {
        self.shareMounted = shareMounted
        self.sessionCount = sessionCount
        self.blobCount = blobCount
        self.onboardingComplete = onboardingComplete
    }
}
