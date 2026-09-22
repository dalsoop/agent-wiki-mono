import XCTest
@testable import VPNKit

final class VPNTargetProbeTests: XCTestCase {
    func testReachableDirectIsSuccess() async {
        let probe = makeProbe(services: [], interface: "en0", reachable: true)

        let result = await probe.diagnose(
            .init(host: "example.test", port: 443, displayName: "Example")
        )

        XCTAssertTrue(result.reachable)
        XCTAssertEqual(result.path, .direct(interface: "en0"))
        XCTAssertNil(result.failure)
    }

    func testReachableThroughDifferentVPNIsSuccess() async {
        let vpn = VPNService(
            id: "actual",
            name: "official wg",
            providerBundleID: "com.wireguard.macos",
            status: .connected,
            interfaceName: "utun5"
        )
        let probe = VPNTargetProbe(
            inventory: FixedInventory([vpn]),
            resolver: FixedResolver(.success(["192.168.2.50"])),
            route: FixedRoute(.success("utun5")),
            tcp: FixedTCP(true)
        )

        let result = await probe.diagnose(
            .init(host: "pve", port: 8006, displayName: "Proxmox")
        )

        XCTAssertTrue(result.reachable)
        XCTAssertEqual(result.path, .vpn(service: vpn))
    }

    func testTCPUsesSameSelectedAddressAsRouteInspection() async {
        let target = VPNTarget(
            host: "multi-address.test",
            port: 443,
            displayName: "Multi-address API"
        )
        let tcp = RecordingTCP(true)
        let probe = VPNTargetProbe(
            inventory: FixedInventory([]),
            resolver: FixedResolver(
                .success(["192.0.2.10", "198.51.100.20"])
            ),
            route: FixedRoute(.success("en0")),
            tcp: tcp
        )

        let result = await probe.diagnose(target)
        let probedHosts = await tcp.hosts

        XCTAssertEqual(probedHosts, ["192.0.2.10"])
        XCTAssertEqual(result.target, target)
    }

    func testReachableUnknownUtunDoesNotInventService() async {
        let probe = makeProbe(services: [], interface: "utun9", reachable: true)

        let result = await probe.diagnose(
            .init(host: "10.0.0.8", port: 443, displayName: "API")
        )

        XCTAssertEqual(result.path, .unidentifiedTunnel(interface: "utun9"))
    }

    func testVPNRouteWithClosedPortIsTargetFailure() async {
        let vpn = connectedService(id: "v", interface: "utun5")
        let probe = makeProbe(services: [vpn], interface: "utun5", reachable: false)

        let result = await probe.diagnose(
            .init(host: "10.0.0.8", port: 443, displayName: "API")
        )

        XCTAssertEqual(result.failure, .targetDidNotRespond(path: .vpn(service: vpn)))
    }

    func testNoRouteIsReportedSeparately() async {
        let target = VPNTarget(host: "missing.test", port: 443, displayName: "Missing")
        let probe = VPNTargetProbe(
            inventory: FixedInventory([]),
            resolver: FixedResolver(.success(["203.0.113.1"])),
            route: FixedRoute(.failure(.noRoute)),
            tcp: FixedTCP(false)
        )

        let result = await probe.diagnose(target)

        XCTAssertFalse(result.reachable)
        XCTAssertEqual(result.path, .unavailable)
        XCTAssertEqual(result.failure, .noRoute)
    }

    func testDirectClosedPortWithConnectedVPNIsRouteMismatch() async {
        let vpn = connectedService(id: "v", interface: "utun5")
        let probe = makeProbe(services: [vpn], interface: "en0", reachable: false)

        let result = await probe.diagnose(
            .init(host: "10.0.0.8", port: 443, displayName: "API")
        )

        XCTAssertEqual(
            result.failure,
            .routeDoesNotUseConnectedVPN(activeServices: [vpn])
        )
    }

    func testDNSFailureRemainsDiagnosticFailure() async {
        let target = VPNTarget(host: "bad.test", port: 443, displayName: "Bad")
        let probe = VPNTargetProbe(
            inventory: FixedInventory([]),
            resolver: FixedResolver(.failure(.dnsResolutionFailed)),
            route: FixedRoute(.success("en0")),
            tcp: FixedTCP(false)
        )

        let result = await probe.diagnose(target)

        XCTAssertEqual(result.path, .unavailable)
        XCTAssertEqual(result.failure, .dnsResolutionFailed)
    }
}
