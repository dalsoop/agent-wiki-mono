import CommandKit
import Foundation
import InteropKit

/// 2026-10-31까지 유지하는 기존 VPN 게이트 어댑터.
/// 새 코드는 대상별 `VPNConnectivityModel`을 사용한다.
///
/// 사용 예(도달 실패 시):
///   if !reachable, let tunnel = requiredTunnel, await VPNGate().ensure(tunnel) { retry() }
public struct VPNGate: Sendable {
    private let inventory: any VPNServiceInventoryProviding
    private let controller: any VPNServiceControlling
    private let diagnoser: (any VPNConnectivityDiagnosing)?
    /// 다른 게이팅 CLI 로 바꿔 끼울 수 있게 실행 파일 후보를 주입 가능.
    private let candidates: [String]

    public init(
        runner: any CommandRunning = ProcessCommandRunner(),
        candidates: [String] = [
            HostPlatform.cliBinPath("vpn-wireguardctl"),
            "/usr/local/bin/vpn-wireguardctl",
            HostPlatform.cliBinPath("wireguardctl"),
            "/usr/local/bin/wireguardctl",
        ]
    ) {
        self.inventory = VPNSystemInventory(runner: runner)
        self.controller = VPNServiceController(runner: runner)
        self.diagnoser = nil
        self.candidates = candidates
    }

    public init(
        inventory: any VPNServiceInventoryProviding,
        controller: any VPNServiceControlling,
        candidates: [String] = [],
        diagnoser: (any VPNConnectivityDiagnosing)? = nil
    ) {
        self.inventory = inventory
        self.controller = controller
        self.diagnoser = diagnoser
        self.candidates = candidates
    }

    /// 기존 소비자의 소스 호환을 위해 남긴 레거시 CLI 탐색 결과.
    public func locate() -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public var systemControlAvailable: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// ID 또는 이름을 시스템 VPN 서비스로 해석하고 사용자의 명시적 호출에서만 시작한다.
    @discardableResult
    public func ensure(_ tunnel: String) async -> Bool {
        guard let service = await resolveService(tunnel) else {
            return false
        }
        guard !service.isConnected else {
            return true
        }
        return await controller.start(serviceID: service.id) == .success
    }

    /// 하나라도 연결된 터널이 있는지.
    public func anyActive() async -> Bool? {
        await inventory.services().contains(where: \.isConnected)
    }

    /// 현재 연결된 시스템 VPN 서비스 이름 목록.
    public func activeTunnels() async -> [String]? {
        await inventory.services()
            .filter(\.isConnected)
            .map(\.name)
    }

    /// 사용자의 명시적 호출에서만 ID 또는 이름으로 해석한 시스템 VPN을 중지한다.
    @discardableResult
    public func disconnect(_ tunnel: String) async -> Bool {
        guard let serviceID = await resolveServiceID(tunnel) else {
            return false
        }
        return await controller.stop(serviceID: serviceID) == .success
    }

    func resolveServiceID(_ identifier: String) async -> String? {
        await resolveService(identifier)?.id
    }

    func resolveService(_ identifier: String) async -> VPNService? {
        guard !identifier.isEmpty else {
            return nil
        }
        return await inventory.services().first(where: {
            $0.id == identifier || $0.name == identifier
        })
    }

    @MainActor
    func connectivityModel(
        target: VPNTarget,
        preferred: VPNServiceReference?
    ) -> VPNConnectivityModel {
        VPNConnectivityModel(
            target: target,
            preferred: preferred,
            diagnoser: diagnoser ?? VPNTargetProbe(inventory: inventory),
            inventory: inventory,
            controller: controller
        )
    }
}
