import Foundation
import StateRootKit

/// 과거 룸의 인지 원장 종합 기록 (검색 및 시냅스 탐색 결과)
public struct RoomCognitiveRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(tenantID):\(roomID)" }
    public let roomID: String
    public let tenantID: String
    public let precompute: RoomPrecompute?
    public let delta: RoomDelta?
    public let synapses: [RoomSynapseEdge]
    public let relevanceScore: Double

    public init(
        roomID: String,
        tenantID: String,
        precompute: RoomPrecompute? = nil,
        delta: RoomDelta? = nil,
        synapses: [RoomSynapseEdge] = [],
        relevanceScore: Double = 0.0
    ) {
        self.roomID = roomID
        self.tenantID = tenantID
        self.precompute = precompute
        self.delta = delta
        self.synapses = synapses
        self.relevanceScore = relevanceScore
    }
}

/// 룸 단위 가계산(Precompute), 사후 오차(Delta), 시냅스 그래프를 영구 관리하는 단일 진실의 원천
public struct RoomCognitiveLedger: Sendable {
    private var fileManager: FileManager { .default }
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    // MARK: - Precompute (선제적 가계산)

    /// 룸 착수 전 마이크로 가계산을 원자적으로 기록
    @discardableResult
    public func recordPrecompute(_ precompute: RoomPrecompute, in layout: RoomVaultLayout) throws -> RoomPrecompute {
        try ensureCognitiveDirectory(at: layout)
        let data = try encoder.encode(precompute)
        try data.write(to: layout.precomputeFile, options: .atomic)
        return precompute
    }

    /// 룸의 선제적 가계산 조회
    public func readPrecompute(in layout: RoomVaultLayout) -> RoomPrecompute? {
        guard fileManager.fileExists(atPath: layout.precomputeFile.path) else { return nil }
        do {
            let data = try Data(contentsOf: layout.precomputeFile)
            return try decoder.decode(RoomPrecompute.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Delta (사후 오차 평가 - 기계적 실측치)

    /// 룸 완료 후 기계적으로 측정된 사후 델타를 원자적으로 기록
    @discardableResult
    public func recordDelta(_ delta: RoomDelta, in layout: RoomVaultLayout) throws -> RoomDelta {
        try ensureCognitiveDirectory(at: layout)
        let data = try encoder.encode(delta)
        try data.write(to: layout.deltaFile, options: .atomic)

        // 가설 기각 또는 심각한 스쿱 침범 발생 시, 선행 룸들에 반증/비판 시냅스 자동 체결
        if delta.requiresFalsificationSynapse || delta.driftScore >= 35.0 {
            if let precompute = readPrecompute(in: layout) {
                for priorRoomID in precompute.predecessorRoomIDs {
                    let edge = RoomSynapseEdge(
                        sourceRoomID: delta.roomID,
                        targetRoomID: priorRoomID,
                        kind: delta.requiresFalsificationSynapse ? .invalidates : .critiques,
                        weight: delta.driftScore / 100.0,
                        summary: "Empirical drift breach (\(Int(delta.driftScore)) pts) in room \(delta.roomID)"
                    )
                    try appendSynapse(edge, in: layout)
                }
            }
        }

        return delta
    }

    /// 룸의 사후 오차 기록 조회
    public func readDelta(in layout: RoomVaultLayout) -> RoomDelta? {
        guard fileManager.fileExists(atPath: layout.deltaFile.path) else { return nil }
        do {
            let data = try Data(contentsOf: layout.deltaFile)
            return try decoder.decode(RoomDelta.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Synapse (시냅스 그래프 및 물리적 마스크)

    /// 룸 간 시냅스 에지 추가
    public func appendSynapse(_ edge: RoomSynapseEdge, in layout: RoomVaultLayout) throws {
        try ensureCognitiveDirectory(at: layout)
        var edges = readSynapses(in: layout)
        if !edges.contains(where: { $0.id == edge.id }) {
            edges.append(edge)
            let data = try encoder.encode(edges)
            try data.write(to: layout.synapsesFile, options: .atomic)
        }
    }

    /// 룸의 시냅스 에지 목록 조회
    public func readSynapses(in layout: RoomVaultLayout) -> [RoomSynapseEdge] {
        guard fileManager.fileExists(atPath: layout.synapsesFile.path) else { return [] }
        do {
            let data = try Data(contentsOf: layout.synapsesFile)
            return try decoder.decode([RoomSynapseEdge].self, from: data)
        } catch {
            return []
        }
    }

    /// 선행 룸들 중 기각/비판(invalidates)된 방들의 실패 경로를 수집하여 물리적 쓰기 마스크를 생성
    public func buildSynapseMask(
        for roomID: String,
        tenant: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> RoomSynapseMask {
        let indexer = RoomMemoryIndexer()
        let layouts = indexer.listRooms(tenant: tenant, environment: environment)

        var maskedFiles: Set<String> = []
        var blockingRooms: Set<String> = []

        for layout in layouts {
            let otherRoomID = layout.roomURL.lastPathComponent
            guard otherRoomID != roomID else { continue }

            let edges = readSynapses(in: layout)
            let hasInvalidatingEdge = edges.contains { $0.kind == .invalidates }
            guard let delta = readDelta(in: layout), delta.requiresFalsificationSynapse || hasInvalidatingEdge else {
                continue
            }

            maskedFiles.formUnion(delta.actualTouchedFiles)
            blockingRooms.insert(otherRoomID)
        }

        return RoomSynapseMask(
            roomID: roomID,
            maskedFilePaths: Array(maskedFiles),
            blockingRoomIDs: Array(blockingRooms)
        )
    }

    // MARK: - Context Retrieval (선행 경험 및 실패 교훈 우선 인출)

    /// 새로운 룸 가계산 시점에 테넌트 내 이전 룸들의 실패/성공 경험을 자동 탐색
    public func findPriorCognitiveRecords(
        matching query: String,
        tenant: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [RoomCognitiveRecord] {
        let indexer = RoomMemoryIndexer()
        let layouts = indexer.listRooms(tenant: tenant, environment: environment)
        let loweredQuery = query.lowercased().trimmingCharacters(in: .whitespaces)

        var records: [RoomCognitiveRecord] = []

        for layout in layouts {
            let roomID = layout.roomURL.lastPathComponent
            let precompute = readPrecompute(in: layout)
            let delta = readDelta(in: layout)
            let synapses = readSynapses(in: layout)

            guard precompute != nil || delta != nil else { continue }

            let score = calculateRelevance(
                loweredQuery: loweredQuery,
                precompute: precompute,
                delta: delta
            )

            guard score > 0.0 || loweredQuery.isEmpty else { continue }

            records.append(
                RoomCognitiveRecord(
                    roomID: roomID,
                    tenantID: tenant,
                    precompute: precompute,
                    delta: delta,
                    synapses: synapses,
                    relevanceScore: score
                )
            )
        }

        return records.sorted { $0.relevanceScore > $1.relevanceScore }
    }

    // MARK: - Private Helpers

    private func ensureCognitiveDirectory(at layout: RoomVaultLayout) throws {
        if !fileManager.fileExists(atPath: layout.cognitiveDir.path) {
            try fileManager.createDirectory(at: layout.cognitiveDir, withIntermediateDirectories: true)
        }
    }

    private func calculateRelevance(
        loweredQuery: String,
        precompute: RoomPrecompute?,
        delta: RoomDelta?
    ) -> Double {
        scorePrecompute(loweredQuery: loweredQuery, precompute: precompute)
            + scoreDelta(loweredQuery: loweredQuery, delta: delta)
    }

    private func scorePrecompute(loweredQuery: String, precompute: RoomPrecompute?) -> Double {
        guard let pre = precompute else { return 0.0 }
        let targetMatch = pre.targets.contains { $0.lowercased().contains(loweredQuery) } ? 40.0 : 0.0
        let importMatch = pre.declaredImports.contains { $0.lowercased().contains(loweredQuery) } ? 20.0 : 0.0
        return targetMatch + importMatch
    }

    private func scoreDelta(loweredQuery: String, delta: RoomDelta?) -> Double {
        guard let d = delta else { return 0.0 }
        let fileMatch = d.actualTouchedFiles.contains { $0.lowercased().contains(loweredQuery) } ? 30.0 : 0.0
        // 실패/기각된 방은 다음 에이전트가 반드시 회피해야 하므로 음성 교훈 가중치 50점 추가 부스트
        let falsificationBoost = d.requiresFalsificationSynapse ? 50.0 : 0.0
        let breachBoost = d.verdict == .breach ? 30.0 : 0.0
        return fileMatch + falsificationBoost + breachBoost
    }
}
