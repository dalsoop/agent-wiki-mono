import Foundation
import XCTest
@testable import RuleMiningKit

final class TraitBaselineStoreTests: XCTestCase {

    private var tempDirectory: URL!
    private var store: TraitBaselineStore!

    override func setUp() {
        super.setUp()
        let uniqueDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TraitBaselineStoreTests-\(UUID().uuidString)")
        do { try FileManager.default.createDirectory(at: uniqueDir, withIntermediateDirectories: true) } catch { _ = error }
        self.tempDirectory = uniqueDir
        self.store = TraitBaselineStore()
    }

    override func tearDown() {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func makeMockAppResult(
        slug: String,
        missing: [GoldenTrait],
        boilerplatesPerTrait: [GoldenTrait: Int] = [:]
    ) -> AppGapScanResult {
        var gaps: [TraitGap] = []
        var totalBoilerplates = 0

        for trait in GoldenTrait.allCases {
            let isMissing = missing.contains(trait)
            let count = isMissing ? (boilerplatesPerTrait[trait] ?? 3) : 0
            totalBoilerplates += count

            var locations: [RawBoilerplateLocation] = []
            if count > 0 {
                locations.append(RawBoilerplateLocation(
                    trait: trait,
                    filePath: "Sources/\(slug)/Main.swift",
                    lineNumber: 42,
                    snippet: "// Raw boilerplate for \(trait.rawValue)",
                    description: "Raw boilerplate detection"
                ))
            }

            gaps.append(TraitGap(
                trait: trait,
                isAdopted: !isMissing,
                isApplicable: true,
                boilerplateCount: count,
                boilerplateLocations: locations,
                missingReason: isMissing ? "\(trait.rawValue) 결손" : nil
            ))
        }

        return AppGapScanResult(
            appSlug: slug,
            appDirectory: "/mock/\(slug)",
            scannedFilesCount: 5,
            scanDurationMs: 1.2,
            missingTraits: missing,
            adoptedTraits: GoldenTrait.allCases.filter { !missing.contains($0) },
            gaps: gaps,
            totalBoilerplateCount: totalBoilerplates
        )
    }

    // MARK: - 1. 베이스라인 영구 동결 (Freeze) 및 디스크 로드 테스트

    func testFreezeBaselineAndLoadRoundTrip() throws {
        let app1 = makeMockAppResult(slug: "legacy-app-alpha", missing: [.appPersistenceKit, .appWindowKit])
        let app2 = makeMockAppResult(slug: "clean-app-beta", missing: [])
        let app3 = makeMockAppResult(slug: "legacy-app-gamma", missing: [.iso8601DateCodecKit])

        let baselineFile = tempDirectory.appendingPathComponent("trait-baseline.json")

        // 1. 동결 저장
        let baseline = try store.freezeBaseline(
            from: [app1, app2, app3],
            totalAppsCount: 3,
            into: baselineFile
        )

        XCTAssertEqual(baseline.totalAppsEvaluated, 3)
        XCTAssertEqual(baseline.appsWithDebtCount, 2)
        XCTAssertEqual(baseline.totalDebtsCount, 3) // alpha: 2, gamma: 1
        XCTAssertTrue(FileManager.default.fileExists(atPath: baselineFile.path))

        // 2. 디스크에서 다시 로드
        let loaded = try store.loadBaseline(from: baselineFile)
        XCTAssertEqual(loaded.version, baseline.version)
        XCTAssertEqual(loaded.totalAppsEvaluated, 3)
        XCTAssertEqual(loaded.appsWithDebtCount, 2)
        XCTAssertEqual(loaded.debts["legacy-app-alpha"]?.missingTraits, [.appPersistenceKit, .appWindowKit])
        XCTAssertEqual(loaded.debts["legacy-app-gamma"]?.missingTraits, [.iso8601DateCodecKit])
        XCTAssertNil(loaded.debts["clean-app-beta"])
        XCTAssertTrue(loaded.isClean(appSlug: "clean-app-beta"))
        XCTAssertFalse(loaded.isClean(appSlug: "legacy-app-alpha"))
    }

    // MARK: - 2. 기존 기등록 부채 용인 (Pass Tolerated Debt) 테스트

    func testTolerateExistingBaselineDebt() {
        let app1 = makeMockAppResult(slug: "legacy-app-alpha", missing: [.appPersistenceKit, .appWindowKit])
        let baseline = try! store.freezeBaseline(from: [app1], totalAppsCount: 1)

        // 동일한 결손 상태로 검사 수행
        let currentApp1 = makeMockAppResult(slug: "legacy-app-alpha", missing: [.appPersistenceKit, .appWindowKit])
        let evalResult = store.evaluate(currentResults: [currentApp1], against: baseline)

        XCTAssertTrue(evalResult.passed, "기존 베이스라인에 등록된 기술 부채는 통과되어야 함")
        XCTAssertEqual(evalResult.toleratedDebtsCount, 2)
        XCTAssertTrue(evalResult.regressions.isEmpty)
        XCTAssertTrue(evalResult.healedDebts.isEmpty)
    }

    // MARK: - 3. 신규 결손 엄격 차단 (Fail on New Regression) 테스트

    func testFailOnNewRegressionForExistingApp() {
        let app1 = makeMockAppResult(slug: "legacy-app-alpha", missing: [.appPersistenceKit])
        let baseline = try! store.freezeBaseline(from: [app1], totalAppsCount: 1)

        // 기존 부채(.appPersistenceKit) 외에 신규 결손(.iso8601DateCodecKit) 유입
        let regressedApp1 = makeMockAppResult(
            slug: "legacy-app-alpha",
            missing: [.appPersistenceKit, .iso8601DateCodecKit]
        )
        let evalResult = store.evaluate(currentResults: [regressedApp1], against: baseline)

        XCTAssertFalse(evalResult.passed, "새로 유입된 결손은 반드시 실패(차단)되어야 함")
        XCTAssertEqual(evalResult.toleratedDebtsCount, 1)
        XCTAssertEqual(evalResult.regressions.count, 1)
        XCTAssertEqual(evalResult.regressions.first?.trait, .iso8601DateCodecKit)
        XCTAssertEqual(evalResult.regressions.first?.appSlug, "legacy-app-alpha")
    }

    func testFailOnNewRegressionForPreviouslyCleanApp() {
        let cleanApp = makeMockAppResult(slug: "clean-app-beta", missing: [])
        let baseline = try! store.freezeBaseline(from: [cleanApp], totalAppsCount: 1)

        // 정상이었던 앱에 결손 유입
        let regressedApp = makeMockAppResult(slug: "clean-app-beta", missing: [.settingsUIKit])
        let evalResult = store.evaluate(currentResults: [regressedApp], against: baseline)

        XCTAssertFalse(evalResult.passed)
        XCTAssertEqual(evalResult.toleratedDebtsCount, 0)
        XCTAssertEqual(evalResult.regressions.count, 1)
        XCTAssertEqual(evalResult.regressions.first?.trait, .settingsUIKit)
    }

    func testFailOnNewRegressionForBrandNewApp() {
        let baseline = TraitBaseline(
            totalAppsEvaluated: 10,
            debts: [:]
        )

        // 베이스라인 동결 당시 존재하지 않던 신규 앱이 결손 상태로 생성됨
        let brandNewApp = makeMockAppResult(slug: "new-unregistered-app", missing: [.onboardingUIKit])
        let evalResult = store.evaluate(currentResults: [brandNewApp], against: baseline)

        XCTAssertFalse(evalResult.passed)
        XCTAssertEqual(evalResult.regressions.count, 1)
        XCTAssertEqual(evalResult.regressions.first?.trait, .onboardingUIKit)
    }

    // MARK: - 4. 단방향 래칫 삭감 (One-Way Ratchet Decrement) 테스트

    func testRatchetDecrementOnPartialHealing() {
        let app1 = makeMockAppResult(
            slug: "legacy-app-alpha",
            missing: [.appPersistenceKit, .appWindowKit]
        )
        let baseline = try! store.freezeBaseline(from: [app1], totalAppsCount: 1)

        // 공용 킷 AppPersistenceKit 채택으로 결손 치유! (appWindowKit만 잔존)
        let healedApp1 = makeMockAppResult(
            slug: "legacy-app-alpha",
            missing: [.appWindowKit]
        )
        let evalResult = store.evaluate(currentResults: [healedApp1], against: baseline)

        XCTAssertTrue(evalResult.passed)
        XCTAssertEqual(evalResult.healedDebts.count, 1)
        XCTAssertEqual(evalResult.healedDebts.first?.healedTrait, .appPersistenceKit)
        XCTAssertEqual(evalResult.toleratedDebtsCount, 1)

        // 최신 래칫 베이스라인 검증: appPersistenceKit이 영구 삭감되어 appWindowKit만 남아야 함
        let updatedBaseline = evalResult.updatedBaseline
        XCTAssertEqual(updatedBaseline.debts["legacy-app-alpha"]?.missingTraits, [.appWindowKit])

        // 🌟 단방향 래칫 핵심 검증:
        // 치유된 상태의 updatedBaseline에 대해 나중에 누군가 AppPersistenceKit을 다시 제거/결손 유입시키면?
        let reRegressedApp1 = makeMockAppResult(
            slug: "legacy-app-alpha",
            missing: [.appPersistenceKit, .appWindowKit]
        )
        let secondEval = store.evaluate(currentResults: [reRegressedApp1], against: updatedBaseline)

        XCTAssertFalse(secondEval.passed, "한 번 치유된 항목은 래칫에 의해 영구 삭감되므로 재유입 시 신규 결손으로 차단되어야 함")
        XCTAssertEqual(secondEval.regressions.count, 1)
        XCTAssertEqual(secondEval.regressions.first?.trait, .appPersistenceKit)
    }

    func testRatchetFullHealingRemovesAppFromDebt() {
        let app1 = makeMockAppResult(
            slug: "legacy-app-alpha",
            missing: [.packageIdentityKit]
        )
        let baseline = try! store.freezeBaseline(from: [app1], totalAppsCount: 1)
        XCTAssertEqual(baseline.appsWithDebtCount, 1)

        // 완전히 완치되어 결손 0건
        let cleanApp1 = makeMockAppResult(slug: "legacy-app-alpha", missing: [])
        let evalResult = store.evaluate(currentResults: [cleanApp1], against: baseline)

        XCTAssertTrue(evalResult.passed)
        XCTAssertEqual(evalResult.healedDebts.count, 1)
        XCTAssertEqual(evalResult.healedDebts.first?.healedTrait, .packageIdentityKit)

        // 베이스라인에서 앱이 완전 제거되어 정상(Clean) 처리되어야 함
        let updatedBaseline = evalResult.updatedBaseline
        XCTAssertNil(updatedBaseline.debts["legacy-app-alpha"])
        XCTAssertEqual(updatedBaseline.appsWithDebtCount, 0)
        XCTAssertEqual(updatedBaseline.totalDebtsCount, 0)
    }

    // MARK: - 5. 파일 기반 래칫 자동 저장 (evaluateAndRatchet) E2E 테스트

    func testEvaluateAndRatchetFilePersistence() throws {
        let baselineFile = tempDirectory.appendingPathComponent("auto-ratchet-baseline.json")

        let appA = makeMockAppResult(slug: "app-a", missing: [.appPersistenceKit, .iso8601DateCodecKit])
        let appB = makeMockAppResult(slug: "app-b", missing: [.settingsUIKit])

        // 초기 동결
        try store.freezeBaseline(from: [appA, appB], totalAppsCount: 2, into: baselineFile)

        // app-a가 appPersistenceKit 치유, app-b는 그대로 유지
        let healedAppA = makeMockAppResult(slug: "app-a", missing: [.iso8601DateCodecKit])
        let currentAppB = makeMockAppResult(slug: "app-b", missing: [.settingsUIKit])

        let result = try store.evaluateAndRatchet(
            currentResults: [healedAppA, currentAppB],
            baselineURL: baselineFile,
            autoSaveOnHeal: true
        )

        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.healedDebts.count, 1)

        // 디스크의 파일이 실제로 래칫 삭감되어 갱신되었는지 검증
        let reloadedBaseline = try store.loadBaseline(from: baselineFile)
        XCTAssertEqual(reloadedBaseline.debts["app-a"]?.missingTraits, [.iso8601DateCodecKit])
        XCTAssertEqual(reloadedBaseline.debts["app-b"]?.missingTraits, [.settingsUIKit])
        XCTAssertEqual(reloadedBaseline.totalDebtsCount, 2)
    }

    // MARK: - 6. 리포트 포맷팅 요약 테스트

    func testReportSummaryFormatting() {
        let app1 = makeMockAppResult(slug: "app-1", missing: [.appPersistenceKit])
        let baseline = try! store.freezeBaseline(from: [app1], totalAppsCount: 1)

        // 치유 케이스
        let healedApp = makeMockAppResult(slug: "app-1", missing: [])
        let passResult = store.evaluate(currentResults: [healedApp], against: baseline)
        let passReport = passResult.summaryReport()

        XCTAssertTrue(passReport.contains("PASS"))
        XCTAssertTrue(passReport.contains("치유 완료"))

        // 회귀 케이스
        let regApp = makeMockAppResult(slug: "app-1", missing: [.appPersistenceKit, .appWindowKit])
        let failResult = store.evaluate(currentResults: [regApp], against: baseline)
        let failReport = failResult.summaryReport()

        XCTAssertTrue(failReport.contains("FAIL"))
        XCTAssertTrue(failReport.contains("REGRESSION"))
        XCTAssertTrue(failReport.contains("AppWindowKit"))
    }
}
