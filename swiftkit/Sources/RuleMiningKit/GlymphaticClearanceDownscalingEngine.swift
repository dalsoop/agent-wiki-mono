import Foundation
import SQLite3
import CryptoKit

// MARK: - 1. 글림프 정화 및 축소 보고서 모델

public struct GlymphaticClearanceReport: Sendable, Codable, Equatable {
    public let initialTotalEnergy: Double
    public let finalTotalEnergy: Double
    public let energyConvergenceRatio: Double
    public let prunedLinksCount: Int
    public let purgedOrphanEntitiesCount: Int
    public let purgedOrphanCoordinatesCount: Int
    public let frozenBaseline: StrataBaselineMetrics
    public let isSuccess: Bool

    public init(
        initialTotalEnergy: Double,
        finalTotalEnergy: Double,
        energyConvergenceRatio: Double,
        prunedLinksCount: Int,
        purgedOrphanEntitiesCount: Int,
        purgedOrphanCoordinatesCount: Int,
        frozenBaseline: StrataBaselineMetrics,
        isSuccess: Bool
    ) {
        self.initialTotalEnergy = initialTotalEnergy
        self.finalTotalEnergy = finalTotalEnergy
        self.energyConvergenceRatio = energyConvergenceRatio
        self.prunedLinksCount = prunedLinksCount
        self.purgedOrphanEntitiesCount = purgedOrphanEntitiesCount
        self.purgedOrphanCoordinatesCount = purgedOrphanCoordinatesCount
        self.frozenBaseline = frozenBaseline
        self.isSuccess = isSuccess
    }
}

// MARK: - 2. 시냅스 항상성 축소(SHY) 및 글림프 정화 엔진 액터

public actor GlymphaticClearanceDownscalingEngine {
    private let sqliteStore: SpatiotemporalSQLiteStore
    private let stratumEngine: DailyStratumLedgerEngine

    public init(
        sqliteStore: SpatiotemporalSQLiteStore,
        stratumEngine: DailyStratumLedgerEngine = .shared
    ) {
        self.sqliteStore = sqliteStore
        self.stratumEngine = stratumEngine
    }

    /// SpatiotemporalSQLiteStore 액터를 통한 고수준 비동기 정화 진입점
    public func executeClearance(
        currentUptime: Double = ProcessInfo.processInfo.systemUptime,
        targetBaselineEnergy: Double,
        pruningThreshold: Double? = nil,
        protectionDeltaThreshold: Double? = nil
    ) async throws -> GlymphaticClearanceReport {
        try await sqliteStore.withDatabase { (db: OpaquePointer) in
            try self.executeDirect(
                on: db,
                currentUptime: currentUptime,
                targetBaselineEnergy: targetBaselineEnergy,
                pruningThreshold: pruningThreshold,
                protectionDeltaThreshold: protectionDeltaThreshold
            )
        }
    }

    /// SQLite 저수준 포인터 기반 닫힌 해 동기 실행 함수 (워커 4 명세 충족)
    public nonisolated func executeDirect(
        on db: OpaquePointer,
        currentUptime: Double,
        targetBaselineEnergy: Double,
        pruningThreshold: Double? = nil,
        protectionDeltaThreshold: Double? = nil
    ) throws -> GlymphaticClearanceReport {
        // Step 0: 트랜잭션 원자성 개시
        try Self.executeSQL(db, "BEGIN IMMEDIATE;")
        do {
            let report = try Self.performClearancePipeline(
                db: db,
                currentUptime: currentUptime,
                targetBaselineEnergy: targetBaselineEnergy,
                pruningThreshold: pruningThreshold,
                protectionDeltaThreshold: protectionDeltaThreshold
            )
            try Self.executeSQL(db, "COMMIT;")
            return report
        } catch {
            Self.rollbackSilently(db)
            throw error
        }
    }

    // MARK: - 내부 파이프라인 연산

    private static func performClearancePipeline(
        db: OpaquePointer,
        currentUptime: Double,
        targetBaselineEnergy: Double,
        pruningThreshold: Double?,
        protectionDeltaThreshold: Double?
    ) throws -> GlymphaticClearanceReport {
        // Step 1: 초기 가중치 총합(Total Synaptic Energy) 실측
        let initialEnergy = try queryTotalWeight(db)

        // Step 2: Phase 4.1 지수 감쇠 (W * exp(-lambda * delta_t))
        // 보호 대상: 항상성 델타가 유의미하게 높은 핵심 좌표 (하드코딩 배제, 동적 임계치)
        let effectiveProtectionDelta = protectionDeltaThreshold ?? (1.0 - Double.ulpOfOne * 1024.0)
        let decaySQL = """
        UPDATE homeostatic_binding_links
        SET binding_weight = binding_weight * exp(-decay_lambda * max(0.0, ? - last_activated_time))
        WHERE coord_id NOT IN (
            SELECT coord_id FROM spatiotemporal_coordinates WHERE homeostatic_delta >= ?
        );
        """
        try executeParameterized(db, sql: decaySQL, double1: currentUptime, double2: effectiveProtectionDelta)

        // Step 2.1: 시스템 목표 에너지 비례 재규격화(Renormalization)
        let intermediateEnergy = try queryTotalWeight(db)
        if targetBaselineEnergy > 0.0 && intermediateEnergy > targetBaselineEnergy {
            let gamma = targetBaselineEnergy / max(Double.ulpOfOne, intermediateEnergy)
            let scaleSQL = """
            UPDATE homeostatic_binding_links
            SET binding_weight = binding_weight * ?
            WHERE coord_id NOT IN (
                SELECT coord_id FROM spatiotemporal_coordinates WHERE homeostatic_delta >= ?
            );
            """
            try executeParameterized(db, sql: scaleSQL, double1: gamma, double2: effectiveProtectionDelta)
        }

        // Step 3: Phase 4.2 저가중치 결속 링크 소거 (Synaptic Pruning)
        // 동적 임계치: 외부 주입 또는 기계 정밀도 기반
        let effectivePruningThreshold = pruningThreshold ?? (Double.ulpOfOne * 1048576.0)
        let pruneSQL = "DELETE FROM homeostatic_binding_links WHERE binding_weight < ?;"
        var pruneStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, pruneSQL, -1, &pruneStmt, nil) == SQLITE_OK, let pruneStmt else {
            throw NSError(domain: "GlymphaticClearanceDownscalingEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Prepare prune failed"])
        }
        defer { sqlite3_finalize(pruneStmt) }
        sqlite3_bind_double(pruneStmt, 1, effectivePruningThreshold)
        guard sqlite3_step(pruneStmt) == SQLITE_DONE else {
            throw NSError(domain: "GlymphaticClearanceDownscalingEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "Execute prune failed"])
        }
        let prunedLinksCount = Int(sqlite3_changes(db))

        // Step 4: Phase 4.3 글림프 고아 원자적 소거 (Glymphatic Orphan Purge)
        // 4.1 고아 좌표 삭제: homeostatic_binding_links에 참조되지 않는 좌표 영구 삭제
        let purgeCoordsSQL = "DELETE FROM spatiotemporal_coordinates WHERE coord_id NOT IN (SELECT DISTINCT coord_id FROM homeostatic_binding_links);"
        try executeSQL(db, purgeCoordsSQL)
        let purgedCoordsCount = Int(sqlite3_changes(db))

        // 4.2 고아 엔티티 삭제: 결속 링크가 없고 불변 기호(symbol)가 아닌 엔티티 영구 삭제
        let purgeEntitiesSQL = "DELETE FROM semantic_entities WHERE entity_id NOT IN (SELECT DISTINCT entity_id FROM homeostatic_binding_links) AND entity_type != 'symbol';"
        try executeSQL(db, purgeEntitiesSQL)
        let purgedEntitiesCount = Int(sqlite3_changes(db))

        // Step 5: Phase 4.4 고아 잔존 0건 검증 쿼리 (Zero Tolerance)
        let orphanEntityCount = try queryCount(db, sql: "SELECT COUNT(*) FROM semantic_entities WHERE entity_id NOT IN (SELECT DISTINCT entity_id FROM homeostatic_binding_links) AND entity_type != 'symbol';")
        let orphanCoordCount = try queryCount(db, sql: "SELECT COUNT(*) FROM spatiotemporal_coordinates WHERE coord_id NOT IN (SELECT DISTINCT coord_id FROM homeostatic_binding_links);")

        guard orphanEntityCount == 0 && orphanCoordCount == 0 else {
            throw NSError(
                domain: "GlymphaticClearanceDownscalingEngine",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Orphan residual detected: entities=\(orphanEntityCount), coords=\(orphanCoordCount)"]
            )
        }

        // Step 6: 최종 시스템 에너지 계측
        let finalEnergy = try queryTotalWeight(db)

        // Step 7: Phase 4.5 차세대 지층 롤링 기준선 동결 (StrataBaselineMetrics)
        let survivingWeights = try queryAllWeights(db)
        let frozenBaseline: StrataBaselineMetrics
        if survivingWeights.isEmpty {
            frozenBaseline = StrataBaselineMetrics(
                baselineMean: max(Double.ulpOfOne, targetBaselineEnergy),
                baselineP95: max(Double.ulpOfOne, targetBaselineEnergy),
                baselineSigma: Double.ulpOfOne
            )
        } else {
            let n = Double(survivingWeights.count)
            let mean = survivingWeights.reduce(0.0, +) / n
            let variance = survivingWeights.map { pow($0 - mean, 2.0) }.reduce(0.0, +) / n
            let sigma = sqrt(variance)

            let sorted = survivingWeights.sorted()
            let p95Index = min(sorted.count - 1, max(0, Int(Double(sorted.count) * 0.95)))
            let p95 = sorted[p95Index]

            frozenBaseline = StrataBaselineMetrics(
                baselineMean: mean,
                baselineP95: p95,
                baselineSigma: max(Double.ulpOfOne, sigma)
            )
        }

        let ratio = targetBaselineEnergy > 0.0 ? (abs(finalEnergy - targetBaselineEnergy) / targetBaselineEnergy) : 0.0
        let isSuccess = (ratio <= 0.05) && (orphanEntityCount == 0) && (orphanCoordCount == 0)

        return GlymphaticClearanceReport(
            initialTotalEnergy: initialEnergy,
            finalTotalEnergy: finalEnergy,
            energyConvergenceRatio: ratio,
            prunedLinksCount: prunedLinksCount,
            purgedOrphanEntitiesCount: purgedEntitiesCount,
            purgedOrphanCoordinatesCount: purgedCoordsCount,
            frozenBaseline: frozenBaseline,
            isSuccess: isSuccess
        )
    }

    // MARK: - SQLite C-API 저수준 헬퍼

    private static func executeSQL(_ db: OpaquePointer, _ sql: String) throws {
        var errmsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errmsg) != SQLITE_OK {
            let msg = errmsg.map { String(cString: $0) } ?? "Unknown SQLite error"
            sqlite3_free(errmsg)
            throw NSError(domain: "GlymphaticClearanceDownscalingEngine", code: 4, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    private static func executeParameterized(_ db: OpaquePointer, sql: String, double1: Double, double2: Double) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw NSError(domain: "GlymphaticClearanceDownscalingEngine", code: 5, userInfo: [NSLocalizedDescriptionKey: "Prepare parameterized failed"])
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, double1)
        sqlite3_bind_double(stmt, 2, double2)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw NSError(domain: "GlymphaticClearanceDownscalingEngine", code: 6, userInfo: [NSLocalizedDescriptionKey: "Step parameterized failed"])
        }
    }

    private static func queryTotalWeight(_ db: OpaquePointer) throws -> Double {
        let sql = "SELECT COALESCE(SUM(binding_weight), 0.0) FROM homeostatic_binding_links;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw NSError(domain: "GlymphaticClearanceDownscalingEngine", code: 7, userInfo: [NSLocalizedDescriptionKey: "Prepare total weight failed"])
        }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_double(stmt, 0)
        }
        return 0.0
    }

    private static func queryCount(_ db: OpaquePointer, sql: String) throws -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw NSError(domain: "GlymphaticClearanceDownscalingEngine", code: 8, userInfo: [NSLocalizedDescriptionKey: "Prepare count failed"])
        }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }

    private static func queryAllWeights(_ db: OpaquePointer) throws -> [Double] {
        let sql = "SELECT binding_weight FROM homeostatic_binding_links ORDER BY binding_weight ASC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw NSError(domain: "GlymphaticClearanceDownscalingEngine", code: 9, userInfo: [NSLocalizedDescriptionKey: "Prepare all weights failed"])
        }
        defer { sqlite3_finalize(stmt) }
        var weights: [Double] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            weights.append(sqlite3_column_double(stmt, 0))
        }
        return weights
    }

    private static func rollbackSilently(_ db: OpaquePointer) {
        sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
    }
}
