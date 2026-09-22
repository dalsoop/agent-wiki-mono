import CommandKit
import Foundation

public enum VPNControlResult: Equatable, Sendable {
    case success
    case cancelled
    case unsupported(String)
    case failed(String)
}

public protocol VPNServiceControlling: Sendable {
    func start(serviceID: String) async -> VPNControlResult
    func stop(serviceID: String) async -> VPNControlResult
}

public struct VPNServiceController: VPNServiceControlling, Sendable {
    private let runner: any CommandRunning

    public init(runner: any CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func start(serviceID: String) async -> VPNControlResult {
        await control(action: "start", serviceID: serviceID)
    }

    public func stop(serviceID: String) async -> VPNControlResult {
        await control(action: "stop", serviceID: serviceID)
    }

    private func control(action: String, serviceID: String) async -> VPNControlResult {
        #if os(macOS)
        let result = await runner.run(
            "/usr/sbin/scutil",
            ["--nc", action, serviceID]
        )
        guard !result.ok else {
            return .success
        }

        let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.localizedCaseInsensitiveContains("not supported") {
            return .unsupported(detail)
        }
        return .failed(
            detail.isEmpty
                ? "scutil --nc \(action) failed with exit code \(result.exitCode)"
                : detail
        )
        #else
        return .unsupported("VPN service control requires macOS")
        #endif
    }
}
