import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// macOS 애플리케이션 활성화 단일 진실(SSOT).
/// CLI 스텁에서 GUI 앱을 비동기로 띄우고 CLI는 즉시 정상 종료(0초 위임)하는 표준 인터페이스.
///
/// 헌법 규약 (docs/agents/disciplines.md §1.1):
/// - 날것의 `Process("/usr/bin/open")` 실행을 전면 배제하고, Apple 표준 LaunchServices XPC를 직접 호출한다.
/// - CLI 도구는 `case "open": try AppActivation.open()` 1줄로 호출한다.
public enum AppActivation: Sendable {
    public enum ActivationError: Error, LocalizedError, Sendable {
        case appNotFound(String)
        case noGUISession
        case activationFailed(String)
        case timedOut

        public var errorDescription: String? {
            switch self {
            case .appNotFound(let name):
                return "Application not found: \(name)"
            case .noGUISession:
                return "GUI WindowServer session unavailable (headless or SSH session)"
            case .activationFailed(let reason):
                return "Application activation failed: \(reason)"
            case .timedOut:
                return "Application activation timed out"
            }
        }
    }

    /// 현재 CLI의 실행 파일 이름(hint)을 기반으로 상응하는 GUI 앱 번들을 활성화한다.
    /// `case "open": try AppActivation.open()` 1줄 표준 규약.
    public static func open(
        hint: String? = nil,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) throws {
        let appHint = hint ?? URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
        try activate(appName: appHint, arguments: arguments, environment: environment)
    }

    /// 지정된 애플리케이션 이름 또는 번들 식별자를 활성화한다.
    public static func activate(
        appName: String,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) throws {
        #if canImport(AppKit)
        guard hasGraphicalSession() else {
            throw ActivationError.noGUISession
        }

        if activateRunningApplication(named: appName) {
            return
        }

        guard let appURL = resolveApplicationURL(named: appName) else {
            throw ActivationError.appNotFound(appName)
        }

        try dispatchOpenApplication(at: appURL, arguments: arguments, environment: environment)
        #else
        throw ActivationError.activationFailed("AppKit unavailable on current platform")
        #endif
    }

    #if canImport(AppKit)
    /// 그래픽 디스플레이 세션 보유 여부 확인 (SSH 원격 헤드리스 방어)
    private static func hasGraphicalSession() -> Bool {
        let env = ProcessInfo.processInfo.environment
        let sshKeys = ["SSH_CONNECTION", "SSH_CLIENT", "SSH_TTY"]
        let isSSH = sshKeys.contains(where: { env[$0] != nil })
        if isSSH && env["DISPLAY"] == nil {
            return false
        }
        return true
    }

    /// 이미 실행 중인 프로세스가 있다면 포커스 활성화 (0.1ms 반환)
    private static func activateRunningApplication(named appName: String) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        guard let target = runningApps.first(where: {
            $0.localizedName == appName ||
            $0.bundleIdentifier == appName ||
            $0.bundleIdentifier?.hasSuffix(".\(appName)") == true ||
            $0.bundleURL?.deletingPathExtension().lastPathComponent == appName
        }) else {
            return false
        }
        target.activate(options: [.activateAllWindows])
        return true
    }

    private final class DispatchBox: Sendable {
        private let lock = NSLock()
        private nonisolated(unsafe) var _error: Error?
        private nonisolated(unsafe) var _completed = false

        func finish(with error: Error?) {
            lock.lock()
            defer { lock.unlock() }
            _error = error
            _completed = true
        }

        var isCompleted: Bool {
            lock.lock()
            defer { lock.unlock() }
            return _completed
        }

        var launchError: Error? {
            lock.lock()
            defer { lock.unlock() }
            return _error
        }
    }

    /// LaunchServices 비동기 호출 후 CFRunLoop 기반 안전 대기 (데드락 방지)
    private static func dispatchOpenApplication(
        at appURL: URL,
        arguments: [String],
        environment: [String: String]
    ) throws {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.arguments = arguments
        config.environment = environment

        let runLoop = CFRunLoopGetCurrent()
        let box = DispatchBox()

        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
            box.finish(with: error)
            guard let runLoop else { return }
            CFRunLoopStop(runLoop)
        }

        // 최대 3초간 RunLoop 구동
        let runLoopResult = CFRunLoopRunInMode(.defaultMode, 3.0, false)
        guard box.isCompleted || runLoopResult != .timedOut else {
            throw ActivationError.timedOut
        }

        guard let err = box.launchError else { return }
        throw ActivationError.activationFailed(err.localizedDescription)
    }

    /// 번들 식별자 및 표준 경로 기반 앱 URL 탐색 SSOT
    public static func resolveApplicationURL(named name: String) -> URL? {
        let ws = NSWorkspace.shared

        // 1. 번들 ID 직접 조회 (gujo.<name>, net.ranode.<name>, com.gujo.<name> 등)
        let prefixes = ["gujo.", "net.ranode.", "com.gujo.", ""]
        for prefix in prefixes {
            let bundleID = prefix.isEmpty ? name : "\(prefix)\(name)"
            if let url = ws.urlForApplication(withBundleIdentifier: bundleID) {
                return url
            }
        }

        // 2. 표준 애플리케이션 설치 디렉터리 탐색
        let fm = FileManager.default
        let homePath = NSHomeDirectory()
        let candidateDirs = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            homePath + "/Applications"
        ]

        let searchNames = [name, "\(name).app"]
        for dir in candidateDirs {
            for sName in searchNames {
                let candidate = URL(fileURLWithPath: dir).appendingPathComponent(sName)
                if fm.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        return nil
    }
    #endif
}
