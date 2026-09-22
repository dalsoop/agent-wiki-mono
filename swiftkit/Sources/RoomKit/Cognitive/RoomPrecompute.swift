import Foundation
import CryptoKit

/// 작업 복잡도 및 감사 강도 계층 (Tiered Ledgering)
public enum CognitiveTier: String, Codable, Sendable, CaseIterable {
    /// 1~2개 파일의 단순 오타, 린트 기계 수정, 버전 범프 (원장 면제 또는 최소 기록)
    case trivial = "trivial"
    /// 일반적인 기능 구현 및 단위 테스트 작성 (초경량 Precompute 4대 필드 필수)
    case standard = "standard"
    /// 공유 Kit 수정, 아키텍처 결합도 변경 (전수 정밀 Precompute + 의존성 선언 필수)
    case architectural = "architectural"
}

/// 사전 가계산 수치 및 선언 스펙
public struct CognitiveEstimate: Codable, Sendable, Equatable {
    public let lines: Int
    public let durationSec: Int
    public let declaredImports: [String]

    public init(
        lines: Int,
        durationSec: Int,
        declaredImports: [String] = []
    ) {
        self.lines = max(lines, 0)
        self.durationSec = max(durationSec, 0)
        self.declaredImports = declaredImports.sorted()
    }
}

/// 룸 작업 착수 전 선제적 초경량 가계산 (Micro-Precompute)
///
/// [Zero-Self-Report 원칙]:
/// 자유 서술 산문(Prose)을 100% 금지하며, 128 토큰 이내의 엄밀한 마이크로 스펙만 선언한다.
/// 파일 수정 도구가 실행되기 전에 반드시 SHA-256 해시로 잠금(Commitment Lock)되어야 한다.
public struct RoomPrecompute: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(tenantID):\(roomID):precompute" }
    public let roomID: String
    public let tenantID: String
    public let tier: CognitiveTier
    /// 수정 예정인 대상 파일 상대 경로 목록
    public let targets: [String]
    /// 예상 수정 라인 수 (추가 + 삭제)
    public var estimatedLines: Int { estimate.lines }
    /// 예상 소요 시간 (초)
    public var estimatedDurationSec: Int { estimate.durationSec }
    /// 신규 추가할 외부 모듈/임포트 목록
    public var declaredImports: [String] { estimate.declaredImports }
    /// 정량 가계산 스펙
    public let estimate: CognitiveEstimate
    /// 참조하는 선행 룸 ID 목록 (시냅스 입력)
    public let predecessorRoomIDs: [String]
    /// 가계산 선언 고정 해시 (SHA-256)
    public let commitmentHash: String
    /// 기록 시점
    public let recordedAt: Date

    public init(
        roomID: String,
        tenantID: String,
        tier: CognitiveTier = .standard,
        targets: [String],
        estimate: CognitiveEstimate,
        predecessorRoomIDs: [String] = [],
        recordedAt: Date = Date()
    ) {
        self.roomID = roomID
        self.tenantID = tenantID
        self.tier = tier
        self.targets = targets.sorted()
        self.estimate = estimate
        self.predecessorRoomIDs = predecessorRoomIDs.sorted()
        self.recordedAt = recordedAt

        // 정규화된 마이크로 페이로드로 불변 SHA-256 계산
        let rawPayload = "\(roomID):\(tenantID):\(tier.rawValue):\(self.targets.joined(separator: ",")):\(estimate.lines):\(estimate.durationSec):\(estimate.declaredImports.joined(separator: ","))"
        let digest = SHA256.hash(data: Data(rawPayload.utf8))
        self.commitmentHash = digest.map { String(format: "%02x", $0) }.joined()
    }
}
