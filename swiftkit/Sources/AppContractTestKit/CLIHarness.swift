import Foundation

public struct CLIResult: Sendable, Equatable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var succeeded: Bool {
        status == 0
    }

    public func json() throws -> Any {
        let data = Data(stdout.utf8)
        return try JSONSerialization.jsonObject(with: data)
    }

    public func jsonResult() throws -> Any {
        let raw = try json()
        guard let envelope = raw as? [String: Any], envelope["ok"] != nil else {
            return raw
        }
        guard let result = envelope["result"] else {
            throw CLIHarnessError.notAnObject(stdout)
        }
        return result
    }

    public func jsonObject() throws -> [String: Any] {
        guard let object = try jsonResult() as? [String: Any] else {
            throw CLIHarnessError.notAnObject(stdout)
        }
        return object
    }

    public func jsonArray() throws -> [Any] {
        guard let array = try jsonResult() as? [Any] else {
            throw CLIHarnessError.notAnArray(stdout)
        }
        return array
    }
}

public enum CLIHarnessError: Error, CustomStringConvertible, Equatable {
    case binaryNotFound(String)
    case notAnObject(String)
    case notAnArray(String)

    public var description: String {
        switch self {
        case .binaryNotFound(let path):
            return "CLI binary not found: \(path)"
        case .notAnObject(let output):
            return "Output is not a valid JSON object: \(output)"
        case .notAnArray(let output):
            return "Output is not a valid JSON array: \(output)"
        }
    }
}

public final class CLISink: @unchecked Sendable {
    private let lock = NSLock()
    private var _output = ""
    private var _errors = ""

    public init() {}

    public func appendOutput(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        _output.append(text)
    }

    public func appendError(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        _errors.append(text)
    }

    public var output: String {
        lock.lock()
        defer { lock.unlock() }
        return _output
    }

    public var errors: String {
        lock.lock()
        defer { lock.unlock() }
        return _errors
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        _output = ""
        _errors = ""
    }
}

public final class CLIHarness: Sendable {
    public static let defaultTimeout: TimeInterval = 30.0

    public let binaryName: String
    public let root: URL
    public let binary: URL
    public let timeout: TimeInterval
    public let sink = CLISink()

    public init(rootPrefix: String = "test", timeout: TimeInterval = defaultTimeout) {
        self.binaryName = ""
        self.binary = URL(fileURLWithPath: "/dev/null")
        self.timeout = timeout
        self.root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(rootPrefix)-cli-\(UUID().uuidString)", isDirectory: true)
        do { try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true) } catch { _ = error }
    }

    public init(
        binaryName: String,
        rootPrefix: String? = nil,
        timeout: TimeInterval = defaultTimeout
    ) throws {
        self.binaryName = binaryName
        self.binary = try Self.locateBinary(named: binaryName)
        self.timeout = timeout
        let prefix = rootPrefix ?? binaryName
        self.root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-cli-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    deinit {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            _ = error
        }
    }

    public func path(_ name: String) -> String {
        root.appendingPathComponent(name).path
    }

    @discardableResult
    public func run(_ arguments: String...) throws -> CLIResult {
        try run(arguments)
    }

    @discardableResult
    public func run(
        _ arguments: [String],
        extraEnvironment: [String: String] = [:]
    ) throws -> CLIResult {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments

        var env = ProcessInfo.processInfo.environment
        for (k, v) in extraEnvironment {
            env[k] = v
        }
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        let group = DispatchGroup()
        group.enter()
        Thread.detachNewThread {
            process.waitUntilExit()
            group.leave()
        }
        let waitResult = group.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            process.terminate()
        }

        return CLIResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    public static func locateBinary(
        named binaryName: String,
        anchorBundle: Bundle? = nil
    ) throws -> URL {
        let bundle = anchorBundle ?? Bundle(for: CLIHarness.self)
        var directory = bundle.bundleURL
        for _ in 0..<6 {
            let candidate = directory.appendingPathComponent(binaryName)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
            directory = directory.deletingLastPathComponent()
        }
        let envKey = "\(binaryName.uppercased().replacingOccurrences(of: "-", with: "_"))_BINARY"
        if let envPath = ProcessInfo.processInfo.environment[envKey],
           FileManager.default.isExecutableFile(atPath: envPath) {
            return URL(fileURLWithPath: envPath)
        }
        throw CLIHarnessError.binaryNotFound(bundle.bundleURL.path)
    }
}
