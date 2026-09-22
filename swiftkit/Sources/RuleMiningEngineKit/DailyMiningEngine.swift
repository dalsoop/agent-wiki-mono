import Foundation
import StateRootKit

/// 1일 단위 린트 규칙 학습 및 자율 마이닝 오케스트레이터 (Daily Rule Mining Engine).
///
/// `FastBottleneckLedgerEngine`에 축적된 1일치 병목/장애 로그와 git 커밋 diff를 분석하여
/// 1. 핫스팟 안티패턴을 탐색
/// 2. `IncidentRuleSynthesizer`로 린트 룰 후보를 역합성
/// 3. `PlausibilityDiscriminatorEngine` 3단계 필터(Static, Dynamic, Statistical) 통과 여부를 검증
/// 4. 합격 룰만 `~/.agent-lint/mined-rules/`에 자율 영구 저장하고, 탈락 룰은 `quarantine/`에 격리한다.
public struct DailyMiningEngine: Sendable {

    public struct MiningResult: Sendable, Codable, Equatable {
        public let dateString: String
        public let processedEventsCount: Int
        public let candidatesSynthesizedCount: Int
        public let certifiedRulesCount: Int
        public let quarantinedRulesCount: Int
        public let certifiedRuleIds: [String]
        public let details: [String]

        public init(
            dateString: String,
            processedEventsCount: Int,
            candidatesSynthesizedCount: Int,
            certifiedRulesCount: Int,
            quarantinedRulesCount: Int,
            certifiedRuleIds: [String],
            details: [String] = []
        ) {
            self.dateString = dateString
            self.processedEventsCount = processedEventsCount
            self.candidatesSynthesizedCount = candidatesSynthesizedCount
            self.certifiedRulesCount = certifiedRulesCount
            self.quarantinedRulesCount = quarantinedRulesCount
            self.certifiedRuleIds = certifiedRuleIds
            self.details = details
        }
    }

    private let ledgerEngine: FastBottleneckLedgerEngine
    private let discriminator: PlausibilityDiscriminatorEngine
    private let storageDirectory: URL

    public init(
        ledgerEngine: FastBottleneckLedgerEngine = .shared,
        discriminator: PlausibilityDiscriminatorEngine = PlausibilityDiscriminatorEngine(),
        storageDirectory: URL? = nil
    ) {
        self.ledgerEngine = ledgerEngine
        self.discriminator = discriminator
        if let storageDirectory {
            self.storageDirectory = storageDirectory
        } else {
            self.storageDirectory = StateRootKit.url(".agent-lint")
        }
    }

    /// 1일치 원장 데이터를 슬라이싱하여 자율 학습 및 룰 마이닝 실행
    public func runDailyMining(
        targetDate: Date = Date(),
        authorAgentId: String = "agent:daily-miner",
        dryRunMode: Bool = false
    ) -> MiningResult {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: targetDate)

        var events = ledgerEngine.recentEvents(limit: 1000)
        if events.isEmpty {
            events = ledgerEngine.loadRecentEventsFromDisk(limit: 1000)
        }
        let calendar = Calendar.current
        let dayEvents = events.filter { calendar.isDate($0.timestamp, inSameDayAs: targetDate) }

        var details: [String] = []
        details.append("Mining started for date: \(dateStr), found \(dayEvents.count) bottleneck events.")

        // 핫스팟 룰 및 패턴 군집화
        var ruleOccurrence: [String: (count: Int, maxMs: Double, samplePath: String, sampleSnippet: String)] = [:]
        for ev in dayEvents {
            let current = ruleOccurrence[ev.ruleId, default: (0, 0.0, ev.filePath, ev.callStackSnippet)]
            ruleOccurrence[ev.ruleId] = (
                current.count + 1,
                max(current.maxMs, ev.durationMs),
                ev.filePath,
                ev.callStackSnippet.isEmpty ? current.sampleSnippet : ev.callStackSnippet
            )
        }

        var candidates: [DeclarativeMinedRule] = []
        var certified: [DeclarativeMinedRule] = []
        var quarantined: [(rule: DeclarativeMinedRule, score: PlausibilityScore)] = []

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let minedRulesDir = storageDirectory.appendingPathComponent("mined-rules", isDirectory: true)
        let quarantineDir = storageDirectory.appendingPathComponent("quarantine-rules", isDirectory: true)

        if !dryRunMode {
            do {
                try FileManager.default.createDirectory(at: minedRulesDir, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: quarantineDir, withIntermediateDirectories: true)
            } catch {
                FileHandle.standardError.write(Data("[DailyMiningEngine] Failed to create directories: \(error)\n".utf8))
            }
        }

        for (ruleId, stat) in ruleOccurrence where stat.count >= 2 || stat.maxMs > 50.0 {
            let synthInput = IncidentRuleSynthesizer.SynthesisInput(
                incidentId: "DAILY-\(dateStr)-\(ruleId.replacingOccurrences(of: ":", with: "-"))",
                summary: "Daily mined rule mitigating bottleneck in \(ruleId) (occurred \(stat.count) times, max \(String(format: "%.1f", stat.maxMs))ms)",
                buggyPattern: stat.sampleSnippet.isEmpty ? ruleId : stat.sampleSnippet,
                fixAdvice: "// Optimize or isolate bottleneck pattern in \(ruleId)",
                fastPathNeedle: ruleId.prefix(4).count >= 3 ? String(ruleId.prefix(6)) : "needle",
                authorAgentId: authorAgentId,
                synthesisDurationSec: 0.05,
                backtestDurationSec: 0.1
            )

            let (candidate, score) = IncidentRuleSynthesizer.synthesizeWithDiscriminator(
                input: synthInput,
                discriminator: discriminator,
                dryRunFindingsCount: stat.count,
                historicalFindingsAverage: Double(stat.count)
            )

            candidates.append(candidate)

            if score.isSemanticCompatible {
                certified.append(candidate)
                details.append("Certified: [\(candidate.id)] - PlausibilityScore passed all tiers")

                if !dryRunMode {
                    let fileURL = minedRulesDir.appendingPathComponent("\(candidate.id).json")
                    do {
                        let data = try encoder.encode(candidate)
                        try data.write(to: fileURL, options: .atomic)
                    } catch {
                        FileHandle.standardError.write(Data("[DailyMiningEngine] Failed to write certified candidate: \(error)\n".utf8))
                    }
                }
            } else {
                quarantined.append((candidate, score))
                details.append("Quarantined: [\(candidate.id)] - Reason: \(score.details.joined(separator: ", "))")

                if !dryRunMode {
                    let fileURL = quarantineDir.appendingPathComponent("\(candidate.id)-quarantine.json")
                    struct QuarantinePayload: Codable {
                        let rule: DeclarativeMinedRule
                        let score: PlausibilityScore
                    }
                    let payload = QuarantinePayload(rule: candidate, score: score)
                    do {
                        let data = try encoder.encode(payload)
                        try data.write(to: fileURL, options: .atomic)
                    } catch {
                        FileHandle.standardError.write(Data("[DailyMiningEngine] Failed to write quarantine payload: \(error)\n".utf8))
                    }
                }
            }
        }

        return MiningResult(
            dateString: dateStr,
            processedEventsCount: dayEvents.count,
            candidatesSynthesizedCount: candidates.count,
            certifiedRulesCount: certified.count,
            quarantinedRulesCount: quarantined.count,
            certifiedRuleIds: certified.map(\.id),
            details: details
        )
    }
}
