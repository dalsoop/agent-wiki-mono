import XCTest
@testable import AppErrorKit

final class UniversalErrorPatcherTests: XCTestCase {

    // MARK: - CLI Patching Tests

    func testLegacyCLIPatchingWrapsUniversalErrorAndInjectsBothLifecycleGuards() {
        let legacySource = """
        import Foundation
        import InteropKit

        let args = Array(CommandLine.arguments.dropFirst())
        let cmd = args.first ?? "help"
        print("Running \\(cmd)")
        """

        let result = UniversalErrorPatcher.patchCLISource(
            legacySource,
            appName: "demo-cli",
            options: .init(appName: "demo-cli")
        )

        XCTAssertTrue(result.isModified)
        XCTAssertTrue(result.injectedRunWithUniversalError)
        XCTAssertTrue(result.injectedSingleInstanceGuard)
        XCTAssertTrue(result.injectedTerminationHook)

        let patched = result.patchedSource

        // 필수 임포트 확인
        XCTAssertTrue(patched.contains("import AgentCLIKit"))
        XCTAssertTrue(patched.contains("import AppErrorKit"))
        XCTAssertTrue(patched.contains("import SingleInstanceKit"))
        XCTAssertTrue(patched.contains("import StateMirrorKit"))

        // runWithUniversalError 래핑 확인
        XCTAssertTrue(patched.contains("runWithUniversalError {"))

        // 2대 필수 수명주기 가드 주입 확인
        XCTAssertTrue(patched.contains("SingleInstanceCLI.exitIfAlreadyRunning(name: \"demo-cli\", scope: .worktree)"))
        XCTAssertTrue(patched.contains("StateMirror.onTerminate(app: \"demo-cli\", .clear)"))

        // 기존 비즈니스 로직 보존 확인
        XCTAssertTrue(patched.contains("let args = Array(CommandLine.arguments.dropFirst())"))
        XCTAssertTrue(patched.contains("print(\"Running \\(cmd)\")"))

        // 린트 규칙 기준 준수 여부 정적 검증
        XCTAssertTrue(UniversalCLIPatcher.hasSingleInstanceGuard(in: patched))
        XCTAssertTrue(UniversalCLIPatcher.hasTerminationHook(in: patched))
        XCTAssertTrue(UniversalCLIPatcher.hasImport("SingleInstanceKit", in: patched))
    }

    func testCLIPatchingPreservesGujoManagedAtTopLevel() {
        let legacySource = """
        import Foundation
        import InteropKit

        // Cloud Apps 게이트
        GujoManaged.exitIfNotEntitledSync()

        let args = Array(CommandLine.arguments.dropFirst())
        print("Hello")
        """

        let result = UniversalErrorPatcher.patchCLISource(
            legacySource,
            appName: "guarded-app"
        )

        let patched = result.patchedSource

        // GujoManaged 가 runWithUniversalError 앞에 위치해야 함
        guard let gujoRange = patched.range(of: "GujoManaged.exitIfNotEntitledSync()"),
              let runErrorRange = patched.range(of: "runWithUniversalError {") else {
            XCTFail("Missing GujoManaged or runWithUniversalError")
            return
        }

        XCTAssertTrue(gujoRange.upperBound < runErrorRange.lowerBound, "GujoManaged must execute before runWithUniversalError")
        XCTAssertTrue(patched.contains("SingleInstanceCLI.exitIfAlreadyRunning(name: \"guarded-app\", scope: .worktree)"))
        XCTAssertTrue(patched.contains("StateMirror.onTerminate(app: \"guarded-app\", .clear)"))
    }

    func testCLIPatchingWhenAlreadyWrappedInRunWithUniversalErrorInjectsMissingGuards() {
        let sourceWithOnlyUniversalError = """
        import Foundation
        import AgentCLIKit
        import AppErrorKit

        runWithUniversalError {
            let args = Array(CommandLine.arguments.dropFirst())
            print("Args: \\(args)")
        }
        """

        let result = UniversalErrorPatcher.patchCLISource(
            sourceWithOnlyUniversalError,
            appName: "already-wrapped-app"
        )

        XCTAssertTrue(result.isModified)
        XCTAssertFalse(result.injectedRunWithUniversalError, "Should not re-wrap runWithUniversalError")
        XCTAssertTrue(result.injectedSingleInstanceGuard)
        XCTAssertTrue(result.injectedTerminationHook)

        let patched = result.patchedSource
        XCTAssertTrue(patched.contains("import SingleInstanceKit"))
        XCTAssertTrue(patched.contains("import StateMirrorKit"))
        XCTAssertTrue(patched.contains("SingleInstanceCLI.exitIfAlreadyRunning(name: \"already-wrapped-app\", scope: .worktree)"))
        XCTAssertTrue(patched.contains("StateMirror.onTerminate(app: \"already-wrapped-app\", .clear)"))
    }

    func testCLIPatchingWhenSingleInstancePresentOnlyInjectsMissingTerminationHook() {
        let sourceWithSingleInstanceOnly = """
        import Foundation
        import AgentCLIKit
        import AppErrorKit
        import SingleInstanceKit

        runWithUniversalError {
            SingleInstanceCLI.exitIfAlreadyRunning(name: "custom-app", scope: .worktree)
            let args = Array(CommandLine.arguments.dropFirst())
            print("Running")
        }
        """

        let result = UniversalErrorPatcher.patchCLISource(
            sourceWithSingleInstanceOnly,
            appName: "custom-app"
        )

        XCTAssertTrue(result.isModified)
        XCTAssertFalse(result.injectedSingleInstanceGuard, "Should not duplicate SingleInstance guard")
        XCTAssertTrue(result.injectedTerminationHook, "Should inject missing StateMirror.onTerminate")

        let patched = result.patchedSource
        XCTAssertTrue(patched.contains("StateMirror.onTerminate(app: \"custom-app\", .clear)"))
        // SingleInstanceCLI 가 중복 호출되지 않았는지 검사 (정확히 1번만 등장)
        let occurrences = patched.components(separatedBy: "SingleInstanceCLI.exitIfAlreadyRunning").count - 1
        XCTAssertEqual(occurrences, 1)
    }

    func testCLIPatchingKeepsFileScopeDeclarationsOutsideWrapper() {
        let source = """
        #if canImport(Foundation)
        import Foundation
        #endif
        import InteropKit

        @main
        struct DemoCLI {
            static func main() {
                print("entry")
            }
        }

        extension String {
            var demoFlag: String { self }
        }

        let args = Array(CommandLine.arguments.dropFirst())
        print("Running")
        """

        let result = UniversalErrorPatcher.patchCLISource(source, appName: "demo-cli")
        let patched = result.patchedSource

        XCTAssertTrue(result.injectedRunWithUniversalError)
        XCTAssertTrue(patched.contains("#if canImport(Foundation)"))
        XCTAssertTrue(patched.contains("import Foundation"))
        guard let ifRange = patched.range(of: "#if canImport(Foundation)"),
              let runRange = patched.range(of: "runWithUniversalError {"),
              let mainRange = patched.range(of: "@main"),
              let extRange = patched.range(of: "extension String") else {
            XCTFail("Missing file-scope markers")
            return
        }
        XCTAssertTrue(ifRange.lowerBound < runRange.lowerBound)
        XCTAssertTrue(mainRange.lowerBound < runRange.lowerBound)
        XCTAssertTrue(extRange.lowerBound < runRange.lowerBound)

        let wrapper = String(patched[runRange.lowerBound...])
        XCTAssertFalse(wrapper.contains("@main"))
        XCTAssertFalse(wrapper.contains("extension String"))
        XCTAssertFalse(wrapper.contains("import Foundation"))
        XCTAssertTrue(wrapper.contains("let args = Array(CommandLine.arguments.dropFirst())"))
    }

    func testCLIPatchingNoOpWhenOnlyMainTypeExists() {
        let source = """
        import Foundation

        @main
        struct DemoCLI {
            static func main() {
                print("entry")
            }
        }
        """

        let result = UniversalErrorPatcher.patchCLISource(source, appName: "demo-cli")
        XCTAssertFalse(result.isModified)
        XCTAssertEqual(result.originalSource, result.patchedSource)
        XCTAssertFalse(result.injectedRunWithUniversalError)
        XCTAssertFalse(result.patchedSource.contains("runWithUniversalError {"))
    }

    func testCLIPatchingDoesNotTreatStringLiteralAsExistingWrapper() {
        let source = """
        import Foundation

        let help = "call runWithUniversalError { } from main"
        print(help)
        """

        let result = UniversalErrorPatcher.patchCLISource(source, appName: "demo-cli")
        XCTAssertTrue(result.injectedRunWithUniversalError)
        let occurrences = result.patchedSource.components(separatedBy: "runWithUniversalError {").count - 1
        XCTAssertEqual(occurrences, 2)
        XCTAssertTrue(result.patchedSource.contains("SingleInstanceCLI.exitIfAlreadyRunning"))
    }

    func testGuardInjectionUsesStringIndexNotUTF16Offset() {
        let source = """
        import Foundation
        import AgentCLIKit
        import AppErrorKit

        // 🎉 emoji surrogate pair
        runWithUniversalError {
            print("ok")
        }
        """

        let result = UniversalErrorPatcher.patchCLISource(source, appName: "emoji-cli")
        XCTAssertTrue(result.injectedSingleInstanceGuard)
        XCTAssertTrue(result.patchedSource.contains("runWithUniversalError {"))
        XCTAssertTrue(result.patchedSource.contains("SingleInstanceCLI.exitIfAlreadyRunning(name: \"emoji-cli\", scope: .worktree)"))
        XCTAssertFalse(result.patchedSource.contains("🎉    SingleInstanceCLI"))
    }

    func testCLIPatchingIdempotencyOnFullyCompliantCode() {
        let fullyCompliantSource = """
        import Foundation
        import AgentCLIKit
        import AppErrorKit
        import SingleInstanceKit
        import StateMirrorKit

        runWithUniversalError {
            SingleInstanceCLI.exitIfAlreadyRunning(name: "compliant-app", scope: .worktree)
            StateMirror.onTerminate(app: "compliant-app", .clear)
            print("OK")
        }
        """

        let result = UniversalErrorPatcher.patchCLISource(
            fullyCompliantSource,
            appName: "compliant-app"
        )

        XCTAssertFalse(result.isModified)
        XCTAssertEqual(result.originalSource, result.patchedSource)
        XCTAssertFalse(result.injectedRunWithUniversalError)
        XCTAssertFalse(result.injectedSingleInstanceGuard)
        XCTAssertFalse(result.injectedTerminationHook)
        XCTAssertTrue(result.addedImports.isEmpty)
    }

    // MARK: - View Patching Tests

    func testDefaultOptionsDoNotSuppressSurfaceParity() {
        XCTAssertFalse(UniversalErrorPatcher.Options().suppressSurfaceParity)

        let viewSource = """
        import SwiftUI

        struct MainView: View {
            var body: some View {
                VStack {
                    Text("Main Screen")
                }
            }
        }
        """

        let result = UniversalErrorPatcher.patchViewSource(viewSource)

        XCTAssertFalse(result.injectedParitySuppression)
        XCTAssertFalse(result.patchedSource.contains("parity-suppress"))
        XCTAssertFalse(result.patchedSource.contains("backlog#101"))
        XCTAssertTrue(result.addedImports.contains("AppErrorKit"))
        XCTAssertTrue(result.patchedSource.contains("import AppErrorKit"))
        XCTAssertFalse(UniversalViewPatcher.hasParitySuppression(in: result.patchedSource))
    }

    func testFakeBacklog101SuppressionCommentIsNotInjected() {
        let viewSource = """
        import SwiftUI

        struct MainView: View {
            var body: some View {
                Text("Main Screen")
            }
        }
        """

        let result = UniversalErrorPatcher.patchViewSource(
            viewSource,
            options: .init(
                suppressSurfaceParity: true,
                paritySuppressionComment: "// parity-suppress: fleet-error-handling-rollout backlog#101",
                ensureAppErrorKitImport: false
            )
        )

        XCTAssertFalse(result.injectedParitySuppression)
        XCTAssertFalse(result.patchedSource.contains("backlog#101"))
        XCTAssertFalse(UniversalViewPatcher.isValidParitySuppressionComment(
            "// parity-suppress: fleet-error-handling-rollout backlog#101"
        ))
    }

    func testValidUUIDBacklogSuppressionIsInjectedWhenEnabled() {
        let viewSource = """
        import SwiftUI

        struct MainView: View {
            var body: some View {
                Text("Main Screen")
            }
        }
        """
        let uuid = "849fdf51-441a-4742-8668-f186149df89e"
        let comment = "// parity-suppress: documented exception backlog#\(uuid)"

        let result = UniversalErrorPatcher.patchViewSource(
            viewSource,
            options: .init(
                suppressSurfaceParity: true,
                paritySuppressionComment: comment,
                ensureAppErrorKitImport: true
            )
        )

        XCTAssertTrue(result.isModified)
        XCTAssertTrue(result.injectedParitySuppression)
        XCTAssertTrue(result.addedImports.contains("AppErrorKit"))
        XCTAssertTrue(result.patchedSource.hasPrefix(comment))
        XCTAssertTrue(result.patchedSource.contains("import AppErrorKit"))
        XCTAssertTrue(UniversalViewPatcher.hasParitySuppression(in: result.patchedSource))
    }

    func testViewPatchingIdempotencyWhenValidSuppressionAlreadyPresent() {
        let uuid = "849fdf51-441a-4742-8668-f186149df89e"
        let alreadySuppressedSource = """
        // parity-suppress: documented exception backlog#\(uuid)
        import SwiftUI
        import AppErrorKit

        struct DetailScreen: View {
            var body: some View {
                Text("Detail")
            }
        }
        """

        let result = UniversalErrorPatcher.patchViewSource(
            alreadySuppressedSource,
            options: .init(
                suppressSurfaceParity: true,
                paritySuppressionComment: "// parity-suppress: documented exception backlog#\(uuid)",
                ensureAppErrorKitImport: true
            )
        )

        XCTAssertFalse(result.isModified)
        XCTAssertFalse(result.injectedParitySuppression)
        XCTAssertEqual(result.originalSource, result.patchedSource)

        let occurrences = result.patchedSource.components(separatedBy: "parity-suppress").count - 1
        XCTAssertEqual(occurrences, 1)
    }

    func testViewPatchingWithAppErrorModifierDoesNotInjectParitySuppressionByDefault() {
        let viewSource = """
        import SwiftUI
        import AppErrorKit

        struct StatusView: View {
            @Bindable var model: AppModel

            var body: some View {
                VStack {
                    Text("Status")
                }
                .frame(minWidth: 400)
            }
        }
        """

        var options = UniversalErrorPatcher.Options()
        options.viewErrorBinding = "$model.currentError"

        let result = UniversalErrorPatcher.patchViewSource(viewSource, options: options)

        XCTAssertTrue(result.isModified)
        XCTAssertFalse(result.injectedParitySuppression)
        XCTAssertFalse(result.patchedSource.contains("parity-suppress"))
        XCTAssertTrue(result.injectedAppErrorHandling)
        XCTAssertTrue(result.patchedSource.contains(".appErrorHandling(error: $model.currentError)"))
    }

    // MARK: - App Directory Batch Patching & Inspection Tests

    func testAppDirectoryBatchPatchingAndInspection() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("UniversalErrorPatcherTests_\(UUID().uuidString)")
        let sourcesDir = tempDir.appendingPathComponent("Sources")
        let cliDir = sourcesDir.appendingPathComponent("DemoCLI")
        let viewsDir = sourcesDir.appendingPathComponent("Views")

        try FileManager.default.createDirectory(at: cliDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: viewsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cliMainPath = cliDir.appendingPathComponent("main.swift").path
        let viewPath = viewsDir.appendingPathComponent("MainView.swift").path

        let rawCLI = """
        import Foundation
        print("CLI Start")
        """
        let rawView = """
        import SwiftUI

        struct MainView: View {
            var body: some View {
                Text("View")
            }
        }
        """

        try rawCLI.write(toFile: cliMainPath, atomically: true, encoding: .utf8)
        try rawView.write(toFile: viewPath, atomically: true, encoding: .utf8)

        // 패치 전 진단
        let beforeInspection = UniversalErrorPatcher.inspectApp(at: tempDir.path)
        XCTAssertTrue(beforeInspection.cliRequiresUniversalError)
        XCTAssertTrue(beforeInspection.cliRequiresSingleInstance)
        XCTAssertTrue(beforeInspection.cliRequiresTermination)
        XCTAssertTrue(beforeInspection.viewsRequireParitySuppression)

        // 일괄 패치 실행
        let appResult = try UniversalErrorPatcher.patchApp(
            at: tempDir.path,
            saveToFile: true,
            options: .init(appName: "demo-app")
        )

        XCTAssertTrue(appResult.isModified)
        XCTAssertEqual(appResult.cliResults.count, 1)
        XCTAssertEqual(appResult.viewResults.count, 1)

        // 파일에 실제로 기록되었는지 검증
        let writtenCLI = try String(contentsOfFile: cliMainPath, encoding: .utf8)
        let writtenView = try String(contentsOfFile: viewPath, encoding: .utf8)

        XCTAssertTrue(writtenCLI.contains("runWithUniversalError {"))
        XCTAssertTrue(writtenCLI.contains("SingleInstanceCLI.exitIfAlreadyRunning(name: \"demo-app\", scope: .worktree)"))
        XCTAssertTrue(writtenCLI.contains("StateMirror.onTerminate(app: \"demo-app\", .clear)"))

        XCTAssertFalse(writtenView.contains("parity-suppress"))
        XCTAssertFalse(writtenView.contains("backlog#101"))
        XCTAssertTrue(writtenView.contains("import AppErrorKit"))

        // 패치 후 진단 — 기본 옵션은 패리티 억제를 넣지 않으므로 View 쪽 요구는 남는다.
        let afterInspection = UniversalErrorPatcher.inspectApp(at: tempDir.path)
        XCTAssertFalse(afterInspection.cliRequiresUniversalError)
        XCTAssertFalse(afterInspection.cliRequiresSingleInstance)
        XCTAssertFalse(afterInspection.cliRequiresTermination)
        XCTAssertTrue(afterInspection.viewsRequireParitySuppression)
    }

    func testPatchAppReadFailureIsRecordedAsFailed() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("UniversalErrorPatcherReadFail_\(UUID().uuidString)")
        let cliDir = tempDir.appendingPathComponent("Sources").appendingPathComponent("BadCLI")
        try FileManager.default.createDirectory(at: cliDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let badMain = cliDir.appendingPathComponent("main.swift")
        try Data([0xFF, 0xFE, 0x00]).write(to: badMain)

        let result = try UniversalErrorPatcher.patchApp(
            at: tempDir.path,
            saveToFile: false,
            options: .init(appName: "bad-app")
        )

        XCTAssertTrue(result.cliResults.isEmpty)
        XCTAssertFalse(result.failed.isEmpty)
        XCTAssertTrue(result.failed.keys.contains { $0.hasSuffix("main.swift") })
    }

    func testPatchAppWriteFailureThrows() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("UniversalErrorPatcherWriteFail_\(UUID().uuidString)")
        let cliDir = tempDir.appendingPathComponent("Sources").appendingPathComponent("DemoCLI")
        try FileManager.default.createDirectory(at: cliDir, withIntermediateDirectories: true)

        let cliMain = cliDir.appendingPathComponent("main.swift")
        try "import Foundation\nprint(\"CLI Start\")\n".write(to: cliMain, atomically: true, encoding: .utf8)

        var immutable = URLResourceValues()
        immutable.isUserImmutable = true
        var mutableMain = cliMain
        try mutableMain.setResourceValues(immutable)

        defer {
            var revert = URLResourceValues()
            revert.isUserImmutable = false
            try? mutableMain.setResourceValues(revert)
            try? FileManager.default.removeItem(at: tempDir)
        }

        XCTAssertThrowsError(
            try UniversalErrorPatcher.patchApp(
                at: tempDir.path,
                saveToFile: true,
                options: .init(appName: "demo-app")
            )
        ) { error in
            guard case UniversalErrorPatcher.PatchError.writeFailed = error else {
                XCTFail("Expected PatchError.writeFailed, got \(error)")
                return
            }
        }
    }

    // MARK: - Single File Dynamic Patching Tests

    func testPatchFileDispatch() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("UniversalErrorPatcherFile_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cliFile = tempDir.appendingPathComponent("main.swift").path
        let viewFile = tempDir.appendingPathComponent("CustomScreen.swift").path
        let otherFile = tempDir.appendingPathComponent("Helper.swift").path

        try "import Foundation\nprint(1)".write(toFile: cliFile, atomically: true, encoding: .utf8)
        let viewCode = "import SwiftUI\nstruct CustomScreen: View { var body: some View { Text(\"A\") } }"
        try viewCode.write(toFile: viewFile, atomically: true, encoding: .utf8)
        try "func add() {}".write(toFile: otherFile, atomically: true, encoding: .utf8)

        let cliRes = try UniversalErrorPatcher.patchFile(atPath: cliFile, saveToFile: false)
        let viewRes = try UniversalErrorPatcher.patchFile(atPath: viewFile, saveToFile: false)
        let otherRes = try UniversalErrorPatcher.patchFile(atPath: otherFile, saveToFile: false)

        guard case .cli(let c) = cliRes else { XCTFail("Expected .cli"); return }
        guard case .view(let v) = viewRes else { XCTFail("Expected .view"); return }
        guard case .skipped(let reason) = otherRes else { XCTFail("Expected .skipped"); return }

        XCTAssertTrue(c.isModified)
        XCTAssertTrue(v.isModified)
        XCTAssertTrue(reason.contains("Not a CLI"))
    }
}
