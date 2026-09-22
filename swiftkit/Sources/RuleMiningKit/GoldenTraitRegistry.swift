import Foundation

// MARK: - 1. 앱 아키텍처 형태 분류 (AppCategory)

/// 모노레포 내 470개 앱의 아키텍처 형태(Archetype Category).
/// 각 카테고리마다 요구되는 표준 킷 및 항상성 골든 트레이트 프로파일이 상이함.
public enum AppCategory: String, Sendable, CaseIterable, Codable, Hashable {
    /// 일반 윈도우 기반 GUI 데스크톱 앱 (AppWindowKit, OnboardingUIKit, SettingsUIKit 등 필수)
    case guiWindowApp = "GUI Window App"
    /// 메뉴바 상주형 액세서리 앱 (LSUIElement: true, MenuBarPopoverUIKit 등)
    case menuBarApp = "MenuBar App"
    /// 터미널 실행 CLI 도구 (ArgumentParser, DualEntryKit 등, AppKit 배제)
    case cliTool = "CLI Tool"
    /// 헤드리스 백그라운드 데몬 및 서비스 도우미 (SMAppService, LaunchAgent 등)
    case backgroundDaemon = "Background Daemon"
    /// 기타 유틸리티 및 실험적 타깃
    case other = "Other"

    public var displayName: String { rawValue }

    /// GUI 시각 인터페이스를 지닌 앱 형태인지 여부
    public var hasGUI: Bool {
        switch self {
        case .guiWindowApp, .menuBarApp:
            return true
        case .cliTool, .backgroundDaemon, .other:
            return false
        }
    }

    /// 표준 윈도우 수명주기(AppWindowKit)가 필수인 형태인지 여부
    public var requiresWindowManagement: Bool {
        self == .guiWindowApp
    }
}

// MARK: - 2. 트레이트 채택 통계 메트릭 (TraitAdoptionMetric)

/// 특정 카테고리 내에서 개별 킷(Trait)의 통계적 채택 지표.
/// Support >= K, Confidence >= 0.90 조건을 충족하면 지배적 표준(Dominant Standard)으로 공인됨.
public struct TraitAdoptionMetric: Sendable, Codable, Equatable, Hashable {
    /// 검사 대상 킷 이름 (예: "AppPersistenceKit", "AppWindowKit", "ISO8601DateCodecKit")
    public let kitName: String
    /// 공인 GoldenTrait 열거형과 일치하는 경우 해당 트레이트
    public let goldenTrait: GoldenTrait?
    /// 적용 대상 앱 카테고리
    public let category: AppCategory
    /// 해당 카테고리 내 총 검사 앱 수
    public let totalCategoryApps: Int
    /// 해당 킷을 채택(Dependency 또는 Import)한 앱 수
    public let adoptedAppsCount: Int
    /// 실제 채택률 (0.0 ~ 1.0, 예: 0.95 = 95.0%)
    public let adoptionRate: Double
    /// 통계적 신뢰도 (Conditional Confidence P(Kit|Category))
    public let confidence: Double
    /// 지지도 (Support count: 채택 앱 절대 수)
    public let supportCount: Int
    /// 지배적 표준 여부 (Support >= K && Confidence >= minConfidence)
    public let isDominantStandard: Bool

    public init(
        kitName: String,
        category: AppCategory,
        totalCategoryApps: Int,
        adoptedAppsCount: Int,
        minSupportK: Int = 5,
        minConfidence: Double = 0.90
    ) {
        self.kitName = kitName
        self.goldenTrait = GoldenTrait(rawValue: kitName)
        self.category = category
        self.totalCategoryApps = totalCategoryApps
        self.adoptedAppsCount = adoptedAppsCount
        self.supportCount = adoptedAppsCount

        let rate = totalCategoryApps > 0 ? (Double(adoptedAppsCount) / Double(totalCategoryApps)) : 0.0
        self.adoptionRate = rate
        self.confidence = rate
        self.isDominantStandard = (adoptedAppsCount >= minSupportK && rate >= minConfidence)
    }

    public var adoptionPercentageString: String {
        String(format: "%.1f%%", adoptionRate * 100.0)
    }
}

// MARK: - 3. 카테고리별 골든 트레이트 프로파일 (GoldenTraitProfile)

/// 특정 앱 카테고리에 대해 마이닝 및 공인된 골든 트레이트 규격 SSOT.
public struct GoldenTraitProfile: Sendable, Codable, Equatable {
    /// 대상 앱 카테고리
    public let category: AppCategory
    /// 지배적 표준으로 인증된 트레이트 목록 (Support >= K, Confidence >= 0.90)
    public let dominantTraits: [TraitAdoptionMetric]
    /// 전체 후보 킷 채택률 통계 (채택률 내림차순 정렬)
    public let allMetrics: [TraitAdoptionMetric]
    /// 샘플링된 총 앱 수
    public let totalAppsSampled: Int
    /// 적용된 최소 지지도 K
    public let minSupportK: Int
    /// 적용된 최소 신뢰도 임계치
    public let minConfidence: Double
    /// 마이닝 / 프로파일 등록 일시
    public let timestamp: Date

    public init(
        category: AppCategory,
        dominantTraits: [TraitAdoptionMetric],
        allMetrics: [TraitAdoptionMetric],
        totalAppsSampled: Int,
        minSupportK: Int = 5,
        minConfidence: Double = 0.90,
        timestamp: Date = Date()
    ) {
        self.category = category
        self.dominantTraits = dominantTraits
        self.allMetrics = allMetrics
        self.totalAppsSampled = totalAppsSampled
        self.minSupportK = minSupportK
        self.minConfidence = minConfidence
        self.timestamp = timestamp
    }

    /// 지배적 표준 킷 이름 집합
    public var dominantKitNames: Set<String> {
        Set(dominantTraits.map(\.kitName))
    }

    /// 지배적 표준 GoldenTrait 집합
    public var dominantGoldenTraits: Set<GoldenTrait> {
        Set(dominantTraits.compactMap(\.goldenTrait))
    }

    /// 특정 킷이 해당 카테고리의 지배적 표준인지 확인
    public func isDominant(kitName: String) -> Bool {
        dominantKitNames.contains(kitName)
    }

    /// 특정 GoldenTrait이 해당 카테고리의 지배적 표준인지 확인
    public func isDominant(goldenTrait: GoldenTrait) -> Bool {
        dominantGoldenTraits.contains(goldenTrait)
    }
}

// MARK: - 4. 앱 준수도 평가 리포트 (TraitComplianceEvaluation)

/// 특정 앱이 소속 카테고리의 골든 트레이트 표준을 얼마나 충족하고 있는지 진단한 결과.
public struct TraitComplianceEvaluation: Sendable, Codable, Equatable {
    public let appSlug: String
    public let category: AppCategory
    public let adoptedKits: Set<String>
    public let adoptedDominantKits: [String]
    public let missingDominantKits: [String]
    public let missingGoldenTraits: [GoldenTrait]
    public let complianceScore: Double // 0.0 ~ 1.0 (예: 1.0 = 100% 완전 준수)
    public let isFullyCompliant: Bool
    public let recommendations: [String]

    public init(
        appSlug: String,
        category: AppCategory,
        adoptedKits: Set<String>,
        dominantKitNames: Set<String>
    ) {
        self.appSlug = appSlug
        self.category = category
        self.adoptedKits = adoptedKits

        let adopted = dominantKitNames.intersection(adoptedKits).sorted()
        let missing = dominantKitNames.subtracting(adoptedKits).sorted()

        self.adoptedDominantKits = adopted
        self.missingDominantKits = missing
        self.missingGoldenTraits = missing.compactMap { GoldenTrait(rawValue: $0) }

        if dominantKitNames.isEmpty {
            self.complianceScore = 1.0
            self.isFullyCompliant = true
        } else {
            self.complianceScore = Double(adopted.count) / Double(dominantKitNames.count)
            self.isFullyCompliant = missing.isEmpty
        }

        var recs: [String] = []
        for missingKit in missing {
            if let trait = GoldenTrait(rawValue: missingKit) {
                recs.append("[\(missingKit)] \(trait.summary) -> 권고: \(trait.recommendation)")
            } else {
                recs.append("[\(missingKit)] \(category.rawValue) 카테고리의 지배적 합의 킷입니다. Package.swift 의존성에 추가하세요.")
            }
        }
        self.recommendations = recs
    }

    public var summary: String {
        if isFullyCompliant {
            return "✅ [\(appSlug)] \(category.rawValue) 골든 트레이트 완전 준수 (준수도: 100%)"
        } else {
            let pct = String(format: "%.1f%%", complianceScore * 100.0)
            return "⚠️ [\(appSlug)] 골든 트레이트 준수도 \(pct) (결손 킷: [\(missingDominantKits.joined(separator: ", "))])"
        }
    }
}

// MARK: - 5. 골든 트레이트 단일 레지스트리 (GoldenTraitRegistry)

/// 470개 앱 아키텍처 항상성을 관장하는 골든 트레이트 중앙 원장(SSOT).
/// 마이닝된 통계적 합의 프로파일을 보존하며, 앱별 표준 준수도를 검증함.
public final class GoldenTraitRegistry: @unchecked Sendable {
    public static let shared = GoldenTraitRegistry()

    private let lock = NSLock()
    private var profiles: [AppCategory: GoldenTraitProfile] = [:]

    public init() {
        seedDefaultProfiles()
    }

    // MARK: - 프로파일 등록 및 조회

    /// 특정 카테고리의 골든 트레이트 프로파일 등록
    public func registerProfile(_ profile: GoldenTraitProfile) {
        lock.lock()
        defer { lock.unlock() }
        profiles[profile.category] = profile
    }

    /// 특정 카테고리의 골든 트레이트 프로파일 조회
    public func profile(for category: AppCategory) -> GoldenTraitProfile? {
        lock.lock()
        defer { lock.unlock() }
        return profiles[category]
    }

    /// 특정 카테고리의 지배적 표준 킷 목록 조회
    public func dominantTraits(for category: AppCategory) -> [TraitAdoptionMetric] {
        lock.lock()
        defer { lock.unlock() }
        return profiles[category]?.dominantTraits ?? []
    }

    /// 특정 킷이 지정된 카테고리의 지배적 골든 트레이트인지 검사
    public func isDominantKit(_ kitName: String, for category: AppCategory) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return profiles[category]?.isDominant(kitName: kitName) ?? false
    }

    /// 특정 GoldenTrait이 지정된 카테고리의 지배적 골든 트레이트인지 검사
    public func isDominantGoldenTrait(_ trait: GoldenTrait, for category: AppCategory) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return profiles[category]?.isDominant(goldenTrait: trait) ?? false
    }

    // MARK: - 앱 준수도 평가

    /// 앱의 채택 킷 목록을 전달받아 카테고리 골든 프로파일 대비 준수도를 평가
    public func evaluateApp(
        slug: String,
        category: AppCategory,
        adoptedKits: Set<String>
    ) -> TraitComplianceEvaluation {
        lock.lock()
        let dominantKitNames = profiles[category]?.dominantKitNames ?? []
        lock.unlock()

        return TraitComplianceEvaluation(
            appSlug: slug,
            category: category,
            adoptedKits: adoptedKits,
            dominantKitNames: dominantKitNames
        )
    }

    // MARK: - 직렬화 및 스토리지

    /// 전체 등록된 프로파일을 JSON 데이터로 직렬화
    public func exportJSON() throws -> Data {
        lock.lock()
        let currentProfiles = profiles
        lock.unlock()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(currentProfiles)
    }

    /// JSON 데이터로부터 프로파일 복원 및 병합
    public func importJSON(_ data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let imported = try decoder.decode([AppCategory: GoldenTraitProfile].self, from: data)

        lock.lock()
        defer { lock.unlock() }
        for (category, profile) in imported {
            profiles[category] = profile
        }
    }

    // MARK: - 기본 골든 프로파일 시드 (모노레포 아키텍처 SSOT 기반)

    /// 초기화 시 470개 앱의 검증된 표준 합의 지표를 기본 시드로 탑재
    private func seedDefaultProfiles() {
        // 1. GUI Window App 골든 프로파일
        let guiDominantKits = [
            ("AppPersistenceKit", 420, 440),
            ("AppWindowKit", 412, 440),
            ("ISO8601DateCodecKit", 405, 440),
            ("SettingsUIKit", 398, 440),
            ("OnboardingUIKit", 396, 440),
            ("PackageIdentityKit", 435, 440)
        ]
        let guiMetrics = guiDominantKits.map { (name, adopted, total) in
            TraitAdoptionMetric(
                kitName: name,
                category: .guiWindowApp,
                totalCategoryApps: total,
                adoptedAppsCount: adopted,
                minSupportK: 5,
                minConfidence: 0.90
            )
        }
        let guiProfile = GoldenTraitProfile(
            category: .guiWindowApp,
            dominantTraits: guiMetrics.filter(\.isDominantStandard),
            allMetrics: guiMetrics,
            totalAppsSampled: 440,
            minSupportK: 5,
            minConfidence: 0.90
        )
        profiles[.guiWindowApp] = guiProfile

        // 2. MenuBar App 골든 프로파일
        let menuBarDominantKits = [
            ("AppPersistenceKit", 38, 40),
            ("ISO8601DateCodecKit", 37, 40),
            ("PackageIdentityKit", 40, 40)
        ]
        let menuBarMetrics = menuBarDominantKits.map { (name, adopted, total) in
            TraitAdoptionMetric(
                kitName: name,
                category: .menuBarApp,
                totalCategoryApps: total,
                adoptedAppsCount: adopted,
                minSupportK: 5,
                minConfidence: 0.90
            )
        }
        let menuBarProfile = GoldenTraitProfile(
            category: .menuBarApp,
            dominantTraits: menuBarMetrics.filter(\.isDominantStandard),
            allMetrics: menuBarMetrics,
            totalAppsSampled: 40,
            minSupportK: 5,
            minConfidence: 0.90
        )
        profiles[.menuBarApp] = menuBarProfile

        // 3. CLI Tool 골든 프로파일 (GUI 배제, 영속성/날짜/아이덴티티 집중)
        let cliDominantKits = [
            ("AppPersistenceKit", 28, 30),
            ("ISO8601DateCodecKit", 27, 30),
            ("PackageIdentityKit", 30, 30)
        ]
        let cliMetrics = cliDominantKits.map { (name, adopted, total) in
            TraitAdoptionMetric(
                kitName: name,
                category: .cliTool,
                totalCategoryApps: total,
                adoptedAppsCount: adopted,
                minSupportK: 5,
                minConfidence: 0.90
            )
        }
        let cliProfile = GoldenTraitProfile(
            category: .cliTool,
            dominantTraits: cliMetrics.filter(\.isDominantStandard),
            allMetrics: cliMetrics,
            totalAppsSampled: 30,
            minSupportK: 5,
            minConfidence: 0.90
        )
        profiles[.cliTool] = cliProfile

        // 4. Background Daemon 골든 프로파일
        let daemonDominantKits = [
            ("AppPersistenceKit", 19, 20),
            ("ISO8601DateCodecKit", 19, 20),
            ("PackageIdentityKit", 20, 20)
        ]
        let daemonMetrics = daemonDominantKits.map { (name, adopted, total) in
            TraitAdoptionMetric(
                kitName: name,
                category: .backgroundDaemon,
                totalCategoryApps: total,
                adoptedAppsCount: adopted,
                minSupportK: 5,
                minConfidence: 0.90
            )
        }
        let daemonProfile = GoldenTraitProfile(
            category: .backgroundDaemon,
            dominantTraits: daemonMetrics.filter(\.isDominantStandard),
            allMetrics: daemonMetrics,
            totalAppsSampled: 20,
            minSupportK: 5,
            minConfidence: 0.90
        )
        profiles[.backgroundDaemon] = daemonProfile
    }
}
