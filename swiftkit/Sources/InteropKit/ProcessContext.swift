import Foundation

/// 프로세스 실행 인터페이스.
public protocol ProcessRunner: Sendable {
    func run(_ executablePath: String, _ arguments: [String]) -> (Int32, Data)
}

public extension ProcessRunner {
    func run(executablePath: String, arguments: [String]) -> (Int32, Data) {
        run(executablePath, arguments)
    }
}

public typealias ProcessDataRunner = @Sendable (String, [String]) -> (Int32, Data)
public typealias ProcessStringRunner = @Sendable (String, [String]) -> (Int32, String)

/// 프로세스 실행 컨텍스트 및 주입점.
/// TaskLocal 기반 격리를 제공하여 동시 실행 테스트 환경에서 경합 없이 실행기를 스텁/목으로 대체합니다.
public enum ProcessContext {
    @TaskLocal public static var currentDataRunner: ProcessDataRunner?
    @TaskLocal public static var currentStringRunner: ProcessStringRunner?

    /// Data 출력을 반환하는 기본 프로세스 실행기.
    public static func defaultRunProcess(_ path: String, _ arguments: [String]) -> (Int32, Data) {
        guard FileManager.default.isExecutableFile(atPath: path) else { return (127, Data()) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return (127, Data()) }
        let watchdog = Task.detached { [weak process] in
            do {
                try await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                guard let process, process.isRunning else { return }
                process.terminate()
            } catch {
                return
            }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return (process.terminationStatus, data)
    }

    /// 문자열 출력을 반환하는 기본 프로세스 실행기.
    public static func defaultRunStringProcess(_ path: String, _ arguments: [String]) -> (Int32, String) {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return (127, "\(path) 이(가) 설치돼 있지 않거나 실행 불가능합니다")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (127, "\(error)") }
        let watchdog = Task.detached { [weak process] in
            do {
                try await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                guard let process, process.isRunning else { return }
                process.terminate()
            } catch {
                return
            }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// 문자열 출력을 반환하는 오버로드.
    public static func defaultRunProcess(_ path: String, _ arguments: [String]) -> (Int32, String) {
        defaultRunStringProcess(path, arguments)
    }
}

public struct DefaultProcessRunner: ProcessRunner {
    public init() {}

    public func run(_ executablePath: String, _ arguments: [String]) -> (Int32, Data) {
        ProcessContext.defaultRunProcess(executablePath, arguments)
    }
}
