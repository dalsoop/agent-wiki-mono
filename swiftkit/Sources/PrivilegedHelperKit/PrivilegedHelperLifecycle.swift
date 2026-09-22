#if os(macOS)
import ServiceManagement
#endif

/// SMAppService.daemon 상태. ServiceManagement 를 테스트에 끌어오지 않기 위한 사본.
public enum PrivilegedHelperStatus: Equatable, Sendable {
    case enabled
    case requiresApproval
    case notRegistered
    case notFound
    case unknown
}

/// 등록된 쓰기 헬퍼(privileged launch daemon)에 다음에 할 일.
///
/// ping 이 되면 재등록하지 않는다. Sequoia 는 이미 `.enabled` 인 데몬에
/// `register()` 를 다시 치면 EPERM 을 반복한다.
public enum PrivilegedHelperNextStep: Equatable, Sendable {
    case done
    case register
    case waitAndPing
    case approveThenRegister
    case missingBundle
    /// SMAppService 와 launchd 가 어긋났거나, 응답하지 않는 옛 헬퍼가 자리를 차지함.
    /// unregister 후 register.
    case replaceStale
}

/// 앱별 XPC ping·plist 이름과 무관한 다음 단계 판정.
public enum PrivilegedHelperLifecycle {
    /// - Parameter occupied: mach 서비스를 누군가 잡고 있음(프로세스 경로 또는 XPC 연결).
    /// - Parameter waitAlreadyTried: `.enabled` 인데 ping 을 이미 기다렸음.
    public static func nextStep(
        pingOK: Bool,
        status: PrivilegedHelperStatus,
        occupied: Bool = false,
        waitAlreadyTried: Bool = false
    ) -> PrivilegedHelperNextStep {
        if pingOK {
            switch status {
            case .enabled, .requiresApproval:
                return .done
            case .notFound, .notRegistered, .unknown:
                return .register
            }
        }
        switch status {
        case .requiresApproval:
            return .approveThenRegister
        case .enabled:
            return waitAlreadyTried ? .replaceStale : .waitAndPing
        case .notFound:
            return occupied ? .replaceStale : .missingBundle
        case .notRegistered:
            return occupied ? .replaceStale : .register
        case .unknown:
            return occupied ? .replaceStale : .register
        }
    }
}

/// 테스트에서 SMAppService 를 대체한다.
public protocol PrivilegedHelperControlling: Sendable {
    var status: PrivilegedHelperStatus { get }
    func register() throws
    func unregister() async throws
}

public enum PrivilegedHelperError: Error, Equatable, Sendable {
    case stillEnabledAfterReplace
    case registerFailed(String)
}

#if os(macOS)
extension PrivilegedHelperStatus {
    public init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notRegistered: self = .notRegistered
        case .notFound: self = .notFound
        @unknown default: self = .unknown
        }
    }
}

/// `SMAppService.daemon(plistName:)`.
public struct SMAppServiceDaemon: PrivilegedHelperControlling {
    public let plistName: String

    public init(plistName: String) {
        self.plistName = plistName
    }

    private var service: SMAppService {
        SMAppService.daemon(plistName: plistName)
    }

    public var status: PrivilegedHelperStatus { PrivilegedHelperStatus(service.status) }

    public func register() throws {
        try service.register()
    }

    public func unregister() async throws {
        try await service.unregister()
    }

    public static func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
#endif
