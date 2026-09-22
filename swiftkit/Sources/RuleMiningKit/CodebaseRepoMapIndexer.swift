import Foundation

// MARK: - 1. Repository Map DTOs

/// Swift 접근 제어 레벨
public enum AccessLevel: String, Sendable, Codable, Comparable, CaseIterable {
    case `open`
    case `public`
    case `package`
    case `internal`
    case `fileprivate`
    case `private`

    public var isPublicOrOpen: Bool {
        self == .open || self == .public
    }

    public var isInternalOrAbove: Bool {
        self != .fileprivate && self != .private
    }

    private var priority: Int {
        switch self {
        case .open: return 5
        case .public: return 4
        case .package: return 3
        case .internal: return 2
        case .fileprivate: return 1
        case .private: return 0
        }
    }

    public static func < (lhs: AccessLevel, rhs: AccessLevel) -> Bool {
        lhs.priority < rhs.priority
    }
}

/// Swift 핵심 선언 타입
public enum DeclarationKind: String, Sendable, Codable, CaseIterable {
    case `struct`
    case `class`
    case `actor`
    case `protocol`
    case `enum`
    case `extension`
}

/// 프로퍼티 시그니처 맵
public struct PropertySignatureMap: Sendable, Codable, Equatable, Identifiable {
    public var id: String { "\(accessLevel.rawValue)_\(name)_\(line)" }

    public let name: String
    public let type: String?
    public let accessLevel: AccessLevel
    public let isStatic: Bool
    public let isConstant: Bool
    public let attributes: [String]
    public let line: Int

    public init(
        name: String,
        type: String? = nil,
        accessLevel: AccessLevel = .internal,
        isStatic: Bool = false,
        isConstant: Bool = false,
        attributes: [String] = [],
        line: Int = 1
    ) {
        self.name = name
        self.type = type
        self.accessLevel = accessLevel
        self.isStatic = isStatic
        self.isConstant = isConstant
        self.attributes = attributes
        self.line = line
    }

    public var formattedSignature: String {
        var parts: [String] = []
        if !attributes.isEmpty {
            parts.append(attributes.joined(separator: " "))
        }
        if accessLevel != .internal {
            parts.append(accessLevel.rawValue)
        }
        if isStatic {
            parts.append("static")
        }
        parts.append(isConstant ? "let" : "var")
        if let type = type, !type.isEmpty {
            parts.append("\(name): \(type)")
        } else {
            parts.append(name)
        }
        return parts.joined(separator: " ")
    }
}

/// 함수 / 메서드 시그니처 맵
public struct FunctionSignatureMap: Sendable, Codable, Equatable, Identifiable {
    public var id: String { "\(accessLevel.rawValue)_\(name)_\(line)" }

    public let name: String
    public let signature: String
    public let parameters: [String]
    public let returnType: String?
    public let accessLevel: AccessLevel
    public let isStatic: Bool
    public let isAsync: Bool
    public let isThrows: Bool
    public let isMutating: Bool
    public let attributes: [String]
    public let line: Int

    public init(
        name: String,
        signature: String,
        parameters: [String] = [],
        returnType: String? = nil,
        accessLevel: AccessLevel = .internal,
        isStatic: Bool = false,
        isAsync: Bool = false,
        isThrows: Bool = false,
        isMutating: Bool = false,
        attributes: [String] = [],
        line: Int = 1
    ) {
        self.name = name
        self.signature = signature
        self.parameters = parameters
        self.returnType = returnType
        self.accessLevel = accessLevel
        self.isStatic = isStatic
        self.isAsync = isAsync
        self.isThrows = isThrows
        self.isMutating = isMutating
        self.attributes = attributes
        self.line = line
    }

    public var formattedSignature: String {
        var parts: [String] = []
        if !attributes.isEmpty {
            parts.append(attributes.joined(separator: " "))
        }
        if accessLevel != .internal {
            parts.append(accessLevel.rawValue)
        }
        if isStatic {
            parts.append("static")
        }
        if isMutating {
            parts.append("mutating")
        }
        parts.append(signature)
        return parts.joined(separator: " ")
    }
}

/// 타입 선언 맵 (Struct, Class, Actor, Protocol, Enum, Extension)
public struct TypeDeclarationMap: Sendable, Codable, Equatable, Identifiable {
    public var id: String { "\(kind.rawValue)_\(name)_\(line)" }

    public let kind: DeclarationKind
    public let name: String
    public let generics: String?
    public let conformances: [String]
    public let accessLevel: AccessLevel
    public let attributes: [String]
    public let cases: [String]
    public let properties: [PropertySignatureMap]
    public let functions: [FunctionSignatureMap]
    public let nestedTypes: [TypeDeclarationMap]
    public let line: Int

    public init(
        kind: DeclarationKind,
        name: String,
        generics: String? = nil,
        conformances: [String] = [],
        accessLevel: AccessLevel = .internal,
        attributes: [String] = [],
        cases: [String] = [],
        properties: [PropertySignatureMap] = [],
        functions: [FunctionSignatureMap] = [],
        nestedTypes: [TypeDeclarationMap] = [],
        line: Int = 1
    ) {
        self.kind = kind
        self.name = name
        self.generics = generics
        self.conformances = conformances
        self.accessLevel = accessLevel
        self.attributes = attributes
        self.cases = cases
        self.properties = properties
        self.functions = functions
        self.nestedTypes = nestedTypes
        self.line = line
    }

    /// 헤더 라인 (예: `public struct MyModel<T>: Codable, Identifiable`)
    public var headerLine: String {
        var parts: [String] = []
        if !attributes.isEmpty {
            parts.append(attributes.joined(separator: " "))
        }
        if accessLevel != .internal {
            parts.append(accessLevel.rawValue)
        }
        parts.append(kind.rawValue)
        var nameWithGenerics = name
        if let generics = generics, !generics.isEmpty {
            nameWithGenerics += generics
        }
        if !conformances.isEmpty {
            nameWithGenerics += ": " + conformances.joined(separator: ", ")
        }
        parts.append(nameWithGenerics)
        return parts.joined(separator: " ")
    }
}

/// 파일 단위 Repo Map
public struct FileRepoMap: Sendable, Codable, Equatable, Identifiable {
    public var id: String { path }

    /// 대상 앱 루트 기준 상대 경로 (예: `Sources/AppCore/Models.swift`)
    public let path: String
    /// import 선언 모듈 목록
    public let imports: [String]
    /// 파일 내 정의된 핵심 타입 선언 목록
    public let types: [TypeDeclarationMap]
    /// 탑레벨 함수 목록
    public let standaloneFunctions: [FunctionSignatureMap]
    /// 탑레벨 프로퍼티 목록
    public let standaloneProperties: [PropertySignatureMap]
    /// 타입알리아스 목록
    public let typealiases: [String]

    public init(
        path: String,
        imports: [String] = [],
        types: [TypeDeclarationMap] = [],
        standaloneFunctions: [FunctionSignatureMap] = [],
        standaloneProperties: [PropertySignatureMap] = [],
        typealiases: [String] = []
    ) {
        self.path = path
        self.imports = imports
        self.types = types
        self.standaloneFunctions = standaloneFunctions
        self.standaloneProperties = standaloneProperties
        self.typealiases = typealiases
    }

    public var totalTypeCount: Int {
        var count = types.count
        for t in types {
            count += t.nestedTypes.count
        }
        return count
    }

    public var totalFunctionCount: Int {
        var count = standaloneFunctions.count
        for t in types {
            count += t.functions.count
            for n in t.nestedTypes {
                count += n.functions.count
            }
        }
        return count
    }

    public var totalPropertyCount: Int {
        var count = standaloneProperties.count
        for t in types {
            count += t.properties.count
            for n in t.nestedTypes {
                count += n.properties.count
            }
        }
        return count
    }
}

/// 타깃 요약 정보
public struct TargetSummary: Sendable, Codable, Equatable {
    public let name: String
    public let isTest: Bool
    public let dependencies: [String]

    public init(name: String, isTest: Bool = false, dependencies: [String] = []) {
        self.name = name
        self.isTest = isTest
        self.dependencies = dependencies
    }
}

/// `Package.swift` 의존성 및 패키지 요약 정보
public struct PackageSummary: Sendable, Codable, Equatable {
    public let name: String
    public let products: [String]
    public let targets: [TargetSummary]
    public let kitDependencies: [String]
    public let externalDependencies: [String]

    public init(
        name: String,
        products: [String] = [],
        targets: [TargetSummary] = [],
        kitDependencies: [String] = [],
        externalDependencies: [String] = []
    ) {
        self.name = name
        self.products = products
        self.targets = targets
        self.kitDependencies = kitDependencies
        self.externalDependencies = externalDependencies
    }
}

/// 에이전트의 컨텍스트 윈도우(예: 2,000 토큰 이내)에 최적화된 컴팩트 Repo Map DTO
public struct RepoMapSummary: Sendable, Codable, Equatable {
    /// 대상 앱 식별자 (slug, e.g. "agent-chat-swift")
    public let appSlug: String
    /// 분석 대상 디렉터리 경로
    public let rootPath: String
    /// Package.swift 분석 요약 정보
    public let packageSummary: PackageSummary?
    /// 소스 파일별 Repo Map
    public let files: [FileRepoMap]
    /// 총 분석 파일 수
    public let totalFiles: Int
    /// 총 추출 타입 수
    public let totalTypes: Int
    /// 총 추출 함수/메서드 수
    public let totalFunctions: Int
    /// 총 추출 프로퍼티 수
    public let totalProperties: Int
    /// 추정 토큰 수 (LLM 컨텍스트 환산)
    public let estimatedTokens: Int
    /// 에이전트 프롬프트 주입용 컴팩트 텍스트 맵
    public let formattedMap: String

    public init(
        appSlug: String,
        rootPath: String,
        packageSummary: PackageSummary? = nil,
        files: [FileRepoMap] = [],
        totalFiles: Int = 0,
        totalTypes: Int = 0,
        totalFunctions: Int = 0,
        totalProperties: Int = 0,
        estimatedTokens: Int = 0,
        formattedMap: String = ""
    ) {
        self.appSlug = appSlug
        self.rootPath = rootPath
        self.packageSummary = packageSummary
        self.files = files
        self.totalFiles = totalFiles
        self.totalTypes = totalTypes
        self.totalFunctions = totalFunctions
        self.totalProperties = totalProperties
        self.estimatedTokens = estimatedTokens
        self.formattedMap = formattedMap
    }

    /// 에이전트 컨텍스트 주입용 표준 프롬프트 블록 반환 (ACI)
    public func asAgentContextPrompt(title: String? = nil) -> String {
        let displayTitle = title ?? "Codebase Repository Map (\(appSlug))"
        let prompt = """
        ### \(displayTitle)
        - Files: \(totalFiles) | Types: \(totalTypes) | Functions: \(totalFunctions)
        - Estimated Tokens: ~\(estimatedTokens)

        ```swift
        \(formattedMap)
        ```
        """
        return prompt
    }

    /// JSON 인코딩 문자열 반환
    public func toJSONString(prettyPrinted: Bool = true) -> String? {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
}

// MARK: - 2. Repo Map 옵션 (RepoMapOptions)

public struct RepoMapOptions: Sendable, Codable, Equatable {
    /// 최대 토큰 예산 (기본값: 2,000 토큰)
    public var maxTokenBudget: Int
    /// 테스트 대상(Tests 디렉터리 등) 포함 여부 (기본값: false)
    public var includeTests: Bool
    /// private / fileprivate 멤버 포함 여부 (기본값: false)
    public var includePrivate: Bool
    /// 소스 파일 확장자 (기본값: ["swift"])
    public var fileExtensions: Set<String>
    /// 제외 디렉터리 이름 목록
    public var excludedDirectoryNames: Set<String>
    /// 상세도 수준
    public var detailLevel: DetailLevel

    public enum DetailLevel: String, Sendable, Codable, CaseIterable {
        case full        // 전체 시그니처 및 프로퍼티 상세
        case standard    // 주요 타입, 메서드 시그니처, 주요 프로퍼티
        case compact     // 타입 헤더 + 공개/내부 메서드 시그니처
        case outline     // 파일 및 타입 헤더만
    }

    public init(
        maxTokenBudget: Int = 2000,
        includeTests: Bool = false,
        includePrivate: Bool = false,
        fileExtensions: Set<String> = ["swift"],
        excludedDirectoryNames: Set<String> = [".build", ".git", ".worktrees", "DerivedData", "Fixtures", "Tests"],
        detailLevel: DetailLevel = .standard
    ) {
        self.maxTokenBudget = maxTokenBudget
        self.includeTests = includeTests
        self.includePrivate = includePrivate
        self.fileExtensions = fileExtensions
        self.excludedDirectoryNames = excludedDirectoryNames
        self.detailLevel = detailLevel
    }

    public static let `default` = RepoMapOptions()

    public static let compact = RepoMapOptions(
        maxTokenBudget: 2000,
        includeTests: false,
        includePrivate: false,
        detailLevel: .compact
    )
}

// MARK: - 3. CodebaseRepoMapIndexer

/// aider의 Tree-sitter Repo Map 아키텍처를 순수 Swift로 고속 이식한 AST 코드베이스 인덱서.
///
/// 컴파일러 의존성 없이 Swift 소스 코드를 단일 패스(O(N))로 토크나이징하고,
/// 중괄호 스코프 스택 및 선언 상태 기계를 통해 핵심 타입과 공개 메서드 시그니처를 추출합니다.
/// 추출된 맵은 2,000 토큰 컨텍스트 예산 내에 맞춰 적응형으로 압축됩니다.
public final class CodebaseRepoMapIndexer: Sendable {

    public init() {}

    // MARK: - 공개 API

    /// 앱 디렉터리(`apps/<slug>`)를 인덱싱하여 컴팩트 `RepoMapSummary` 생성
    public func indexApp(
        at appDirectory: URL,
        options: RepoMapOptions = .default
    ) throws -> RepoMapSummary {
        let appSlug = appDirectory.lastPathComponent
        let rootPath = appDirectory.path

        // 1. Package.swift 파싱
        let packageSwiftURL = appDirectory.appendingPathComponent("Package.swift")
        let packageSummary = parsePackageSwift(at: packageSwiftURL)

        // 2. 소스 파일 수집 및 인덱싱
        let sourceFiles = discoverSourceFiles(in: appDirectory, options: options)
        var fileMaps: [FileRepoMap] = []

        for fileURL in sourceFiles {
            let relativePath = makeRelativePath(for: fileURL, relativeTo: appDirectory)
            do {
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                let fileMap = indexSource(code: content, relativePath: relativePath, options: options)
                // 타입이나 함수 또는 import가 하나라도 있으면 포함
                if !fileMap.types.isEmpty || !fileMap.standaloneFunctions.isEmpty || !fileMap.imports.isEmpty {
                    fileMaps.append(fileMap)
                }
            } catch {}
        }

        // 3. 통계 집계
        var totalTypes = 0
        var totalFunctions = 0
        var totalProperties = 0
        for f in fileMaps {
            totalTypes += f.totalTypeCount
            totalFunctions += f.totalFunctionCount
            totalProperties += f.totalPropertyCount
        }

        // 4. 에이전트 컨텍스트 윈도우(예: 2,000 토큰)에 맞춘 컴팩트 렌더링
        let formatted = formatRepoMap(
            appSlug: appSlug,
            packageSummary: packageSummary,
            files: fileMaps,
            options: options
        )
        let estimatedTokens = Self.estimateTokenCount(formatted)

        return RepoMapSummary(
            appSlug: appSlug,
            rootPath: rootPath,
            packageSummary: packageSummary,
            files: fileMaps,
            totalFiles: fileMaps.count,
            totalTypes: totalTypes,
            totalFunctions: totalFunctions,
            totalProperties: totalProperties,
            estimatedTokens: estimatedTokens,
            formattedMap: formatted
        )
    }

    /// 단일 Swift 소스 코드 텍스트를 인덱싱하여 `FileRepoMap` 생성
    public func indexSource(
        code: String,
        relativePath: String = "Source.swift",
        options: RepoMapOptions = .default
    ) -> FileRepoMap {
        let parser = FastSwiftASTParser(code: code, options: options)
        return parser.parse(relativePath: relativePath)
    }

    /// 토큰 수 추정치 계산 (LLM 토크나이저 기준 근사치: ~3.8 자 / 토큰)
    public static func estimateTokenCount(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let charCount = Double(text.utf8.count)
        return max(1, Int(ceil(charCount / 3.8)))
    }

    // MARK: - Package.swift 파싱

    public func parsePackageSwift(at fileURL: URL) -> PackageSummary? {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        // 패키지 이름 추출
        let name = extractRegex(pattern: #"name:\s*"([^"]+)""#, from: content) ?? fileURL.deletingLastPathComponent().lastPathComponent

        // Products 추출
        var products: [String] = []
        do {
            let regex = try NSRegularExpression(pattern: #"\.(?:executable|library)\(\s*name:\s*"([^"]+)""#)
            let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
            for match in matches {
                if let range = Range(match.range(at: 1), in: content) {
                    products.append(String(content[range]))
                }
            }
        } catch {}

        // Targets 및 의존성 추출
        var targets: [TargetSummary] = []
        do {
            let regex = try NSRegularExpression(
                pattern: #"\.(?:target|executableTarget|testTarget)\(\s*name:\s*"([^"]+)"(?:[^\)]*?dependencies:\s*\[(.*?)\])?"#,
                options: [.dotMatchesLineSeparators]
            )
            let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
            for match in matches {
                guard let nameRange = Range(match.range(at: 1), in: content) else { continue }
                let targetName = String(content[nameRange])
                let isTest = content[Range(match.range(at: 0), in: content)!].contains(".testTarget")

                var deps: [String] = []
                if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound,
                   let depsRange = Range(match.range(at: 2), in: content) {
                    let depsString = String(content[depsRange])
                    do {
                        let dRegex = try NSRegularExpression(pattern: #""([^"]+)""#)
                        let dMatches = dRegex.matches(in: depsString, range: NSRange(depsString.startIndex..., in: depsString))
                        for dm in dMatches {
                            if let r = Range(dm.range(at: 1), in: depsString) {
                                deps.append(String(depsString[r]))
                            }
                        }
                    } catch {}
                }
                targets.append(TargetSummary(name: targetName, isTest: isTest, dependencies: deps))
            }
        } catch {}

        // Kit 의존성 및 외부 패키지 추출
        var kitDeps = Set<String>()
        var externalDeps = Set<String>()

        // 1) .package(path: "...") / .package(url: "...")
        do {
            let regex = try NSRegularExpression(pattern: #"\.package\(\s*(?:path|url):\s*"([^"]+)""#)
            let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
            for match in matches {
                if let range = Range(match.range(at: 1), in: content) {
                    let pathOrUrl = String(content[range])
                    let lastPart = URL(fileURLWithPath: pathOrUrl).lastPathComponent
                    externalDeps.insert(lastPart)
                }
            }
        } catch {}

        // 2) Kit 모듈 추출
        do {
            let regex = try NSRegularExpression(pattern: #""([A-Za-z0-9_]+Kit)""#)
            let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
            for match in matches {
                if let range = Range(match.range(at: 1), in: content) {
                    kitDeps.insert(String(content[range]))
                }
            }
        } catch {}

        return PackageSummary(
            name: name,
            products: products,
            targets: targets,
            kitDependencies: kitDeps.sorted(),
            externalDependencies: externalDeps.sorted()
        )
    }

    // MARK: - 소스 파일 탐색

    private func discoverSourceFiles(in directoryURL: URL, options: RepoMapOptions) -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directoryURL.path) else { return [] }

        guard let enumerator = fm.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var sourceFiles: [URL] = []
        for case let fileURL as URL in enumerator {
            let relativePath = makeRelativePath(for: fileURL, relativeTo: directoryURL)
            let pathComponents = relativePath.split(separator: "/").map(String.init)

            // 제외 디렉터리 필터
            let isExcluded = pathComponents.contains { options.excludedDirectoryNames.contains($0) }
            if isExcluded {
                if !options.includeTests && pathComponents.contains("Tests") {
                    continue
                }
                if isExcluded && !pathComponents.contains("Tests") {
                    continue
                }
            }

            if !options.includeTests && (relativePath.hasPrefix("Tests/") || relativePath.contains("/Tests/")) {
                continue
            }

            if options.fileExtensions.contains(fileURL.pathExtension) {
                sourceFiles.append(fileURL)
            }
        }

        return sourceFiles.sorted { $0.path < $1.path }
    }

    private func makeRelativePath(for fileURL: URL, relativeTo baseURL: URL) -> String {
        let basePath = baseURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        if filePath.hasPrefix(basePath) {
            var rel = String(filePath.dropFirst(basePath.count))
            if rel.hasPrefix("/") {
                rel.removeFirst()
            }
            return rel
        }
        return fileURL.lastPathComponent
    }

    private func extractRegex(pattern: String, from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    // MARK: - 적응형 Repo Map 텍스트 포매팅 (Aider 스타일 + 토큰 예산 피팅)

    public func formatRepoMap(
        appSlug: String,
        packageSummary: PackageSummary?,
        files: [FileRepoMap],
        options: RepoMapOptions
    ) -> String {
        // 1단계: 지정된 상세도로 렌더링 시도
        var rendered = renderMap(
            appSlug: appSlug,
            packageSummary: packageSummary,
            files: files,
            detailLevel: options.detailLevel,
            includePrivate: options.includePrivate
        )

        var tokens = Self.estimateTokenCount(rendered)
        if tokens <= options.maxTokenBudget {
            return rendered
        }

        // 2단계: 예산 초과 시 단계별 다운스케일링
        let fallbacks: [(RepoMapOptions.DetailLevel, Bool)] = [
            (.standard, false),
            (.compact, false),
            (.outline, false)
        ]

        for (fallbackLevel, fallbackPrivate) in fallbacks {
            if fallbackLevel == options.detailLevel && fallbackPrivate == options.includePrivate {
                continue
            }
            rendered = renderMap(
                appSlug: appSlug,
                packageSummary: packageSummary,
                files: files,
                detailLevel: fallbackLevel,
                includePrivate: fallbackPrivate
            )
            tokens = Self.estimateTokenCount(rendered)
            if tokens <= options.maxTokenBudget {
                return rendered
            }
        }

        // 3단계: 그래도 초과하는 거대 모노레포의 경우 파일 단위 프루닝
        return pruneToFitTokenBudget(
            appSlug: appSlug,
            packageSummary: packageSummary,
            files: files,
            maxTokens: options.maxTokenBudget
        )
    }

    private func renderMap(
        appSlug: String,
        packageSummary: PackageSummary?,
        files: [FileRepoMap],
        detailLevel: RepoMapOptions.DetailLevel,
        includePrivate: Bool
    ) -> String {
        var lines: [String] = []

        // Package.swift 요약 정보
        if let pkg = packageSummary {
            lines.append("Package.swift: \(pkg.name)")
            if !pkg.products.isEmpty {
                lines.append("  Products: [\(pkg.products.joined(separator: ", "))]")
            }
            if !pkg.kitDependencies.isEmpty {
                lines.append("  Kit Dependencies: [\(pkg.kitDependencies.joined(separator: ", "))]")
            }
            let nonTestTargets = pkg.targets.filter { !$0.isTest }.map(\.name)
            if !nonTestTargets.isEmpty {
                lines.append("  Targets: [\(nonTestTargets.joined(separator: ", "))]")
            }
            lines.append("")
        }

        // 파일 목록 정렬 및 렌더링
        for file in files {
            lines.append("\(file.path):")

            if detailLevel == .full && !file.imports.isEmpty {
                lines.append("  import " + file.imports.joined(separator: ", "))
            }

            for typealiasDef in file.typealiases {
                lines.append("  \(typealiasDef)")
            }

            for type in file.types {
                if !includePrivate && (type.accessLevel == .private || type.accessLevel == .fileprivate) {
                    continue
                }
                renderTypeDeclaration(type, into: &lines, indent: "  ", detailLevel: detailLevel, includePrivate: includePrivate)
            }

            for fn in file.standaloneFunctions {
                if !includePrivate && (fn.accessLevel == .private || fn.accessLevel == .fileprivate) {
                    continue
                }
                lines.append("  \(fn.formattedSignature)")
            }

            for prop in file.standaloneProperties {
                if !includePrivate && (prop.accessLevel == .private || prop.accessLevel == .fileprivate) {
                    continue
                }
                lines.append("  \(prop.formattedSignature)")
            }

            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func renderTypeDeclaration(
        _ type: TypeDeclarationMap,
        into lines: inout [String],
        indent: String,
        detailLevel: RepoMapOptions.DetailLevel,
        includePrivate: Bool
    ) {
        let header = "\(indent)\(type.headerLine)"

        if detailLevel == .outline {
            lines.append(header)
            return
        }

        lines.append("\(header) {")

        // Enum Cases
        if !type.cases.isEmpty {
            for c in type.cases {
                lines.append("\(indent)  case \(c)")
            }
        }

        // Properties
        if detailLevel == .full || detailLevel == .standard {
            for prop in type.properties {
                if !includePrivate && (prop.accessLevel == .private || prop.accessLevel == .fileprivate) {
                    continue
                }
                lines.append("\(indent)  \(prop.formattedSignature)")
            }
        }

        // Functions
        for fn in type.functions {
            if !includePrivate && (fn.accessLevel == .private || fn.accessLevel == .fileprivate) {
                continue
            }
            if detailLevel == .compact && !fn.accessLevel.isPublicOrOpen {
                continue
            }
            lines.append("\(indent)  \(fn.formattedSignature)")
        }

        // Nested Types
        for nested in type.nestedTypes {
            if !includePrivate && (nested.accessLevel == .private || nested.accessLevel == .fileprivate) {
                continue
            }
            renderTypeDeclaration(nested, into: &lines, indent: indent + "  ", detailLevel: detailLevel, includePrivate: includePrivate)
        }

        lines.append("\(indent)}")
    }

    private func pruneToFitTokenBudget(
        appSlug: String,
        packageSummary: PackageSummary?,
        files: [FileRepoMap],
        maxTokens: Int
    ) -> String {
        var lines: [String] = []

        if let pkg = packageSummary {
            lines.append("Package.swift: \(pkg.name)")
            if !pkg.kitDependencies.isEmpty {
                lines.append("  Kit Dependencies: [\(pkg.kitDependencies.joined(separator: ", "))]")
            }
            lines.append("")
        }

        var includedFilesCount = 0
        for file in files {
            var fileChunk: [String] = []
            fileChunk.append("\(file.path):")
            for type in file.types {
                fileChunk.append("  \(type.headerLine)")
            }
            for fn in file.standaloneFunctions where fn.accessLevel.isPublicOrOpen {
                fileChunk.append("  \(fn.formattedSignature)")
            }
            fileChunk.append("")

            let candidate = (lines + fileChunk).joined(separator: "\n")
            if Self.estimateTokenCount(candidate) <= maxTokens {
                lines.append(contentsOf: fileChunk)
                includedFilesCount += 1
            } else {
                let remaining = files.count - includedFilesCount
                if remaining > 0 {
                    lines.append("// ... [\(remaining) additional files omitted to stay within token budget]")
                }
                break
            }
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 4. 고속 Swift AST 파서 (FastSwiftASTParser)

/// Swift 소스 코드를 Tree-sitter AST 수준으로 정밀 파싱하는 내장 고속 토크나이저 및 구문 분석기.
/// 외부 바이너리나 SPM 의존성 없이 주석, 문자열, 중괄호 스택, 접근 제어자, 시그니처를 고속 분석합니다.
final class FastSwiftASTParser {
    private let code: String
    private let options: RepoMapOptions
    private let lines: [String]

    init(code: String, options: RepoMapOptions) {
        self.code = code
        self.options = options
        self.lines = code.components(separatedBy: "\n")
    }

    func parse(relativePath: String) -> FileRepoMap {
        let tokens = tokenize()
        var index = 0

        var imports: [String] = []
        var types: [TypeDeclarationMap] = []
        var standaloneFunctions: [FunctionSignatureMap] = []
        var standaloneProperties: [PropertySignatureMap] = []
        var typealiases: [String] = []

        while index < tokens.count {
            let token = tokens[index]

            // 1. import 문
            if token.text == "import" {
                index += 1
                if index < tokens.count {
                    imports.append(tokens[index].text)
                    index += 1
                }
                continue
            }

            // 2. typealias 문
            if token.text == "typealias" {
                let startLine = token.line
                var defParts: [String] = ["typealias"]
                index += 1
                while index < tokens.count && tokens[index].line == startLine && tokens[index].text != ";" {
                    defParts.append(tokens[index].text)
                    index += 1
                }
                typealiases.append(defParts.joined(separator: " "))
                continue
            }

            // 3. 탑레벨 선언 파싱 (속성, 수정자 수집 후 선언 본체 파싱)
            if let decl = parseDeclarationAt(tokens: tokens, index: &index) {
                switch decl {
                case .type(let t):
                    types.append(t)
                case .function(let f):
                    standaloneFunctions.append(f)
                case .property(let p):
                    standaloneProperties.append(p)
                }
            } else {
                index += 1
            }
        }

        return FileRepoMap(
            path: relativePath,
            imports: imports,
            types: types,
            standaloneFunctions: standaloneFunctions,
            standaloneProperties: standaloneProperties,
            typealiases: typealiases
        )
    }

    // MARK: - 선언 파싱 상태 기계

    private enum ParsedItem {
        case type(TypeDeclarationMap)
        case function(FunctionSignatureMap)
        case property(PropertySignatureMap)
    }

    private func parseDeclarationAt(tokens: [Token], index: inout Int) -> ParsedItem? {
        let startIndex = index
        var attributes: [String] = []
        var accessLevel: AccessLevel = .internal
        var isStatic = false
        var isMutating = false

        while index < tokens.count {
            let t = tokens[index]

            // 속성 (@Observable, @MainActor 등)
            if t.text.hasPrefix("@") {
                attributes.append(t.text)
                index += 1
                continue
            }

            // 접근 제어자
            if let access = AccessLevel(rawValue: t.text) {
                accessLevel = access
                index += 1
                // private(set) 등 괄호 수식 처리
                if index < tokens.count && tokens[index].text == "(" {
                    index += 1
                    while index < tokens.count && tokens[index].text != ")" {
                        index += 1
                    }
                    if index < tokens.count && tokens[index].text == ")" {
                        index += 1
                    }
                }
                continue
            }

            // 수정자
            if t.text == "static" || t.text == "class" && peekNextIsVarOrFunc(tokens: tokens, from: index + 1) {
                isStatic = true
                index += 1
                continue
            }
            if t.text == "mutating" {
                isMutating = true
                index += 1
                continue
            }
            if t.text == "final" || t.text == "override" {
                index += 1
                continue
            }

            // 핵심 타입 선언 키워드 확인
            if let kind = DeclarationKind(rawValue: t.text) {
                return parseTypeBody(
                    kind: kind,
                    attributes: attributes,
                    accessLevel: accessLevel,
                    tokens: tokens,
                    index: &index
                )
            }

            // 함수 / 초기화 메서드 키워드 확인
            if t.text == "func" || t.text == "init" || t.text == "subscript" {
                return parseFunction(
                    attributes: attributes,
                    accessLevel: accessLevel,
                    isStatic: isStatic,
                    isMutating: isMutating,
                    tokens: tokens,
                    index: &index
                )
            }

            // 변수 / 상수 키워드 확인
            if t.text == "var" || t.text == "let" {
                return parseProperty(
                    isConstant: t.text == "let",
                    attributes: attributes,
                    accessLevel: accessLevel,
                    isStatic: isStatic,
                    tokens: tokens,
                    index: &index
                )
            }

            // 일치하는 선언 시작 키워드가 아니면 중단
            break
        }

        // 매칭 실패 시 원래 위치로 복귀하지 않고 index는 외부 루프에서 1 증가
        index = startIndex
        return nil
    }

    private func peekNextIsVarOrFunc(tokens: [Token], from index: Int) -> Bool {
        guard index < tokens.count else { return false }
        let next = tokens[index].text
        return next == "func" || next == "var" || next == "let"
    }

    // MARK: - 타입 본체 파싱

    private func parseTypeBody(
        kind: DeclarationKind,
        attributes: [String],
        accessLevel: AccessLevel,
        tokens: [Token],
        index: inout Int
    ) -> ParsedItem? {
        guard index < tokens.count else { return nil }
        let kindToken = tokens[index]
        let line = kindToken.line
        index += 1 // skip struct/class/etc.

        guard index < tokens.count else { return nil }
        let typeName = tokens[index].text
        index += 1

        var generics: String? = nil
        var conformances: [String] = []

        // 제네릭 수식어 파싱 <T, U: Codable>
        if index < tokens.count && tokens[index].text == "<" {
            let genStart = index
            var angleDepth = 0
            while index < tokens.count {
                if tokens[index].text == "<" { angleDepth += 1 }
                else if tokens[index].text == ">" {
                    angleDepth -= 1
                    if angleDepth == 0 {
                        index += 1
                        break
                    }
                }
                index += 1
            }
            generics = tokens[genStart..<index].map(\.text).joined()
        }

        // 상속 및 프로토콜 채택 파싱 (: Codable, Sendable)
        if index < tokens.count && tokens[index].text == ":" {
            index += 1 // skip ':'
            var currentConf: [String] = []
            while index < tokens.count && tokens[index].text != "{" && tokens[index].text != "where" {
                if tokens[index].text == "," {
                    if !currentConf.isEmpty {
                        conformances.append(currentConf.joined())
                        currentConf.removeAll()
                    }
                } else {
                    currentConf.append(tokens[index].text)
                }
                index += 1
            }
            if !currentConf.isEmpty {
                conformances.append(currentConf.joined())
            }
        }

        // where 절 스킵
        while index < tokens.count && tokens[index].text != "{" {
            index += 1
        }

        // 타입 바디 `{ ... }` 파싱
        guard index < tokens.count && tokens[index].text == "{" else {
            return .type(TypeDeclarationMap(
                kind: kind,
                name: typeName,
                generics: generics,
                conformances: conformances,
                accessLevel: accessLevel,
                attributes: attributes,
                line: line
            ))
        }

        index += 1 // skip '{'

        var cases: [String] = []
        var properties: [PropertySignatureMap] = []
        var functions: [FunctionSignatureMap] = []
        var nestedTypes: [TypeDeclarationMap] = []

        var braceDepth = 1
        while index < tokens.count && braceDepth > 0 {
            let t = tokens[index]

            if t.text == "{" {
                braceDepth += 1
                index += 1
                continue
            }
            if t.text == "}" {
                braceDepth -= 1
                index += 1
                if braceDepth == 0 { break }
                continue
            }

            // Enum Case 파싱
            if kind == .enum && t.text == "case" {
                index += 1
                var caseParts: [String] = []
                let caseLine = t.line
                while index < tokens.count && tokens[index].line == caseLine && tokens[index].text != ";" && tokens[index].text != "{" {
                    caseParts.append(tokens[index].text)
                    index += 1
                }
                if !caseParts.isEmpty {
                    cases.append(caseParts.joined(separator: " "))
                }
                continue
            }

            // 멤버 선언 파싱
            if let decl = parseDeclarationAt(tokens: tokens, index: &index) {
                switch decl {
                case .type(let nested):
                    nestedTypes.append(nested)
                case .function(let fn):
                    functions.append(fn)
                case .property(let prop):
                    properties.append(prop)
                }
            } else {
                index += 1
            }
        }

        return .type(TypeDeclarationMap(
            kind: kind,
            name: typeName,
            generics: generics,
            conformances: conformances,
            accessLevel: accessLevel,
            attributes: attributes,
            cases: cases,
            properties: properties,
            functions: functions,
            nestedTypes: nestedTypes,
            line: line
        ))
    }

    // MARK: - 함수 / 메서드 시그니처 파싱

    private func parseFunction(
        attributes: [String],
        accessLevel: AccessLevel,
        isStatic: Bool,
        isMutating: Bool,
        tokens: [Token],
        index: inout Int
    ) -> ParsedItem? {
        guard index < tokens.count else { return nil }
        let keywordToken = tokens[index]
        let fnKind = keywordToken.text
        let line = keywordToken.line
        index += 1 // skip func/init/subscript

        var fnName = fnKind
        if fnKind == "func" && index < tokens.count {
            fnName = tokens[index].text
            index += 1
        }

        // 매개변수 및 반환 타입 등 시그니처 추출
        var signatureParts: [String] = [fnKind]
        if fnKind == "func" {
            signatureParts.append(fnName)
        }

        var isAsync = false
        var isThrows = false
        var parameters: [String] = []
        var returnType: String? = nil

        var parenDepth = 0
        var hasSeenParen = false
        var currentParam: [String] = []

        while index < tokens.count {
            let t = tokens[index]

            if t.text == "{" {
                // 함수 본체 시작 -> 본체 스킵
                skipBraces(tokens: tokens, index: &index)
                break
            }
            if t.text == ";" || (parenDepth == 0 && hasSeenParen && isEndOfSignature(token: t)) {
                // 프로토콜 요구사항 등 바디가 없는 함수 시그니처 종료
                break
            }

            if t.text == "(" {
                hasSeenParen = true
                parenDepth += 1
                if parenDepth == 1 { currentParam.removeAll() }
            } else if t.text == ")" {
                parenDepth -= 1
                if parenDepth == 0 && !currentParam.isEmpty {
                    parameters.append(currentParam.joined(separator: " "))
                    currentParam.removeAll()
                }
            } else if parenDepth == 1 && t.text == "," {
                if !currentParam.isEmpty {
                    parameters.append(currentParam.joined(separator: " "))
                    currentParam.removeAll()
                }
            } else if parenDepth >= 1 {
                currentParam.append(t.text)
            }

            if t.text == "async" { isAsync = true }
            if t.text == "throws" || t.text == "rethrows" { isThrows = true }

            signatureParts.append(t.text)
            index += 1
        }

        // 화살표 -> 다음 반환 타입 추출
        let sigText = signatureParts.joined(separator: " ")
            .replacingOccurrences(of: " ( ", with: "(")
            .replacingOccurrences(of: " )", with: ")")
            .replacingOccurrences(of: " -> ", with: " -> ")

        if let arrowIndex = sigText.range(of: "->") {
            let ret = sigText[arrowIndex.upperBound...].trimmingCharacters(in: .whitespaces)
            returnType = ret
        }

        return .function(FunctionSignatureMap(
            name: fnName,
            signature: sigText,
            parameters: parameters,
            returnType: returnType,
            accessLevel: accessLevel,
            isStatic: isStatic,
            isAsync: isAsync,
            isThrows: isThrows,
            isMutating: isMutating,
            attributes: attributes,
            line: line
        ))
    }

    private func isEndOfSignature(token: Token) -> Bool {
        let text = token.text
        return text == "func" || text == "var" || text == "let" || text == "init" ||
               text == "struct" || text == "class" || text == "enum" || text == "protocol" ||
               text == "}" || text == "public" || text == "private" || text == "internal" ||
               text == "static" || text == "mutating"
    }

    // MARK: - 프로퍼티 시그니처 파싱

    private func parseProperty(
        isConstant: Bool,
        attributes: [String],
        accessLevel: AccessLevel,
        isStatic: Bool,
        tokens: [Token],
        index: inout Int
    ) -> ParsedItem? {
        guard index < tokens.count else { return nil }
        let propKeyword = tokens[index]
        let line = propKeyword.line
        index += 1 // skip var/let

        guard index < tokens.count else { return nil }
        let propName = tokens[index].text
        index += 1

        var type: String? = nil

        // 타입 어노테이션 : Type 파싱
        if index < tokens.count && tokens[index].text == ":" {
            index += 1 // skip ':'
            var typeParts: [String] = []
            while index < tokens.count && tokens[index].text != "=" && tokens[index].text != "{" && tokens[index].text != ";" && tokens[index].line == line {
                typeParts.append(tokens[index].text)
                index += 1
            }
            if !typeParts.isEmpty {
                type = typeParts.joined(separator: " ")
            }
        }

        // 초기화 값 = ... 또는 연산 프로퍼티 { ... } 스킵
        while index < tokens.count {
            let t = tokens[index]
            if t.text == "{" {
                skipBraces(tokens: tokens, index: &index)
                break
            }
            if t.line > line || t.text == ";" {
                break
            }
            index += 1
        }

        return .property(PropertySignatureMap(
            name: propName,
            type: type,
            accessLevel: accessLevel,
            isStatic: isStatic,
            isConstant: isConstant,
            attributes: attributes,
            line: line
        ))
    }

    private func skipBraces(tokens: [Token], index: inout Int) {
        guard index < tokens.count && tokens[index].text == "{" else { return }
        var depth = 0
        while index < tokens.count {
            if tokens[index].text == "{" {
                depth += 1
            } else if tokens[index].text == "}" {
                depth -= 1
                if depth == 0 {
                    index += 1
                    break
                }
            }
            index += 1
        }
    }

    // MARK: - 고속 토크나이저

    struct Token {
        let text: String
        let line: Int
    }

    private func tokenize() -> [Token] {
        var tokens: [Token] = []
        let scalarArray = Array(code.unicodeScalars)
        var i = 0
        var line = 1

        while i < scalarArray.count {
            let c = scalarArray[i]

            // 줄바꿈 카운팅
            if c == "\n" {
                line += 1
                i += 1
                continue
            }

            // 공백 스킵
            if CharacterSet.whitespaces.contains(c) {
                i += 1
                continue
            }

            // 단일행 주석 스킵 // ...
            if c == "/" && i + 1 < scalarArray.count && scalarArray[i + 1] == "/" {
                i += 2
                while i < scalarArray.count && scalarArray[i] != "\n" {
                    i += 1
                }
                continue
            }

            // 중첩 다중행 주석 스킵 /* ... */
            if c == "/" && i + 1 < scalarArray.count && scalarArray[i + 1] == "*" {
                i += 2
                var commentDepth = 1
                while i < scalarArray.count && commentDepth > 0 {
                    if scalarArray[i] == "\n" {
                        line += 1
                    } else if scalarArray[i] == "/" && i + 1 < scalarArray.count && scalarArray[i + 1] == "*" {
                        commentDepth += 1
                        i += 1
                    } else if scalarArray[i] == "*" && i + 1 < scalarArray.count && scalarArray[i + 1] == "/" {
                        commentDepth -= 1
                        i += 1
                    }
                    i += 1
                }
                continue
            }

            // 문자열 리터럴 스킵 "..."
            if c == "\"" {
                // 멀티라인 문자열 """
                if i + 2 < scalarArray.count && scalarArray[i + 1] == "\"" && scalarArray[i + 2] == "\"" {
                    i += 3
                    while i + 2 < scalarArray.count {
                        if scalarArray[i] == "\n" { line += 1 }
                        if scalarArray[i] == "\"" && scalarArray[i + 1] == "\"" && scalarArray[i + 2] == "\"" {
                            i += 3
                            break
                        }
                        i += 1
                    }
                } else {
                    // 단일행 문자열
                    i += 1
                    var escaped = false
                    while i < scalarArray.count {
                        let sc = scalarArray[i]
                        if sc == "\n" { break }
                        if escaped {
                            escaped = false
                        } else if sc == "\\" {
                            escaped = true
                        } else if sc == "\"" {
                            i += 1
                            break
                        }
                        i += 1
                    }
                }
                continue
            }

            // 속성 식별자 @Identifier
            if c == "@" {
                var attrStr = "@"
                i += 1
                while i < scalarArray.count && (isIdentifierPart(scalarArray[i])) {
                    attrStr.unicodeScalars.append(scalarArray[i])
                    i += 1
                }
                tokens.append(Token(text: attrStr, line: line))
                continue
            }

            // 화살표 ->
            if c == "-" && i + 1 < scalarArray.count && scalarArray[i + 1] == ">" {
                tokens.append(Token(text: "->", line: line))
                i += 2
                continue
            }

            // 구두점 및 기호
            let singleSymbols: Set<UnicodeScalar> = ["{", "}", "(", ")", "[", "]", ":", ";", ",", "<", ">", "=", "?"]
            if singleSymbols.contains(c) {
                tokens.append(Token(text: String(c), line: line))
                i += 1
                continue
            }

            // 식별자 및 키워드
            if isIdentifierStart(c) {
                var word = ""
                while i < scalarArray.count && isIdentifierPart(scalarArray[i]) {
                    word.unicodeScalars.append(scalarArray[i])
                    i += 1
                }
                tokens.append(Token(text: word, line: line))
                continue
            }

            i += 1
        }

        return tokens
    }

    private func isIdentifierStart(_ c: UnicodeScalar) -> Bool {
        return c == "_" || CharacterSet.letters.contains(c)
    }

    private func isIdentifierPart(_ c: UnicodeScalar) -> Bool {
        return c == "_" || CharacterSet.alphanumerics.contains(c)
    }
}
