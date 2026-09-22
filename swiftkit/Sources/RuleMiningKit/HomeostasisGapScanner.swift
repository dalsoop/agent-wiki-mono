import Foundation
import FastDiskIOKit

// MARK: - 1. Golden Trait (표준 항상성 특성 SSOT)

/// Worker 1이 정의하고 모노레포 표준으로 수립한 고유 아키텍처 항상성 특성(Golden Traits).
public enum GoldenTrait: String, Sendable, CaseIterable, Codable {
    /// 단일화된 영속성 및 SafeJSON 파싱 SSOT (AppPersistence / SafeJSON)
    case appPersistenceKit = "AppPersistenceKit"
    /// 단일화된 윈도우 수명주기, 크기/자동복원, 닫기방지 SSOT (StandardWindow / standardWindow)
    case appWindowKit = "AppWindowKit"
    /// 무락/제로할당 날짜/시간 파싱/포맷팅 SSOT (DateCodec / ISO8601DateCodec)
    case iso8601DateCodecKit = "ISO8601DateCodecKit"
    /// 단일화된 설정 및 About 화면 SSOT (StandardSettingsView / StandardAboutView / SettingsConfig)
    case settingsUIKit = "SettingsUIKit"
    /// 단일화된 온보딩 및 권한 안내 화면 SSOT (StandardOnboardingView / OnboardingItem)
    case onboardingUIKit = "OnboardingUIKit"
    /// 470개 앱 번들 ID 단일 진실의 원천 SSOT (AppBundleID)
    case packageIdentityKit = "PackageIdentityKit"

    public var displayName: String { rawValue }

    public var standardKitPath: String {
        switch self {
        case .appPersistenceKit:
            return "swiftkit/Sources/AppPersistenceKit"
        case .appWindowKit:
            return "swiftkit/Sources/AppWindowKit"
        case .iso8601DateCodecKit:
            return "swiftkit/Sources/ISO8601DateCodecKit"
        case .settingsUIKit:
            return "swiftkit/Sources/SettingsUIKit"
        case .onboardingUIKit:
            return "swiftkit/Sources/OnboardingUIKit"
        case .packageIdentityKit:
            return "swiftkit/Sources/PackageIdentityKit"
        }
    }

    public var summary: String {
        switch self {
        case .appPersistenceKit:
            return "단일화된 영속성 및 SafeJSON 파싱 SSOT (AppPersistence / SafeJSON)"
        case .appWindowKit:
            return "단일화된 윈도우 수명주기, 자동복원, 닫기방지 SSOT (StandardWindow / standardWindow)"
        case .iso8601DateCodecKit:
            return "무락/제로할당 날짜 시간 파싱/포맷팅 SSOT (DateCodec / ISO8601DateCodec)"
        case .settingsUIKit:
            return "단일화된 설정 및 About 화면 SSOT (StandardSettingsView / StandardAboutView)"
        case .onboardingUIKit:
            return "단일화된 온보딩 및 권한 안내 화면 SSOT (StandardOnboardingView / OnboardingItem)"
        case .packageIdentityKit:
            return "470개 앱 번들 ID 단일 진실의 원천 SSOT (AppBundleID)"
        }
    }

    public var recommendation: String {
        switch self {
        case .appPersistenceKit:
            return "원시 JSONDecoder/Encoder, Data(contentsOf:) 대신 `AppPersistence.load/save` 또는 `SafeJSON.decode` 채택"
        case .appWindowKit:
            return "수작업 WindowGroup, frame, autosaveName 대신 `StandardWindow` 또는 `.standardWindow()` 채택"
        case .iso8601DateCodecKit:
            return "인스턴스 매번 생성되는 ISO8601DateFormatter/DateFormatter 대신 `DateCodec.formatISO8601` / `DateCodec.parseISO8601` 채택"
        case .settingsUIKit:
            return "수작업 CFBundle 정보 추출 및 About/Settings 뷰 대신 `StandardSettingsView` / `StandardAboutView` 채택"
        case .onboardingUIKit:
            return "수작업 온보딩/권한 체크리스트 대신 `StandardOnboardingView(items: ...)` 채택"
        case .packageIdentityKit:
            return "하드코딩된 'net.ranode.' 문자열 대신 `AppBundleID` 타입 안전 SSOT 채택"
        }
    }
}

// MARK: - 2. 결손 및 보일러플레이트 보고 모델

/// 표준 킷 결손으로 인해 소스 코드에 잔존한 원시 보일러플레이트 위치.
public struct RawBoilerplateLocation: Sendable, Codable, Equatable {
    public let trait: GoldenTrait
    public let filePath: String
    public let lineNumber: Int
    public let snippet: String
    public let description: String

    public init(
        trait: GoldenTrait,
        filePath: String,
        lineNumber: Int,
        snippet: String,
        description: String
    ) {
        self.trait = trait
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.snippet = snippet
        self.description = description
    }
}

/// 개별 특성(Trait)에 대한 갭 진단 결과.
public struct TraitGap: Sendable, Codable, Equatable {
    public let trait: GoldenTrait
    public let isAdopted: Bool
    public let isApplicable: Bool
    public let boilerplateCount: Int
    public let boilerplateLocations: [RawBoilerplateLocation]
    public let missingReason: String?

    public init(
        trait: GoldenTrait,
        isAdopted: Bool,
        isApplicable: Bool,
        boilerplateCount: Int,
        boilerplateLocations: [RawBoilerplateLocation],
        missingReason: String? = nil
    ) {
        self.trait = trait
        self.isAdopted = isAdopted
        self.isApplicable = isApplicable
        self.boilerplateCount = boilerplateCount
        self.boilerplateLocations = boilerplateLocations
        self.missingReason = missingReason
    }

    public var isMissing: Bool {
        !isAdopted && isApplicable && boilerplateCount > 0
    }
}

/// 단일 앱 스캔 결과 DTO.
public struct AppGapScanResult: Sendable, Codable, Equatable {
    public let appSlug: String
    public let appDirectory: String
    public let scannedFilesCount: Int
    public let scanDurationMs: Double
    public let missingTraits: [GoldenTrait]
    public let adoptedTraits: [GoldenTrait]
    public let gaps: [TraitGap]
    public let totalBoilerplateCount: Int

    public init(
        appSlug: String,
        appDirectory: String,
        scannedFilesCount: Int,
        scanDurationMs: Double,
        missingTraits: [GoldenTrait],
        adoptedTraits: [GoldenTrait],
        gaps: [TraitGap],
        totalBoilerplateCount: Int
    ) {
        self.appSlug = appSlug
        self.appDirectory = appDirectory
        self.scannedFilesCount = scannedFilesCount
        self.scanDurationMs = scanDurationMs
        self.missingTraits = missingTraits
        self.adoptedTraits = adoptedTraits
        self.gaps = gaps
        self.totalBoilerplateCount = totalBoilerplateCount
    }

    public var summary: String {
        if missingTraits.isEmpty {
            return "✅ [\(appSlug)] All Golden Traits adopted! (0 gaps)"
        } else {
            let traitsStr = missingTraits.map(\.rawValue).joined(separator: ", ")
            return "⚠️ [\(appSlug)] Missing Traits: [\(traitsStr)] (Total \(totalBoilerplateCount) raw boilerplates detected across \(missingTraits.count) traits)"
        }
    }

    public func detailedReport() -> String {
        var lines: [String] = []
        lines.append("=== 🧬 Homeostasis Gap Scanner (\(appSlug)) ===")
        lines.append("경로: \(appDirectory)")
        lines.append("스캔 파일: \(scannedFilesCount)개 (소요시간: \(String(format: "%.2f", scanDurationMs))ms)")
        if missingTraits.isEmpty {
            lines.append("상태: ✅ Golden Trait 완전 채택 (0 gaps)")
            lines.append("채택된 표준 킷: [\(adoptedTraits.map(\.rawValue).joined(separator: ", "))]")
            lines.append("원시 보일러플레이트 잔재: 0건")
        } else {
            lines.append("상태: ⚠️ 항상성 결손 발견 (Missing Traits: [\(missingTraits.map(\.rawValue).joined(separator: ", "))])")
            lines.append("채택된 표준 킷: \(adoptedTraits.count)개 (\(adoptedTraits.map(\.rawValue).joined(separator: ", ")))")
            lines.append("결손된 표준 킷: \(missingTraits.count)개 (원시 보일러플레이트 총 \(totalBoilerplateCount)건 적발)")
            lines.append("")
            lines.append("[결손 상세 내역]")

            for gap in gaps where gap.isMissing {
                lines.append("  ❌ Missing Trait: \(gap.trait.rawValue)")
                lines.append("     - 표준 킷: \(gap.trait.standardKitPath)")
                lines.append("     - 역할: \(gap.trait.summary)")
                lines.append("     - 조치 권고: \(gap.trait.recommendation)")
                lines.append("     - 원시 보일러플레이트 (\(gap.boilerplateCount)건):")
                for loc in gap.boilerplateLocations.prefix(10) {
                    lines.append("       • \(loc.filePath):\(loc.lineNumber) -> \(loc.description)")
                }
                if gap.boilerplateLocations.count > 10 {
                    lines.append("       ...외 \(gap.boilerplateLocations.count - 10)건 추가 생략")
                }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// 플릿(Fleet) 전체 앱 스캔 결과 DTO.
public struct FleetGapScanResult: Sendable, Codable, Equatable {
    public let totalAppsScanned: Int
    public let cleanAppsCount: Int
    public let appsWithGapsCount: Int
    public let totalBoilerplatesCount: Int
    public let missingTraitHistogram: [String: Int]
    public let appResults: [AppGapScanResult]
    public let scanDurationMs: Double

    public init(
        totalAppsScanned: Int,
        cleanAppsCount: Int,
        appsWithGapsCount: Int,
        totalBoilerplatesCount: Int,
        missingTraitHistogram: [String: Int],
        appResults: [AppGapScanResult],
        scanDurationMs: Double
    ) {
        self.totalAppsScanned = totalAppsScanned
        self.cleanAppsCount = cleanAppsCount
        self.appsWithGapsCount = appsWithGapsCount
        self.totalBoilerplatesCount = totalBoilerplatesCount
        self.missingTraitHistogram = missingTraitHistogram
        self.appResults = appResults
        self.scanDurationMs = scanDurationMs
    }

    public func summaryReport() -> String {
        var lines: [String] = []
        lines.append("=== 🧬 Fleet Homeostasis Gap Scanner 종합 결과 ===")
        lines.append("총 검사 앱: \(totalAppsScanned)개 (정상: \(cleanAppsCount)개 / 결손: \(appsWithGapsCount)개)")
        lines.append("발견된 총 원시 보일러플레이트: \(totalBoilerplatesCount)건 (소요시간: \(String(format: "%.2f", scanDurationMs))ms)")
        lines.append("")
        lines.append("[결손 킷별 분포 (히스토그램)]")
        let sortedHistogram = missingTraitHistogram.sorted { $0.value > $1.value }
        for (trait, count) in sortedHistogram {
            lines.append("  • \(trait): \(count)개 앱에서 결손 발생")
        }
        lines.append("")
        lines.append("[앱별 상태]")
        for result in appResults {
            lines.append("  \(result.summary)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 3. HomeostasisGapScanner 엔진

/// Golden Trait 대비 결손(Missing Trait) 및 원시 보일러플레이트를 초고속으로 식별하는 스캐너.
public final class HomeostasisGapScanner: Sendable {

    public init() {}

    // MARK: - Public Scanning APIs

    /// 특정 앱 디렉터리를 스캔하여 항상성 결손 진단 결과를 반환합니다.
    public func scanApp(directory: URL, slug: String? = nil) throws -> AppGapScanResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        let resolvedSlug = slug ?? directory.lastPathComponent

        // Sources/ 내부 Swift 파일 수집 (빠른 재귀 열거)
        let sourcesDir = directory.appendingPathComponent("Sources")
        var swiftFiles: [URL] = []
        if FileManager.default.fileExists(atPath: sourcesDir.path) {
            swiftFiles = enumerateSwiftFiles(at: sourcesDir)
        } else {
            swiftFiles = enumerateSwiftFiles(at: directory, maxDepth: 4)
        }

        // 각 Trait 채택 여부 추적 상태
        var adopted: Set<GoldenTrait> = []
        var boilerplatesByTrait: [GoldenTrait: [RawBoilerplateLocation]] = [:]
        var hasGUIWindowOrScene = false

        for trait in GoldenTrait.allCases {
            boilerplatesByTrait[trait] = []
        }

        let appRootPath = directory.path

        // Swift 소스 파일들을 고속 파싱하여 Trait 채택 및 원시 보일러플레이트 탐지
        for fileURL in swiftFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let relativePath: String
            if fileURL.path.hasPrefix(appRootPath) {
                relativePath = String(fileURL.path.dropFirst(appRootPath.count).drop(while: { $0 == "/" }))
            } else {
                relativePath = fileURL.lastPathComponent
            }

            // 1. Import 문 및 핵심 시그니처 기반 Trait 채택 여부 확인
            checkTraitAdoption(content: content, adopted: &adopted)

            // 2. GUI 앱 여부 (WindowGroup, RanodeWindowGroupApp 등)
            if content.contains("WindowGroup") ||
                content.contains("RanodeWindowGroupApp") ||
                content.contains("FleetManagedWindowGroupApp") ||
                content.contains("RanodeMenuBarWindowGroupApp") {
                hasGUIWindowOrScene = true
            }

            // 3. 라인 단위 초고속 보일러플레이트 매칭
            scanFileLines(
                content: content,
                relativePath: relativePath,
                boilerplatesByTrait: &boilerplatesByTrait
            )
        }

        // Trait별 갭(Gap) 판정
        var gaps: [TraitGap] = []
        var missingTraits: [GoldenTrait] = []
        var totalBoilerplates = 0

        for trait in GoldenTrait.allCases {
            let isAdopted = adopted.contains(trait)
            let rawLocations = boilerplatesByTrait[trait] ?? []

            // GUI 전용 킷(AppWindowKit, SettingsUIKit, OnboardingUIKit)은 GUI가 없는 순수 CLI/백엔드에서는 미적용
            let isApplicable: Bool
            switch trait {
            case .appWindowKit, .settingsUIKit, .onboardingUIKit:
                isApplicable = hasGUIWindowOrScene || !rawLocations.isEmpty
            case .appPersistenceKit, .iso8601DateCodecKit, .packageIdentityKit:
                isApplicable = true
            }

            // 이미 표준 킷을 채택했으면 결손 보일러플레이트에서 제외 (정상 사용)
            let actualBoilerplates: [RawBoilerplateLocation]
            if isAdopted {
                actualBoilerplates = []
            } else {
                actualBoilerplates = rawLocations
            }

            totalBoilerplates += actualBoilerplates.count

            let missingReason: String?
            if !isAdopted && isApplicable && !actualBoilerplates.isEmpty {
                missingReason = "\(trait.displayName) 미채택으로 인한 원시 보일러플레이트 \(actualBoilerplates.count)건 잔존"
                missingTraits.append(trait)
            } else {
                missingReason = nil
            }

            gaps.append(TraitGap(
                trait: trait,
                isAdopted: isAdopted,
                isApplicable: isApplicable,
                boilerplateCount: actualBoilerplates.count,
                boilerplateLocations: actualBoilerplates,
                missingReason: missingReason
            ))
        }

        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        return AppGapScanResult(
            appSlug: resolvedSlug,
            appDirectory: directory.path,
            scannedFilesCount: swiftFiles.count,
            scanDurationMs: elapsedMs,
            missingTraits: missingTraits,
            adoptedTraits: GoldenTrait.allCases.filter { adopted.contains($0) },
            gaps: gaps,
            totalBoilerplateCount: totalBoilerplates
        )
    }

    /// 슬러그와 모노레포 루트 경로로부터 앱을 찾아 스캔합니다.
    public func scanApp(slug: String, rootPath: String) throws -> AppGapScanResult {
        let appDir = resolveAppDirectory(slug: slug, rootPath: rootPath)
        guard FileManager.default.fileExists(atPath: appDir.path) else {
            throw NSError(domain: "HomeostasisGapScanner", code: 404, userInfo: [NSLocalizedDescriptionKey: "App not found at \(appDir.path)"])
        }
        return try scanApp(directory: appDir, slug: slug)
    }

    /// 여러 앱(또는 전체 앱 디렉터리)을 스캔하여 플릿 종합 결과를 반환합니다.
    public func scanFleet(appsDirectory: URL, targetSlugs: [String]? = nil) throws -> FleetGapScanResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(at: appsDirectory, includingPropertiesForKeys: [.isDirectoryKey])

        var appResults: [AppGapScanResult] = []
        var missingHistogram: [String: Int] = [:]
        for trait in GoldenTrait.allCases {
            missingHistogram[trait.rawValue] = 0
        }

        for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let slug = item.lastPathComponent
            if let targetSlugs, !targetSlugs.contains(slug) {
                continue
            }
            let hasPackage = fm.fileExists(atPath: item.appendingPathComponent("Package.swift").path)
            let hasSources = fm.fileExists(atPath: item.appendingPathComponent("Sources").path)
            guard hasPackage || hasSources else { continue }

            do {
                let result = try scanApp(directory: item, slug: slug)
                appResults.append(result)
                for missing in result.missingTraits {
                    missingHistogram[missing.rawValue, default: 0] += 1
                }
            } catch {}
        }

        let cleanCount = appResults.filter { $0.missingTraits.isEmpty }.count
        let gapCount = appResults.filter { !$0.missingTraits.isEmpty }.count
        let totalBoilerplates = appResults.reduce(0) { $0 + $1.totalBoilerplateCount }
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        return FleetGapScanResult(
            totalAppsScanned: appResults.count,
            cleanAppsCount: cleanCount,
            appsWithGapsCount: gapCount,
            totalBoilerplatesCount: totalBoilerplates,
            missingTraitHistogram: missingHistogram,
            appResults: appResults,
            scanDurationMs: elapsedMs
        )
    }

    // MARK: - Internal Scanning Helpers

    private func checkTraitAdoption(content: String, adopted: inout Set<GoldenTrait>) {
        // AppPersistenceKit
        if content.contains("import AppPersistenceKit") ||
            content.contains("AppPersistence.") ||
            content.contains("SafeJSON.") {
            adopted.insert(.appPersistenceKit)
        }

        // AppWindowKit
        if content.contains("import AppWindowKit") ||
            content.contains("StandardWindow(") ||
            content.contains(".standardWindow(") {
            adopted.insert(.appWindowKit)
        }

        // ISO8601DateCodecKit
        if content.contains("import ISO8601DateCodecKit") ||
            content.contains("DateCodec.") ||
            content.contains("ISO8601DateCodec.") {
            adopted.insert(.iso8601DateCodecKit)
        }

        // SettingsUIKit
        if content.contains("import SettingsUIKit") ||
            content.contains("StandardSettingsView") ||
            content.contains("StandardAboutView") ||
            content.contains("SettingsConfig(") {
            adopted.insert(.settingsUIKit)
        }

        // OnboardingUIKit
        if content.contains("import OnboardingUIKit") ||
            content.contains("StandardOnboardingView(") ||
            content.contains("StandardOnboardingView<") {
            adopted.insert(.onboardingUIKit)
        }

        // PackageIdentityKit
        if content.contains("import PackageIdentityKit") ||
            content.contains("AppBundleID.") ||
            content.contains("AppBundleID(") {
            adopted.insert(.packageIdentityKit)
        }
    }

    private func scanFileLines(
        content: String,
        relativePath: String,
        boilerplatesByTrait: inout [GoldenTrait: [RawBoilerplateLocation]]
    ) {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

        for (index, lineSubstring) in lines.enumerated() {
            let line = String(lineSubstring)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lineNum = index + 1

            // 주석 줄 건너뛰기
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") {
                continue
            }

            // 1. AppPersistenceKit 결손 보일러플레이트 탐지
            if trimmed.contains("JSONDecoder().decode(") {
                boilerplatesByTrait[.appPersistenceKit]?.append(RawBoilerplateLocation(
                    trait: .appPersistenceKit,
                    filePath: relativePath,
                    lineNumber: lineNum,
                    snippet: trimmed,
                    description: "raw `JSONDecoder().decode(...)` 보일러플레이트 (AppPersistence.decode 권장)"
                ))
            } else if trimmed.contains("let decoder = JSONDecoder()") ||
                        trimmed.contains("var decoder = JSONDecoder()") ||
                        trimmed.contains("= JSONDecoder()") {
                if !relativePath.contains("AppPersistence") {
                    boilerplatesByTrait[.appPersistenceKit]?.append(RawBoilerplateLocation(
                        trait: .appPersistenceKit,
                        filePath: relativePath,
                        lineNumber: lineNum,
                        snippet: trimmed,
                        description: "raw `JSONDecoder()` 인스턴스화 (AppPersistence.defaultDecoder 권장)"
                    ))
                }
            } else if trimmed.contains("JSONEncoder().encode(") {
                boilerplatesByTrait[.appPersistenceKit]?.append(RawBoilerplateLocation(
                    trait: .appPersistenceKit,
                    filePath: relativePath,
                    lineNumber: lineNum,
                    snippet: trimmed,
                    description: "raw `JSONEncoder().encode(...)` 보일러플레이트 (AppPersistence.encode 권장)"
                ))
            } else if trimmed.contains("let encoder = JSONEncoder()") ||
                        trimmed.contains("var encoder = JSONEncoder()") ||
                        trimmed.contains("= JSONEncoder()") {
                if !relativePath.contains("AppPersistence") {
                    boilerplatesByTrait[.appPersistenceKit]?.append(RawBoilerplateLocation(
                        trait: .appPersistenceKit,
                        filePath: relativePath,
                        lineNumber: lineNum,
                        snippet: trimmed,
                        description: "raw `JSONEncoder()` 인스턴스화 (AppPersistence.defaultEncoder 권장)"
                    ))
                }
            } else if trimmed.contains("Data(contentsOf: URL(fileURLWithPath:") ||
                        trimmed.contains("Data(contentsOf: url)") {
                if !relativePath.contains("AppPersistence") {
                    boilerplatesByTrait[.appPersistenceKit]?.append(RawBoilerplateLocation(
                        trait: .appPersistenceKit,
                        filePath: relativePath,
                        lineNumber: lineNum,
                        snippet: trimmed,
                        description: "raw `Data(contentsOf:)` 직접 디스크 로딩 (AppPersistence.load 권장)"
                    ))
                }
            }

            // 2. AppWindowKit 결손 보일러플레이트 탐지
            if (trimmed.contains("WindowGroup(") || trimmed.contains("WindowGroup {")) &&
                !trimmed.contains("StandardWindow") {
                boilerplatesByTrait[.appWindowKit]?.append(RawBoilerplateLocation(
                    trait: .appWindowKit,
                    filePath: relativePath,
                    lineNumber: lineNum,
                    snippet: trimmed,
                    description: "수작업 `WindowGroup` 선언 (StandardWindow Scene 권장)"
                ))
            } else if trimmed.contains("setFrameAutosaveName(") {
                if !relativePath.contains("StandardWindow") {
                    boilerplatesByTrait[.appWindowKit]?.append(RawBoilerplateLocation(
                        trait: .appWindowKit,
                        filePath: relativePath,
                        lineNumber: lineNum,
                        snippet: trimmed,
                        description: "수작업 창 프레임 자동저장 (StandardWindow autosaveKey 권장)"
                    ))
                }
            } else if trimmed.contains("func windowShouldClose(") {
                if !relativePath.contains("StandardWindow") {
                    boilerplatesByTrait[.appWindowKit]?.append(RawBoilerplateLocation(
                        trait: .appWindowKit,
                        filePath: relativePath,
                        lineNumber: lineNum,
                        snippet: trimmed,
                        description: "수작업 창 닫기 방지/숨김 구현 (StandardWindow preventsClose 권장)"
                    ))
                }
            }

            // 3. ISO8601DateCodecKit 결손 보일러플레이트 탐지
            if trimmed.contains("ISO8601DateFormatter()") {
                boilerplatesByTrait[.iso8601DateCodecKit]?.append(RawBoilerplateLocation(
                    trait: .iso8601DateCodecKit,
                    filePath: relativePath,
                    lineNumber: lineNum,
                    snippet: trimmed,
                    description: "매번 할당되는 `ISO8601DateFormatter()` (DateCodec 캐시 권장)"
                ))
            } else if trimmed.contains("let formatter = DateFormatter()") ||
                        trimmed.contains("var formatter = DateFormatter()") ||
                        trimmed.contains("= DateFormatter()") {
                if !relativePath.contains("DateCodec") {
                    boilerplatesByTrait[.iso8601DateCodecKit]?.append(RawBoilerplateLocation(
                        trait: .iso8601DateCodecKit,
                        filePath: relativePath,
                        lineNumber: lineNum,
                        snippet: trimmed,
                        description: "로컬 `DateFormatter()` 인스턴스화 (DateCodec.cachedFormatter 권장)"
                    ))
                }
            }

            // 4. SettingsUIKit 결손 보일러플레이트 탐지
            if (trimmed.contains("\"CFBundleShortVersionString\"") ||
                trimmed.contains("\"CFBundleVersion\"") ||
                trimmed.contains("\"NSHumanReadableCopyright\"")) &&
                !relativePath.contains("SettingsUIKit") &&
                !relativePath.contains("SettingsConfig") &&
                !relativePath.contains("StandardWindow") {
                boilerplatesByTrait[.settingsUIKit]?.append(RawBoilerplateLocation(
                    trait: .settingsUIKit,
                    filePath: relativePath,
                    lineNumber: lineNum,
                    snippet: trimmed,
                    description: "수작업 CFBundle 정보 추출 (SettingsConfig 자동 주입 권장)"
                ))
            } else if (trimmed.contains("struct SettingsView:") ||
                        trimmed.contains("struct AboutView:") ||
                        trimmed.contains("struct AboutAppView:")) &&
                        !relativePath.contains("SettingsUIKit") {
                boilerplatesByTrait[.settingsUIKit]?.append(RawBoilerplateLocation(
                    trait: .settingsUIKit,
                    filePath: relativePath,
                    lineNumber: lineNum,
                    snippet: trimmed,
                    description: "수작업 About/Settings 뷰 선언 (StandardSettingsView / StandardAboutView 권장)"
                ))
            }

            // 5. OnboardingUIKit 결손 보일러플레이트 탐지
            if (trimmed.contains("struct OnboardingView:") ||
                trimmed.contains("struct WelcomeView:") ||
                trimmed.contains("struct PermissionView:")) &&
                !relativePath.contains("OnboardingUIKit") {
                boilerplatesByTrait[.onboardingUIKit]?.append(RawBoilerplateLocation(
                    trait: .onboardingUIKit,
                    filePath: relativePath,
                    lineNumber: lineNum,
                    snippet: trimmed,
                    description: "수작업 온보딩 뷰 선언 (StandardOnboardingView 권장)"
                ))
            }

            // 6. PackageIdentityKit 결손 보일러플레이트 탐지
            if trimmed.contains("\"net.ranode.") &&
                !relativePath.contains("AppBundleID") &&
                !relativePath.contains("Tests") {
                boilerplatesByTrait[.packageIdentityKit]?.append(RawBoilerplateLocation(
                    trait: .packageIdentityKit,
                    filePath: relativePath,
                    lineNumber: lineNum,
                    snippet: trimmed,
                    description: "하드코딩된 'net.ranode.' 번들 식별자 문자열 (AppBundleID SSOT 권장)"
                ))
            }
        }
    }

    private func resolveAppDirectory(slug: String, rootPath: String) -> URL {
        let root = URL(fileURLWithPath: rootPath)
        let direct = URL(fileURLWithPath: slug)
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }

        let inApps = root.appendingPathComponent("apps").appendingPathComponent(slug)
        if FileManager.default.fileExists(atPath: inApps.path) {
            return inApps
        }

        let inAppsSwift = root.appendingPathComponent("apps").appendingPathComponent("\(slug)-swift")
        if FileManager.default.fileExists(atPath: inAppsSwift.path) {
            return inAppsSwift
        }

        return inApps
    }

    private func enumerateSwiftFiles(at directoryURL: URL, maxDepth: Int = 10) -> [URL] {
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            let path = fileURL.path
            if path.contains("/.build/") || path.contains("/.git/") || path.contains("/Packaging/") {
                continue
            }
            if fileURL.pathExtension == "swift" {
                results.append(fileURL)
            }
        }
        return results
    }
}
