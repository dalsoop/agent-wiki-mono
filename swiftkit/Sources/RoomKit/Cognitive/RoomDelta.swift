import Foundation

/// 인지 드리프트 판정 결과
public enum CognitiveVerdict: String, Codable, Sendable, CaseIterable {
    /// driftScore <= 15: 정상 통과 (가계산과 실측치가 완벽히 부합)
    case pass = "pass"
    /// 16 <= driftScore <= 35: 경고 (허용 가능한 범위의 탐색적 편차, 회고 기록)
    case warning = "warning"
    /// driftScore > 35: 거부 및 게이트 차단 (심각한 스쿱 크립 또는 헛다리)
    case breach = "breach"
    /// 비상 탈출구(Break-Glass)로 게이트 우회 승인됨
    case bypassed = "bypassed"
}

/// 룸 작업 완료 후 사후 오차 평가 및 기계 계측치 (Empirical Delta)
///
/// [Zero-Self-Report 원칙]:
/// 에이전트가 이 구조체의 값을 직접 작성하거나 조작할 수 없다.
/// Git 인덱스, OS 커널 타이머, AST 분석 프로브(`RoomMechanicalProbe`)에 의해서만 산출된다.
public struct RoomDelta: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(tenantID):\(roomID):delta" }
    public let roomID: String
    public let tenantID: String
    /// 가계산 시점의 커밋먼트 해시
    public let commitmentHash: String
    /// 실제 수정된 파일 상대경로 목록 (git diff --name-only 실측)
    public let actualTouchedFiles: [String]
    /// 실제 추가된 라인 수 (git diff --numstat 실측)
    public let actualLinesAdded: Int
    /// 실제 삭제된 라인 수 (git diff --numstat 실측)
    public let actualLinesDeleted: Int
    /// 실제 벽시계 소요 시간 (초) (커널 타이머 실측)
    public let actualDurationSec: Double
    /// 사전 신고 없이 신규 추가된 의존성/임포트 목록
    public let unauthorizedImports: [String]
    /// 파일 집합 자카드 거리 기반 오차 (0.0 ~ 1.0)
    public let driftFile: Double
    /// 코드 규모 오차 (0.0 ~ 1.0)
    public let driftLines: Double
    /// 실행 시간 오차 (0.0 ~ 1.0)
    public let driftTime: Double
    /// 결합도 오차 (0.0 ~ 1.0)
    public let driftCoupling: Double
    /// 4대 오차 가중합 종합 점수 (0.0 ~ 100.0)
    public let driftScore: Double
    /// 최종 기계 판정 결과
    public let verdict: CognitiveVerdict
    /// 가설 기각 또는 스쿱 침범으로 인한 선행 룸 반증 필요 여부
    public let requiresFalsificationSynapse: Bool
    /// 비상 탈출구(Break-Glass) 발동 여부
    public let isBreakGlass: Bool
    /// 비상 탈출구 발동 사유 (긴급 P0 핫픽스 등)
    public let breakGlassReason: String?
    /// 계측 일시
    public let recordedAt: Date

    public init(
        roomID: String,
        tenantID: String,
        commitmentHash: String,
        actualTouchedFiles: [String],
        actualLinesAdded: Int,
        actualLinesDeleted: Int,
        actualDurationSec: Double,
        unauthorizedImports: [String] = [],
        driftFile: Double,
        driftLines: Double,
        driftTime: Double,
        driftCoupling: Double,
        driftScore: Double,
        verdict: CognitiveVerdict,
        requiresFalsificationSynapse: Bool,
        isBreakGlass: Bool = false,
        breakGlassReason: String? = nil,
        recordedAt: Date = Date()
    ) {
        self.roomID = roomID
        self.tenantID = tenantID
        self.commitmentHash = commitmentHash
        self.actualTouchedFiles = actualTouchedFiles.sorted()
        self.actualLinesAdded = max(actualLinesAdded, 0)
        self.actualLinesDeleted = max(actualLinesDeleted, 0)
        self.actualDurationSec = max(actualDurationSec, 0.0)
        self.unauthorizedImports = unauthorizedImports.sorted()
        self.driftFile = min(max(driftFile, 0.0), 1.0)
        self.driftLines = min(max(driftLines, 0.0), 1.0)
        self.driftTime = min(max(driftTime, 0.0), 1.0)
        self.driftCoupling = min(max(driftCoupling, 0.0), 1.0)
        self.driftScore = min(max(driftScore, 0.0), 100.0)
        self.verdict = verdict
        self.requiresFalsificationSynapse = requiresFalsificationSynapse
        self.isBreakGlass = isBreakGlass
        self.breakGlassReason = breakGlassReason
        self.recordedAt = recordedAt
    }
}
