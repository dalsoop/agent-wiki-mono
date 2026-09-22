import Foundation

/// 함대 일괄 에러 핸들링 및 수명주기 패치 엔진.
///
/// 주요 기능:
/// 1. CLI 엔트리포인트(main.swift):
///    runWithUniversalError 래핑과 함께 누락된 2대 수명주기 가드
///    (SingleInstanceCLI.exitIfAlreadyRunning, StateMirror.onTerminate)를 세트로 주입.
/// 2. View 소스코드:
///    AppErrorKit 임포트·바인딩 주입. 표면 패리티 억제 주석은 기본 삽입하지 않으며,
///    `suppressSurfaceParity`가 true이고 유효 UUID backlog 주석이 있을 때만 넣는다.
/// 3. 단일 파일 및 앱 디렉터리 단위 일괄 검사/패치 지원.
public struct UniversalErrorPatcher: Sendable {

    /// 패처 I/O 실패. 쓰기 실패는 침묵하지 않고 이 오류로 throw 한다.
    public enum PatchError: Error, Equatable, LocalizedError {
        case writeFailed(path: String, message: String)

        public var errorDescription: String? {
            switch self {
            case .writeFailed(let path, let message):
                return "Failed to write \(path): \(message)"
            }
        }
    }

    /// 패처 동작 옵션
    public struct Options: Sendable {
        public var appName: String?
        public var suppressSurfaceParity: Bool
        public var paritySuppressionComment: String
        public var singleInstanceScope: String
        public var terminationPolicy: String
        public var wrapWithUniversalError: Bool
        public var injectLifecycleGuards: Bool
        public var ensureAppErrorKitImport: Bool
        public var viewErrorBinding: String?

        public init(
            appName: String? = nil,
            suppressSurfaceParity: Bool = false,
            paritySuppressionComment: String = "",
            singleInstanceScope: String = ".worktree",
            terminationPolicy: String = ".clear",
            wrapWithUniversalError: Bool = true,
            injectLifecycleGuards: Bool = true,
            ensureAppErrorKitImport: Bool = true,
            viewErrorBinding: String? = nil
        ) {
            self.appName = appName
            self.suppressSurfaceParity = suppressSurfaceParity
            self.paritySuppressionComment = paritySuppressionComment
            self.singleInstanceScope = singleInstanceScope
            self.terminationPolicy = terminationPolicy
            self.wrapWithUniversalError = wrapWithUniversalError
            self.injectLifecycleGuards = injectLifecycleGuards
            self.ensureAppErrorKitImport = ensureAppErrorKitImport
            self.viewErrorBinding = viewErrorBinding
        }
    }

    /// 파일 단위 패치 결과
    public enum FilePatchResult: Sendable, Equatable {
        case cli(UniversalCLIPatcher.Result)
        case view(UniversalViewPatcher.Result)
        case skipped(reason: String)
        case failed(reason: String)

        public var isModified: Bool {
            switch self {
            case .cli(let res): return res.isModified
            case .view(let res): return res.isModified
            case .skipped, .failed: return false
            }
        }
    }

    /// 앱 단위 패치 종합 결과
    public struct AppPatchResult: Sendable {
        public let appDirectory: String
        public let cliResults: [String: UniversalCLIPatcher.Result]
        public let viewResults: [String: UniversalViewPatcher.Result]
        public let skipped: [String: String]
        public let failed: [String: String]

        public var isModified: Bool {
            cliResults.values.contains { $0.isModified } || viewResults.values.contains { $0.isModified }
        }

        public init(
            appDirectory: String,
            cliResults: [String: UniversalCLIPatcher.Result],
            viewResults: [String: UniversalViewPatcher.Result],
            skipped: [String: String] = [:],
            failed: [String: String] = [:]
        ) {
            self.appDirectory = appDirectory
            self.cliResults = cliResults
            self.viewResults = viewResults
            self.skipped = skipped
            self.failed = failed
        }
    }

    /// 앱 현황 정적 검사 리포트
    public struct AppInspection: Sendable {
        public let appDirectory: String
        public let cliMainFiles: [String]
        public let screenViewFiles: [String]
        public let cliRequiresUniversalError: Bool
        public let cliRequiresSingleInstance: Bool
        public let cliRequiresTermination: Bool
        public let viewsRequireParitySuppression: Bool
    }

    public let options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    // MARK: - 소스 코드 직접 패치 API

    public static func patchCLISource(
        _ source: String,
        appName: String? = nil,
        options: Options = Options()
    ) -> UniversalCLIPatcher.Result {
        UniversalCLIPatcher.patch(source: source, appName: appName, options: options)
    }

    public static func patchViewSource(
        _ source: String,
        options: Options = Options()
    ) -> UniversalViewPatcher.Result {
        UniversalViewPatcher.patch(source: source, options: options)
    }

    // MARK: - 파일 기반 패치 API

    public static func patchFile(
        atPath path: String,
        saveToFile: Bool = true,
        options: Options = Options()
    ) throws -> FilePatchResult {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let filename = (path as NSString).lastPathComponent

        if filename == "main.swift" {
            let res = try patchCLIFile(atPath: path, appName: options.appName, saveToFile: saveToFile, options: options)
            return .cli(res)
        }

        guard UniversalViewPatcher.isScreenView(fileName: filename, content: content, relativePath: path) else {
            return .skipped(reason: "Not a CLI main.swift or Screen View file")
        }

        let res = try patchViewFile(atPath: path, saveToFile: saveToFile, options: options)
        return .view(res)
    }

    public static func patchCLIFile(
        atPath path: String,
        appName: String? = nil,
        saveToFile: Bool = true,
        options: Options = Options()
    ) throws -> UniversalCLIPatcher.Result {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let resolvedApp = appName ?? options.appName ?? UniversalCLIPatcher.inferAppName(fromPath: path)
        let result = UniversalCLIPatcher.patch(source: content, appName: resolvedApp, options: options)
        if saveToFile && result.isModified {
            try result.patchedSource.write(toFile: path, atomically: true, encoding: .utf8)
        }
        return result
    }

    public static func patchViewFile(
        atPath path: String,
        saveToFile: Bool = true,
        options: Options = Options()
    ) throws -> UniversalViewPatcher.Result {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let result = UniversalViewPatcher.patch(source: content, options: options)
        if saveToFile && result.isModified {
            try result.patchedSource.write(toFile: path, atomically: true, encoding: .utf8)
        }
        return result
    }

    // MARK: - 앱 디렉터리 일괄 패치 API

    public static func patchApp(
        at appDirectory: String,
        saveToFile: Bool = true,
        options: Options = Options()
    ) throws -> AppPatchResult {
        let fm = FileManager.default
        let sourcesDir = (appDirectory as NSString).appendingPathComponent("Sources")
        guard let enumerator = fm.enumerator(atPath: sourcesDir) else {
            return AppPatchResult(appDirectory: appDirectory, cliResults: [:], viewResults: [:])
        }

        var cliResults: [String: UniversalCLIPatcher.Result] = [:]
        var viewResults: [String: UniversalViewPatcher.Result] = [:]
        let skipped: [String: String] = [:]
        var failed: [String: String] = [:]

        while let relPath = enumerator.nextObject() as? String {
            guard shouldProcessPath(relPath, enumerator: enumerator) else { continue }
            let fullPath = (sourcesDir as NSString).appendingPathComponent(relPath)
            try patchSingleEntry(
                fullPath: fullPath,
                relPath: relPath,
                saveToFile: saveToFile,
                options: options,
                cliResults: &cliResults,
                viewResults: &viewResults,
                failed: &failed
            )
        }

        return AppPatchResult(
            appDirectory: appDirectory,
            cliResults: cliResults,
            viewResults: viewResults,
            skipped: skipped,
            failed: failed
        )
    }

    private static func patchSingleEntry(
        fullPath: String,
        relPath: String,
        saveToFile: Bool,
        options: Options,
        cliResults: inout [String: UniversalCLIPatcher.Result],
        viewResults: inout [String: UniversalViewPatcher.Result],
        failed: inout [String: String]
    ) throws {
        let content: String
        do {
            content = try String(contentsOfFile: fullPath, encoding: .utf8)
        } catch {
            failed[relPath] = error.localizedDescription
            return
        }
        let fileName = (relPath as NSString).lastPathComponent

        if fileName == "main.swift" {
            try patchMainFile(fullPath: fullPath, relPath: relPath, content: content, save: saveToFile, options: options, results: &cliResults)
            return
        }

        try patchViewFileIfMatched(
            fullPath: fullPath,
            relPath: relPath,
            fileName: fileName,
            content: content,
            save: saveToFile,
            options: options,
            results: &viewResults
        )
    }

    private static func patchMainFile(
        fullPath: String,
        relPath: String,
        content: String,
        save: Bool,
        options: Options,
        results: inout [String: UniversalCLIPatcher.Result]
    ) throws {
        let res = UniversalCLIPatcher.patch(
            source: content,
            appName: options.appName ?? UniversalCLIPatcher.inferAppName(fromPath: fullPath),
            options: options
        )
        results[relPath] = res
        if save && res.isModified {
            try writePatchedFile(res.patchedSource, to: fullPath)
        }
    }

    private static func patchViewFileIfMatched(
        fullPath: String,
        relPath: String,
        fileName: String,
        content: String,
        save: Bool,
        options: Options,
        results: inout [String: UniversalViewPatcher.Result]
    ) throws {
        guard UniversalViewPatcher.isScreenView(fileName: fileName, content: content, relativePath: relPath) else {
            return
        }
        let res = UniversalViewPatcher.patch(source: content, options: options)
        results[relPath] = res
        if save && res.isModified {
            try writePatchedFile(res.patchedSource, to: fullPath)
        }
    }

    private static func writePatchedFile(_ text: String, to path: String) throws {
        do {
            try text.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            throw PatchError.writeFailed(path: path, message: error.localizedDescription)
        }
    }
}

extension UniversalErrorPatcher {
    public static func inspectApp(at appDirectory: String) -> AppInspection {
        let fm = FileManager.default
        let sourcesDir = (appDirectory as NSString).appendingPathComponent("Sources")
        guard let enumerator = fm.enumerator(atPath: sourcesDir) else {
            return AppInspection(
                appDirectory: appDirectory,
                cliMainFiles: [],
                screenViewFiles: [],
                cliRequiresUniversalError: false,
                cliRequiresSingleInstance: false,
                cliRequiresTermination: false,
                viewsRequireParitySuppression: false
            )
        }

        var cliMainFiles: [String] = []
        var screenViewFiles: [String] = []
        var needsUniversalError = false
        var needsSingleInstance = false
        var needsTermination = false
        var needsParitySuppression = false

        while let relPath = enumerator.nextObject() as? String {
            guard shouldProcessPath(relPath, enumerator: enumerator) else { continue }
            let fullPath = (sourcesDir as NSString).appendingPathComponent(relPath)
            inspectSingleEntry(
                fullPath: fullPath,
                relPath: relPath,
                cliMainFiles: &cliMainFiles,
                screenViewFiles: &screenViewFiles,
                needsUniversalError: &needsUniversalError,
                needsSingleInstance: &needsSingleInstance,
                needsTermination: &needsTermination,
                needsParitySuppression: &needsParitySuppression
            )
        }

        return AppInspection(
            appDirectory: appDirectory,
            cliMainFiles: cliMainFiles,
            screenViewFiles: screenViewFiles,
            cliRequiresUniversalError: needsUniversalError,
            cliRequiresSingleInstance: needsSingleInstance,
            cliRequiresTermination: needsTermination,
            viewsRequireParitySuppression: needsParitySuppression
        )
    }

    private static func inspectSingleEntry(
        fullPath: String,
        relPath: String,
        cliMainFiles: inout [String],
        screenViewFiles: inout [String],
        needsUniversalError: inout Bool,
        needsSingleInstance: inout Bool,
        needsTermination: inout Bool,
        needsParitySuppression: inout Bool
    ) {
        guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { return }
        let fileName = (relPath as NSString).lastPathComponent

        if fileName == "main.swift" {
            inspectMainEntry(
                content: content,
                relPath: relPath,
                cliMainFiles: &cliMainFiles,
                needsUniversalError: &needsUniversalError,
                needsSingleInstance: &needsSingleInstance,
                needsTermination: &needsTermination
            )
            return
        }

        inspectViewEntry(
            content: content,
            fileName: fileName,
            relPath: relPath,
            screenViewFiles: &screenViewFiles,
            needsParitySuppression: &needsParitySuppression
        )
    }

    private static func inspectMainEntry(
        content: String,
        relPath: String,
        cliMainFiles: inout [String],
        needsUniversalError: inout Bool,
        needsSingleInstance: inout Bool,
        needsTermination: inout Bool
    ) {
        cliMainFiles.append(relPath)
        let hasUniversal = content.contains("runWithUniversalError")
        needsUniversalError = needsUniversalError || !hasUniversal
        let hasSingle = UniversalCLIPatcher.hasSingleInstanceGuard(in: content)
        needsSingleInstance = needsSingleInstance || !hasSingle
        let hasTerm = UniversalCLIPatcher.hasTerminationHook(in: content)
        needsTermination = needsTermination || !hasTerm
    }

    private static func inspectViewEntry(
        content: String,
        fileName: String,
        relPath: String,
        screenViewFiles: inout [String],
        needsParitySuppression: inout Bool
    ) {
        guard UniversalViewPatcher.isScreenView(fileName: fileName, content: content, relativePath: relPath) else {
            return
        }
        screenViewFiles.append(relPath)
        let hasSuppression = UniversalViewPatcher.hasParitySuppression(in: content)
        needsParitySuppression = needsParitySuppression || !hasSuppression
    }

    private static let hiddenArtifactMarkers = [".build", ".git", "DerivedData"]

    private static func shouldProcessPath(_ relPath: String, enumerator: FileManager.DirectoryEnumerator) -> Bool {
        if hiddenArtifactMarkers.contains(where: relPath.contains) {
            enumerator.skipDescendants()
            return false
        }
        guard relPath.hasSuffix(".swift") && !relPath.contains("/Tests/") else {
            return false
        }
        return true
    }
}
