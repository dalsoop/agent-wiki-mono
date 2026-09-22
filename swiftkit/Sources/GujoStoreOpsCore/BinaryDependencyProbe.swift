import Foundation
import InteropKit
import LocalizationKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Specification for binary dependency probe.
public struct BinaryProbeSpec: Sendable, Equatable, Codable {
    public var executableName: String
    public var searchPaths: [String]
    public var minVersion: String?
    public var versionPattern: String?
    public var requiredArch: String?
    public var timeoutMs: Int

    public init(
        executableName: String,
        searchPaths: [String] = [],
        minVersion: String? = nil,
        versionPattern: String? = nil,
        requiredArch: String? = "arm64",
        timeoutMs: Int = 500
    ) {
        self.executableName = executableName
        self.searchPaths = searchPaths
        self.minVersion = minVersion
        self.versionPattern = versionPattern
        self.requiredArch = requiredArch
        self.timeoutMs = timeoutMs
    }

    /// Gujo Hub Auditor CLI specification default.
    public static var gujoAuditorSpec: BinaryProbeSpec {
        BinaryProbeSpec(
            executableName: "gujo-download-pipeline-auditor",
            searchPaths: [
                HostPlatform.cliBinPath("gujo-download-pipeline-auditor"),
                StoreOpsPaths.usrLocalCLI("gujo-download-pipeline-auditor"),
            ],
            minVersion: "1.0.0",
            versionPattern: #"(\d+\.\d+\.\d+)"#,
            requiredArch: "arm64"
        )
    }
}

/// Inspection phase failure reason.
public enum BinaryProbeFailure: Sendable, Equatable, Codable {
    case missing(candidatePaths: [String])
    case permissionDenied(path: String)
    case architectureMismatch(path: String, foundArch: String, requiredArch: String)
    case versionOutdated(path: String, foundVersion: String, minVersion: String)
    case probeExecutionFailed(path: String, exitCode: Int32, message: String)
}

/// 1:1 Prescription (remediation action) corresponding to probe result.
public struct BinaryRemediation: Sendable, Equatable, Codable {
    public var failure: BinaryProbeFailure?
    public var prescription: String
    public var actionCommand: String?

    public init(failure: BinaryProbeFailure?, prescription: String, actionCommand: String? = nil) {
        self.failure = failure
        self.prescription = prescription
        self.actionCommand = actionCommand
    }

    public static func forFailure(_ failure: BinaryProbeFailure, executableName: String) -> BinaryRemediation {
        switch failure {
        case let .missing(paths):
            let targetPath = paths.first ?? HostPlatform.cliBinPath(executableName)
            return BinaryRemediation(
                failure: failure,
                prescription: "Install \(executableName) to \(targetPath)",
                actionCommand: "app-build-manager ship apps/\(executableName)-swift release"
            )
        case let .permissionDenied(path):
            return BinaryRemediation(
                failure: failure,
                prescription: "Fix execute permission: chmod +x \(path)",
                actionCommand: "chmod +x \(path)"
            )
        case let .architectureMismatch(path, found, required):
            return BinaryRemediation(
                failure: failure,
                prescription: "Architecture mismatch for \(path) (found: \(found), required: \(required)) — recompile for \(required)",
                actionCommand: "app-build-manager ship apps/\(executableName)-swift release"
            )
        case let .versionOutdated(path, found, min):
            return BinaryRemediation(
                failure: failure,
                prescription: "Upgrade \(executableName) at \(path) from \(found) to >= \(min)",
                actionCommand: "app-build-manager ship apps/\(executableName)-swift release"
            )
        case let .probeExecutionFailed(path, code, msg):
            return BinaryRemediation(
                failure: failure,
                prescription: "CLI probe execution failed for \(path) (exit \(code)): \(msg)",
                actionCommand: "\(path) --version"
            )
        }
    }
}

/// Result of BinaryProbe inspection.
public struct BinaryProbeResult: Sendable, Equatable, Codable {
    public var ok: Bool
    public var resolvedPath: String?
    public var detectedVersion: String?
    public var detectedArch: String?
    public var failure: BinaryProbeFailure?
    public var remediation: BinaryRemediation?
    public var durationMs: Int

    public init(
        ok: Bool,
        resolvedPath: String? = nil,
        detectedVersion: String? = nil,
        detectedArch: String? = nil,
        failure: BinaryProbeFailure? = nil,
        remediation: BinaryRemediation? = nil,
        durationMs: Int = 0
    ) {
        self.ok = ok
        self.resolvedPath = resolvedPath
        self.detectedVersion = detectedVersion
        self.detectedArch = detectedArch
        self.failure = failure
        self.remediation = remediation
        self.durationMs = durationMs
    }
}

/// Phase 2: Mach-O Header Inspector.
/// Reads initial bytes to verify architecture (e.g. arm64: MH_MAGIC_64 0xfeedfacf + CPU_TYPE_ARM64 0x0100000c).
public enum MachOInspector {
    public static let MH_MAGIC_64: UInt32 = 0xfeedfacf
    public static let MH_CIGAM_64: UInt32 = 0xcffaedfe
    public static let MH_MAGIC: UInt32 = 0xfeedface
    public static let MH_CIGAM: UInt32 = 0xcefaedfe
    public static let FAT_MAGIC: UInt32 = 0xcafebabe
    public static let FAT_CIGAM: UInt32 = 0xbebafeca

    public static let CPU_TYPE_ARM64: UInt32 = 0x0100000c
    public static let CPU_TYPE_X86_64: UInt32 = 0x01000007

    public enum ArchitectureInfo: Sendable, Equatable {
        case arm64
        case x86_64
        case universal([ArchitectureInfo])
        case other(cpuType: UInt32)
        case unknown

        public var name: String {
            switch self {
            case .arm64: return "arm64"
            case .x86_64: return "x86_64"
            case let .universal(archs): return "universal(\(archs.map(\.name).joined(separator: ",")))"
            case let .other(cpu): return "other(\(String(format: "0x%08x", cpu)))"
            case .unknown: return "unknown"
            }
        }

        public func supports(arch: String) -> Bool {
            let target = arch.lowercased()
            switch self {
            case .arm64:
                return target == "arm64" || target == "arm64e"
            case .x86_64:
                return target == "x86_64" || target == "x86"
            case let .universal(sub):
                return sub.contains { $0.supports(arch: target) }
            default:
                return false
            }
        }
    }

    /// Inspect Mach-O or Universal binary header from file at `path`.
    public static func inspect(path: String) -> ArchitectureInfo {
        guard let file = fopen(path, "rb") else { return .unknown }
        defer { fclose(file) }

        var header = [UInt8](repeating: 0, count: 16)
        let bytesRead = fread(&header, 1, 16, file)
        guard bytesRead >= 8 else { return .unknown }

        let magic = header.withUnsafeBytes { $0.load(as: UInt32.self) }

        switch magic {
        case MH_MAGIC_64:
            let cpuType = header[4...7].withUnsafeBytes { $0.load(as: UInt32.self) }
            return archForCPUType(cpuType)
        case MH_CIGAM_64:
            let cpuType = CFSwapInt32(header[4...7].withUnsafeBytes { $0.load(as: UInt32.self) })
            return archForCPUType(cpuType)
        case FAT_MAGIC, FAT_CIGAM:
            return inspectFatBinary(file: file, header: header, isSwapped: magic == FAT_CIGAM)
        default:
            return .unknown
        }
    }

    private static func inspectFatBinary(file: UnsafeMutablePointer<FILE>, header: [UInt8], isSwapped: Bool) -> ArchitectureInfo {
        let nfatArchRaw = header[4...7].withUnsafeBytes { $0.load(as: UInt32.self) }
        let nfatArch = isSwapped ? CFSwapInt32(nfatArchRaw) : nfatArchRaw
        fseek(file, 8, SEEK_SET)

        var subArchs: [ArchitectureInfo] = []
        for _ in 0..<min(nfatArch, 16) {
            var buf = [UInt32](repeating: 0, count: 5)
            if fread(&buf, 4, 5, file) == 5 {
                let cputype = isSwapped ? CFSwapInt32(buf[0]) : buf[0]
                subArchs.append(archForCPUType(cputype))
            }
        }
        return .universal(subArchs)
    }

    private static func archForCPUType(_ cpuType: UInt32) -> ArchitectureInfo {
        switch cpuType {
        case CPU_TYPE_ARM64: return .arm64
        case CPU_TYPE_X86_64: return .x86_64
        default: return .other(cpuType: cpuType)
        }
    }
}

/// Phase 3: Ultra-fast posix_spawn executor with microsecond/millisecond timeout.
public enum FastSpawnProbe {
    public struct SpawnOutput: Sendable {
        public var exitCode: Int32
        public var stdout: String
        public var stderr: String
        public var timedOut: Bool
    }

    /// Execute `path [args]` via posix_spawn with timeout in milliseconds.
    public static func run(
        path: String,
        args: [String],
        timeoutMs: Int = 50
    ) -> SpawnOutput {
        guard let spawnInfo = setupSpawn(path: path, args: args) else {
            return SpawnOutput(exitCode: -1, stdout: "", stderr: "Spawn setup failed", timedOut: false)
        }

        return waitForSpawnOutput(spawnInfo: spawnInfo, timeoutMs: timeoutMs)
    }

    private struct SpawnProcessInfo {
        let pid: pid_t
        let outFD: Int32
        let errFD: Int32
    }

    private static func setupSpawn(path: String, args: [String]) -> SpawnProcessInfo? {
        var outPipe: [Int32] = [-1, -1]
        var errPipe: [Int32] = [-1, -1]
        guard pipe(&outPipe) == 0 else { return nil }
        guard pipe(&errPipe) == 0 else {
            close(outPipe[0])
            close(outPipe[1])
            return nil
        }

        #if os(macOS)
        var fileActions: posix_spawn_file_actions_t? = nil
        var attr: posix_spawnattr_t? = nil
        #else
        var fileActions = posix_spawn_file_actions_t()
        var attr = posix_spawnattr_t()
        #endif

        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        posix_spawn_file_actions_adddup2(&fileActions, outPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, errPipe[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, outPipe[0])
        posix_spawn_file_actions_addclose(&fileActions, errPipe[0])
        posix_spawn_file_actions_addclose(&fileActions, outPipe[1])
        posix_spawn_file_actions_addclose(&fileActions, errPipe[1])

        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        #if os(macOS)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))
        #endif

        let fullArgs = [path] + args
        let env = ProcessInfo.processInfo.environment
        let envp = env.map { "\($0.key)=\($0.value)" }

        var pid: pid_t = 0
        let spawnResult = withCStrings(fullArgs) { cArgv in
            withCStrings(envp) { cEnvp in
                posix_spawn(&pid, path, &fileActions, &attr, cArgv, cEnvp)
            }
        }

        close(outPipe[1])
        close(errPipe[1])

        guard spawnResult == 0 else {
            close(outPipe[0])
            close(errPipe[0])
            return nil
        }

        for fd in [outPipe[0], errPipe[0]] {
            let flags = fcntl(fd, F_GETFL)
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }

        return SpawnProcessInfo(pid: pid, outFD: outPipe[0], errFD: errPipe[0])
    }

    private static func hasPendingWork(outFD: Int32, errFD: Int32, childExited: Bool) -> Bool {
        if !childExited { return true }
        return outFD >= 0 || errFD >= 0
    }

    private static func isProcessFinished(childExited: Bool, pollIdle: Bool, timedOut: Bool) -> Bool {
        let exitedAndIdle = childExited && pollIdle
        guard !exitedAndIdle else { return true }
        guard timedOut else { return false }
        return pollIdle || childExited
    }

    private static func buildPollFDs(outFD: Int32, errFD: Int32) -> [pollfd] {
        var pollFds: [pollfd] = []
        if outFD >= 0 { pollFds.append(pollfd(fd: outFD, events: Int16(POLLIN), revents: 0)) }
        if errFD >= 0 { pollFds.append(pollfd(fd: errFD, events: Int16(POLLIN), revents: 0)) }
        return pollFds
    }

    private static func waitForSpawnOutput(spawnInfo: SpawnProcessInfo, timeoutMs: Int) -> SpawnOutput {
        var outData = Data()
        var errData = Data()
        var outFD = spawnInfo.outFD
        var errFD = spawnInfo.errFD
        var buffer = [UInt8](repeating: 0, count: 4096)

        let start = DispatchTime.now()
        let timeoutNs = UInt64(timeoutMs) * 1_000_000
        var timedOut = false
        var childExited = false
        var childStatus: Int32 = 0

        while hasPendingWork(outFD: outFD, errFD: errFD, childExited: childExited) {
            let now = DispatchTime.now()
            let elapsedNs = now.uptimeNanoseconds >= start.uptimeNanoseconds ? (now.uptimeNanoseconds - start.uptimeNanoseconds) : 0

            checkChildStatus(
                pid: spawnInfo.pid,
                elapsedNs: elapsedNs,
                timeoutNs: timeoutNs,
                childExited: &childExited,
                childStatus: &childStatus,
                timedOut: &timedOut
            )

            let pollFds = buildPollFDs(outFD: outFD, errFD: errFD)
            guard !pollFds.isEmpty else { break }

            let waitMs: Int32 = childExited ? 5 : (timedOut ? 0 : Int32(max(1, (Int64(timeoutNs) - Int64(elapsedNs)) / 1_000_000)))
            var mutablePollFds = pollFds
            let ret = poll(&mutablePollFds, nfds_t(mutablePollFds.count), waitMs)
            guard ret >= 0 || errno != EINTR else { continue }

            for pfd in mutablePollFds {
                handlePollEvent(
                    pfd: pfd,
                    buffer: &buffer,
                    outFD: &outFD,
                    errFD: &errFD,
                    outData: &outData,
                    errData: &errData
                )
            }

            let pollIdle = (ret == 0)
            guard !isProcessFinished(childExited: childExited, pollIdle: pollIdle, timedOut: timedOut) else { break }
        }

        return finalizeSpawnProcess(
            pid: spawnInfo.pid,
            outFD: outFD,
            errFD: errFD,
            childExited: childExited,
            childStatus: childStatus,
            timedOut: timedOut,
            outData: outData,
            errData: errData
        )
    }

    private static func closeFDs(outFD: Int32, errFD: Int32) {
        if outFD >= 0 { close(outFD) }
        if errFD >= 0 { close(errFD) }
    }

    private static func finalizeSpawnProcess(
        pid: pid_t,
        outFD: Int32,
        errFD: Int32,
        childExited: Bool,
        childStatus: Int32,
        timedOut: Bool,
        outData: Data,
        errData: Data
    ) -> SpawnOutput {
        closeFDs(outFD: outFD, errFD: errFD)

        var finalStatus = childStatus
        if !childExited {
            var status: Int32 = 0
            waitpid(pid, &status, 0)
            finalStatus = status
        }

        let exitCode: Int32 = timedOut ? 124 : (WIFEXITED(finalStatus) ? WEXITSTATUS(finalStatus) : -1)
        let stdoutStr = String(data: outData, encoding: .utf8) ?? ""
        let stderrStr = String(data: errData, encoding: .utf8) ?? ""

        return SpawnOutput(exitCode: exitCode, stdout: stdoutStr, stderr: stderrStr, timedOut: timedOut)
    }

    private static func checkChildStatus(
        pid: pid_t,
        elapsedNs: UInt64,
        timeoutNs: UInt64,
        childExited: inout Bool,
        childStatus: inout Int32,
        timedOut: inout Bool
    ) {
        guard !childExited else { return }
        var status: Int32 = 0
        let w = waitpid(pid, &status, WNOHANG)
        if w == pid {
            childExited = true
            childStatus = status
        } else if elapsedNs >= timeoutNs {
            timedOut = true
            kill(pid, SIGKILL)
            waitpid(pid, &status, 0)
            childExited = true
            childStatus = status
        }
    }

    private static func handlePollEvent(
        pfd: pollfd,
        buffer: inout [UInt8],
        outFD: inout Int32,
        errFD: inout Int32,
        outData: inout Data,
        errData: inout Data
    ) {
        let isPollIn = (pfd.revents & Int16(POLLIN)) != 0
        let isHupOrErr = (pfd.revents & (Int16(POLLHUP) | Int16(POLLERR) | Int16(POLLNVAL))) != 0
        guard isPollIn || isHupOrErr else { return }

        let n = read(pfd.fd, &buffer, buffer.count)
        if n > 0 {
            appendBufferData(fd: pfd.fd, outFD: outFD, buffer: buffer, count: n, outData: &outData, errData: &errData)
        }
        if n == 0 || isHupOrErr {
            closeMatchingFD(pfd.fd, outFD: &outFD, errFD: &errFD)
        }
    }

    private static func appendBufferData(
        fd: Int32,
        outFD: Int32,
        buffer: [UInt8],
        count: Int,
        outData: inout Data,
        errData: inout Data
    ) {
        if fd == outFD {
            outData.append(buffer, count: count)
        } else {
            errData.append(buffer, count: count)
        }
    }

    private static func closeMatchingFD(_ fd: Int32, outFD: inout Int32, errFD: inout Int32) {
        if fd == outFD {
            close(outFD)
            outFD = -1
        } else if fd == errFD {
            close(errFD)
            errFD = -1
        }
    }

    private static func withCStrings<R>(_ strings: [String], _ body: ([UnsafeMutablePointer<CChar>?]) -> R) -> R {
        var cStrings = strings.map { strdup($0) }
        cStrings.append(nil)
        defer {
            for ptr in cStrings where ptr != nil {
                free(ptr)
            }
        }
        return body(cStrings)
    }

    private static func WIFEXITED(_ status: Int32) -> Bool {
        (status & 0x7f) == 0
    }

    private static func WEXITSTATUS(_ status: Int32) -> Int32 {
        (status >> 8) & 0xff
    }
}

/// Fast Binary Probe Engine implementing 4 pre-flight phases (<50ms).
public enum FastBinaryProbeEngine {
    /// Probe binary specification synchronously (< 50ms).
    public static func probe(spec: BinaryProbeSpec) -> BinaryProbeResult {
        let startTime = DispatchTime.now()

        guard let path = resolveCandidatePath(spec: spec) else {
            let candidates = spec.searchPaths.isEmpty
                ? HostPlatform.binCandidates(forCLI: spec.executableName)
                : spec.searchPaths
            return makeFailureResult(
                startTime: startTime,
                spec: spec,
                path: nil,
                failure: .missing(candidatePaths: candidates)
            )
        }

        if access(path, X_OK) != 0 {
            return makeFailureResult(
                startTime: startTime,
                spec: spec,
                path: path,
                failure: .permissionDenied(path: path)
            )
        }

        let archInfo = MachOInspector.inspect(path: path)
        let archName = archInfo.name
        if let requiredArch = spec.requiredArch, !archInfo.supports(arch: requiredArch) {
            return makeFailureResult(
                startTime: startTime,
                spec: spec,
                path: path,
                archName: archName,
                failure: .architectureMismatch(path: path, foundArch: archName, requiredArch: requiredArch)
            )
        }

        return executeVersionProbe(
            path: path,
            archName: archName,
            spec: spec,
            startTime: startTime
        )
    }

    private static func resolveCandidatePath(spec: BinaryProbeSpec) -> String? {
        let candidates = spec.searchPaths.isEmpty ? HostPlatform.binCandidates(forCLI: spec.executableName) : spec.searchPaths
        for path in candidates {
            var statBuf = stat()
            guard lstat(path, &statBuf) == 0 else { continue }
            let mode = statBuf.st_mode & S_IFMT
            if mode == S_IFLNK {
                var resolvedBuffer = [CChar](repeating: 0, count: Int(PATH_MAX))
                if realpath(path, &resolvedBuffer) != nil {
                    return path
                }
            } else if mode == S_IFREG {
                return path
            }
        }
        return nil
    }

    private static func executeVersionProbe(
        path: String,
        archName: String,
        spec: BinaryProbeSpec,
        startTime: DispatchTime
    ) -> BinaryProbeResult {
        let timeout = spec.timeoutMs
        let spawnRes = FastSpawnProbe.run(path: path, args: ["--version"], timeoutMs: timeout)
        guard spawnRes.exitCode == 0 else {
            let msg = spawnRes.timedOut ? "Timed out after \(timeout)ms" : (spawnRes.stderr.isEmpty ? spawnRes.stdout : spawnRes.stderr)
            return makeFailureResult(
                startTime: startTime,
                spec: spec,
                path: path,
                archName: archName,
                failure: .probeExecutionFailed(path: path, exitCode: spawnRes.exitCode, message: msg.trimmingCharacters(in: .whitespacesAndNewlines))
            )
        }

        let detectedVersion = parseVersion(from: spawnRes.stdout + "\n" + spawnRes.stderr, pattern: spec.versionPattern)
        if let minVer = spec.minVersion, let foundVer = detectedVersion, compareVersions(foundVer, minVer) == .orderedAscending {
            return makeFailureResult(
                startTime: startTime,
                spec: spec,
                path: path,
                archName: archName,
                version: foundVer,
                failure: .versionOutdated(path: path, foundVersion: foundVer, minVersion: minVer)
            )
        }

        return BinaryProbeResult(
            ok: true,
            resolvedPath: path,
            detectedVersion: detectedVersion,
            detectedArch: archName,
            failure: nil,
            remediation: nil,
            durationMs: elapsedMs(since: startTime)
        )
    }

    private static func parseVersion(from output: String, pattern: String?) -> String? {
        let regexPattern = pattern ?? #"(\d+\.\d+\.\d+)"#
        do {
            let regex = try NSRegularExpression(pattern: regexPattern)
            guard let match = regex.firstMatch(in: output, range: NSRange(location: 0, length: (output as NSString).length)) else {
                return nil
            }
            let nsRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
            guard let range = Range(nsRange, in: output) else { return nil }
            return String(output[range])
        } catch {
            return nil
        }
    }

    private static func makeFailureResult(
        startTime: DispatchTime,
        spec: BinaryProbeSpec,
        path: String?,
        archName: String? = nil,
        version: String? = nil,
        failure: BinaryProbeFailure
    ) -> BinaryProbeResult {
        BinaryProbeResult(
            ok: false,
            resolvedPath: path,
            detectedVersion: version,
            detectedArch: archName,
            failure: failure,
            remediation: BinaryRemediation.forFailure(failure, executableName: spec.executableName),
            durationMs: elapsedMs(since: startTime)
        )
    }

    private static func elapsedMs(since start: DispatchTime) -> Int {
        let now = DispatchTime.now()
        let diff = now.uptimeNanoseconds >= start.uptimeNanoseconds ? (now.uptimeNanoseconds - start.uptimeNanoseconds) : 0
        return Int(diff / 1_000_000)
    }

    /// Compare semver-like version strings ("1.0.2" vs "1.0.0").
    public static func compareVersions(_ v1: String, _ v2: String) -> ComparisonResult {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }
        let count = max(parts1.count, parts2.count)
        for i in 0..<count {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 < p2 { return .orderedAscending }
            if p1 > p2 { return .orderedDescending }
        }
        return .orderedSame
    }
}
