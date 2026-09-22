import Foundation

// MARK: - 1. 단일 앱 트레이트 프로파일 (AppTraitProfile)

/// 470개 앱 중 단일 앱을 정밀 분석한 트레이트 스캔 결과.
public struct AppTraitProfile: Sendable, Codable, Equatable, Identifiable {
    public var id: String { appSlug }

    /// 앱 슬러그 (예: "agent-chat-swift", "search-agent-menubar-swift")
    public let appSlug: String
    /// 앱 파일시스템 디렉터리 경로
    public let appPath: String
    /// 판정된 앱 아키텍처 카테고리
    public let category: AppCategory
    /// 카테고리 판정 사유
    public let categoryClassificationReason: String
    /// Package.swift 에서 선언된 의존성 킷 목록
    public let packageDependencies: Set<String>
    /// Sources/**/*.swift 소스 코드에서 import한 모듈 목록
    public let sourceImports: Set<String>
    /// Package 의존성 및 소스 import의 합집합 (실제 채택된 총 킷)
    public let adoptedKits: Set<String>

    public init(
        appSlug: String,
        appPath: String,
        category: AppCategory,
        categoryClassificationReason: String,
        packageDependencies: Set<String>,
        sourceImports: Set<String>
    ) {
        self.appSlug = appSlug
        self.appPath = appPath
        self.category = category
        self.categoryClassificationReason = categoryClassificationReason
        self.packageDependencies = packageDependencies
        self.sourceImports = sourceImports
        self.adoptedKits = packageDependencies.union(sourceImports)
    }

    /// 특정 킷을 채택하고 있는지 여부
    public func adopts(kitName: String) -> Bool {
        adoptedKits.contains(kitName)
    }

    /// 특정 GoldenTrait을 채택하고 있는지 여부
    public func adopts(goldenTrait: GoldenTrait) -> Bool {
        adoptedKits.contains(goldenTrait.rawValue)
    }
}

// MARK: - 2. 마이닝 옵션 (ConsensusMiningOptions)

/// 합의 트레이트 마이닝 엔진 설정.
public struct ConsensusMiningOptions: Sendable, Codable, Equatable {
    /// 지배적 표준 인정을 위한 최소 절대 채택 앱 수 (K)
    public var minSupportK: Int
    /// 지배적 표준 인정을 위한 최소 채택률/신뢰도 임계치 (기본값: 0.90 = 90%)
    public var minConfidence: Double
    /// 특정 킷만 집중 마이닝하고자 할 때 필터 (nil이면 모든 *Kit 자동 발굴)
    public var targetKits: Set<String>?

    public init(
        minSupportK: Int = 5,
        minConfidence: Double = 0.90,
        targetKits: Set<String>? = nil
    ) {
        self.minSupportK = minSupportK
        self.minConfidence = minConfidence
        self.targetKits = targetKits
    }
}

// MARK: - 3. 마이닝 종합 보고서 (ConsensusMiningReport)

/// 470개 앱 마이닝 완료 후 집계된 종합 보고서.
public struct ConsensusMiningReport: Sendable, Codable, Equatable {
    public let totalAppsScanned: Int
    public let categoryCounts: [AppCategory: Int]
    public let profilesByCategory: [AppCategory: GoldenTraitProfile]
    public let appProfiles: [AppTraitProfile]
    public let executionDurationMs: Double
    public let timestamp: Date

    public init(
        totalAppsScanned: Int,
        categoryCounts: [AppCategory: Int],
        profilesByCategory: [AppCategory: GoldenTraitProfile],
        appProfiles: [AppTraitProfile],
        executionDurationMs: Double,
        timestamp: Date = Date()
    ) {
        self.totalAppsScanned = totalAppsScanned
        self.categoryCounts = categoryCounts
        self.profilesByCategory = profilesByCategory
        self.appProfiles = appProfiles
        self.executionDurationMs = executionDurationMs
        self.timestamp = timestamp
    }

    public func summary() -> String {
        var lines: [String] = []
        lines.append("=== 🏛️ Consensus Trait Mining Report ===")
        lines.append("총 분석 앱: \(totalAppsScanned)개 (분석 시간: \(String(format: "%.2f", executionDurationMs))ms)")
        lines.append("")
        lines.append("[카테고리별 앱 분포]")
        for category in AppCategory.allCases {
            let count = categoryCounts[category] ?? 0
            lines.append("  • \(category.rawValue): \(count)개 앱")
        }
        lines.append("")
        lines.append("[카테고리별 도출된 지배적 골든 트레이트 (Support >= K, Confidence >= 90%)]")
        for (category, profile) in profilesByCategory.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            lines.append("  📂 [\(category.rawValue)] (샘플: \(profile.totalAppsSampled)개)")
            if profile.dominantTraits.isEmpty {
                lines.append("     (지배적 기준을 충족한 트레이트 없음)")
            } else {
                for trait in profile.dominantTraits {
                    lines.append("     ⭐ \(trait.kitName): 채택률 \(trait.adoptionPercentageString) (지지도: \(trait.supportCount)/\(profile.totalAppsSampled)개, 신뢰도: \(String(format: "%.2f", trait.confidence)))")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 4. 합의 트레이트 마이닝 엔진 (ConsensusTraitMiner)

/// 470개 앱의 Package.swift 및 소스 코드 import를 초고속 스캔하여
/// 형태별 실제 채택률(Adoption Rate %)을 산출하고 지배적 골든 트레이트를 도출하는 엔진.
public final class ConsensusTraitMiner: Sendable {
    public let options: ConsensusMiningOptions

    public init(options: ConsensusMiningOptions = ConsensusMiningOptions()) {
        self.options = options
    }

    // MARK: - 파일시스템 스캔 및 마이닝 진입점

    /// 지정된 apps/ 루트 디렉터리 내 모든 앱 디렉터리를 스캔하고 마이닝 수행
    public func scanAndMine(appsDirectory: URL) throws -> ConsensusMiningReport {
        let startTime = CFAbsoluteTimeGetCurrent()
        let fm = FileManager.default

        guard let appDirs = try? fm.contentsOfDirectory(
            at: appsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ConsensusMiningReport(
                totalAppsScanned: 0,
                categoryCounts: [:],
                profilesByCategory: [:],
                appProfiles: [],
                executionDurationMs: 0
            )
        }

        let profiles = appDirs.compactMap { scanApp(at: $0) }
        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        return mine(from: profiles, executionDurationMs: durationMs)
    }

    /// 명시된 앱 경로 목록들을 대상으로 마이닝 수행
    public func scanAndMine(appPaths: [URL]) -> ConsensusMiningReport {
        let startTime = CFAbsoluteTimeGetCurrent()
        let profiles = appPaths.compactMap { scanApp(at: $0) }
        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        return mine(from: profiles, executionDurationMs: durationMs)
    }

    /// 사전에 수집된 앱 프로파일 목록으로부터 통계 마이닝 수행
    public func mine(
        from profiles: [AppTraitProfile],
        executionDurationMs: Double = 0.0
    ) -> ConsensusMiningReport {
        var categoryCounts: [AppCategory: Int] = [:]
        var appsByCategory: [AppCategory: [AppTraitProfile]] = [:]

        for profile in profiles {
            categoryCounts[profile.category, default: 0] += 1
            appsByCategory[profile.category, default: []].append(profile)
        }

        var profilesByCategory: [AppCategory: GoldenTraitProfile] = [:]

        for category in AppCategory.allCases {
            guard let categoryApps = appsByCategory[category], !categoryApps.isEmpty else {
                continue
            }

            let totalInCat = categoryApps.count

            // 해당 카테고리 내에서 채택된 모든 킷 집계
            var kitAdoptionCount: [String: Int] = [:]

            // 만약 targetKits가 지정되어 있다면 이를 기본 킷 세트로 포함
            if let targets = options.targetKits {
                for target in targets {
                    kitAdoptionCount[target] = 0
                }
            }

            // 모든 골든 트레이트도 기본 관찰 세트로 포함
            for trait in GoldenTrait.allCases {
                kitAdoptionCount[trait.rawValue] = 0
            }

            for app in categoryApps {
                for kit in app.adoptedKits {
                    if let targets = options.targetKits, !targets.contains(kit) {
                        continue
                    }
                    kitAdoptionCount[kit, default: 0] += 1
                }
            }

            // 트레이트 메트릭 계산
            var metrics: [TraitAdoptionMetric] = []
            for (kit, count) in kitAdoptionCount {
                let metric = TraitAdoptionMetric(
                    kitName: kit,
                    category: category,
                    totalCategoryApps: totalInCat,
                    adoptedAppsCount: count,
                    minSupportK: options.minSupportK,
                    minConfidence: options.minConfidence
                )
                metrics.append(metric)
            }

            // 채택률 내림차순 정렬
            metrics.sort { (a, b) -> Bool in
                if a.adoptionRate != b.adoptionRate {
                    return a.adoptionRate > b.adoptionRate
                }
                return a.kitName < b.kitName
            }

            let dominant = metrics.filter(\.isDominantStandard)

            let goldenProfile = GoldenTraitProfile(
                category: category,
                dominantTraits: dominant,
                allMetrics: metrics,
                totalAppsSampled: totalInCat,
                minSupportK: options.minSupportK,
                minConfidence: options.minConfidence
            )
            profilesByCategory[category] = goldenProfile
        }

        return ConsensusMiningReport(
            totalAppsScanned: profiles.count,
            categoryCounts: categoryCounts,
            profilesByCategory: profilesByCategory,
            appProfiles: profiles,
            executionDurationMs: executionDurationMs
        )
    }

    /// 마이닝 완료 후 GoldenTraitRegistry에 즉시 등록
    @discardableResult
    public func mineAndRegister(
        appsDirectory: URL,
        registry: GoldenTraitRegistry = .shared
    ) throws -> ConsensusMiningReport {
        let report = try scanAndMine(appsDirectory: appsDirectory)
        for (_, profile) in report.profilesByCategory {
            registry.registerProfile(profile)
        }
        return report
    }

    // MARK: - 단일 앱 정밀 스캔 로직

    /// 지정된 단일 앱 디렉터리를 분석하여 AppTraitProfile 생성
    public func scanApp(at appDirectory: URL) -> AppTraitProfile? {
        let fm = FileManager.default
        let appSlug = appDirectory.lastPathComponent

        // Package.swift 존재 확인 (앱 단위 패키지여야 함)
        let packageSwiftURL = appDirectory.appendingPathComponent("Package.swift")
        guard fm.fileExists(atPath: packageSwiftURL.path) else {
            return nil
        }

        // 1. Package.swift 의존성 추출
        let packageDependencies = extractDependenciesFromPackageSwift(at: packageSwiftURL)

        // 2. Sources 소스 코드 import 추출
        let sourcesURL = appDirectory.appendingPathComponent("Sources")
        let sourceImports = extractImportsFromSources(at: sourcesURL)

        // 3. 앱 카테고리 형태 분류
        let (category, reason) = classifyCategory(forApp: appDirectory, sourceImports: sourceImports)

        return AppTraitProfile(
            appSlug: appSlug,
            appPath: appDirectory.path,
            category: category,
            categoryClassificationReason: reason,
            packageDependencies: packageDependencies,
            sourceImports: sourceImports
        )
    }

    // MARK: - 카테고리 분류 휴리스틱

    /// Info.plist, package-identity.json 및 소스 코드를 통해 앱 카테고리 결정
    public func classifyCategory(
        forApp appDirectory: URL,
        sourceImports: Set<String>
    ) -> (AppCategory, String) {
        let slug = appDirectory.lastPathComponent.lowercased()

        // 1. Packaging/Info.plist 검사
        let infoPlistURL = appDirectory.appendingPathComponent("Packaging/Info.plist")
        do {
            let plistData = try Data(contentsOf: infoPlistURL)
            if let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] {
                if let lsUIElement = plist["LSUIElement"] as? Bool, lsUIElement {
                    return (.menuBarApp, "Packaging/Info.plist에 LSUIElement: true 지정됨")
                }
                if let lsUIElementStr = plist["LSUIElement"] as? String, lsUIElementStr == "1" || lsUIElementStr.lowercased() == "true" {
                    return (.menuBarApp, "Packaging/Info.plist에 LSUIElement: true 문자열 지정됨")
                }
            }
        } catch {}

        // 2. Packaging/package-identity.json 검사
        let identityURL = appDirectory.appendingPathComponent("Packaging/package-identity.json")
        do {
            let identityData = try Data(contentsOf: identityURL)
            let identityObj: [String: Any]?
            do {
                identityObj = try JSONSerialization.jsonObject(with: identityData) as? [String: Any]
            } catch {
                identityObj = nil
            }
            if let identity = identityObj {
                if let prefix = identity["prefix"] as? String, prefix == "daemon" {
                    return (.backgroundDaemon, "Packaging/package-identity.json prefix가 daemon임")
                }
                let purpose = (identity["purpose"] as? String)?.lowercased() ?? ""
                if purpose.contains("데몬") || purpose.contains("daemon") || purpose.contains("백그라운드 서비스") {
                    return (.backgroundDaemon, "Packaging/package-identity.json purpose가 daemon 성격임")
                }
                if purpose.contains("데몬") || purpose.contains("daemon") {
                    return (.backgroundDaemon, "package-identity.json purpose에 데몬 표기")
                }
                if purpose.contains("메뉴바") || purpose.contains("menubar") {
                    return (.menuBarApp, "package-identity.json purpose에 메뉴바 표기")
                }
                if identity["gui_product"] == nil && identity["cli_product"] != nil {
                    return (.cliTool, "package-identity.json에 gui_product 없고 cli_product만 존재")
                }
            }
        } catch {}

        // 3. 디렉터리 이름 규칙 검사
        if slug.contains("menubar") || slug.contains("-status-") {
            return (.menuBarApp, "디렉터리 이름에 menubar/status 키워드 포함")
        }
        if slug.contains("daemon") || slug.contains("service-broker") {
            return (.backgroundDaemon, "디렉터리 이름에 daemon/service 키워드 포함")
        }
        if slug.contains("-cli") || slug.hasSuffix("-tool-swift") {
            return (.cliTool, "디렉터리 이름에 cli/tool 키워드 포함")
        }

        // 4. 소스 코드 import 검사
        if sourceImports.contains("MenuBarPopoverUIKit") || sourceImports.contains("MenuBarExtra") {
            return (.menuBarApp, "소스 코드에서 MenuBarPopoverUIKit 채택")
        }
        if sourceImports.contains("SwiftUI") || sourceImports.contains("AppKit") || sourceImports.contains("AppWindowKit") {
            return (.guiWindowApp, "소스 코드에서 SwiftUI/AppKit/AppWindowKit 채택")
        }
        if sourceImports.contains("ArgumentParser") && !sourceImports.contains("AppKit") && !sourceImports.contains("SwiftUI") {
            return (.cliTool, "소스 코드에서 ArgumentParser 채택 및 GUI 프레임워크 미사용")
        }

        // 기본값: 일반 GUI 앱으로 간주
        return (.guiWindowApp, "기본 데스크톱 GUI 앱으로 판정")
    }

    // MARK: - 의존성 및 Import 파싱 유틸리티

    /// Package.swift 파일 내용에서 swiftkit 의존성 모듈 이름 추출
    public func extractDependenciesFromPackageSwift(at fileURL: URL) -> Set<String> {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }

        var dependencies = Set<String>()

        // 패턴 1: .product(name: "XYZKit", package: ...)
        do {
            let regex = try NSRegularExpression(pattern: #"\.product\(\s*name:\s*"([A-Za-z0-9_]+)""#)
            let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
            for match in matches {
                if let range = Range(match.range(at: 1), in: content) {
                    let name = String(content[range])
                    if name.hasSuffix("Kit") || GoldenTrait(rawValue: name) != nil {
                        dependencies.insert(name)
                    }
                }
            }
        } catch {}

        // 패턴 2: "XYZKit" 직접 나열 의존성
        do {
            let regex = try NSRegularExpression(pattern: #""([A-Za-z0-9_]+Kit)""#)
            let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
            for match in matches {
                if let range = Range(match.range(at: 1), in: content) {
                    dependencies.insert(String(content[range]))
                }
            }
        } catch {}

        return dependencies
    }

    /// Sources 디렉터리 내 Swift 파일들을 순회하며 import 문 추출
    public func extractImportsFromSources(at sourcesDirectory: URL) -> Set<String> {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourcesDirectory.path) else {
            return []
        }

        guard let enumerator = fm.enumerator(
            at: sourcesDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var imports = Set<String>()
        let importRegex: NSRegularExpression?
        do {
            importRegex = try NSRegularExpression(pattern: #"^\s*import\s+([A-Za-z0-9_]+)"#, options: [.anchorsMatchLines])
        } catch {
            importRegex = nil
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift" else { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            if let regex = importRegex {
                let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
                for match in matches {
                    if let range = Range(match.range(at: 1), in: content) {
                        imports.insert(String(content[range]))
                    }
                }
            }
        }

        return imports
    }
}
