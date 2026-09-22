import XCTest
import CommandKit
@testable import VPNKit

final class VPNGateTests: XCTestCase {
    func testEnsureEmptyTunnelIsFalse() async {
        let gate = VPNGate(
            inventory: FixedInventory([]),
            controller: RecordingController(),
            candidates: ["/bin/sh"]
        )
        let ok = await gate.ensure("")
        XCTAssertFalse(ok)
    }

    func testEnsureResolvesNameAndStartsSystemServiceID() async {
        let service = VPNService(
            id: "service-id",
            name: "pve",
            providerBundleID: "test.provider",
            status: .disconnected,
            interfaceName: nil
        )
        let controller = RecordingController()
        let gate = VPNGate(
            inventory: FixedInventory([service]),
            controller: controller,
            candidates: ["/nonexistent"]
        )

        let ok = await gate.ensure(service.name)

        XCTAssertTrue(ok)
        let started = await controller.startedServices()
        XCTAssertEqual(started, [service.id])
    }

    func testEnsureDoesNotRestartConnectedSystemService() async {
        let service = connectedService(id: "service-id", name: "pve", interface: "utun5")
        let controller = RecordingController()
        let gate = VPNGate(
            inventory: FixedInventory([service]),
            controller: controller
        )

        let ok = await gate.ensure(service.id)

        XCTAssertTrue(ok)
        let started = await controller.startedServices()
        XCTAssertEqual(started, [])
    }

    func testActiveTunnelsUsesConnectedSystemServices() async {
        let connected = connectedService(id: "connected", name: "Connected", interface: "utun5")
        let disconnected = VPNService(
            id: "disconnected",
            name: "Disconnected",
            providerBundleID: "test.provider",
            status: .disconnected,
            interfaceName: nil
        )
        let gate = VPNGate(
            inventory: FixedInventory([connected, disconnected]),
            controller: RecordingController(),
            candidates: []
        )

        let activeTunnels = await gate.activeTunnels()
        XCTAssertEqual(activeTunnels, [connected.name])
    }

    // `VPNGate.activeIdentifiers(cliJSON:scutilOutput:)` 는 VPNKit 가 시스템 VPN
    // inventory 로 리팩터링되면서 사라졌다(CLI JSON 경로 자체가 없어짐). 검사 의도는
    // "연결된 서비스에서 id 와 이름을 모두 뽑아낸다" 였으므로 현재 API 로 옮긴다.
    func testParseListExtractsConnectedServiceIDAndName() {
        let scutil = """
        Available network connection services in the current set (*=enabled):
        * (Connected) AC17EE48-D976-47F4-A9ED-F6085F11D04C VPN (com.wireguard.macos) "jeonghan.yun mac 14 m1 max 64gb" [VPN:com.wireguard.macos]
        * (Disconnected) 2E67CA98-0F9D-4964-A04B-D72D9ECC97C0 VPN (net.ranode.wireguard) "other" [VPN:net.ranode.wireguard]
        """
        let services = VPNSystemInventory.parseList(scutil)
        XCTAssertEqual(services.count, 2)

        let connected = services.filter(\.isConnected)
        XCTAssertEqual(connected.map(\.id), ["AC17EE48-D976-47F4-A9ED-F6085F11D04C"])
        XCTAssertEqual(connected.map(\.name), ["jeonghan.yun mac 14 m1 max 64gb"])

        // 연결 안 된 것은 목록에는 남되 isConnected 가 false 여야 한다.
        XCTAssertEqual(services.filter { !$0.isConnected }.map(\.name), ["other"])
    }

    func testParseListIgnoresNonServiceLines() {
        XCTAssertTrue(VPNSystemInventory.parseList("""
        Available network connection services in the current set (*=enabled):
        (nothing here)
        """).isEmpty)
    }

}

@MainActor
@available(*, deprecated, message: "Legacy compatibility coverage through 2026-10-31")
final class VPNGateModelTests: XCTestCase {
    func testRequireSetsAndClears() {
        let m = VPNGateModel(gate: VPNGate(candidates: ["/nonexistent"]))
        m.require(tunnel: "pve", host: "h")
        XCTAssertTrue(m.isPending)
        XCTAssertEqual(m.pendingTunnel, "pve")
        XCTAssertEqual(m.equivalentCommand, "vpn-wireguardctl ensure pve")
        m.require(tunnel: nil, host: "h")     // 터널 없으면 프롬프트 없음
        XCTAssertFalse(m.isPending)
        m.require(tunnel: "", host: "h")       // 빈 문자열도 없음
        XCTAssertFalse(m.isPending)
    }
    func testGateAvailabilityReflectsPlatformControl() {
        #if os(macOS)
        XCTAssertTrue(VPNGateModel(gate: VPNGate(candidates: ["/nope"])).gateAvailable)
        #else
        XCTAssertFalse(VPNGateModel(gate: VPNGate(candidates: ["/bin/echo"])).gateAvailable)
        #endif
    }

    func testConnectTreatsAlreadyConnectedServiceAsNoOpSuccess() async {
        let service = connectedService(id: "vpn", name: "VPN", interface: "utun5")
        let diagnosis = reachableDiagnosis(path: .vpn(service: service))
        let controller = RecordingController()
        let gate = VPNGate(
            inventory: FixedInventory([service]),
            controller: controller,
            diagnoser: SequenceDiagnoser([diagnosis])
        )
        let model = VPNGateModel(gate: gate)
        let reloaded = expectation(description: "legacy reload callback")
        model.require(tunnel: service.id, host: diagnosis.target.host)

        model.connect {
            reloaded.fulfill()
        }
        await fulfillment(of: [reloaded], timeout: 1)

        let started = await controller.startedServices()
        XCTAssertEqual(started, [])
        XCTAssertFalse(model.isPending)
        XCTAssertEqual(model.connectivity?.appStartedServiceIDs, [])
    }

    func testCompatibilityViewCanConnectExplicitlySelectedSystemService() async {
        let service = VPNService(
            id: "selected-vpn",
            name: "Selected VPN",
            providerBundleID: "test.provider",
            status: .disconnected,
            interfaceName: nil
        )
        let diagnosis = unreachableDiagnosis()
        let controller = RecordingController()
        let gate = VPNGate(
            inventory: FixedInventory([service]),
            controller: controller,
            diagnoser: SequenceDiagnoser([diagnosis])
        )
        let model = VPNGateModel(gate: gate)
        let reloaded = expectation(description: "legacy reload callback")
        model.require(tunnel: "old-preference", host: diagnosis.target.host)

        model.connect(serviceID: service.id) {
            reloaded.fulfill()
        }
        await fulfillment(of: [reloaded], timeout: 1)

        let started = await controller.startedServices()
        XCTAssertEqual(started, [service.id])
        XCTAssertFalse(model.isPending)
    }

    func testLegacyRecoveryDoesNotExposeInternalModelName() {
        let model = VPNGateModel(
            gate: VPNGate(candidates: ["/nonexistent"])
        )

        model.require(tunnel: "legacy", host: "Target")

        guard case .recovery(let context) = model.connectivity?.phase,
              let failure = context.diagnosis.failure
        else {
            return XCTFail("Expected legacy recovery context")
        }
        let korean = VPNPresentation(language: .korean)
            .recoveryMessage(for: failure)
        let english = VPNPresentation(language: .english)
            .recoveryMessage(for: failure)
        XCTAssertFalse(korean.contains("Legacy"))
        XCTAssertFalse(korean.contains("VPNGateModel"))
        XCTAssertFalse(english.contains("Legacy"))
        XCTAssertFalse(english.contains("VPNGateModel"))
    }
}
