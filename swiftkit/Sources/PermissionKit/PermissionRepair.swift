import Foundation

private func waitWithTimeout(_ process: Process, seconds: TimeInterval = 30) {
    let item = DispatchWorkItem { process.terminate() }
    DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: item)
    process.waitUntilExit()
    item.cancel()
}

/// `Permission.repair` 결과 — 앱 UI 가 “안 되면 이렇게” 대신 상태만 보여 준다.
public struct PermissionRepairReport: Sendable, Equatable {
    public enum Phase: String, Sendable, Equatable {
        /// 이미 이 프로세스에 권한이 있음.
        case alreadyGranted
        /// 옛 TCC 항목을 지우고 재요청·설정 오픈까지 진행함.
        case clearedStaleAndPrompted
        /// tccutil 실패(권한/환경) — 그래도 요청·설정은 열었음.
        case promptOnly
        /// 지원하지 않는 권한 타입.
        case unsupported
    }

    public let phase: Phase
    public let granted: Bool
    public let resetAttempted: Bool
    public let resetSucceeded: Bool
    public let service: TCCService?
    public let detail: String

    public init(
        phase: Phase,
        granted: Bool,
        resetAttempted: Bool,
        resetSucceeded: Bool,
        service: TCCService? = nil,
        detail: String
    ) {
        self.phase = phase
        self.granted = granted
        self.resetAttempted = resetAttempted
        self.resetSucceeded = resetSucceeded
        self.service = service
        self.detail = detail
    }
}

// MARK: - tccutil runner (테스트 주입 가능)

/// `/usr/bin/tccutil` 실행 계약 — mac-permissions-manager 테스트가 mock 한다.
public protocol TCCUtilRunning: Sendable {
    /// - Returns: process termination status (0 = success).
    func runTCCUtil(arguments: [String]) -> Int32
}

public struct ProcessTCCUtilRunner: TCCUtilRunning {
    public init() {}

    public func runTCCUtil(arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            waitWithTimeout(process, seconds: 10)
            return process.terminationStatus
        } catch {
            return 127
        }
    }
}

/// Apple 공식 TCC 재설정 명령의 얇은 래퍼 (PermissionKit + mac-permissions-manager SSOT).
/// reset 은 허용을 자동 부여하지 않고, 해당 앱의 결정을 지워 다음 요청 때 다시 묻게 한다.
public enum TCCUtil {
    /// 기본 러너(실기기). 테스트에서 `runner` 인자로 교체.
    nonisolated(unsafe) public static var defaultRunner: any TCCUtilRunning = ProcessTCCUtilRunner()

    /// Own-bundle(또는 지정 번들) TCC 항목을 지운다. 재서명 후 남는 옛 csreq 줄 정리.
    @discardableResult
    public static func reset(
        service: TCCService,
        bundleID: String,
        runner: (any TCCUtilRunning)? = nil
    ) -> Bool {
        guard !bundleID.isEmpty else { return false }
        let r = runner ?? defaultRunner
        let status = r.runTCCUtil(arguments: ["reset", service.tccutilName, bundleID])
        return status == 0
    }

    /// 인자만 생성(단위 테스트·드라이런). 실제 실행 없음.
    public static func resetArguments(service: TCCService, bundleID: String) -> [String] {
        ["reset", service.tccutilName, bundleID]
    }
}

/// 하위 호환 별칭 — 예전 `TCCUtilService.screenCapture` 스타일.
@available(*, deprecated, renamed: "TCCService")
public typealias TCCUtilService = TCCService
