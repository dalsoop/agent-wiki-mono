import Foundation
import Darwin
import XCTest

final class PackageGraphContractTests: XCTestCase {
    func testExactProductTargetAndResourceGraph() throws {
        try assertCommandRunnerLiveness()

        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifest = try dumpPackage(at: packageRoot)
        let products = try objects(named: "products", in: manifest)
        let targets = try objects(named: "targets", in: manifest)
        let productsByName = try indexedByName(products)
        let targetsByName = try indexedByName(targets)

        let expectedProducts: [String: (target: String, kind: String)] = [
            "game-realtime-state-kit": ("GameRealtimeStateKit", "library"),
            "game-realtime-protocol-kit": ("GameRealtimeProtocolKit", "library"),
            "game-realtime-simulation-kit": ("GameRealtimeSimulationKit", "library"),
            "game-realtime-runtime-kit": ("GameRealtimeRuntimeKit", "library"),
            "game-realtime-engine-kit": ("GameRealtimeEngineKit", "library"),
            "game-realtime-debug-kit": ("GameRealtimeDebugKit", "library"),
            "game-realtime-benchmark": ("GameRealtimeBenchmark", "executable"),
        ]
        let realtimeProductNames = Set(
            productsByName.keys.filter { $0.hasPrefix("game-realtime-") }
        )
        XCTAssertEqual(realtimeProductNames, Set(expectedProducts.keys))

        for (productName, expectation) in expectedProducts {
            let product = try XCTUnwrap(productsByName[productName])
            XCTAssertEqual(product["targets"] as? [String], [expectation.target])
            let type = try XCTUnwrap(product["type"] as? [String: Any])
            XCTAssertEqual(Set(type.keys), [expectation.kind])
        }

        let expectedDependencies: [String: Set<String>] = [
            "GameRealtimeStateKit": [],
            "GameRealtimeProtocolKit": ["GameRealtimeStateKit"],
            "GameRealtimeSimulationKit": [
                "GameRealtimeStateKit",
                "GameRealtimeProtocolKit",
            ],
            "GameRealtimeRuntimeKit": [
                "GameRealtimeStateKit",
                "GameRealtimeProtocolKit",
                "GameRealtimeSimulationKit",
            ],
            "GameRealtimeEngineKit": [
                "GameRealtimeProtocolKit",
                "GameRealtimeRuntimeKit",
                "GameRealtimeStateKit",
            ],
            "GameRealtimeDebugKit": [
                "GameRealtimeStateKit",
                "GameRealtimeProtocolKit",
                "GameRealtimeSimulationKit",
                "GameRealtimeRuntimeKit",
                "GameRealtimeEngineKit",
            ],
            "GameRealtimeBenchmark": [
                "GameRealtimeDebugKit",
                "GameRealtimeEngineKit",
                "GameRealtimeProtocolKit",
                // Bundle.module → LocalizationKit 리졸버 전환(8a84fb8b8b)으로 추가.
                "LocalizationKit",
            ],
            "GameRealtimeStateKitTests": ["GameRealtimeStateKit"],
            "GameRealtimeProtocolKitTests": ["GameRealtimeProtocolKit"],
            "GameRealtimeSimulationKitTests": ["GameRealtimeSimulationKit"],
            "GameRealtimeRuntimeKitTests": ["GameRealtimeRuntimeKit"],
            "GameRealtimeEngineKitTests": ["GameRealtimeEngineKit"],
            "GameRealtimeDebugKitTests": ["GameRealtimeDebugKit"],
            "GameRealtimeBenchmarkTests": ["GameRealtimeDebugKit"],
            "GameRealtimePackageGraphTests": [],
        ]
        let realtimeTargetNames = Set(
            targetsByName.keys.filter { $0.hasPrefix("GameRealtime") }
        )
        XCTAssertEqual(realtimeTargetNames, Set(expectedDependencies.keys))

        for (targetName, dependencies) in expectedDependencies {
            let target = try XCTUnwrap(targetsByName[targetName])
            XCTAssertEqual(try dependencyNames(in: target), dependencies, targetName)
        }

        let expectedTestTargets: Set<String> = [
            "GameRealtimeStateKitTests",
            "GameRealtimeProtocolKitTests",
            "GameRealtimeSimulationKitTests",
            "GameRealtimeRuntimeKitTests",
            "GameRealtimeEngineKitTests",
            "GameRealtimeDebugKitTests",
            "GameRealtimeBenchmarkTests",
            "GameRealtimePackageGraphTests",
        ]
        let testTargets = Set(
            targetsByName.compactMap { name, target in
                target["type"] as? String == "test" && name.hasPrefix("GameRealtime")
                    ? name
                    : nil
            }
        )
        XCTAssertEqual(testTargets, expectedTestTargets)
        XCTAssertEqual(targetsByName["GameRealtimeBenchmark"]?["type"] as? String, "executable")

        let expectedResources: [String: Set<ResourceRule>] = [
            "GameRealtimeBenchmark": [
                ResourceRule(path: "Resources/GameRealtimeBenchmarkV1", rule: "copy"),
            ],
            "GameRealtimeDebugKitTests": [
                ResourceRule(path: "Fixtures/GameRealtimeDeterminismV1", rule: "copy"),
            ],
        ]
        for targetName in expectedDependencies.keys {
            let target = try XCTUnwrap(targetsByName[targetName])
            XCTAssertEqual(
                try resourceRules(in: target),
                expectedResources[targetName] ?? [],
                targetName
            )
        }

        let requiredResourceFiles = [
            "Sources/GameRealtimeBenchmark/Resources/GameRealtimeBenchmarkV1/fixture.json",
            "Sources/GameRealtimeBenchmark/Resources/GameRealtimeBenchmarkV1/baseline.json",
            "Tests/GameRealtimeDebugKitTests/Fixtures/GameRealtimeDeterminismV1/input.json",
        ]
        for relativePath in requiredResourceFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: packageRoot.appendingPathComponent(relativePath).path
                ),
                relativePath
            )
        }

        let productionStages = [
            // 공용 현지화 기반 — Benchmark 만 의존하며 계층상 맨 아래(8a84fb8b8b).
            "LocalizationKit",
            "GameRealtimeStateKit",
            "GameRealtimeProtocolKit",
            "GameRealtimeSimulationKit",
            "GameRealtimeRuntimeKit",
            "GameRealtimeEngineKit",
            "GameRealtimeDebugKit",
            "GameRealtimeBenchmark",
        ]
        let stageByTarget = Dictionary(
            uniqueKeysWithValues: productionStages.enumerated().map { ($1, $0) }
        )
        for targetName in productionStages {
            let target = try XCTUnwrap(targetsByName[targetName])
            for dependency in try dependencyNames(in: target) {
                let dependencyStage = try XCTUnwrap(stageByTarget[dependency])
                let targetStage = try XCTUnwrap(stageByTarget[targetName])
                XCTAssertLessThan(dependencyStage, targetStage, "\(targetName) -> \(dependency)")
            }
        }

        let forbiddenManifestReferences = [
            "GameSimulation",
            "SwiftUI",
            "UIKit",
            "AppKit",
            "SpriteKit",
            "SceneKit",
        ]
        for targetName in expectedDependencies.keys {
            let target = try XCTUnwrap(targetsByName[targetName])
            let manifestBytes = try JSONSerialization.data(withJSONObject: target, options: [.sortedKeys])
            let manifestText = try XCTUnwrap(String(data: manifestBytes, encoding: .utf8))
            for forbiddenReference in forbiddenManifestReferences {
                XCTAssertFalse(
                    manifestText.contains(forbiddenReference),
                    "\(targetName) contains forbidden manifest reference \(forbiddenReference)"
                )
            }
        }
    }

    private struct ResourceRule: Hashable {
        let path: String
        let rule: String
    }

    private struct CommandResult {
        let status: Int32
        let standardOutput: Data
        let standardError: Data
        let processID: pid_t
        let processGroup: pid_t
    }

    private struct SpawnedCommand {
        let processID: pid_t
        let processGroup: pid_t
        let outputDrain: PipeDrain
        let errorDrain: PipeDrain
        let drains: DispatchGroup
    }

    private final class PipeDrain: @unchecked Sendable {
        private let fileHandle: FileHandle
        private let lock = NSLock()
        private var capturedData = Data()

        init(_ fileHandle: FileHandle) {
            self.fileHandle = fileHandle
        }

        var data: Data {
            lock.withLock { capturedData }
        }

        func readToEnd() {
            let result = fileHandle.readDataToEndOfFile()
            lock.withLock {
                capturedData = result
            }
        }
    }

    private enum ManifestError: Error {
        case commandFailed(status: Int32, stderr: String)
        case commandTimedOut(
            timeout: TimeInterval,
            forcedTermination: Bool,
            processGroup: pid_t,
            elapsedAfterReadiness: TimeInterval
        )
        case commandTerminationFailed(errno: Int32)
        case commandSpawnFailed(errno: Int32)
        case childReapFailed(errno: Int32)
        case outputDrainTimedOut
        case readinessTimedOut
        case invalidJSONMember(String)
        case unnamedObject
        case unsupportedDependency
        case unsupportedResource
    }

    private func assertCommandRunnerLiveness() throws {
        let largeOutputSize = 1_048_576
        let largeOutput = try runCommand(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                "/usr/bin/head -c \(largeOutputSize) /dev/zero; /usr/bin/head -c \(largeOutputSize) /dev/zero >&2",
            ],
            timeout: 30,
            terminationGrace: 0.1,
            forcedKillGrace: 1
        )
        XCTAssertEqual(largeOutput.status, 0)
        XCTAssertEqual(largeOutput.standardOutput.count, largeOutputSize)
        XCTAssertEqual(largeOutput.standardError.count, largeOutputSize)

        let fixtureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GameRealtimeProcessGroupTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: fixtureDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

        let successfulGroupFile = fixtureDirectory.appendingPathComponent("success-group")
        let successfulGrandchildFile = fixtureDirectory
            .appendingPathComponent("success-grandchild")
        let successfulReadinessFile = fixtureDirectory
            .appendingPathComponent("success-ready")
        defer {
            if let processGroup = try? readProcessID(from: successfulGroupFile) {
                Darwin.kill(-processGroup, SIGKILL)
            }
        }
        let successfulParent = try runCommand(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                """
                echo $$ > "$1"
                /bin/sh -c 'trap "" TERM; echo $$ > "$1"; : > "$2"; while :; do /bin/sleep 1; done' grandchild "$2" "$3" &
                while [ ! -s "$2" ] || [ ! -e "$3" ]; do /bin/sleep 0.01; done
                exit 0
                """,
                "success-parent",
                successfulGroupFile.path,
                successfulGrandchildFile.path,
                successfulReadinessFile.path,
            ],
            timeout: 2,
            terminationGrace: 0.1,
            forcedKillGrace: 1,
            readinessFile: successfulReadinessFile,
            readinessTimeout: 10
        )
        XCTAssertEqual(successfulParent.status, 0)
        let successfulGroup = try readProcessID(from: successfulGroupFile)
        let successfulGrandchild = try readProcessID(from: successfulGrandchildFile)
        XCTAssertEqual(successfulParent.processID, successfulGroup)
        XCTAssertEqual(successfulParent.processGroup, successfulGroup)
        assertProcessDoesNotExist(successfulGrandchild)
        assertProcessGroupDoesNotExist(successfulGroup)
        assertDirectChildWasReaped(successfulParent.processID)

        let readinessFile = fixtureDirectory.appendingPathComponent("grandchild-ready")

        do {
            _ = try runCommand(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: [
                    "-c",
                    "(trap '' TERM; : > \"$1\"; while :; do /bin/sleep 1; done) & wait",
                    "timeout-fixture",
                    readinessFile.path,
                ],
                timeout: 0.2,
                terminationGrace: 0.1,
                forcedKillGrace: 1,
                readinessFile: readinessFile,
                readinessTimeout: 10
            )
            XCTFail("expected typed command timeout")
        } catch ManifestError.commandTimedOut(
            let timeout,
            let forcedTermination,
            let processGroup,
            let elapsedAfterReadiness
        ) {
            XCTAssertEqual(timeout, 0.2)
            XCTAssertTrue(forcedTermination)
            XCTAssertLessThan(elapsedAfterReadiness, 2)
            XCTAssertTrue(FileManager.default.fileExists(atPath: readinessFile.path))
            assertProcessGroupDoesNotExist(processGroup)
            assertDirectChildWasReaped(processGroup)
        }
    }

    private func readProcessID(from file: URL) throws -> pid_t {
        let contents = try String(contentsOf: file, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return try XCTUnwrap(pid_t(contents))
    }

    private func assertProcessDoesNotExist(
        _ processID: pid_t,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        errno = 0
        XCTAssertEqual(Darwin.kill(processID, 0), -1, file: file, line: line)
        XCTAssertEqual(errno, ESRCH, file: file, line: line)
    }

    private func assertProcessGroupDoesNotExist(
        _ processGroup: pid_t,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        errno = 0
        XCTAssertEqual(Darwin.kill(-processGroup, 0), -1, file: file, line: line)
        XCTAssertEqual(errno, ESRCH, file: file, line: line)
    }

    private func assertDirectChildWasReaped(
        _ processID: pid_t,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var status: Int32 = 0
        errno = 0
        XCTAssertEqual(
            Darwin.waitpid(processID, &status, WNOHANG),
            -1,
            file: file,
            line: line
        )
        XCTAssertEqual(errno, ECHILD, file: file, line: line)
    }

    private func runCommand(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval,
        terminationGrace: TimeInterval,
        forcedKillGrace: TimeInterval,
        readinessFile: URL? = nil,
        readinessTimeout: TimeInterval = 0
    ) throws -> CommandResult {
        let command = try spawnProcessGroup(
            executableURL: executableURL,
            arguments: arguments
        )
        var rawStatus: Int32 = 0
        var directChildReaped = false
        var primaryError: Error?
        var commandTimedOut = false
        var timeoutStartedAt = monotonicNow()

        do {
            try signalProcessGroup(command.processGroup, signal: SIGCONT)
            if let readinessFile {
                let readinessDeadline = deadline(after: readinessTimeout)
                while !FileManager.default.fileExists(atPath: readinessFile.path) {
                    directChildReaped = try reapIfExited(
                        command.processID,
                        status: &rawStatus
                    )
                    if directChildReaped {
                        throw ManifestError.readinessTimedOut
                    }
                    guard monotonicNow() < readinessDeadline else {
                        throw ManifestError.readinessTimedOut
                    }
                    usleep(5_000)
                }
            }

            if !directChildReaped {
                timeoutStartedAt = monotonicNow()
                let commandDeadline = deadline(after: timeout)
                while monotonicNow() < commandDeadline {
                    directChildReaped = try reapIfExited(
                        command.processID,
                        status: &rawStatus
                    )
                    if directChildReaped {
                        break
                    }
                    usleep(5_000)
                }
                commandTimedOut = !directChildReaped
            }
        } catch {
            primaryError = error
        }

        let forcedTermination = try finalizeCommand(
            command,
            directChildReaped: &directChildReaped,
            rawStatus: &rawStatus,
            terminationGrace: terminationGrace,
            forcedKillGrace: forcedKillGrace
        )
        if let primaryError {
            throw primaryError
        }
        if commandTimedOut {
            throw ManifestError.commandTimedOut(
                timeout: timeout,
                forcedTermination: forcedTermination,
                processGroup: command.processGroup,
                elapsedAfterReadiness: elapsedSeconds(since: timeoutStartedAt)
            )
        }
        return CommandResult(
            status: exitStatus(rawStatus),
            standardOutput: command.outputDrain.data,
            standardError: command.errorDrain.data,
            processID: command.processID,
            processGroup: command.processGroup
        )
    }

    private func spawnProcessGroup(
        executableURL: URL,
        arguments: [String]
    ) throws -> SpawnedCommand {
        var outputPipe = [Int32](repeating: -1, count: 2)
        var errorPipe = [Int32](repeating: -1, count: 2)
        guard Darwin.pipe(&outputPipe) == 0 else {
            throw ManifestError.commandSpawnFailed(errno: errno)
        }
        guard Darwin.pipe(&errorPipe) == 0 else {
            let pipeError = errno
            Darwin.close(outputPipe[0])
            Darwin.close(outputPipe[1])
            throw ManifestError.commandSpawnFailed(errno: pipeError)
        }

        var parentOwnsOutputRead = true
        var parentOwnsOutputWrite = true
        var parentOwnsErrorRead = true
        var parentOwnsErrorWrite = true
        defer {
            if parentOwnsOutputRead { Darwin.close(outputPipe[0]) }
            if parentOwnsOutputWrite { Darwin.close(outputPipe[1]) }
            if parentOwnsErrorRead { Darwin.close(errorPipe[0]) }
            if parentOwnsErrorWrite { Darwin.close(errorPipe[1]) }
        }

        var fileActions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        var setupError = posix_spawn_file_actions_init(&fileActions)
        guard setupError == 0 else {
            throw ManifestError.commandSpawnFailed(errno: setupError)
        }
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        setupError = posix_spawnattr_init(&attributes)
        guard setupError == 0 else {
            throw ManifestError.commandSpawnFailed(errno: setupError)
        }
        defer { posix_spawnattr_destroy(&attributes) }

        let fileActionResults = [
            posix_spawn_file_actions_adddup2(&fileActions, outputPipe[1], STDOUT_FILENO),
            posix_spawn_file_actions_adddup2(&fileActions, errorPipe[1], STDERR_FILENO),
            posix_spawn_file_actions_addclose(&fileActions, outputPipe[0]),
            posix_spawn_file_actions_addclose(&fileActions, errorPipe[0]),
            posix_spawn_file_actions_addclose(&fileActions, outputPipe[1]),
            posix_spawn_file_actions_addclose(&fileActions, errorPipe[1]),
        ]
        if let actionError = fileActionResults.first(where: { $0 != 0 }) {
            throw ManifestError.commandSpawnFailed(errno: actionError)
        }

        let flags = Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_START_SUSPENDED)
        setupError = posix_spawnattr_setflags(&attributes, flags)
        guard setupError == 0 else {
            throw ManifestError.commandSpawnFailed(errno: setupError)
        }
        setupError = posix_spawnattr_setpgroup(&attributes, 0)
        guard setupError == 0 else {
            throw ManifestError.commandSpawnFailed(errno: setupError)
        }

        var processID: pid_t = 0
        var cArguments = ([executableURL.path] + arguments).map { strdup($0) }
        cArguments.append(nil)
        var cEnvironment = ProcessInfo.processInfo.environment.map {
            strdup("\($0.key)=\($0.value)")
        }
        cEnvironment.append(nil)
        defer {
            for argument in cArguments {
                free(argument)
            }
            for environmentEntry in cEnvironment {
                free(environmentEntry)
            }
        }
        let spawnError = cArguments.withUnsafeMutableBufferPointer {
            argumentBuffer in
            cEnvironment.withUnsafeMutableBufferPointer { environmentBuffer in
                executableURL.path.withCString { executablePath in
                    posix_spawn(
                        &processID,
                        executablePath,
                        &fileActions,
                        &attributes,
                        argumentBuffer.baseAddress,
                        environmentBuffer.baseAddress
                    )
                }
            }
        }
        guard spawnError == 0 else {
            throw ManifestError.commandSpawnFailed(errno: spawnError)
        }

        Darwin.close(outputPipe[1])
        parentOwnsOutputWrite = false
        Darwin.close(errorPipe[1])
        parentOwnsErrorWrite = false

        let actualProcessGroup = Darwin.getpgid(processID)
        guard actualProcessGroup == processID else {
            Darwin.kill(processID, SIGKILL)
            var status: Int32 = 0
            let reapDeadline = deadline(after: 1)
            var reaped = false
            while monotonicNow() < reapDeadline {
                let result = Darwin.waitpid(processID, &status, WNOHANG)
                if result == processID || (result == -1 && errno == ECHILD) {
                    reaped = true
                    break
                }
                if result == -1 && errno != EINTR {
                    throw ManifestError.childReapFailed(errno: errno)
                }
                usleep(5_000)
            }
            guard reaped else {
                throw ManifestError.commandTerminationFailed(errno: ETIMEDOUT)
            }
            throw ManifestError.commandSpawnFailed(errno: EPERM)
        }

        let outputDrain = PipeDrain(
            FileHandle(fileDescriptor: outputPipe[0], closeOnDealloc: true)
        )
        parentOwnsOutputRead = false
        let errorDrain = PipeDrain(
            FileHandle(fileDescriptor: errorPipe[0], closeOnDealloc: true)
        )
        parentOwnsErrorRead = false
        let drains = DispatchGroup()
        for drain in [outputDrain, errorDrain] {
            drains.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                drain.readToEnd()
                drains.leave()
            }
        }

        return SpawnedCommand(
            processID: processID,
            processGroup: processID,
            outputDrain: outputDrain,
            errorDrain: errorDrain,
            drains: drains
        )
    }

    private func finalizeCommand(
        _ command: SpawnedCommand,
        directChildReaped: inout Bool,
        rawStatus: inout Int32,
        terminationGrace: TimeInterval,
        forcedKillGrace: TimeInterval
    ) throws -> Bool {
        var forcedTermination = false
        var cleanupError: Error?
        if processGroupExists(command.processGroup) {
            do {
                try signalProcessGroup(command.processGroup, signal: SIGTERM)
            } catch {
                cleanupError = error
            }
            let terminationDeadline = deadline(after: terminationGrace)
            while monotonicNow() < terminationDeadline {
                if !directChildReaped {
                    do {
                        directChildReaped = try reapIfExited(
                            command.processID,
                            status: &rawStatus
                        )
                    } catch {
                        cleanupError = cleanupError ?? error
                        break
                    }
                }
                if directChildReaped && !processGroupExists(command.processGroup) {
                    break
                }
                usleep(5_000)
            }

            if processGroupExists(command.processGroup) {
                forcedTermination = true
                do {
                    try signalProcessGroup(command.processGroup, signal: SIGKILL)
                } catch {
                    cleanupError = cleanupError ?? error
                }
            }
        }

        let forcedDeadline = deadline(after: forcedKillGrace)
        while monotonicNow() < forcedDeadline {
            if !directChildReaped {
                do {
                    directChildReaped = try reapIfExited(
                        command.processID,
                        status: &rawStatus
                    )
                } catch {
                    cleanupError = cleanupError ?? error
                    break
                }
            }
            if directChildReaped && !processGroupExists(command.processGroup) {
                break
            }
            usleep(5_000)
        }
        do {
            try waitForDrains(command.drains, timeout: forcedKillGrace)
        } catch {
            cleanupError = cleanupError ?? error
        }
        guard directChildReaped && !processGroupExists(command.processGroup) else {
            throw cleanupError ?? ManifestError.commandTerminationFailed(errno: ETIMEDOUT)
        }
        if let cleanupError {
            throw cleanupError
        }
        return forcedTermination
    }

    private func signalProcessGroup(_ processGroup: pid_t, signal: Int32) throws {
        guard Darwin.kill(-processGroup, signal) == 0 || errno == ESRCH else {
            throw ManifestError.commandTerminationFailed(errno: errno)
        }
    }

    private func processGroupExists(_ processGroup: pid_t) -> Bool {
        errno = 0
        if Darwin.kill(-processGroup, 0) == 0 {
            return true
        }
        return errno != ESRCH
    }

    private func reapIfExited(_ processID: pid_t, status: inout Int32) throws -> Bool {
        while true {
            let result = Darwin.waitpid(processID, &status, WNOHANG)
            if result == processID {
                return true
            }
            if result == 0 {
                return false
            }
            if errno == EINTR {
                continue
            }
            if errno == ECHILD {
                return true
            }
            throw ManifestError.childReapFailed(errno: errno)
        }
    }

    private func waitForDrains(
        _ drains: DispatchGroup,
        timeout: TimeInterval
    ) throws {
        guard drains.wait(timeout: .now() + timeout) == .success else {
            throw ManifestError.outputDrainTimedOut
        }
    }

    private func exitStatus(_ rawStatus: Int32) -> Int32 {
        let terminationSignal = rawStatus & 0x7f
        if terminationSignal == 0 {
            return (rawStatus >> 8) & 0xff
        }
        return 128 + terminationSignal
    }

    private func monotonicNow() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    private func deadline(after interval: TimeInterval) -> UInt64 {
        monotonicNow() + UInt64(max(0, interval) * 1_000_000_000)
    }

    private func elapsedSeconds(since start: UInt64) -> TimeInterval {
        TimeInterval(monotonicNow() - start) / 1_000_000_000
    }

    private func dumpPackage(at packageRoot: URL) throws -> [String: Any] {
        let scratchPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("GameRealtimePackageGraphTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: scratchPath,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: scratchPath) }

        let command = try runCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "swift",
                "package",
                "--package-path",
                packageRoot.path,
                "--scratch-path",
                scratchPath.path,
                "dump-package",
            ],
            timeout: 60,
            terminationGrace: 0.5,
            forcedKillGrace: 1
        )
        guard command.status == 0 else {
            throw ManifestError.commandFailed(
                status: command.status,
                stderr: String(decoding: command.standardError, as: UTF8.self)
            )
        }
        guard
            let manifest = try JSONSerialization.jsonObject(
                with: command.standardOutput
            ) as? [String: Any]
        else {
            throw ManifestError.invalidJSONMember("root")
        }
        return manifest
    }

    private func objects(
        named name: String,
        in object: [String: Any]
    ) throws -> [[String: Any]] {
        guard let values = object[name] as? [[String: Any]] else {
            throw ManifestError.invalidJSONMember(name)
        }
        return values
    }

    private func indexedByName(
        _ objects: [[String: Any]]
    ) throws -> [String: [String: Any]] {
        var result: [String: [String: Any]] = [:]
        for object in objects {
            guard let name = object["name"] as? String else {
                throw ManifestError.unnamedObject
            }
            XCTAssertNil(result[name], "duplicate manifest object \(name)")
            result[name] = object
        }
        return result
    }

    private func dependencyNames(in target: [String: Any]) throws -> Set<String> {
        guard let dependencies = target["dependencies"] as? [[String: Any]] else {
            throw ManifestError.invalidJSONMember("dependencies")
        }
        return try Set(dependencies.map { dependency in
            guard
                let byName = dependency["byName"] as? [Any],
                let name = byName.first as? String
            else {
                throw ManifestError.unsupportedDependency
            }
            return name
        })
    }

    private func resourceRules(in target: [String: Any]) throws -> Set<ResourceRule> {
        guard let resources = target["resources"] as? [[String: Any]] else {
            throw ManifestError.invalidJSONMember("resources")
        }
        return try Set(resources.map { resource in
            guard
                let path = resource["path"] as? String,
                let rule = resource["rule"] as? [String: Any],
                rule.count == 1,
                let ruleName = rule.keys.first
            else {
                throw ManifestError.unsupportedResource
            }
            return ResourceRule(path: path, rule: ruleName)
        })
    }
}
