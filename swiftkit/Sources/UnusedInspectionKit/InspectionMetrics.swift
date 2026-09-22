import Foundation

/// 분석 결과의 3단계 확신도 게이트
public enum InspectionConfidence: String, Codable, Sendable {
    case high       // 명확한 0회 참조 / 미사용 (일괄 격리 허용)
    case medium     // 주석/로그/유사 토큰 존재 (확인 필요)
    case low        // 동적 라우터 경유, 보간식 유사성 (자동 격리 원천 금지, 수동 확인 필수)
}

/// 공통 리포트 요약 통계
public struct InspectionMetrics: Codable, Sendable {
    public let appSlug: String
    public let scannedAt: Date
    public let totalItemsChecked: Int
    public let unusedCount: Int
    public let reclaimableByteSize: Int64
    public let highConfidenceCount: Int
    public let mediumConfidenceCount: Int
    public let lowConfidenceCount: Int

    public init(
        appSlug: String,
        scannedAt: Date = Date(),
        totalItemsChecked: Int,
        unusedCount: Int,
        reclaimableByteSize: Int64,
        highConfidenceCount: Int,
        mediumConfidenceCount: Int = 0,
        lowConfidenceCount: Int = 0
    ) {
        self.appSlug = appSlug
        self.scannedAt = scannedAt
        self.totalItemsChecked = totalItemsChecked
        self.unusedCount = unusedCount
        self.reclaimableByteSize = reclaimableByteSize
        self.highConfidenceCount = highConfidenceCount
        self.mediumConfidenceCount = mediumConfidenceCount
        self.lowConfidenceCount = lowConfidenceCount
    }
}

/// CLI 표준 Envelope 출력 래퍼 (모노레포 정본)
public struct InspectionEnvelope<T: Codable & Sendable>: Codable, Sendable {
    public let ok: Bool
    public let result: T?
    public let error: String?

    public init(ok: Bool, result: T? = nil, error: String? = nil) {
        self.ok = ok
        self.result = result
        self.error = error
    }
}
