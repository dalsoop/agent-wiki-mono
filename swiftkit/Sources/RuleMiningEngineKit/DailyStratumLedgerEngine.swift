import Foundation
import HomeostasisEngineKit
import StateRootKit

/// 1일 단위 시계열 지층 스냅샷 (Daily Stratum Snapshot).
///
/// 매일 자정 수면 사이클이 완료될 때 단조 적층(Append-Only)되며,
/// 과거 1일 1일 쌓인 학습 데이터를 영구 보존하여 미래의 항상성 베이스라인 SSOT를 제공한다.
public struct DailyStratumSnapshot: Codable, Sendable, Equatable, Identifiable {
    public var id: String { dateString }
    public let dateString: String // "2026-09-14"
    public let timestamp: Date

    // 1일 누적 텔레메트리 (Daily Accumulated Telemetry)
    public let totalEpisodesCount: Int
    public let meanDurationMs: Double
    public let p95DurationMs: Double
    public let complaintCount: Int
    public let complaintRate: Double
    public let totalAstNodesScanned: Int

    // 항상성 공식 파라미터 (Homeostatic Formula Parameters)
    public let rollingBaselineMs: Double
    public let burnRate: Double
    public let entropyDelta: Double

    // 당일 룰 진화 기록 (Rule Evolution)
    public let activeRulesCount: Int
    public let newlyConsolidatedRuleIds: [String]
    public let quarantinedRuleIds: [String]

    public init(
        dateString: String,
        timestamp: Date = Date(),
        totalEpisodesCount: Int,
        meanDurationMs: Double,
        p95DurationMs: Double,
        complaintCount: Int,
        complaintRate: Double,
        totalAstNodesScanned: Int,
        rollingBaselineMs: Double,
        burnRate: Double,
        entropyDelta: Double,
        activeRulesCount: Int,
        newlyConsolidatedRuleIds: [String],
        quarantinedRuleIds: [String]
    ) {
        self.dateString = dateString
        self.timestamp = timestamp
        self.totalEpisodesCount = totalEpisodesCount
        self.meanDurationMs = meanDurationMs
        self.p95DurationMs = p95DurationMs
        self.complaintCount = complaintCount
        self.complaintRate = complaintRate
        self.totalAstNodesScanned = totalAstNodesScanned
        self.rollingBaselineMs = rollingBaselineMs
        self.burnRate = burnRate
        self.entropyDelta = entropyDelta
        self.activeRulesCount = activeRulesCount
        self.newlyConsolidatedRuleIds = newlyConsolidatedRuleIds
        self.quarantinedRuleIds = quarantinedRuleIds
    }
}

/// 1일치 시계열 지층 저장소 및 롤링 베이스라인 엔진 (Daily Stratum Ledger Engine).
public final class DailyStratumLedgerEngine: @unchecked Sendable {
    public static let shared = DailyStratumLedgerEngine()

    private let lock = NSLock()
    private let stratumDirectory: URL
    private let baselineFile: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(storageDirectory: URL? = nil) {
        let dir: URL
        if let storageDirectory {
            dir = storageDirectory
        } else {
            dir = StateRootKit.url(".agent-lint/stratum")
        }
        self.stratumDirectory = dir
        self.baselineFile = dir.appendingPathComponent("current-baseline.json")

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        ensureDirectory()
    }

    private func ensureDirectory() {
        if !FileManager.default.fileExists(atPath: stratumDirectory.path) {
            do { try FileManager.default.createDirectory(at: stratumDirectory, withIntermediateDirectories: true) } catch { _ = error }
        }
    }

    /// 1일 단위 지층 기록 영구 적층 (Freeze Daily Stratum)
    public func recordDailyStratum(_ snapshot: DailyStratumSnapshot) throws {
        lock.lock()
        defer { lock.unlock() }

        ensureDirectory()
        let fileURL = stratumDirectory.appendingPathComponent("\(snapshot.dateString).json")
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)

        // 최신 베이스라인 파일 갱신 (current-baseline.json)
        try data.write(to: baselineFile, options: .atomic)
    }

    /// 과거 N일간의 지층 데이터 질의
    public func queryStratumHistory(limitDays: Int = 30) -> [DailyStratumSnapshot] {
        lock.lock()
        defer { lock.unlock() }

        guard let files = try? FileManager.default.contentsOfDirectory(at: stratumDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        var results: [DailyStratumSnapshot] = []
        for file in files where file.pathExtension == "json" && file.lastPathComponent != "current-baseline.json" {
            guard let data = try? Data(contentsOf: file),
                  let snapshot = try? decoder.decode(DailyStratumSnapshot.self, from: data) else {
                continue
            }
            results.append(snapshot)
        }

        results.sort { $0.dateString < $1.dateString }
        if results.count > limitDays {
            return Array(results.suffix(limitDays))
        }
        return results
    }

    /// 과거 지층이 있으면 EWMA, 없고 오늘 평균이 있으면 그 평균, 둘 다 없으면 없음.
    public func calculateRollingBaseline(fallbackTodayMeanMs: Double? = nil) -> Double? {
        let history = queryStratumHistory(limitDays: 7)
        guard !history.isEmpty else {
            return fallbackTodayMeanMs
        }

        let alpha = 1.0 / (1.0 + Double(history.count))
        var baseline = history.first!.rollingBaselineMs > 0 ? history.first!.rollingBaselineMs : history.first!.meanDurationMs
        for snapshot in history {
            baseline = (alpha * snapshot.meanDurationMs) + ((1.0 - alpha) * baseline)
        }
        return baseline
    }

    /// 기준선이 없으면 평가하지 않는다.
    public func evaluateHomeostaticHealth(
        todayMeanMs: Double,
        todayComplaintRate: Double,
        sampleCount: Int
    ) -> HomeostasisEngineKit.EquilibriumDecision? {
        guard let baseline = calculateRollingBaseline(fallbackTodayMeanMs: todayMeanMs) else {
            return nil
        }
        let snapshot = HomeostasisEngineKit.TimeSeriesSnapshot(
            mean: todayMeanMs,
            baseline: baseline,
            complaintRate: todayComplaintRate,
            sampleCount: sampleCount
        )
        return HomeostasisEngineKit.evaluateHomeostasis(snapshot: snapshot)
    }
}
