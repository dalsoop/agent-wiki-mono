import Foundation
import FastDiskIOKit

// MARK: - 1. 앱별 아키텍처 부채 동결 레코드 (AppTraitDebt)

/// 개별 앱의 항상성 골든 트레이트 결손(기술 부채) 동결 스냅샷.
/// Shopify Packwerk(`package_todo.yml`) 및 ArchUnit(`FreezingArchRule`) 모델 차용.
public struct AppTraitDebt: Sendable, Codable, Equatable {
    /// 대상 앱 식별자 (slug)
    public let appSlug: String
    /// 동결 시점에 미채택된 골든 트레이트 목록 (결손 부채)
    public let missingTraits: [GoldenTrait]
    /// 트레이트별 잔존 원시 보일러플레이트 건수 (Key: GoldenTrait rawValue)
    public let boilerplateCounts: [String: Int]
    /// 잔존 원시 보일러플레이트 총 건수
    public let totalBoilerplateCount: Int
    /// 결손 위치 추적용 스니펫/경로 요약 (Key: GoldenTrait rawValue, Value: ["path:line"])
    public let recordedLocations: [String: [String]]
    /// 동결 타임스탬프
    public let frozenAt: Date

    public init(
        appSlug: String,
        missingTraits: [GoldenTrait],
        boilerplateCounts: [String: Int] = [:],
        totalBoilerplateCount: Int = 0,
        recordedLocations: [String: [String]] = [:],
        frozenAt: Date = Date()
    ) {
        self.appSlug = appSlug
        self.missingTraits = missingTraits.sorted { $0.rawValue < $1.rawValue }
        self.boilerplateCounts = boilerplateCounts
        self.totalBoilerplateCount = totalBoilerplateCount
        self.recordedLocations = recordedLocations
        self.frozenAt = frozenAt
    }

    public init(from result: AppGapScanResult, frozenAt: Date = Date()) {
        self.appSlug = result.appSlug
        self.missingTraits = result.missingTraits.sorted { $0.rawValue < $1.rawValue }
        var counts: [String: Int] = [:]
        var locations: [String: [String]] = [:]
        for gap in result.gaps where gap.isMissing {
            counts[gap.trait.rawValue] = gap.boilerplateCount
            locations[gap.trait.rawValue] = gap.boilerplateLocations.map { "\($0.filePath):\($0.lineNumber)" }
        }
        self.boilerplateCounts = counts
        self.totalBoilerplateCount = result.totalBoilerplateCount
        self.recordedLocations = locations
        self.frozenAt = frozenAt
    }

    /// 특정 트레이트가 동결 부채로 등록되어 있는지 확인
    public func hasDebt(for trait: GoldenTrait) -> Bool {
        missingTraits.contains(trait)
    }
}

// MARK: - 2. 단방향 래칫 베이스라인 SSOT 모델 (TraitBaseline)

/// 모노레포 전체 앱의 항상성 결손 상태를 영구 동결한 단일 진실의 원천(SSOT).
/// Spotify Backstage Soundcheck 및 Shopify Packwerk의 `package_todo` 원리를 구현하여,
/// 기존 부채는 통과시키되 신규 결손 유입을 원천 차단하고 결손 치유 시 단방향 래칫으로 영구 소각함.
public struct TraitBaseline: Sendable, Codable, Equatable {
    /// 베이스라인 규격 버전
    public let version: String
    /// 베이스라인 목적 및 설명
    public let description: String
    /// 참조 아키텍처 모델
    public let modelReference: String
    /// 최초 동결 생성 일시
    public let createdAt: Date
    /// 최근 래칫 갱신 일시
    public let updatedAt: Date
    /// 스캔된 총 앱 수
    public let totalAppsEvaluated: Int
    /// 부채가 등록된 앱 수
    public let appsWithDebtCount: Int
    /// 등록된 총 결손 트레이트(부채) 수
    public let totalDebtsCount: Int
    /// 등록된 총 원시 보일러플레이트 수
    public let totalBoilerplateCount: Int
    /// 앱별 부채 레코드 사전 (Key: appSlug)
    public let debts: [String: AppTraitDebt]

    public init(
        version: String = "1.0.0",
        description: String = "Monorepo Trait Baseline SSOT (One-Way Ratchet)",
        modelReference: String = "Spotify Backstage Soundcheck & Shopify Packwerk package_todo & ArchUnit FreezingArchRule",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        totalAppsEvaluated: Int,
        debts: [String: AppTraitDebt]
    ) {
        self.version = version
        self.description = description
        self.modelReference = modelReference
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.totalAppsEvaluated = totalAppsEvaluated
        self.debts = debts
        self.appsWithDebtCount = debts.count
        self.totalDebtsCount = debts.values.reduce(0) { $0 + $1.missingTraits.count }
        self.totalBoilerplateCount = debts.values.reduce(0) { $0 + $1.totalBoilerplateCount }
    }

    /// 정렬된 부채 앱 레코드 목록
    public var sortedDebts: [AppTraitDebt] {
        debts.values.sorted { $0.appSlug < $1.appSlug }
    }

    /// 특정 앱의 부채 레코드 조회
    public func debt(for appSlug: String) -> AppTraitDebt? {
        debts[appSlug]
    }

    /// 특정 앱의 특정 트레이트 결손이 베이스라인에 등록(허용)되어 있는지 확인
    public func hasDebt(appSlug: String, trait: GoldenTrait) -> Bool {
        debts[appSlug]?.hasDebt(for: trait) ?? false
    }

    /// 특정 앱의 동결 결손 트레이트 집합 반환
    public func recordedMissingTraits(for appSlug: String) -> Set<GoldenTrait> {
        guard let appDebt = debts[appSlug] else { return [] }
        return Set(appDebt.missingTraits)
    }

    /// 특정 앱이 결손 부채가 없는 정상(Clean) 상태인지 확인
    public func isClean(appSlug: String) -> Bool {
        guard let appDebt = debts[appSlug] else { return true }
        return appDebt.missingTraits.isEmpty
    }
}

// MARK: - 3. 신규 결손 위반 (RatchetRegressionViolation)

/// 기존 베이스라인에 등록되지 않은 신규 결손(New Regression) 위반 항목.
/// 베이스라인 게이트를 통과하지 못하고 즉시 빌드/검증을 실패시킴.
public struct RatchetRegressionViolation: Sendable, Codable, Equatable, CustomStringConvertible {
    public let appSlug: String
    public let trait: GoldenTrait
    public let boilerplateCount: Int
    public let reason: String
    public let sampleLocations: [String]
    public let detectedAt: Date

    public init(
        appSlug: String,
        trait: GoldenTrait,
        boilerplateCount: Int,
        reason: String,
        sampleLocations: [String] = [],
        detectedAt: Date = Date()
    ) {
        self.appSlug = appSlug
        self.trait = trait
        self.boilerplateCount = boilerplateCount
        self.reason = reason
        self.sampleLocations = sampleLocations
        self.detectedAt = detectedAt
    }

    public var description: String {
        "❌ [REGRESSION] \(appSlug) - \(trait.rawValue) (원시 보일러플레이트 \(boilerplateCount)건): \(reason)"
    }
}

// MARK: - 4. 치유된 부채 항목 (RatchetHealedDebt)

/// 공용 표준 킷 채택으로 인해 결손이 해소(치유)되어 베이스라인에서 영구 삭감(Decrement)된 항목.
public struct RatchetHealedDebt: Sendable, Codable, Equatable, CustomStringConvertible {
    public let appSlug: String
    public let healedTrait: GoldenTrait
    public let previousBoilerplateCount: Int
    public let healedAt: Date

    public init(
        appSlug: String,
        healedTrait: GoldenTrait,
        previousBoilerplateCount: Int,
        healedAt: Date = Date()
    ) {
        self.appSlug = appSlug
        self.healedTrait = healedTrait
        self.previousBoilerplateCount = previousBoilerplateCount
        self.healedAt = healedAt
    }

    public var description: String {
        "🎉 [HEALED] \(appSlug) - \(healedTrait.rawValue) 치유 완료 (이전 보일러플레이트 \(previousBoilerplateCount)건 삭감)"
    }
}

// MARK: - 5. 단방향 래칫 평가 결과 (RatchetEvaluationResult)

/// 현재 스캔 상태와 동결 베이스라인을 비교 평가한 종합 결과.
public struct RatchetEvaluationResult: Sendable, Codable, Equatable, CustomStringConvertible {
    /// 신규 결손(Regression)이 전혀 없어 검사를 통과(Pass)했는지 여부
    public let passed: Bool
    /// 평가된 총 앱 수
    public let totalAppsEvaluated: Int
    /// 기존 베이스라인에 등록되어 용인(Pass)된 기등록 부채 수
    public let toleratedDebtsCount: Int
    /// 새로 유입되어 차단(Fail)된 신규 결손 목록
    public let regressions: [RatchetRegressionViolation]
    /// 공용 킷 채택으로 치유되어 삭감(Decrement)된 부채 목록
    public let healedDebts: [RatchetHealedDebt]
    /// 치유 항목이 영구 삭감(Ratchet Decrement) 반영된 최신 베이스라인
    public let updatedBaseline: TraitBaseline
    /// 검사 일시
    public let evaluatedAt: Date

    public init(
        passed: Bool,
        totalAppsEvaluated: Int,
        toleratedDebtsCount: Int,
        regressions: [RatchetRegressionViolation],
        healedDebts: [RatchetHealedDebt],
        updatedBaseline: TraitBaseline,
        evaluatedAt: Date = Date()
    ) {
        self.passed = passed
        self.totalAppsEvaluated = totalAppsEvaluated
        self.toleratedDebtsCount = toleratedDebtsCount
        self.regressions = regressions
        self.healedDebts = healedDebts
        self.updatedBaseline = updatedBaseline
        self.evaluatedAt = evaluatedAt
    }

    public var description: String {
        summaryReport()
    }

    public func summaryReport() -> String {
        var lines: [String] = []
        lines.append("=== 🛡️ Trait Baseline One-Way Ratchet Report ===")
        lines.append("평가 대상 앱: \(totalAppsEvaluated)개 | 기등록 용인 부채: \(toleratedDebtsCount)건")
        lines.append("치유된 부채 (Ratchet Decrement): \(healedDebts.count)건 | 신규 결손 (Regressions): \(regressions.count)건")

        if passed {
            lines.append("상태: ✅ PASS (모든 신규 결손 차단 통과)")
            if !healedDebts.isEmpty {
                lines.append("\n[🎉 영구 삭감(Ratchet Decrement)된 치유 내역]")
                for healed in healedDebts {
                    lines.append("  • \(healed)")
                }
            }
        } else {
            lines.append("상태: ❌ FAIL (신규 결손 유입 감지 - 머지/배포 차단)")
            lines.append("\n[🚨 차단된 신규 결손(New Regression) 상세]")
            for reg in regressions {
                lines.append("  • \(reg)")
                for loc in reg.sampleLocations.prefix(5) {
                    lines.append("      - 위치: \(loc)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 6. TraitBaselineStore 엔진

/// Spotify Backstage Soundcheck 및 Shopify Packwerk(`package_todo.yml`), ArchUnit(`FreezingArchRule`) 모델을
/// 모노레포 환경에 단방향 래칫(One-Way Ratchet)으로 구현한 저장소 및 평가 엔진.
public final class TraitBaselineStore: Sendable {

    public let defaultAppsDirectory: URL?
    public let scanner: HomeostasisGapScanner

    public init(
        appsDirectory: URL? = nil,
        scanner: HomeostasisGapScanner = HomeostasisGapScanner()
    ) {
        self.defaultAppsDirectory = appsDirectory
        self.scanner = scanner
    }

    // MARK: - Baseline 영구 동결 (Freeze)

    /// 앱 디렉터리를 스캔하여 현재 결손 상태를 스냅샷으로 영구 동결합니다.
    @discardableResult
    public func freezeBaseline(into fileURL: URL, appsDirectory: URL? = nil) throws -> TraitBaseline {
        let appsDir = try resolveAppsDirectory(appsDirectory)
        let fleetResult = try scanner.scanFleet(appsDirectory: appsDir)
        return try freezeBaseline(from: fleetResult, into: fileURL)
    }

    /// 사전 수집된 FleetGapScanResult로부터 베이스라인을 생성하고 지정된 URL에 영구 저장합니다.
    @discardableResult
    public func freezeBaseline(from fleetResult: FleetGapScanResult, into fileURL: URL? = nil) throws -> TraitBaseline {
        return try freezeBaseline(
            from: fleetResult.appResults,
            totalAppsCount: fleetResult.totalAppsScanned,
            into: fileURL
        )
    }

    /// 개별 AppGapScanResult 목록으로부터 베이스라인을 생성하고 저장합니다.
    @discardableResult
    public func freezeBaseline(
        from appResults: [AppGapScanResult],
        totalAppsCount: Int? = nil,
        into fileURL: URL? = nil
    ) throws -> TraitBaseline {
        var debts: [String: AppTraitDebt] = [:]
        let now = Date()

        for result in appResults where !result.missingTraits.isEmpty {
            debts[result.appSlug] = AppTraitDebt(from: result, frozenAt: now)
        }

        let baseline = TraitBaseline(
            createdAt: now,
            updatedAt: now,
            totalAppsEvaluated: totalAppsCount ?? appResults.count,
            debts: debts
        )

        if let fileURL {
            try saveBaseline(baseline, to: fileURL)
        }

        return baseline
    }

    // MARK: - Baseline 저장 및 로딩

    /// 베이스라인 인스턴스를 디스크에 원자적(Atomic)으로 저장합니다.
    public func saveBaseline(_ baseline: TraitBaseline, to fileURL: URL) throws {
        let parentDir = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(baseline)
        try data.write(to: fileURL, options: .atomic)
    }

    /// 디스크의 베이스라인 JSON 파일로부터 TraitBaseline을 로드합니다.
    public func loadBaseline(from fileURL: URL) throws -> TraitBaseline {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw NSError(
                domain: "TraitBaselineStore",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Trait baseline file not found at: \(fileURL.path)"]
            )
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TraitBaseline.self, from: data)
    }

    // MARK: - 단방향 래칫 평가 (One-Way Ratchet Evaluation)

    /// 현재 스캔 결과와 동결 베이스라인을 대조 평가합니다.
    /// - 기존 베이스라인에 등록된 부채는 통과(Pass).
    /// - 새로 유입된 신규 결손(New Regression)은 엄격 차단(Fail).
    /// - 공용 킷이 채택되어 결손이 치유된 항목은 래칫 삭감(Decrement) 처리.
    public func evaluate(
        currentResults: [AppGapScanResult],
        against baseline: TraitBaseline
    ) -> RatchetEvaluationResult {
        var updatedDebts = baseline.debts
        var toleratedCount = 0
        var regressions: [RatchetRegressionViolation] = []
        var healedDebts: [RatchetHealedDebt] = []
        let now = Date()

        for result in currentResults {
            let slug = result.appSlug
            let currentMissingSet = Set(result.missingTraits)
            let baselineDebt = baseline.debts[slug]
            let baselineMissingSet = Set(baselineDebt?.missingTraits ?? [])

            // 1. 신규 결손(Regression): 기존 베이스라인에 없던 새로운 결손 트레이트 유입 검사
            let newMissingTraits = currentMissingSet.subtracting(baselineMissingSet)
            for newTrait in newMissingTraits.sorted(by: { $0.rawValue < $1.rawValue }) {
                let gap = result.gaps.first(where: { $0.trait == newTrait })
                let count = gap?.boilerplateCount ?? 0
                let locs = gap?.boilerplateLocations.map { "\($0.filePath):\($0.lineNumber)" } ?? []

                let reason: String
                if baselineDebt == nil {
                    reason = "기존에 정상(Clean)이거나 새로 추가된 앱 '\(slug)'에 표준 킷 결손 (\(newTrait.rawValue)) 신규 발생"
                } else {
                    reason = "앱 '\(slug)'의 기존 동결 베이스라인에 없던 표준 킷 결손 (\(newTrait.rawValue)) 신규 유입"
                }

                regressions.append(RatchetRegressionViolation(
                    appSlug: slug,
                    trait: newTrait,
                    boilerplateCount: count,
                    reason: reason,
                    sampleLocations: locs,
                    detectedAt: now
                ))
            }

            // 2. 용인된 기등록 부채(Tolerated Debt): 베이스라인에 이미 기록되어 있는 결손 트레이트
            let toleratedTraits = currentMissingSet.intersection(baselineMissingSet)
            toleratedCount += toleratedTraits.count

            // 3. 결손 치유 및 단방향 래칫 삭감(Ratchet Decrement): 베이스라인에 있었으나 현재 해소된 트레이트
            let healedTraits = baselineMissingSet.subtracting(currentMissingSet)
            for healedTrait in healedTraits.sorted(by: { $0.rawValue < $1.rawValue }) {
                let prevCount = baselineDebt?.boilerplateCounts[healedTrait.rawValue] ?? 0
                healedDebts.append(RatchetHealedDebt(
                    appSlug: slug,
                    healedTrait: healedTrait,
                    previousBoilerplateCount: prevCount,
                    healedAt: now
                ))
            }

            // 4. 평가 대상 앱의 부채 갱신 (치유된 항목은 삭감, 남은 용인 부채만 보존)
            if !toleratedTraits.isEmpty {
                var newBoilerplateCounts: [String: Int] = [:]
                var newLocations: [String: [String]] = [:]
                for gap in result.gaps where toleratedTraits.contains(gap.trait) {
                    newBoilerplateCounts[gap.trait.rawValue] = gap.boilerplateCount
                    newLocations[gap.trait.rawValue] = gap.boilerplateLocations.map { "\($0.filePath):\($0.lineNumber)" }
                }
                let totalCount = newBoilerplateCounts.values.reduce(0, +)

                updatedDebts[slug] = AppTraitDebt(
                    appSlug: slug,
                    missingTraits: Array(toleratedTraits).sorted(by: { $0.rawValue < $1.rawValue }),
                    boilerplateCounts: newBoilerplateCounts,
                    totalBoilerplateCount: totalCount,
                    recordedLocations: newLocations,
                    frozenAt: baselineDebt?.frozenAt ?? now
                )
            } else {
                // 이 앱의 모든 결손이 치유되었거나 원래 부채가 없었으므로 베이스라인 부채 목록에서 영구 제거!
                updatedDebts.removeValue(forKey: slug)
            }
        }

        let passed = regressions.isEmpty
        let updatedBaseline = TraitBaseline(
            version: baseline.version,
            description: baseline.description,
            modelReference: baseline.modelReference,
            createdAt: baseline.createdAt,
            updatedAt: healedDebts.isEmpty ? baseline.updatedAt : now,
            totalAppsEvaluated: baseline.totalAppsEvaluated,
            debts: updatedDebts
        )

        return RatchetEvaluationResult(
            passed: passed,
            totalAppsEvaluated: currentResults.count,
            toleratedDebtsCount: toleratedCount,
            regressions: regressions,
            healedDebts: healedDebts,
            updatedBaseline: updatedBaseline,
            evaluatedAt: now
        )
    }

    /// FleetGapScanResult를 기준으로 단방향 래칫 평가를 수행합니다.
    public func evaluate(
        currentFleetResult: FleetGapScanResult,
        against baseline: TraitBaseline
    ) -> RatchetEvaluationResult {
        evaluate(currentResults: currentFleetResult.appResults, against: baseline)
    }

    /// 파일 기반으로 현재 스캔 결과를 평가하고, 치유 항목 발생 시 베이스라인 파일을 자동 영구 갱신(Auto-Save Ratchet)합니다.
    @discardableResult
    public func evaluateAndRatchet(
        currentResults: [AppGapScanResult],
        baselineURL: URL,
        autoSaveOnHeal: Bool = true
    ) throws -> RatchetEvaluationResult {
        let baseline = try loadBaseline(from: baselineURL)
        let result = evaluate(currentResults: currentResults, against: baseline)

        if autoSaveOnHeal && result.passed && !result.healedDebts.isEmpty {
            try saveBaseline(result.updatedBaseline, to: baselineURL)
        }

        return result
    }

    /// FleetGapScanResult 기준 평가 및 파일 래칫 갱신.
    @discardableResult
    public func evaluateAndRatchet(
        currentFleetResult: FleetGapScanResult,
        baselineURL: URL,
        autoSaveOnHeal: Bool = true
    ) throws -> RatchetEvaluationResult {
        try evaluateAndRatchet(
            currentResults: currentFleetResult.appResults,
            baselineURL: baselineURL,
            autoSaveOnHeal: autoSaveOnHeal
        )
    }

    /// 단일 앱 디렉터리를 스캔하여 베이스라인 대비 평가하고 필요 시 베이스라인을 래칫 갱신합니다.
    @discardableResult
    public func evaluateAndRatchet(
        appDirectory: URL,
        slug: String? = nil,
        baselineURL: URL,
        autoSaveOnHeal: Bool = true
    ) throws -> RatchetEvaluationResult {
        let appResult = try scanner.scanApp(directory: appDirectory, slug: slug)
        return try evaluateAndRatchet(
            currentResults: [appResult],
            baselineURL: baselineURL,
            autoSaveOnHeal: autoSaveOnHeal
        )
    }

    // MARK: - Private Helpers

    private func resolveAppsDirectory(_ customDir: URL?) throws -> URL {
        if let customDir, FileManager.default.fileExists(atPath: customDir.path) {
            return customDir
        }
        if let defaultAppsDirectory, FileManager.default.fileExists(atPath: defaultAppsDirectory.path) {
            return defaultAppsDirectory
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let cwdApps = cwd.appendingPathComponent("apps")
        if FileManager.default.fileExists(atPath: cwdApps.path) {
            return cwdApps
        }
        let parentApps = cwd.deletingLastPathComponent().appendingPathComponent("apps")
        if FileManager.default.fileExists(atPath: parentApps.path) {
            return parentApps
        }
        throw NSError(
            domain: "TraitBaselineStore",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "Apps directory not found. Please provide an explicit appsDirectory URL."]
        )
    }
}
