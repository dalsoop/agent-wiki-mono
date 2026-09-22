import Foundation
import FastDiskIOKit

// MARK: - 1. 처방 레시피 및 변환 규칙 모델 (Prescription Recipe Schema)

/// 단일 소스 변환 규칙 (Google Refaster / OpenRewrite 식 AST 패턴 치환 규칙).
public struct SourceTransformationRule: Sendable {
    public let id: String
    public let description: String
    public let transform: @Sendable (String) -> (transformed: String, count: Int)

    public init(
        id: String,
        description: String,
        transform: @escaping @Sendable (String) -> (transformed: String, count: Int)
    ) {
        self.id = id
        self.description = description
        self.transform = transform
    }

    /// 정규식 기반 치환 규칙 생성 헬퍼
    public static func regex(
        id: String,
        description: String,
        pattern: String,
        template: String
    ) -> SourceTransformationRule {
        SourceTransformationRule(id: id, description: description) { content in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                return (content, 0)
            }
            let nsString = content as NSString
            let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsString.length))
            guard !matches.isEmpty else { return (content, 0) }

            let replaced = regex.stringByReplacingMatches(
                in: content,
                options: [],
                range: NSRange(location: 0, length: nsString.length),
                withTemplate: template
            )
            return (replaced, matches.count)
        }
    }
}

/// 공용 킷 결손에 대한 단일 처방 레시피 (Prescription Recipe).
public struct PrescriptionRecipe: Sendable {
    public let id: String
    public let trait: GoldenTrait
    public let kitName: String
    public let productDependency: String
    public let importModule: String
    public let transformations: [SourceTransformationRule]

    public init(
        id: String,
        trait: GoldenTrait,
        kitName: String,
        productDependency: String? = nil,
        importModule: String? = nil,
        transformations: [SourceTransformationRule]
    ) {
        self.id = id
        self.trait = trait
        self.kitName = kitName
        self.productDependency = productDependency ?? ".product(name: \"\(kitName)\", package: \"swiftkit\")"
        self.importModule = importModule ?? kitName
        self.transformations = transformations
    }
}

// MARK: - 2. 처방 실행 결과 모델 (Prescription Outcome)

/// 단일 파일 변경 내역
public struct FileModification: Sendable, Codable, Equatable {
    public let filePath: String
    public let addedImport: Bool
    public let replacementsCount: Int
    public let appliedRules: [String]

    public init(
        filePath: String,
        addedImport: Bool,
        replacementsCount: Int,
        appliedRules: [String]
    ) {
        self.filePath = filePath
        self.addedImport = addedImport
        self.replacementsCount = replacementsCount
        self.appliedRules = appliedRules
    }
}

/// 앱 단위 처방 실행 결과
public struct PrescriptionResult: Sendable, Codable, Equatable {
    public let appSlug: String
    public let appDirectory: String
    public let recipeID: String
    public let targetKit: String
    public let isDryRun: Bool
    public let manifestModified: Bool
    public let manifestDetail: String?
    public let modifiedFiles: [FileModification]
    public let totalReplacements: Int
    public let success: Bool
    public let message: String

    public init(
        appSlug: String,
        appDirectory: String,
        recipeID: String,
        targetKit: String,
        isDryRun: Bool,
        manifestModified: Bool,
        manifestDetail: String?,
        modifiedFiles: [FileModification],
        totalReplacements: Int,
        success: Bool,
        message: String
    ) {
        self.appSlug = appSlug
        self.appDirectory = appDirectory
        self.recipeID = recipeID
        self.targetKit = targetKit
        self.isDryRun = isDryRun
        self.manifestModified = manifestModified
        self.manifestDetail = manifestDetail
        self.modifiedFiles = modifiedFiles
        self.totalReplacements = totalReplacements
        self.success = success
        self.message = message
    }

    public var summary: String {
        let dryTag = isDryRun ? "[DRY-RUN] " : ""
        if !manifestModified && modifiedFiles.isEmpty {
            return "\(dryTag)[\(appSlug)] \(targetKit): 변경 필요 없음 (이미 최적화됨)"
        }
        return "\(dryTag)[\(appSlug)] \(targetKit): Manifest \(manifestModified ? "수정완료" : "유지"), 소스파일 \(modifiedFiles.count)개 수정 (총 \(totalReplacements)건 치환)"
    }
}

// MARK: - 3. RecipeAutoPrescriber 엔진

/// OpenRewrite 및 Google Refaster 모델 기반 레시피 자동 처방기.
/// 결손(Missing Trait)이 식별된 앱에 원자적으로 공용 킷 의존성을 주입하고 원시 코드를 고수준 API로 치환합니다.
public final class RecipeAutoPrescriber: Sendable {

    public init() {}

    // MARK: - Built-in Recipes (기본 등록 레시피)

    /// AppPersistenceKit 자동 처방 레시피
    public static let appPersistenceRecipe: PrescriptionRecipe = {
        let rules: [SourceTransformationRule] = [
            // Rule 1: try? JSONDecoder().decode(...) ➔ try? AppPersistence.decode(...)
            SourceTransformationRule.regex(
                id: "rule.app-persistence.decode.try-optional",
                description: "raw `try? JSONDecoder().decode(...)` ➔ `try? AppPersistence.decode(...)` 치환",
                pattern: #"try\?\s+JSONDecoder\(\)\.decode\(\s*([^,\n]+)\s*,\s*from:\s*([^)\n]+)\)"#,
                template: "try? AppPersistence.decode($1, from: $2)"
            ),
            // Rule 2: try JSONDecoder().decode(...) ➔ try AppPersistence.decode(...)
            SourceTransformationRule.regex(
                id: "rule.app-persistence.decode.try",
                description: "raw `try JSONDecoder().decode(...)` ➔ `try AppPersistence.decode(...)` 치환",
                pattern: #"try\s+JSONDecoder\(\)\.decode\(\s*([^,\n]+)\s*,\s*from:\s*([^)\n]+)\)"#,
                template: "try AppPersistence.decode($1, from: $2)"
            ),
            // Rule 3: raw JSONDecoder().decode(...) ➔ AppPersistence.decode(...)
            SourceTransformationRule.regex(
                id: "rule.app-persistence.decode.direct",
                description: "raw `JSONDecoder().decode(...)` ➔ `AppPersistence.decode(...)` 치환",
                pattern: #"JSONDecoder\(\)\.decode\(\s*([^,\n]+)\s*,\s*from:\s*([^)\n]+)\)"#,
                template: "AppPersistence.decode($1, from: $2)"
            ),
            // Rule 4: try? JSONEncoder().encode(...) ➔ try? AppPersistence.encode(...)
            SourceTransformationRule.regex(
                id: "rule.app-persistence.encode.try-optional",
                description: "raw `try? JSONEncoder().encode(...)` ➔ `try? AppPersistence.encode(...)` 치환",
                pattern: #"try\?\s+JSONEncoder\(\)\.encode\(\s*([^)\n]+)\)"#,
                template: "try? AppPersistence.encode($1)"
            ),
            // Rule 5: try JSONEncoder().encode(...) ➔ try AppPersistence.encode(...)
            SourceTransformationRule.regex(
                id: "rule.app-persistence.encode.try",
                description: "raw `try JSONEncoder().encode(...)` ➔ `try AppPersistence.encode(...)` 치환",
                pattern: #"try\s+JSONEncoder\(\)\.encode\(\s*([^)\n]+)\)"#,
                template: "try AppPersistence.encode($1)"
            ),
            // Rule 6: raw JSONEncoder().encode(...) ➔ AppPersistence.encode(...)
            SourceTransformationRule.regex(
                id: "rule.app-persistence.encode.direct",
                description: "raw `JSONEncoder().encode(...)` ➔ `AppPersistence.encode(...)` 치환",
                pattern: #"JSONEncoder\(\)\.encode\(\s*([^)\n]+)\)"#,
                template: "AppPersistence.encode($1)"
            )
        ]

        return PrescriptionRecipe(
            id: "recipe.app-persistence-kit",
            trait: .appPersistenceKit,
            kitName: "AppPersistenceKit",
            transformations: rules
        )
    }()

    /// ISO8601DateCodecKit 자동 처방 레시피
    public static let iso8601DateCodecRecipe: PrescriptionRecipe = {
        let rules: [SourceTransformationRule] = [
            // Rule 1: ISO8601DateFormatter().string(from: Date()) ➔ DateCodec.isoNow()
            SourceTransformationRule.regex(
                id: "rule.iso8601.now",
                description: "인라인 `ISO8601DateFormatter().string(from: Date())` ➔ `DateCodec.isoNow()` 치환",
                pattern: #"ISO8601DateFormatter\(\)\.string\(from:\s*Date\(\)\)"#,
                template: "DateCodec.isoNow()"
            ),
            // Rule 2: ISO8601DateFormatter().string(from: <expr>) ➔ DateCodec.formatISO8601(<expr>)
            SourceTransformationRule.regex(
                id: "rule.iso8601.format",
                description: "raw `ISO8601DateFormatter().string(from: ...)` ➔ `DateCodec.formatISO8601(...)` 치환",
                pattern: #"ISO8601DateFormatter\(\)\.string\(from:\s*([^)\n]+)\)"#,
                template: "DateCodec.formatISO8601($1)"
            ),
            // Rule 3: ISO8601DateFormatter().date(from: <expr>) ➔ DateCodec.parseISO8601(<expr>)
            SourceTransformationRule.regex(
                id: "rule.iso8601.parse",
                description: "raw `ISO8601DateFormatter().date(from: ...)` ➔ `DateCodec.parseISO8601(...)` 치환",
                pattern: #"ISO8601DateFormatter\(\)\.date\(from:\s*([^)\n]+)\)"#,
                template: "DateCodec.parseISO8601($1)"
            )
        ]

        return PrescriptionRecipe(
            id: "recipe.iso8601-date-codec-kit",
            trait: .iso8601DateCodecKit,
            kitName: "ISO8601DateCodecKit",
            transformations: rules
        )
    }()

    /// 전체 기본 등록 레시피 목록
    public static let standardRecipes: [PrescriptionRecipe] = [
        appPersistenceRecipe,
        iso8601DateCodecRecipe
    ]

    // MARK: - Prescription Execution API

    /// 단일 앱에 대해 특정 레시피를 적용합니다.
    public func prescribe(
        appDirectory: URL,
        recipe: PrescriptionRecipe,
        dryRun: Bool = false
    ) throws -> PrescriptionResult {
        let appSlug = appDirectory.lastPathComponent
        let fm = FileManager.default

        let pkgURL = appDirectory.appendingPathComponent("Package.swift")
        guard fm.fileExists(atPath: pkgURL.path) else {
            return PrescriptionResult(
                appSlug: appSlug,
                appDirectory: appDirectory.path,
                recipeID: recipe.id,
                targetKit: recipe.kitName,
                isDryRun: dryRun,
                manifestModified: false,
                manifestDetail: "Package.swift 없음",
                modifiedFiles: [],
                totalReplacements: 0,
                success: false,
                message: "Package.swift를 찾을 수 없습니다."
            )
        }

        // Step 2: Source AST Transformation 먼저 시뮬레이션/수행
        // 소스에서 실제 치환 대상이 식별되거나, 이미 결손 킷인 경우에 처방 진행
        let sourcesDir = appDirectory.appendingPathComponent("Sources")
        var swiftFiles: [URL] = []
        if fm.fileExists(atPath: sourcesDir.path) {
            swiftFiles = enumerateSwiftFiles(at: sourcesDir)
        } else {
            swiftFiles = enumerateSwiftFiles(at: appDirectory, maxDepth: 4)
        }

        var fileModifications: [FileModification] = []
        var totalReplacements = 0
        var modifiedTargetNames: Set<String> = []

        for fileURL in swiftFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let (newContent, replacedCount, appliedRules) = applyTransformations(
                content: content,
                transformations: recipe.transformations
            )

            if replacedCount > 0 {
                var finalContent = newContent
                var addedImport = false

                // import 문 추가 필요 여부 확인
                if !finalContent.contains("import \(recipe.importModule)") {
                    finalContent = injectImportStatement(
                        content: finalContent,
                        moduleName: recipe.importModule
                    )
                    addedImport = true
                }

                let relativePath = relativePathOf(fileURL: fileURL, baseDirectory: appDirectory)
                let targetName = targetNameOf(fileURL: fileURL, sourcesDir: sourcesDir)
                if let targetName {
                    modifiedTargetNames.insert(targetName)
                }

                fileModifications.append(FileModification(
                    filePath: relativePath,
                    addedImport: addedImport,
                    replacementsCount: replacedCount,
                    appliedRules: appliedRules
                ))
                totalReplacements += replacedCount

                if !dryRun {
                    try finalContent.write(to: fileURL, atomically: true, encoding: .utf8)
                }
            }
        }

        // Step 1: Manifest Injection (Package.swift)
        // 소스 치환이 발생했거나 결손이 확정된 경우 Manifest에 의존성 주입
        var manifestModified = false
        var manifestDetail: String? = nil

        let pkgContent = (try? String(contentsOf: pkgURL, encoding: .utf8)) ?? ""
        let isAlreadyDepInjected = pkgContent.contains("\"\(recipe.kitName)\"")

        if !isAlreadyDepInjected && (totalReplacements > 0 || !modifiedTargetNames.isEmpty) {
            let injectedPkg = injectManifestDependency(
                pkgContent: pkgContent,
                kitName: recipe.kitName,
                targetNames: modifiedTargetNames
            )
            if injectedPkg != pkgContent {
                manifestModified = true
                manifestDetail = "Package.swift 타깃 [\(modifiedTargetNames.sorted().joined(separator: ", "))]에 \(recipe.kitName) 의존성 주입"
                if !dryRun {
                    try injectedPkg.write(to: pkgURL, atomically: true, encoding: .utf8)
                }
            }
        }

        return PrescriptionResult(
            appSlug: appSlug,
            appDirectory: appDirectory.path,
            recipeID: recipe.id,
            targetKit: recipe.kitName,
            isDryRun: dryRun,
            manifestModified: manifestModified,
            manifestDetail: manifestDetail,
            modifiedFiles: fileModifications,
            totalReplacements: totalReplacements,
            success: true,
            message: "\(recipe.kitName) 처방 완료"
        )
    }

    /// 단일 앱에 대해 복수의 레시피를 일괄 처방합니다.
    public func prescribe(
        appDirectory: URL,
        recipes: [PrescriptionRecipe] = standardRecipes,
        dryRun: Bool = false
    ) throws -> [PrescriptionResult] {
        var results: [PrescriptionResult] = []
        for recipe in recipes {
            let result = try prescribe(appDirectory: appDirectory, recipe: recipe, dryRun: dryRun)
            results.append(result)
        }
        return results
    }

    /// HomeostasisGapScanner 진단 결과를 기반으로 결손된 특성만 자동 처방합니다.
    public func prescribeAllMissing(
        gapResult: AppGapScanResult,
        dryRun: Bool = false
    ) throws -> [PrescriptionResult] {
        let appDir = URL(fileURLWithPath: gapResult.appDirectory)
        var results: [PrescriptionResult] = []

        for missingTrait in gapResult.missingTraits {
            guard let recipe = Self.standardRecipes.first(where: { $0.trait == missingTrait }) else {
                continue
            }
            let result = try prescribe(appDirectory: appDir, recipe: recipe, dryRun: dryRun)
            results.append(result)
        }
        return results
    }

    // MARK: - Internal Transformation Helpers

    /// 소스 코드에 변환 규칙들을 순차적으로 적용합니다.
    public func applyTransformations(
        content: String,
        transformations: [SourceTransformationRule]
    ) -> (transformed: String, totalReplacements: Int, appliedRules: [String]) {
        var current = content
        var totalCount = 0
        var appliedRules: [String] = []

        for rule in transformations {
            let (replaced, count) = rule.transform(current)
            if count > 0 {
                current = replaced
                totalCount += count
                appliedRules.append(rule.id)
            }
        }

        return (current, totalCount, appliedRules)
    }

    /// 소스 파일 상단 적절한 위치에 import 문을 주입합니다.
    public func injectImportStatement(content: String, moduleName: String) -> String {
        let importStatement = "import \(moduleName)"
        if content.contains(importStatement) { return content }

        let lines = content.components(separatedBy: "\n")
        var lastImportIndex = -1

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("import ") {
                lastImportIndex = index
            }
        }

        var newLines = lines
        if lastImportIndex >= 0 {
            // 마지막 import 문 바로 다음 줄에 추가
            newLines.insert(importStatement, at: lastImportIndex + 1)
        } else {
            // import 문이 없으면 첫 비주석 라인 앞 또는 최상단에 추가
            var insertIndex = 0
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") || trimmed.isEmpty {
                    continue
                }
                insertIndex = index
                break
            }
            newLines.insert(importStatement, at: insertIndex)
            newLines.insert("", at: insertIndex + 1)
        }

        return newLines.joined(separator: "\n")
    }

    // MARK: - Internal Manifest Surgery Helpers

    /// Package.swift의 타깃 dependencies에 의존성(.product(name: ..., package: "swiftkit"))을 주입합니다.
    public func injectManifestDependency(
        pkgContent: String,
        kitName: String,
        targetNames: Set<String>
    ) -> String {
        var text = pkgContent

        // 1. swiftkit 패키지 자체 의존성 확인 및 주입
        if !text.contains("package: \"swiftkit\"") && !text.contains("../../swiftkit") {
            text = ensureSwiftkitPackageDependency(text)
        }

        let productItem = ".product(name: \"\(kitName)\", package: \"swiftkit\")"
        if text.contains("\"\(kitName)\"") {
            return text
        }

        // 2. 대상 타깃 결정
        // 우선 전달된 targetNames 중 매칭되는 타깃, 없으면 Core 타깃, 그 다음 일반 타깃
        let targetsToPatch = resolveTargetsToPatch(pkgText: text, preferredTargets: targetNames)

        for targetName in targetsToPatch {
            text = injectProductIntoTarget(
                pkgText: text,
                targetName: targetName,
                productItem: productItem
            )
        }

        return text
    }

    private func ensureSwiftkitPackageDependency(_ text: String) -> String {
        let pattern = #"(?m)^[ \t]*dependencies:\s*\["#
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            if let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
                var mutable = text
                let insertionPoint = match.range.location + match.range.length
                let idx = mutable.index(mutable.startIndex, offsetBy: insertionPoint)
                mutable.insert(contentsOf: "\n        .package(path: \"../../swiftkit\"),", at: idx)
                return mutable
            }
        } catch {}
        return text
    }

    private func resolveTargetsToPatch(pkgText: String, preferredTargets: Set<String>) -> [String] {
        if !preferredTargets.isEmpty {
            // preferredTargets 중 Package.swift에 실제로 존재하는 것 반환
            let existing = preferredTargets.filter { pkgText.contains("\"" + $0 + "\"") }
            if !existing.isEmpty {
                return Array(existing).sorted()
            }
        }

        // Core 타깃 우선 검색
        let corePattern = #"\.target\(\s*name:\s*"([^"]+Core)""#
        do {
            let regex = try NSRegularExpression(pattern: corePattern)
            let matches = regex.matches(in: pkgText, range: NSRange(location: 0, length: (pkgText as NSString).length))
            if let first = matches.first, first.numberOfRanges > 1 {
                let range = first.range(at: 1)
                let name = (pkgText as NSString).substring(with: range)
                return [name]
            }
        } catch {}

        // 일반 executableTarget 또는 target 중 testTarget이 아닌 첫 번째
        let targetPattern = #"\.(?:executableT|t)arget\(\s*name:\s*"([^"]+)""#
        do {
            let regex = try NSRegularExpression(pattern: targetPattern)
            let matches = regex.matches(in: pkgText, range: NSRange(location: 0, length: (pkgText as NSString).length))
            for match in matches where match.numberOfRanges > 1 {
                let name = (pkgText as NSString).substring(with: match.range(at: 1))
                if !name.hasSuffix("Tests") {
                    return [name]
                }
            }
        } catch {}

        return []
    }

    private func injectProductIntoTarget(
        pkgText: String,
        targetName: String,
        productItem: String
    ) -> String {
        let escapedTarget = NSRegularExpression.escapedPattern(for: targetName)
        // .target(name: "...", ... dependencies: [
        let pattern = #"(\.(?:executableT|t)arget\(\s*name:\s*"\#(escapedTarget)"[\s\S]*?dependencies:\s*\[)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: pkgText, range: NSRange(location: 0, length: (pkgText as NSString).length)) else {
            return pkgText
        }

        var mutable = pkgText
        let insertionPoint = match.range.location + match.range.length
        let idx = mutable.index(mutable.startIndex, offsetBy: insertionPoint)

        let injection = "\n                \(productItem),"
        mutable.insert(contentsOf: injection, at: idx)
        return mutable
    }

    // MARK: - File System Helpers

    private func enumerateSwiftFiles(at directory: URL, maxDepth: Int = 10) -> [URL] {
        var results: [URL] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let fileURL as URL in enumerator {
            if enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            if fileURL.pathExtension == "swift" && !fileURL.path.contains("/Tests/") && !fileURL.path.contains("/.build/") {
                results.append(fileURL)
            }
        }
        return results
    }

    private func relativePathOf(fileURL: URL, baseDirectory: URL) -> String {
        let base = baseDirectory.path
        let file = fileURL.path
        if file.hasPrefix(base) {
            return String(file.dropFirst(base.count).drop(while: { $0 == "/" }))
        }
        return fileURL.lastPathComponent
    }

    private func targetNameOf(fileURL: URL, sourcesDir: URL) -> String? {
        let path = fileURL.path
        let sourcesPath = sourcesDir.path
        guard path.hasPrefix(sourcesPath) else { return nil }
        let sub = String(path.dropFirst(sourcesPath.count).drop(while: { $0 == "/" }))
        let parts = sub.split(separator: "/")
        return parts.first.map(String.init)
    }

    /// 무손실 LST 리보솜 엔진을 적용하여 소스 코드를 변환하고 연쇄 소각을 수행합니다.
    public func applyRibosome(
        content: String,
        config: TriviaPreservingRibosome.TransformationConfig = .init()
    ) -> TriviaPreservingRibosome.TransformationReport {
        let ribosome = TriviaPreservingRibosome()
        return ribosome.transform(source: content, config: config)
    }
}
