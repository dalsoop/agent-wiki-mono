import Foundation

/// 룸 간 시냅스 관계 유형 (Synapse Edge Kind)
public enum SynapseKind: String, Codable, Sendable, CaseIterable {
    case predecessor = "predecessor" // 직전 룸 인수인계 사슬
    case derivesFrom = "derivesFrom" // 선행 룸의 문제의식에서 파생됨
    case critiques = "critiques" // 선행 룸의 설계/결과물을 비판·교정함
    case invalidates = "invalidates" // 선행 룸의 가설이 거짓임을 반증함
    case analogousTo = "analogousTo" // 유사한 문제 도메인 또는 패턴을 다룸
    case falsifiedBy = "falsifiedBy" // 후속 룸에 의해 가설이 기각됨
}

/// 룸 간 방향성 시냅스 에지 (Room Synapse Edge)
public struct RoomSynapseEdge: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(sourceRoomID)->\(targetRoomID):\(kind.rawValue)" }
    public let sourceRoomID: String
    public let targetRoomID: String
    public let kind: SynapseKind
    public let weight: Double // 0.0 ~ 1.0 (연관성 및 인과 강도)
    public let summary: String
    public let createdAt: Date

    public init(
        sourceRoomID: String,
        targetRoomID: String,
        kind: SynapseKind,
        weight: Double = 1.0,
        summary: String,
        createdAt: Date = Date()
    ) {
        self.sourceRoomID = sourceRoomID
        self.targetRoomID = targetRoomID
        self.kind = kind
        self.weight = min(max(weight, 0.0), 1.0)
        self.summary = summary
        self.createdAt = createdAt
    }
}

/// 특정 룸의 시냅스 연결망 (Room Synapse Graph)
public struct RoomSynapseGraph: Codable, Sendable, Equatable {
    public let roomID: String
    public let tenantID: String
    public var outgoingEdges: [RoomSynapseEdge]
    public var incomingEdges: [RoomSynapseEdge]
    public let updatedAt: Date

    public init(
        roomID: String,
        tenantID: String,
        outgoingEdges: [RoomSynapseEdge] = [],
        incomingEdges: [RoomSynapseEdge] = [],
        updatedAt: Date = Date()
    ) {
        self.roomID = roomID
        self.tenantID = tenantID
        self.outgoingEdges = outgoingEdges
        self.incomingEdges = incomingEdges
        self.updatedAt = updatedAt
    }
}

/// 시냅스 기반 물리적 쓰기 마스크 (Synaptic Write Mask)
///
/// [헌법 불변식 3: "벽 = 물리, 산문 금지"]:
/// 과거 실패/기각(invalidates)된 방의 잘못된 변경 경로를 물리적 마스크로 등록하여,
/// 다음 에이전트가 동일한 파일에 접근하거나 헛다리를 반복할 때 기계적으로 인터셉트한다.
public struct RoomSynapseMask: Codable, Sendable, Equatable {
    public let roomID: String
    /// 접근 금지 또는 특별 경고가 필요한 파일 패턴 집합
    public let maskedFilePaths: [String]
    /// 차단 사유 (어떤 선행 룸에서 기각되었는지)
    public let blockingRoomIDs: [String]

    public init(
        roomID: String,
        maskedFilePaths: [String] = [],
        blockingRoomIDs: [String] = []
    ) {
        self.roomID = roomID
        self.maskedFilePaths = maskedFilePaths.sorted()
        self.blockingRoomIDs = blockingRoomIDs.sorted()
    }

    /// 주어진 대상 파일 경로 중 마스크에 걸리는 위반 파일 목록 반환
    public func checkViolations(against targets: [String]) -> [String] {
        let maskSet = Set(maskedFilePaths)
        return targets.filter { maskSet.contains($0) }
    }
}
