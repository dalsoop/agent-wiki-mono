import Foundation

/// 설치 상태 검사 항목. 일반 오픈소스 프로그램 설치 검사에 쓰는 5종.
public enum InstallCheck: Codable, Hashable, Sendable {
    case appBundle(String)
    case bundleIdentifier(String)
    case executable(String)
    case brewCask(String)
    case brewFormula(String)

    private enum CodingKeys: String, CodingKey { case kind, value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        let value = try c.decode(String.self, forKey: .value)
        switch kind {
        case "appBundle": self = .appBundle(value)
        case "bundleIdentifier": self = .bundleIdentifier(value)
        case "executable": self = .executable(value)
        case "brewCask": self = .brewCask(value)
        case "brewFormula": self = .brewFormula(value)
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Unknown install check kind: \(kind)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .appBundle(let v): try c.encode("appBundle", forKey: .kind); try c.encode(v, forKey: .value)
        case .bundleIdentifier(let v): try c.encode("bundleIdentifier", forKey: .kind); try c.encode(v, forKey: .value)
        case .executable(let v): try c.encode("executable", forKey: .kind); try c.encode(v, forKey: .value)
        case .brewCask(let v): try c.encode("brewCask", forKey: .kind); try c.encode(v, forKey: .value)
        case .brewFormula(let v): try c.encode("brewFormula", forKey: .kind); try c.encode(v, forKey: .value)
        }
    }
}

public struct InstallEvidence: Equatable, Sendable {
    public var check: InstallCheck
    public var installed: Bool
    public var label: String
    public var detail: String

    public init(check: InstallCheck, installed: Bool, label: String, detail: String) {
        self.check = check
        self.installed = installed
        self.label = label
        self.detail = detail
    }
}

public struct InstallStatus: Equatable, Sendable {
    public var installed: Bool
    public var evidence: [InstallEvidence]

    public init(installed: Bool, evidence: [InstallEvidence]) {
        self.installed = installed
        self.evidence = evidence
    }

    public var matchedEvidence: [InstallEvidence] { evidence.filter(\.installed) }
}

/// 검사기. 파일 존재·PATH 탐색·brew 목록·mdfind 같은 외부 의존은 클로저로 주입해 테스트를 분리한다.
public struct InstallChecker: Sendable {
    private let fileExists: @Sendable (String) -> Bool
    private let bundleIdentifierPaths: @Sendable (String) -> [String]
    private let commandExists: @Sendable (String) -> Bool
    private let brewCaskInstalled: @Sendable (String) -> Bool
    private let brewFormulaInstalled: @Sendable (String) -> Bool

    public init(
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        bundleIdentifierPaths: @escaping @Sendable (String) -> [String] = InstallChecker.defaultBundleIdentifierPaths,
        commandExists: @escaping @Sendable (String) -> Bool = InstallChecker.defaultCommandExists,
        brewCaskInstalled: @escaping @Sendable (String) -> Bool = InstallChecker.defaultBrewCaskInstalled,
        brewFormulaInstalled: @escaping @Sendable (String) -> Bool = InstallChecker.defaultBrewFormulaInstalled
    ) {
        self.fileExists = fileExists
        self.bundleIdentifierPaths = bundleIdentifierPaths
        self.commandExists = commandExists
        self.brewCaskInstalled = brewCaskInstalled
        self.brewFormulaInstalled = brewFormulaInstalled
    }

    public func status(for checks: [InstallCheck]) -> InstallStatus {
        let collected = checks.map { makeEvidence(for: $0) }
        return InstallStatus(installed: collected.contains { $0.installed }, evidence: collected)
    }

    public func isInstalled(_ checks: [InstallCheck]) -> Bool { status(for: checks).installed }

    private func makeEvidence(for check: InstallCheck) -> InstallEvidence {
        switch check {
        case .appBundle(let path):
            let expanded = (path as NSString).expandingTildeInPath
            return InstallEvidence(check: check, installed: fileExists(expanded), label: "App bundle", detail: expanded)
        case .bundleIdentifier(let id):
            let paths = bundleIdentifierPaths(id)
            return InstallEvidence(
                check: check,
                installed: !paths.isEmpty,
                label: "Bundle ID",
                detail: paths.isEmpty ? id : "\(id) -> \(paths.joined(separator: ", "))"
            )
        case .executable(let name):
            return InstallEvidence(check: check, installed: commandExists(name), label: "Executable", detail: name)
        case .brewCask(let name):
            return InstallEvidence(check: check, installed: brewCaskInstalled(name), label: "Homebrew cask", detail: name)
        case .brewFormula(let name):
            return InstallEvidence(check: check, installed: brewFormulaInstalled(name), label: "Homebrew formula", detail: name)
        }
    }

    // MARK: - 기본 구현

    /// 외부 프로세스 없이 PATH 를 직접 탐색해 실행 파일 존재 여부를 결정한다.
    public static func defaultCommandExists(_ name: String) -> Bool {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in path.split(separator: ":") {
            if FileManager.default.isExecutableFile(atPath: "\(dir)/\(name)") { return true }
        }
        return false
    }

    public static func defaultBrewCaskInstalled(_ name: String) -> Bool { runBrewList(["list", "--cask", name]) }
    public static func defaultBrewFormulaInstalled(_ name: String) -> Bool { runBrewList(["list", "--formula", name]) }

    private static func runBrewList(_ arguments: [String]) -> Bool {
        runProcessStatus("/usr/bin/env", arguments: ["brew"] + arguments, timeoutSeconds: 3)
    }

    private static func runProcessStatus(_ executablePath: String, arguments: [String], timeoutSeconds: TimeInterval) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
            if finished.wait(timeout: .now() + timeoutSeconds) == .timedOut {
                process.terminate()
                return false
            }
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    public static func defaultBundleIdentifierPaths(_ identifier: String) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["kMDItemCFBundleIdentifier == '\(identifier)'"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
            if finished.wait(timeout: .now() + 3) == .timedOut {
                process.terminate()
                return []
            }
            guard process.terminationStatus == 0 else { return [] }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        } catch {
            return []
        }
    }
}
