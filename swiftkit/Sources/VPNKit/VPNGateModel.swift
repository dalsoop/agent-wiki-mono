import Foundation
import Observation

/// 내부망(VPN 뒤) 호스트 접속 앱 공용 VPN 게이트 상태.
/// **자동 연결하지 않는다** — 도달 실패 시 `require(tunnel:host:)` 로 프롬프트를 세우고,
/// 사용자가 `VPNPromptView` 의 [VPN 연결] 을 눌러 `connect(then:)` 로 진행한다.
///
/// 사용 (앱 AppModel):
///   let vpn = VPNGateModel()
///   // 조회 실패 시:
///   vpn.require(tunnel: card.requiredTunnel, host: "\(card.name) (\(card.host))")
///   // 성공 시: vpn.clear()
/// 뷰:
///   if vpn.isPending { VPNPromptView(model: vpn) { await reloadAfterConnect() } }
@MainActor
@Observable
@available(*, deprecated, message: "Use VPNConnectivityModel; compatibility ends after 2026-10-31")
public final class VPNGateModel {
    /// 켜야 하는 터널(이름/ID). nil 이면 프롬프트 없음.
    public private(set) var pendingTunnel: String?
    /// 프롬프트에 보여줄 대상 호스트 설명(예: "proxmox (root@10.0.50.1)").
    public private(set) var hostLabel: String = ""
    public private(set) var connecting = false
    public private(set) var lastError: String?
    public private(set) var connectivity: VPNConnectivityModel?

    private let gate: VPNGate
    public init(gate: VPNGate = VPNGate()) { self.gate = gate }

    public var isPending: Bool { pendingTunnel != nil }

    public var gateAvailable: Bool { gate.systemControlAvailable }

    /// 도달 실패 시 호출 — 터널이 있으면 프롬프트를 세운다(자동 연결 안 함). 없으면 클리어.
    public func require(tunnel: String?, host: String) {
        guard let t = tunnel, !t.isEmpty else {
            clear()
            return
        }
        pendingTunnel = t
        hostLabel = host
        let target = VPNTarget(host: host, port: 0, displayName: host)
        let model = gate.connectivityModel(
            target: target,
            preferred: .legacy(t)
        )
        model.apply(
            VPNConnectivityDiagnosis(
                target: target,
                reachable: false,
                path: .unavailable,
                failure: .diagnosisUnavailable(""),
                checkedAt: Date()
            )
        )
        connectivity = model
    }

    public func clear() {
        pendingTunnel = nil
        lastError = nil
        connectivity = nil
    }

    /// 사용자가 [VPN 연결] 을 눌렀을 때만 시스템 VPN을 시작하고 대상 상태를 재진단한다.
    public func connect(then reload: @escaping () -> Void) {
        guard let tunnel = pendingTunnel,
              let connectivity,
              !connecting
        else {
            return
        }
        connecting = true
        lastError = nil
        Task { [gate] in
            guard let service = await gate.resolveService(tunnel) else {
                self.connecting = false
                self.lastError = "VPN 연결 실패: \(tunnel) (시스템 VPN 서비스를 찾을 수 없음)"
                return
            }
            if await self.completeConnection(
                serviceID: service.id,
                failureLabel: tunnel,
                connectivity: connectivity
            ) {
                reload()
            }
        }
    }

    /// deprecated 복구 화면에서 사용자가 고른 시스템 VPN을 연결한다.
    func connect(serviceID: String, then reload: @escaping () -> Void) {
        Task {
            if await connect(serviceID: serviceID) {
                reload()
            }
        }
    }

    /// deprecated 복구 화면의 비동기 단일-flight 연결 어댑터.
    func connect(serviceID: String) async -> Bool {
        guard pendingTunnel != nil,
              let connectivity,
              !connecting
        else {
            return false
        }
        connecting = true
        lastError = nil
        return await completeConnection(
            serviceID: serviceID,
            failureLabel: serviceID,
            connectivity: connectivity
        )
    }

    private func completeConnection(
        serviceID: String,
        failureLabel: String,
        connectivity: VPNConnectivityModel
    ) async -> Bool {
        await connectivity.connect(serviceID: serviceID)
        connecting = false
        let refreshedService = await gate.resolveService(serviceID)
        let isConnected = connectivity.appStartedServiceIDs.contains(serviceID)
            || refreshedService?.isConnected == true
        if isConnected {
            pendingTunnel = nil
            return true
        } else {
            lastError = "VPN 연결 실패: \(failureLabel)"
            return false
        }
    }

    /// 프롬프트에 표시할, 사용자가 수동으로 칠 수 있는 동등 명령.
    public var equivalentCommand: String { pendingTunnel.map { "vpn-wireguardctl ensure \($0)" } ?? "" }
}
