import Foundation
@testable import VPNKit

struct FixedInventory: VPNServiceInventoryProviding {
    let value: [VPNService]

    init(_ value: [VPNService]) {
        self.value = value
    }

    func services() async -> [VPNService] {
        value
    }
}

struct FixedResolver: VPNHostResolving {
    let value: Result<[String], VPNConnectivityFailure>

    init(_ value: Result<[String], VPNConnectivityFailure>) {
        self.value = value
    }

    func addresses(for host: String) async -> Result<[String], VPNConnectivityFailure> {
        value
    }
}

struct FixedRoute: VPNRouteResolving {
    let value: Result<String, VPNConnectivityFailure>

    init(_ value: Result<String, VPNConnectivityFailure>) {
        self.value = value
    }

    func interfaceName(to address: String) async -> Result<String, VPNConnectivityFailure> {
        value
    }
}

struct FixedTCP: VPNTCPProbing {
    let value: Bool

    init(_ value: Bool) {
        self.value = value
    }

    func canConnect(host: String, port: Int, timeoutSeconds: Double) async -> Bool {
        value
    }
}

actor RecordingTCP: VPNTCPProbing {
    let value: Bool
    private(set) var hosts: [String] = []

    init(_ value: Bool) {
        self.value = value
    }

    func canConnect(host: String, port: Int, timeoutSeconds: Double) async -> Bool {
        hosts.append(host)
        return value
    }
}

func connectedService(id: String, name: String = "VPN", interface: String?) -> VPNService {
    VPNService(
        id: id,
        name: name,
        providerBundleID: "test.provider",
        status: .connected,
        interfaceName: interface
    )
}

func makeProbe(
    services: [VPNService],
    interface: String,
    reachable: Bool
) -> VPNTargetProbe {
    VPNTargetProbe(
        inventory: FixedInventory(services),
        resolver: FixedResolver(.success(["10.0.0.8"])),
        route: FixedRoute(.success(interface)),
        tcp: FixedTCP(reachable)
    )
}

func reachableDiagnosis(path: VPNPath) -> VPNConnectivityDiagnosis {
    VPNConnectivityDiagnosis(
        target: VPNTarget(host: "10.0.0.8", port: 443, displayName: "Target"),
        reachable: true,
        path: path,
        failure: nil,
        checkedAt: Date(timeIntervalSince1970: 1)
    )
}

func unreachableDiagnosis() -> VPNConnectivityDiagnosis {
    VPNConnectivityDiagnosis(
        target: VPNTarget(host: "10.0.0.8", port: 443, displayName: "Target"),
        reachable: false,
        path: .unavailable,
        failure: .noRoute,
        checkedAt: Date(timeIntervalSince1970: 1)
    )
}
