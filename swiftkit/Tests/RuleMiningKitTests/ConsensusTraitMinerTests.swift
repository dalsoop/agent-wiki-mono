import XCTest
@testable import RuleMiningKit

final class ConsensusTraitMinerTests: XCTestCase {

    // MARK: - 1. 앱 아키텍처 형태(AppCategory) 테스트

    func testAppCategoryProperties() {
        XCTAssertTrue(AppCategory.guiWindowApp.hasGUI)
        XCTAssertTrue(AppCategory.guiWindowApp.requiresWindowManagement)

        XCTAssertTrue(AppCategory.menuBarApp.hasGUI)
        XCTAssertFalse(AppCategory.menuBarApp.requiresWindowManagement)

        XCTAssertFalse(AppCategory.cliTool.hasGUI)
        XCTAssertFalse(AppCategory.cliTool.requiresWindowManagement)

        XCTAssertFalse(AppCategory.backgroundDaemon.hasGUI)
        XCTAssertFalse(AppCategory.backgroundDaemon.requiresWindowManagement)
    }

    // MARK: - 2. 트레이트 지표(TraitAdoptionMetric) 및 임계치 판정 테스트

    func testTraitAdoptionMetricCalculation() {
        // 케이스 1: 지배적 표준 충족 (Support 40 >= 5, Confidence 1.0 >= 0.90)
        let dominantMetric = TraitAdoptionMetric(
            kitName: "AppPersistenceKit",
            category: .guiWindowApp,
            totalCategoryApps: 40,
            adoptedAppsCount: 40,
            minSupportK: 5,
            minConfidence: 0.90
        )
        XCTAssertEqual(dominantMetric.adoptionRate, 1.0)
        XCTAssertEqual(dominantMetric.confidence, 1.0)
        XCTAssertEqual(dominantMetric.supportCount, 40)
        XCTAssertTrue(dominantMetric.isDominantStandard)
        XCTAssertEqual(dominantMetric.goldenTrait, .appPersistenceKit)
        XCTAssertEqual(dominantMetric.adoptionPercentageString, "100.0%")

        // 케이스 2: Confidence 미달 (35/40 = 87.5% < 90%)
        let subConfidenceMetric = TraitAdoptionMetric(
            kitName: "SomeExperimentalKit",
            category: .guiWindowApp,
            totalCategoryApps: 40,
            adoptedAppsCount: 35,
            minSupportK: 5,
            minConfidence: 0.90
        )
        XCTAssertEqual(subConfidenceMetric.adoptionRate, 0.875)
        XCTAssertFalse(subConfidenceMetric.isDominantStandard)

        // 케이스 3: Support K 미달 (채택률 100%이나 절대 수 4개 < K=5)
        let subSupportMetric = TraitAdoptionMetric(
            kitName: "RareKit",
            category: .backgroundDaemon,
            totalCategoryApps: 4,
            adoptedAppsCount: 4,
            minSupportK: 5,
            minConfidence: 0.90
        )
        XCTAssertEqual(subSupportMetric.adoptionRate, 1.0)
        XCTAssertFalse(subSupportMetric.isDominantStandard)
    }

    // MARK: - 3. 골든 트레이트 레지스트리(GoldenTraitRegistry) 시드 및 조회 테스트

    func testGoldenTraitRegistrySeedProfiles() {
        let registry = GoldenTraitRegistry()

        // GUI Window App 프로파일 검증
        guard let guiProfile = registry.profile(for: .guiWindowApp) else {
            XCTFail("GUI Window App 프로파일이 초기 시드에 존재해야 함")
            return
        }
        XCTAssertEqual(guiProfile.category, .guiWindowApp)
        XCTAssertTrue(guiProfile.isDominant(kitName: "AppPersistenceKit"))
        XCTAssertTrue(guiProfile.isDominant(kitName: "AppWindowKit"))
        XCTAssertTrue(guiProfile.isDominant(kitName: "PackageIdentityKit"))
        XCTAssertTrue(guiProfile.isDominant(kitName: "SettingsUIKit"))
        XCTAssertTrue(guiProfile.isDominant(kitName: "OnboardingUIKit"))
        XCTAssertTrue(guiProfile.isDominant(kitName: "ISO8601DateCodecKit"))
        XCTAssertTrue(guiProfile.isDominant(goldenTrait: .appWindowKit))

        // CLI Tool 프로파일 검증 (WindowKit 등 GUI 전용 킷 배제)
        guard let cliProfile = registry.profile(for: .cliTool) else {
            XCTFail("CLI Tool 프로파일이 초기 시드에 존재해야 함")
            return
        }
        XCTAssertTrue(cliProfile.isDominant(kitName: "AppPersistenceKit"))
        XCTAssertFalse(cliProfile.isDominant(kitName: "AppWindowKit"))
        XCTAssertFalse(cliProfile.isDominant(goldenTrait: .appWindowKit))

        // 헬퍼 쿼리 검증
        XCTAssertTrue(registry.isDominantKit("AppWindowKit", for: .guiWindowApp))
        XCTAssertFalse(registry.isDominantKit("AppWindowKit", for: .cliTool))
        XCTAssertTrue(registry.isDominantGoldenTrait(.appPersistenceKit, for: .guiWindowApp))
    }

    // MARK: - 4. 앱 준수도 평가(TraitComplianceEvaluation) 테스트

    func testAppComplianceEvaluation() {
        let registry = GoldenTraitRegistry()

        // 100% 완전 준수 앱
        let fullyCompliantApp = registry.evaluateApp(
            slug: "perfect-window-app",
            category: .guiWindowApp,
            adoptedKits: [
                "AppPersistenceKit",
                "AppWindowKit",
                "ISO8601DateCodecKit",
                "SettingsUIKit",
                "OnboardingUIKit",
                "PackageIdentityKit"
            ]
        )
        XCTAssertTrue(fullyCompliantApp.isFullyCompliant)
        XCTAssertEqual(fullyCompliantApp.complianceScore, 1.0)
        XCTAssertTrue(fullyCompliantApp.missingDominantKits.isEmpty)
        XCTAssertTrue(fullyCompliantApp.summary.contains("100%"))

        // 결손 앱 (AppWindowKit 및 SettingsUIKit 누락)
        let lackingApp = registry.evaluateApp(
            slug: "incomplete-window-app",
            category: .guiWindowApp,
            adoptedKits: [
                "AppPersistenceKit",
                "ISO8601DateCodecKit",
                "OnboardingUIKit",
                "PackageIdentityKit"
            ]
        )
        XCTAssertFalse(lackingApp.isFullyCompliant)
        XCTAssertEqual(lackingApp.complianceScore, 4.0 / 6.0, accuracy: 0.001)
        XCTAssertEqual(lackingApp.missingDominantKits, ["AppWindowKit", "SettingsUIKit"])
        XCTAssertTrue(lackingApp.missingGoldenTraits.contains(.appWindowKit))
        XCTAssertTrue(lackingApp.missingGoldenTraits.contains(.settingsUIKit))
        XCTAssertFalse(lackingApp.recommendations.isEmpty)
    }

    // MARK: - 5. 인메모리 프로파일 마이닝(ConsensusTraitMiner) 테스트

    func testMinerWithMockAppProfiles() {
        let miner = ConsensusTraitMiner(options: ConsensusMiningOptions(minSupportK: 5, minConfidence: 0.90))

        // 10개의 GUI 앱 모의 데이터 생성
        var mockProfiles: [AppTraitProfile] = []
        for i in 1...10 {
            var adopted: Set<String> = ["AppPersistenceKit", "PackageIdentityKit"]
            // 10개 중 9개 앱(90%)이 AppWindowKit 채택
            if i <= 9 {
                adopted.insert("AppWindowKit")
            }
            // 10개 중 8개 앱(80%)만 ISO8601DateCodecKit 채택 (Confidence 0.90 미달)
            if i <= 8 {
                adopted.insert("ISO8601DateCodecKit")
            }
            // 10개 중 2개 앱만 채택한 임의의 킷
            if i <= 2 {
                adopted.insert("CustomOneOffKit")
            }

            let profile = AppTraitProfile(
                appSlug: "mock-gui-app-\(i)",
                appPath: "/mock/apps/mock-gui-app-\(i)",
                category: .guiWindowApp,
                categoryClassificationReason: "Mock Data",
                packageDependencies: adopted,
                sourceImports: []
            )
            mockProfiles.append(profile)
        }

        // 5개의 CLI 앱 모의 데이터 생성
        for i in 1...5 {
            let adopted: Set<String> = ["AppPersistenceKit", "PackageIdentityKit"]
            let profile = AppTraitProfile(
                appSlug: "mock-cli-app-\(i)",
                appPath: "/mock/apps/mock-cli-app-\(i)",
                category: .cliTool,
                categoryClassificationReason: "Mock CLI",
                packageDependencies: adopted,
                sourceImports: []
            )
            mockProfiles.append(profile)
        }

        let report = miner.mine(from: mockProfiles)

        XCTAssertEqual(report.totalAppsScanned, 15)
        XCTAssertEqual(report.categoryCounts[.guiWindowApp], 10)
        XCTAssertEqual(report.categoryCounts[.cliTool], 5)

        // GUI Window App 마이닝 결과 검증
        guard let guiProfile = report.profilesByCategory[.guiWindowApp] else {
            XCTFail("GUI 카테고리 프로파일이 생성되어야 함")
            return
        }

        let dominantKits = Set(guiProfile.dominantTraits.map(\.kitName))
        // 100% 채택된 킷들
        XCTAssertTrue(dominantKits.contains("AppPersistenceKit"))
        XCTAssertTrue(dominantKits.contains("PackageIdentityKit"))
        // 90% 채택된 AppWindowKit
        XCTAssertTrue(dominantKits.contains("AppWindowKit"))
        // 80% 채택된 ISO8601DateCodecKit은 90% 미만이므로 지배적 표준에서 제외되어야 함
        XCTAssertFalse(dominantKits.contains("ISO8601DateCodecKit"))
        // 20% 채택된 CustomOneOffKit 제외
        XCTAssertFalse(dominantKits.contains("CustomOneOffKit"))

        // CLI Tool 마이닝 결과 검증
        guard let cliProfile = report.profilesByCategory[.cliTool] else {
            XCTFail("CLI 카테고리 프로파일이 생성되어야 함")
            return
        }
        let cliDominantKits = Set(cliProfile.dominantTraits.map(\.kitName))
        XCTAssertTrue(cliDominantKits.contains("AppPersistenceKit"))
        XCTAssertTrue(cliDominantKits.contains("PackageIdentityKit"))
        XCTAssertFalse(cliDominantKits.contains("AppWindowKit"))

        // 리포트 텍스트 요약 검증
        let summaryText = report.summary()
        XCTAssertTrue(summaryText.contains("Consensus Trait Mining Report"))
        XCTAssertTrue(summaryText.contains("GUI Window App"))
    }

    // MARK: - 6. 실제 모노레포 앱 스캔 및 분류 테스트

    func testScanLiveAppsFromRepo() {
        let miner = ConsensusTraitMiner()
        let fm = FileManager.default

        let agentChatURL = URL(fileURLWithPath: "apps/agent-chat-swift")
        if fm.fileExists(atPath: agentChatURL.path) {
            let profile = miner.scanApp(at: agentChatURL)
            XCTAssertNotNil(profile)
            XCTAssertEqual(profile?.appSlug, "agent-chat-swift")
            XCTAssertEqual(profile?.category, .guiWindowApp)
            XCTAssertTrue(profile?.adoptedKits.contains("LocalizationKit") == true)
        }

        let searchMenuBarURL = URL(fileURLWithPath: "apps/search-agent-menubar-swift")
        if fm.fileExists(atPath: searchMenuBarURL.path) {
            let profile = miner.scanApp(at: searchMenuBarURL)
            XCTAssertNotNil(profile)
            XCTAssertEqual(profile?.appSlug, "search-agent-menubar-swift")
            XCTAssertEqual(profile?.category, .menuBarApp)
        }
    }

    // MARK: - 7. 직렬화(JSON Export / Import) 무결성 테스트

    func testRegistryExportAndImport() throws {
        let registry = GoldenTraitRegistry()
        let exportedData = try registry.exportJSON()
        XCTAssertGreaterThan(exportedData.count, 0)

        let freshRegistry = GoldenTraitRegistry()
        try freshRegistry.importJSON(exportedData)

        XCTAssertTrue(freshRegistry.isDominantKit("AppWindowKit", for: .guiWindowApp))
        XCTAssertTrue(freshRegistry.isDominantKit("AppPersistenceKit", for: .cliTool))
    }
}
