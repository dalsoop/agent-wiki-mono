import Foundation
import XCTest
@testable import VPNKit

final class VPNPresentationTests: XCTestCase {
    func testConnectedVPNSummaryUsesActualServiceWithoutServiceID() {
        let service = VPNService(
            id: "secret-service-uuid",
            name: "Office IKEv2",
            providerBundleID: "com.apple.ipsec",
            status: .connected,
            interfaceName: "utun7"
        )
        let presentation = VPNPresentation(language: .korean)

        let summary = presentation.summary(
            for: reachableDiagnosis(path: .vpn(service: service))
        )

        XCTAssertEqual(summary, "Office IKEv2 · com.apple.ipsec · utun7")
        XCTAssertFalse(summary.contains(service.id))
    }

    func testUnknownTunnelDoesNotInventVPNName() {
        let presentation = VPNPresentation(language: .korean)

        XCTAssertEqual(
            presentation.summary(
                for: reachableDiagnosis(
                    path: .unidentifiedTunnel(interface: "utun9")
                )
            ),
            "VPN형 경로 · utun9 · 서비스 이름 확인 불가"
        )
    }

    func testDirectPathIsLabeledHonestly() {
        let presentation = VPNPresentation(language: .korean)

        XCTAssertEqual(
            presentation.summary(
                for: reachableDiagnosis(path: .direct(interface: "en0"))
            ),
            "직접 연결 · en0"
        )
    }

    func testKoreanConnectedTitleNamesTarget() {
        let presentation = VPNPresentation(language: .korean)

        XCTAssertEqual(
            presentation.title(
                for: reachableDiagnosis(path: .direct(interface: "en0"))
            ),
            "Target에 연결됨"
        )
    }

    func testEnglishPresentationCanBeInjectedIndependentlyOfSystemLanguage() {
        let presentation = VPNPresentation(language: .english)
        let diagnosis = reachableDiagnosis(
            path: .unidentifiedTunnel(interface: "utun9")
        )

        XCTAssertEqual(presentation.title(for: diagnosis), "Connected to Target")
        XCTAssertEqual(
            presentation.summary(for: diagnosis),
            "VPN-like route · utun9 · service name unavailable"
        )
    }

    func testRecoveryMessagesDistinguishDNSNoRouteAndRouteMismatch() {
        let presentation = VPNPresentation(language: .korean)
        let active = connectedService(
            id: "vpn-id",
            name: "Office",
            interface: "utun7"
        )

        XCTAssertEqual(
            presentation.recoveryMessage(for: .dnsResolutionFailed),
            "대상의 주소를 찾을 수 없습니다. DNS 설정과 호스트 이름을 확인하세요."
        )
        XCTAssertEqual(
            presentation.recoveryMessage(for: .noRoute),
            "대상까지의 네트워크 경로가 없습니다. 연결할 VPN을 선택해 다시 확인하세요."
        )
        XCTAssertEqual(
            presentation.recoveryMessage(
                for: .routeDoesNotUseConnectedVPN(activeServices: [active])
            ),
            "VPN은 연결되어 있지만 대상 경로에는 사용되지 않습니다. 다른 VPN을 선택하세요."
        )
    }

    func testRoutedVPNPortFailureDirectsUserToServerAndPortNotAnotherVPN() {
        let service = connectedService(
            id: "vpn-id",
            name: "Office",
            interface: "utun7"
        )
        let presentation = VPNPresentation(language: .korean)

        let message = presentation.recoveryMessage(
            for: .targetDidNotRespond(path: .vpn(service: service))
        )

        XCTAssertEqual(
            message,
            "VPN 경로는 확인됐지만 대상 서버·포트가 응답하지 않습니다. 서버, 방화벽, 포트를 확인하세요."
        )
        XCTAssertFalse(message.contains("다른 VPN"))
    }

    func testIdleDisconnectSettingIsLocalized() {
        XCTAssertEqual(
            VPNPresentation(language: .korean).localized(
                "settings.disconnect_when_idle"
            ),
            "유휴 시 VPN 연결 해제"
        )
        XCTAssertEqual(
            VPNPresentation(language: .english).localized(
                "settings.disconnect_when_idle"
            ),
            "Disconnect VPN when idle"
        )
    }

    func testGenericUnavailableRecoveryIsLocalizedWithoutInternalDetails() {
        let korean = VPNPresentation(language: .korean)
            .recoveryMessage(for: .diagnosisUnavailable(""))
        let english = VPNPresentation(language: .english)
            .recoveryMessage(for: .diagnosisUnavailable(""))

        XCTAssertEqual(
            korean,
            "연결 상태를 확인하지 못했습니다. 다시 진단하거나 앱에서 연결을 다시 시도하세요."
        )
        XCTAssertEqual(
            english,
            "The connection status could not be checked. Diagnose again or retry the connection in the app."
        )
        XCTAssertFalse(korean.contains("VPNGateModel"))
        XCTAssertFalse(english.contains("VPNGateModel"))
    }

    func testNoAlternativeVPNGuidanceIsLocalized() {
        XCTAssertEqual(
            VPNPresentation(language: .korean).localized(
                "recovery.no_alternative_vpn"
            ),
            "현재 연결된 VPN은 대상 경로에 사용되지 않으며 시도할 다른 VPN이 없습니다. 시스템 설정에서 다른 VPN을 추가하거나 연결 상태를 확인하세요."
        )
        XCTAssertEqual(
            VPNPresentation(language: .english).localized(
                "recovery.no_alternative_vpn"
            ),
            "The connected VPN is not used for the target route, and no other VPN is available. Add another VPN in System Settings or check the connection."
        )
    }
}

final class VPNRecoverySelectionPolicyTests: XCTestCase {
    func testRouteMismatchExcludesActiveVPNFromCandidatesAndSuggestion() {
        let active = connectedService(
            id: "active",
            name: "Active",
            interface: "utun7"
        )
        let alternative = VPNService(
            id: "alternative",
            name: "Alternative",
            providerBundleID: "test.provider",
            status: .disconnected,
            interfaceName: nil
        )
        let context = routeMismatchContext(
            services: [active, alternative],
            active: [active],
            preferred: .init(
                serviceID: active.id,
                displayName: active.name
            )
        )

        let policy = VPNRecoverySelectionPolicy(context: context)

        XCTAssertEqual(policy.candidates.map(\.id), [alternative.id])
        XCTAssertEqual(policy.suggestedServiceID, alternative.id)
        XCTAssertEqual(policy.availability, .available)
        XCTAssertFalse(policy.permitsConnection(to: active.id))
        XCTAssertTrue(policy.permitsConnection(to: alternative.id))
    }

    func testRouteMismatchWithoutAlternativeHasNoSuggestionOrCTA() {
        let active = connectedService(
            id: "active",
            name: "Active",
            interface: "utun7"
        )
        let context = routeMismatchContext(
            services: [active],
            active: [active],
            preferred: .init(
                serviceID: active.id,
                displayName: active.name
            )
        )

        let policy = VPNRecoverySelectionPolicy(context: context)

        XCTAssertEqual(policy.candidates, [])
        XCTAssertNil(policy.suggestedServiceID)
        XCTAssertEqual(policy.availability, .noAlternativeVPN)
        XCTAssertFalse(policy.permitsConnection(to: active.id))
    }

    func testSelectionRevalidatesWhenCandidateDisappearsButSuggestionIsSame() {
        let serviceA = VPNService(
            id: "A",
            name: "A",
            providerBundleID: "test.provider",
            status: .disconnected,
            interfaceName: nil
        )
        let serviceB = VPNService(
            id: "B",
            name: "B",
            providerBundleID: "test.provider",
            status: .disconnected,
            interfaceName: nil
        )
        let preferred = VPNServiceReference(
            serviceID: serviceA.id,
            displayName: serviceA.name
        )
        let initial = VPNRecoverySelectionPolicy(
            context: noRouteContext(
                services: [serviceA, serviceB],
                preferred: preferred
            )
        )
        let refreshed = VPNRecoverySelectionPolicy(
            context: noRouteContext(
                services: [serviceA],
                preferred: preferred
            )
        )

        XCTAssertEqual(initial.suggestedServiceID, serviceA.id)
        XCTAssertEqual(initial.revalidatedSelection("B"), "B")
        XCTAssertEqual(refreshed.suggestedServiceID, serviceA.id)
        XCTAssertNotEqual(initial.snapshot, refreshed.snapshot)
        XCTAssertEqual(refreshed.revalidatedSelection("B"), "A")
        XCTAssertFalse(refreshed.permitsConnection(to: "B"))
    }

    private func routeMismatchContext(
        services: [VPNService],
        active: [VPNService],
        preferred: VPNServiceReference?
    ) -> VPNRecoveryContext {
        VPNRecoveryContext(
            diagnosis: VPNConnectivityDiagnosis(
                target: VPNTarget(
                    host: "10.0.0.8",
                    port: 443,
                    displayName: "Target"
                ),
                reachable: false,
                path: .direct(interface: "en0"),
                failure: .routeDoesNotUseConnectedVPN(
                    activeServices: active
                ),
                checkedAt: Date(timeIntervalSince1970: 1)
            ),
            services: services,
            preferred: preferred,
            selectedServiceID: preferred?.serviceID,
            message: nil
        )
    }

    private func noRouteContext(
        services: [VPNService],
        preferred: VPNServiceReference?
    ) -> VPNRecoveryContext {
        VPNRecoveryContext(
            diagnosis: unreachableDiagnosis(),
            services: services,
            preferred: preferred,
            selectedServiceID: preferred?.serviceID,
            message: nil
        )
    }
}

@MainActor
final class VPNRecoveryActionStateTests: XCTestCase {
    func testSecondActionDoesNotInvokeOperationWhileFirstIsRunning() async {
        let state = VPNRecoveryActionState()
        let operation = ControlledRecoveryAction()

        let first = Task {
            await state.perform {
                await operation.run()
            }
        }
        while await operation.callCount() == 0 {
            await Task.yield()
        }

        let secondWasStarted = await state.perform {
            await operation.run()
        }

        let callCount = await operation.callCount()
        XCTAssertFalse(secondWasStarted)
        XCTAssertEqual(callCount, 1)
        await operation.resume()
        let firstWasStarted = await first.value
        XCTAssertTrue(firstWasStarted)
        XCTAssertFalse(state.isInProgress)
    }
}

@MainActor
final class VPNConnectivityInventoryPresentationTests: XCTestCase {
    func testSuccessfulDiagnosisKeepsSystemVPNsAvailableForSettingsPicker() async {
        let service = connectedService(
            id: "vpn-id",
            name: "Office",
            interface: "utun7"
        )
        let diagnosis = reachableDiagnosis(path: .direct(interface: "en0"))
        let model = VPNConnectivityModel(
            target: diagnosis.target,
            preferred: nil,
            diagnoser: SequenceDiagnoser([diagnosis]),
            inventory: FixedInventory([service]),
            controller: RecordingController()
        )

        await model.diagnose()

        XCTAssertEqual(model.availableServices, [service])
    }
}

private actor ControlledRecoveryAction {
    private var calls = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func run() async {
        calls += 1
        await withCheckedContinuation {
            continuation = $0
        }
    }

    func callCount() -> Int {
        calls
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
