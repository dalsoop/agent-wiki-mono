import Foundation

/// CLI 엔트리포인트(`main.swift`)를 안전하게 패치하여
/// `runWithUniversalError` 및 필수 수명주기 가드(`SingleInstanceCLI`, `StateMirror.onTerminate`)를 주입하는 도구.
public enum UniversalCLIPatcher {

    /// CLI 패치 결과
    public struct Result: Sendable, Equatable {
        public let originalSource: String
        public let patchedSource: String
        public let isModified: Bool
        public let injectedRunWithUniversalError: Bool
        public let injectedSingleInstanceGuard: Bool
        public let injectedTerminationHook: Bool
        public let addedImports: [String]

        public init(
            originalSource: String,
            patchedSource: String,
            isModified: Bool,
            injectedRunWithUniversalError: Bool,
            injectedSingleInstanceGuard: Bool,
            injectedTerminationHook: Bool,
            addedImports: [String]
        ) {
            self.originalSource = originalSource
            self.patchedSource = patchedSource
            self.isModified = isModified
            self.injectedRunWithUniversalError = injectedRunWithUniversalError
            self.injectedSingleInstanceGuard = injectedSingleInstanceGuard
            self.injectedTerminationHook = injectedTerminationHook
            self.addedImports = addedImports
        }
    }

    /// CLI 소스 코드를 패치합니다.
    public static func patch(
        source: String,
        appName: String? = nil,
        options: UniversalErrorPatcher.Options = .init()
    ) -> Result {
        let resolvedApp = resolveAppName(source: source, explicitApp: appName, options: options)
        let stripped = SourceTransformerHelper.stripCommentsAndStrings(source)

        let hasErrorWrapper = SourceTransformerHelper.hasRunWithUniversalErrorCall(in: source)
        let hasSingleGuard = SourceTransformerHelper.hasSingleInstanceGuard(in: stripped)
        let hasTermHook = SourceTransformerHelper.hasTerminationHook(in: stripped)

        guard !(hasErrorWrapper && hasSingleGuard && hasTermHook) else {
            return unModifiedResult(source: source)
        }

        let neededImports = computeNeededImports(
            hasErrorWrapper: hasErrorWrapper,
            hasSingleGuard: hasSingleGuard,
            hasTermHook: hasTermHook,
            options: options
        )

        let (workingSource, addedImports) = prepareImports(source: source, neededImports: neededImports)

        guard !hasErrorWrapper else {
            return patchExistingWrapper(
                source: source,
                workingSource: workingSource,
                resolvedApp: resolvedApp,
                hasSingleGuard: hasSingleGuard,
                hasTermHook: hasTermHook,
                addedImports: addedImports,
                options: options
            )
        }

        return wrapNewBlock(
            source: source,
            workingSource: workingSource,
            resolvedApp: resolvedApp,
            hasSingleGuard: hasSingleGuard,
            hasTermHook: hasTermHook,
            addedImports: addedImports,
            options: options
        )
    }

    private static func prepareImports(source: String, neededImports: [String]) -> (String, [String]) {
        guard !neededImports.isEmpty else { return (source, []) }
        return SourceTransformerHelper.injectImports(neededImports, into: source)
    }

    // MARK: - 정적 검사 및 앱 이름 유추 위임

    public static func hasSingleInstanceGuard(in code: String) -> Bool {
        SourceTransformerHelper.hasSingleInstanceGuard(in: code)
    }

    public static func hasTerminationHook(in code: String) -> Bool {
        SourceTransformerHelper.hasTerminationHook(in: code)
    }

    public static func hasImport(_ moduleName: String, in code: String) -> Bool {
        SourceTransformerHelper.hasImport(moduleName, in: code)
    }

    public static func inferAppName(from source: String) -> String? {
        SourceTransformerHelper.extractAppName(from: source)
    }

    public static func inferAppName(fromPath path: String) -> String? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.split(separator: "/")

        if let idx = parts.firstIndex(of: "apps"), idx + 1 < parts.count {
            return String(parts[idx + 1])
        }
        guard let cliDir = parts.first(where: { $0.hasSuffix("CLI") }) else {
            return nil
        }
        let base = cliDir.dropLast(3)
        return kebabCase(from: String(base))
    }

    public static func kebabCase(from string: String) -> String {
        var result = ""
        for (i, char) in string.enumerated() {
            let needsHyphen = char.isUppercase && i > 0
            if needsHyphen { result.append("-") }
            result.append(char.lowercased())
        }
        return result
    }

    // MARK: - 내부 처리 분기

    private static func resolveAppName(
        source: String,
        explicitApp: String?,
        options: UniversalErrorPatcher.Options
    ) -> String {
        explicitApp ?? options.appName ?? inferAppName(from: source) ?? "app"
    }

    private static func unModifiedResult(source: String) -> Result {
        Result(
            originalSource: source,
            patchedSource: source,
            isModified: false,
            injectedRunWithUniversalError: false,
            injectedSingleInstanceGuard: false,
            injectedTerminationHook: false,
            addedImports: []
        )
    }

    private static func computeNeededImports(
        hasErrorWrapper: Bool,
        hasSingleGuard: Bool,
        hasTermHook: Bool,
        options: UniversalErrorPatcher.Options
    ) -> [String] {
        var modules: [String] = []
        appendWrapperImportsIfNeeded(hasErrorWrapper: hasErrorWrapper, options: options, modules: &modules)
        appendLifecycleImportsIfNeeded(
            hasErrorWrapper: hasErrorWrapper,
            hasSingleGuard: hasSingleGuard,
            hasTermHook: hasTermHook,
            options: options,
            modules: &modules
        )
        return modules
    }

    private static func appendWrapperImportsIfNeeded(
        hasErrorWrapper: Bool,
        options: UniversalErrorPatcher.Options,
        modules: inout [String]
    ) {
        guard !hasErrorWrapper && options.wrapWithUniversalError else { return }
        modules.append("AgentCLIKit")
        modules.append("AppErrorKit")
    }

    private static func appendLifecycleImportsIfNeeded(
        hasErrorWrapper: Bool,
        hasSingleGuard: Bool,
        hasTermHook: Bool,
        options: UniversalErrorPatcher.Options,
        modules: inout [String]
    ) {
        let singleMissing = !hasSingleGuard && options.injectLifecycleGuards
        if singleMissing || !hasErrorWrapper {
            modules.append("SingleInstanceKit")
        }
        let termMissing = !hasTermHook && options.injectLifecycleGuards
        if termMissing || !hasErrorWrapper {
            modules.append("StateMirrorKit")
        }
    }

    private static func patchExistingWrapper(
        source: String,
        workingSource: String,
        resolvedApp: String,
        hasSingleGuard: Bool,
        hasTermHook: Bool,
        addedImports: [String],
        options: UniversalErrorPatcher.Options
    ) -> Result {
        let guards = buildGuards(
            resolvedApp: resolvedApp,
            injectSingle: !hasSingleGuard && options.injectLifecycleGuards,
            injectTerm: !hasTermHook && options.injectLifecycleGuards,
            options: options
        )

        let patched = SourceTransformerHelper.injectGuardsIntoBlock(source: workingSource, guards: guards)
        return Result(
            originalSource: source,
            patchedSource: patched,
            isModified: patched != source,
            injectedRunWithUniversalError: false,
            injectedSingleInstanceGuard: !hasSingleGuard && options.injectLifecycleGuards,
            injectedTerminationHook: !hasTermHook && options.injectLifecycleGuards,
            addedImports: addedImports
        )
    }

    private static func wrapNewBlock(
        source: String,
        workingSource: String,
        resolvedApp: String,
        hasSingleGuard: Bool,
        hasTermHook: Bool,
        addedImports: [String],
        options: UniversalErrorPatcher.Options
    ) -> Result {
        guard options.wrapWithUniversalError else {
            return Result(
                originalSource: source,
                patchedSource: workingSource,
                isModified: workingSource != source,
                injectedRunWithUniversalError: false,
                injectedSingleInstanceGuard: false,
                injectedTerminationHook: false,
                addedImports: addedImports
            )
        }

        let injectSingle = !hasSingleGuard && options.injectLifecycleGuards
        let injectTerm = !hasTermHook && options.injectLifecycleGuards
        let guards = buildGuards(
            resolvedApp: resolvedApp,
            injectSingle: injectSingle,
            injectTerm: injectTerm,
            options: options
        )

        guard let patched = CLISourcePartitioner.wrapBody(workingSource, guards: guards) else {
            return unModifiedResult(source: source)
        }
        return Result(
            originalSource: source,
            patchedSource: patched,
            isModified: patched != source,
            injectedRunWithUniversalError: true,
            injectedSingleInstanceGuard: injectSingle,
            injectedTerminationHook: injectTerm,
            addedImports: addedImports
        )
    }

    private static func buildGuards(
        resolvedApp: String,
        injectSingle: Bool,
        injectTerm: Bool,
        options: UniversalErrorPatcher.Options
    ) -> [String] {
        var guards: [String] = []
        if injectSingle {
            guards.append("    SingleInstanceCLI.exitIfAlreadyRunning(name: \"\(resolvedApp)\", scope: \(options.singleInstanceScope))")
        }
        if injectTerm {
            guards.append("    StateMirror.onTerminate(app: \"\(resolvedApp)\", \(options.terminationPolicy))")
        }
        return guards
    }
}
