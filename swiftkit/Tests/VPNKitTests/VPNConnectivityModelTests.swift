import CommandKit
import Foundation
import XCTest
@testable import VPNKit

@MainActor
final class VPNConnectivityModelTests: XCTestCase {
    func testAdoptOwnershipsKeepsExactEpochForReachableVPNPath() {
        let service = connectedService(
            id: "shared-vpn",
            interface: "utun8"
        )
        let diagnosis = reachableDiagnosis(path: .vpn(service: service))
        let adopted = VPNServiceOwnership(
            serviceID: service.id,
            epochID: UUID()
        )
        let unrelated = VPNServiceOwnership(
            serviceID: "other-vpn",
            epochID: UUID()
        )
        let model = VPNConnectivityModel(
            target: diagnosis.target,
            preferred: nil,
            diagnoser: SequenceDiagnoser([diagnosis]),
            inventory: FixedInventory([]),
            controller: RecordingController()
        )

        model.adoptServiceOwnerships(
            [adopted, unrelated],
            for: diagnosis
        )

        XCTAssertEqual(model.appStartedServiceOwnerships, [adopted])
    }

    func testSettledOwnershipsWaitsForInflightStartEpoch() async {
        let service = VPNService(
            id: "pending-vpn",
            name: "Pending VPN",
            providerBundleID: "test.provider",
            status: .disconnected,
            interfaceName: nil
        )
        let connected = connectedService(
            id: service.id,
            interface: "utun10"
        )
        let controller = ControlledController()
        let model = VPNConnectivityModel(
            target: reachableDiagnosis(
                path: .vpn(service: connected)
            ).target,
            preferred: nil,
            diagnoser: SequenceDiagnoser([
                reachableDiagnosis(path: .vpn(service: connected))
            ]),
            inventory: FixedInventory([service]),
            controller: controller
        )

        let connect = Task {
            await model.connect(serviceID: service.id)
        }
        for _ in 0..<1_000 {
            if await controller.actionCount() == 1 {
                break
            }
            await Task.yield()
        }
        let actionCount = await controller.actionCount()
        XCTAssertEqual(actionCount, 1)
        let settled = Task {
            await model.settledServiceOwnerships()
        }
        await Task.yield()

        _ = await controller.resume(requestID: 0, with: .success)
        await connect.value
        let ownerships = await settled.value

        XCTAssertEqual(ownerships, model.appStartedServiceOwnerships)
        XCTAssertEqual(ownerships.map(\.serviceID), [service.id])
    }

    func testDiagnosePublishesConnectedPhase() async {
        let diagnosis = reachableDiagnosis(path: .direct(interface: "en0"))
        let controller = RecordingController()
        let model = VPNConnectivityModel(
            target: diagnosis.target,
            preferred: nil,
            diagnoser: SequenceDiagnoser([diagnosis]),
            inventory: FixedInventory([]),
            controller: controller
        )

        await model.diagnose()

        XCTAssertEqual(model.phase, .connected(diagnosis))
        let started = await controller.startedServices()
        XCTAssertEqual(started, [])
    }

    func testConnectStartsDisconnectedServiceThenOwnsAndRediagnosesTarget() async {
        let service = VPNService(
            id: "vpn",
            name: "VPN",
            providerBundleID: "test.provider",
            status: .disconnected,
            interfaceName: nil
        )
        let failed = unreachableDiagnosis()
        let connected = connectedService(id: service.id, interface: "utun5")
        let success = reachableDiagnosis(path: .vpn(service: connected))
        let controller = RecordingController()
        let model = VPNConnectivityModel(
            target: failed.target,
            preferred: .init(serviceID: service.id, displayName: service.name),
            diagnoser: SequenceDiagnoser([failed, success]),
            inventory: FixedInventory([service]),
            controller: controller
        )

        await model.diagnose()
        await model.connect(serviceID: service.id)

        let started = await controller.startedServices()
        XCTAssertEqual(started, [service.id])
        XCTAssertEqual(model.appStartedServiceIDs, [service.id])
        XCTAssertEqual(
            model.appStartedServiceOwnerships.map(\.serviceID),
            [service.id]
        )
        XCTAssertEqual(model.phase, .connected(success))
    }

    func testConnectDoesNotStartOrOwnAlreadyConnectedService() async {
        let cached = VPNService(
            id: "vpn",
            name: "VPN",
            providerBundleID: "test.provider",
            status: .disconnected,
            interfaceName: nil
        )
        let service = connectedService(id: "vpn", interface: "utun5")
        let failed = unreachableDiagnosis()
        let success = reachableDiagnosis(path: .vpn(service: service))
        let controller = RecordingController()
        let model = VPNConnectivityModel(
            target: success.target,
            preferred: nil,
            diagnoser: SequenceDiagnoser([failed, success]),
            inventory: SequenceInventory([
                [cached],
                [service],
                [service],
            ]),
            controller: controller
        )

        await model.diagnose()
        await model.connect(serviceID: service.id)

        let started = await controller.startedServices()
        XCTAssertEqual(started, [])
        XCTAssertEqual(model.appStartedServiceIDs, [])
        XCTAssertTrue(model.appStartedServiceOwnerships.isEmpty)
        XCTAssertEqual(model.phase, .connected(success))
    }

    func testFailedDiagnosisSuggestsAvailableServiceWhenPreferenceIsMissing() async {
        let service = connectedService(id: "available", name: "Available", interface: nil)
        let failed = unreachableDiagnosis()
        let model = VPNConnectivityModel(
            target: failed.target,
            preferred: .init(serviceID: "missing", displayName: "Missing"),
            diagnoser: SequenceDiagnoser([failed]),
            inventory: FixedInventory([service]),
            controller: RecordingController()
        )

        await model.diagnose()

        guard case .recovery(let context) = model.phase else {
            return XCTFail("Expected recovery phase")
        }
        XCTAssertEqual(context.services, [service])
        XCTAssertEqual(context.preferred, model.preferred)
        XCTAssertEqual(context.selectedServiceID, service.id)
    }

    func testFailedStartUsesFreshConnectInventoryForRecovery() async {
        let failed = unreachableDiagnosis()
        let stale = connectedService(id: "stale", name: "Stale", interface: "utun5")
        let service = VPNService(
            id: "vpn",
            name: "Available",
            providerBundleID: "test.provider",
            status: .disconnected,
            interfaceName: nil
        )
        let controller = RecordingController(
            startResult: .unsupported("Open this VPN in its provider app")
        )
        let model = VPNConnectivityModel(
            target: failed.target,
            preferred: nil,
            diagnoser: SequenceDiagnoser([failed, failed]),
            inventory: SequenceInventory([[stale], [service]]),
            controller: controller
        )

        await model.diagnose()
        await model.connect(serviceID: service.id)

        XCTAssertEqual(model.appStartedServiceIDs, [])
        guard case .recovery(let context) = model.phase else {
            return XCTFail("Expected recovery phase")
        }
        XCTAssertEqual(context.services, [service])
        XCTAssertEqual(context.selectedServiceID, service.id)
        XCTAssertEqual(context.message, "Open this VPN in its provider app")
    }

    func testMissingServiceUsesFreshConnectInventoryForRecovery() async {
        let failed = unreachableDiagnosis()
        let stale = connectedService(id: "removed", name: "Removed", interface: "utun5")
        let available = connectedService(
            id: "available",
            name: "Available",
            interface: "utun6"
        )
        let controller = RecordingController()
        let model = VPNConnectivityModel(
            target: failed.target,
            preferred: .init(serviceID: stale.id, displayName: stale.name),
            diagnoser: SequenceDiagnoser([failed, failed]),
            inventory: SequenceInventory([[stale], [available]]),
            controller: controller
        )

        await model.diagnose()
        await model.connect(serviceID: stale.id)

        let started = await controller.startedServices()
        XCTAssertEqual(started, [])
        guard case .recovery(let context) = model.phase else {
            return XCTFail("Expected recovery phase")
        }
        XCTAssertEqual(context.services, [available])
        XCTAssertEqual(context.selectedServiceID, available.id)
        XCTAssertEqual(context.message, "VPN service not found: \(stale.id)")
    }

    func testFailedStartDuringNewerDiagnosisPublishesRecoveryMessage() async {
        let service = VPNService(
            id: "vpn",
            name: "VPN",
            providerBundleID: "test.provider",
            status: .disconnected,
            interfaceName: nil
        )
        let failed = unreachableDiagnosis()
        let olderSuccess = reachableDiagnosis(path: .direct(interface: "en0"))
        let diagnoser = ControlledDiagnoser()
        let controller = ControlledController()
        let model = VPNConnectivityModel(
            target: failed.target,
            preferred: nil,
            diagnoser: diagnoser,
            inventory: FixedInventory([service]),
            controller: controller
        )

        let connectTask = Task { await model.connect(serviceID: service.id) }
        await waitForControlActions(controller, count: 1)
        let diagnoseTask = Task { await model.diagnose() }
        await waitForDiagnosisRequests(diagnoser, count: 1)

        let resumedStart = await resumeControl(
            controller,
            requestID: 0,
            result: .failed("start denied")
        )
        XCTAssertTrue(resumedStart)
        await waitForDiagnosisRequests(diagnoser, count: 2)

        let resumedOlder = await diagnoser.resume(requestID: 0, with: olderSuccess)
        XCTAssertTrue(resumedOlder)
        await diagnoseTask.value
        let resumedRecovery = await diagnoser.resume(requestID: 1, with: failed)
        XCTAssertTrue(resumedRecovery)
        await connectTask.value

        guard case .recovery(let context) = model.phase else {
            return XCTFail("Expected recovery phase")
        }
        XCTAssertEqual(context.diagnosis, failed)
        XCTAssertEqual(context.services, [service])
        XCTAssertEqual(context.message, "start denied")
    }

    func testFailedStopDuringNewerDiagnosisPublishesRecoveryMessage() async {
        let service = connectedService(id: "vpn", interface: "utun5")
        let failed = unreachableDiagnosis()
        let olderSuccess = reachableDiagnosis(path: .direct(interface: "en0"))
        let diagnoser = ControlledDiagnoser()
        let controller = ControlledController()
        let model = VPNConnectivityModel(
            target: failed.target,
            preferred: nil,
            diagnoser: diagnoser,
            inventory: FixedInventory([service]),
            controller: controller
        )

        let disconnectTask = Task { await model.disconnect(serviceID: service.id) }
        await waitForControlActions(controller, count: 1)
        let diagnoseTask = Task { await model.diagnose() }
        await waitForDiagnosisRequests(diagnoser, count: 1)

        let resumedStop = await resumeControl(
            controller,
            requestID: 0,
            result: .failed("stop denied")
        )
        XCTAssertTrue(resumedStop)
        await waitForDiagnosisRequests(diagnoser, count: 2)

        let resumedOlder = await diagnoser.resume(requestID: 0, with: olderSuccess)
        XCTAssertTrue(resumedOlder)
        await diagnoseTask.value
        let resumedRecovery = await diagnoser.resume(requestID: 1, with: failed)
        XCTAssertTrue(resumedRecovery)
        await disconnectTask.value

        guard case .recovery(let context) = model.phase else {
            return XCTFail("Expected recovery phase")
        }
        XCTAssertEqual(context.diagnosis, failed)
        XCTAssertEqual(context.services, [service])
        XCTAssertEqual(context.message, "stop denied")
    }

    func testApplyFailureEventuallyPopulatesRecoveryServicesAndSelection() async {
        let diagnosis = unreachableDiagnosis()
        let service = connectedService(id: "available", name: "Available", interface: "utun5")
        let controller = RecordingController()
        let inventory = ControlledInventory()
        let model = VPNConnectivityModel(
            target: diagnosis.target,
            preferred: .init(serviceID: "missing", displayName: "Missing"),
            diagnoser: SequenceDiagnoser([diagnosis]),
            inventory: inventory,
            controller: controller
        )

        model.apply(diagnosis)
        await waitForInventoryRequests(inventory, count: 1)
        let resumed = await inventory.resume(requestID: 0, with: [service])
        XCTAssertTrue(resumed)
        await waitUntil {
            guard case .recovery(let context) = model.phase else {
                return false
            }
            return context.services == [service]
        }

        guard case .recovery(let context) = model.phase else {
            return XCTFail("Expected recovery phase")
        }
        XCTAssertEqual(context.diagnosis, diagnosis)
        XCTAssertEqual(context.services, [service])
        XCTAssertEqual(context.selectedServiceID, service.id)
        let started = await controller.startedServices()
        XCTAssertEqual(started, [])
    }

    func testOlderDiagnosisCannotOverwriteNewerDiagnosis() async {
        let older = unreachableDiagnosis()
        let newer = reachableDiagnosis(path: .direct(interface: "en0"))
        let diagnoser = ControlledDiagnoser()
        let model = VPNConnectivityModel(
            target: older.target,
            preferred: nil,
            diagnoser: diagnoser,
            inventory: FixedInventory([]),
            controller: RecordingController()
        )

        let olderTask = Task { await model.diagnose() }
        await waitForDiagnosisRequests(diagnoser, count: 1)
        let newerTask = Task { await model.diagnose() }
        await waitForDiagnosisRequests(diagnoser, count: 2)

        let resumedNewer = await diagnoser.resume(requestID: 1, with: newer)
        XCTAssertTrue(resumedNewer)
        await newerTask.value
        let resumedOlder = await diagnoser.resume(requestID: 0, with: older)
        XCTAssertTrue(resumedOlder)
        await olderTask.value

        XCTAssertEqual(model.phase, .connected(newer))
    }

    func testOlderConnectRediagnosisCannotOverwriteNewerDiagnosis() async {
        let service = VPNService(
            id: "vpn",
            name: "VPN",
            providerBundleID: "test.provider",
            status: .disconnected,
            interfaceName: nil
        )
        let older = unreachableDiagnosis()
        let newer = reachableDiagnosis(path: .direct(interface: "en0"))
        let diagnoser = ControlledDiagnoser()
        let model = VPNConnectivityModel(
            target: older.target,
            preferred: nil,
            diagnoser: diagnoser,
            inventory: FixedInventory([service]),
            controller: RecordingController()
        )

        let connectTask = Task { await model.connect(serviceID: service.id) }
        await waitForDiagnosisRequests(diagnoser, count: 1)
        let newerTask = Task { await model.diagnose() }
        await waitForDiagnosisRequests(diagnoser, count: 2)

        let resumedNewer = await diagnoser.resume(requestID: 1, with: newer)
        XCTAssertTrue(resumedNewer)
        await newerTask.value
        let resumedOlder = await diagnoser.resume(requestID: 0, with: older)
        XCTAssertTrue(resumedOlder)
        await connectTask.value

        XCTAssertEqual(model.phase, .connected(newer))
    }

    func testOlderDisconnectRediagnosisCannotOverwriteNewerDiagnosis() async {
        let older = unreachableDiagnosis()
        let newer = reachableDiagnosis(path: .direct(interface: "en0"))
        let diagnoser = ControlledDiagnoser()
        let controller = RecordingController()
        let model = VPNConnectivityModel(
            target: older.target,
            preferred: nil,
            diagnoser: diagnoser,
            inventory: FixedInventory([]),
            controller: controller
        )

        let disconnectTask = Task { await model.disconnect(serviceID: "vpn") }
        await waitForDiagnosisRequests(diagnoser, count: 1)
        let newerTask = Task { await model.diagnose() }
        await waitForDiagnosisRequests(diagnoser, count: 2)

        let resumedNewer = await diagnoser.resume(requestID: 1, with: newer)
        XCTAssertTrue(resumedNewer)
        await newerTask.value
        let resumedOlder = await diagnoser.resume(requestID: 0, with: older)
        XCTAssertTrue(resumedOlder)
        await disconnectTask.value

        XCTAssertEqual(model.phase, .connected(newer))
    }

    func testOlderApplyRecoveryRefreshCannotOverwriteNewerApply() async {
        let older = unreachableDiagnosis()
        let newer = reachableDiagnosis(path: .direct(interface: "en0"))
        let inventory = ControlledInventory()
        let model = VPNConnectivityModel(
            target: older.target,
            preferred: nil,
            diagnoser: SequenceDiagnoser([older]),
            inventory: inventory,
            controller: RecordingController()
        )

        model.apply(older)
        await waitForInventoryRequests(inventory, count: 1)
        model.apply(newer)
        let resumed = await inventory.resume(
            requestID: 0,
            with: [connectedService(id: "stale", interface: "utun5")]
        )
        XCTAssertTrue(resumed)
        await Task.yield()

        XCTAssertEqual(model.phase, .connected(newer))
    }

    func testObservationsDuringConnectInventoryAwaitDoNotCancelStart() async {
        let disconnected = VPNService(
            id: "vpn",
            name: "VPN",
            providerBundleID: "test.provider",
            status: .disconnected,
            interfaceName: nil
        )
        let connected = connectedService(id: disconnected.id, interface: "utun5")
        let diagnosis = reachableDiagnosis(path: .vpn(service: connected))
        let inventory = ControlledInventory()
        let diagnoser = RecordingDiagnoser(diagnosis)
        let controller = RecordingController()
        let model = VPNConnectivityModel(
            target: diagnosis.target,
            preferred: nil,
            diagnoser: diagnoser,
            inventory: inventory,
            controller: controller
        )

        let connectTask = Task { await model.connect(serviceID: disconnected.id) }
        await waitForInventoryRequests(inventory, count: 1)

        model.apply(reachableDiagnosis(path: .direct(interface: "en0")))
        let diagnoseTask = Task { await model.diagnose() }
        await waitForInventoryRequests(inventory, count: 2)
        let resumedObservationInventory = await resumeInventory(
            inventory,
            requestID: 1,
            services: [disconnected]
        )
        XCTAssertTrue(resumedObservationInventory)
        await diagnoseTask.value

        let resumedConnectInventory = await resumeInventory(
            inventory,
            requestID: 0,
            services: [disconnected]
        )
        XCTAssertTrue(resumedConnectInventory)
        await waitForInventoryRequests(inventory, count: 3)
        let resumedPostControlInventory = await resumeInventory(
            inventory,
            requestID: 2,
            services: [connected]
        )
        XCTAssertTrue(resumedPostControlInventory)
        await connectTask.value

        let started = await controller.startedServices()
        XCTAssertEqual(started, [disconnected.id])
        XCTAssertEqual(model.appStartedServiceIDs, [disconnected.id])
        let diagnosisCount = await diagnoser.diagnosisCount()
        XCTAssertEqual(diagnosisCount, 2)
    }

    func testControlQueuePreservesEffectsAndInvocationOrderAcrossObservations() async {
        let service = VPNService(
            id: "vpn",
            name: "VPN",
            providerBundleID: "test.provider",
            status: .disconnected,
            interfaceName: nil
        )
        let diagnosis = reachableDiagnosis(path: .direct(interface: "en0"))
        let diagnoser = RecordingDiagnoser(diagnosis)
        let controller = ControlledController()
        let model = VPNConnectivityModel(
            target: diagnosis.target,
            preferred: nil,
            diagnoser: diagnoser,
            inventory: FixedInventory([service]),
            controller: controller
        )

        let connectTask = Task { await model.connect(serviceID: service.id) }
        await waitForControlActions(controller, count: 1)
        model.apply(diagnosis)

        let disconnectTask = Task { await model.disconnect(serviceID: service.id) }
        for _ in 0..<100 {
            await Task.yield()
        }
        let actionCountBeforeStartCompletion = await controller.actionCount()
        XCTAssertEqual(actionCountBeforeStartCompletion, 1)

        let resumedStart = await resumeControl(
            controller,
            requestID: 0,
            result: .success
        )
        XCTAssertTrue(resumedStart)
        await waitForControlActions(controller, count: 2)
        XCTAssertEqual(model.appStartedServiceIDs, [service.id])

        await model.diagnose()
        let resumedStop = await resumeControl(
            controller,
            requestID: 1,
            result: .success
        )
        XCTAssertTrue(resumedStop)
        await connectTask.value
        await disconnectTask.value

        let actions = await controller.recordedActions()
        XCTAssertEqual(actions, [.start(service.id), .stop(service.id)])
        XCTAssertEqual(model.appStartedServiceIDs, [])
        let diagnosisCount = await diagnoser.diagnosisCount()
        XCTAssertEqual(diagnosisCount, 3)
    }

    private func waitForDiagnosisRequests(
        _ diagnoser: ControlledDiagnoser,
        count: Int
    ) async {
        for _ in 0..<1_000 {
            if await diagnoser.requestCount() >= count {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(count) diagnosis requests")
    }

    private func waitForInventoryRequests(
        _ inventory: ControlledInventory,
        count: Int
    ) async {
        for _ in 0..<1_000 {
            if await inventory.requestCount() >= count {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(count) inventory requests")
    }

    private func waitForControlActions(
        _ controller: ControlledController,
        count: Int
    ) async {
        for _ in 0..<1_000 {
            if await controller.actionCount() >= count {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(count) control actions")
    }

    private func resumeInventory(
        _ inventory: ControlledInventory,
        requestID: Int,
        services: [VPNService]
    ) async -> Bool {
        await inventory.resume(requestID: requestID, with: services)
    }

    private func resumeControl(
        _ controller: ControlledController,
        requestID: Int,
        result: VPNControlResult
    ) async -> Bool {
        await controller.resume(requestID: requestID, with: result)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for model state")
    }
}

final class VPNServiceControllerTests: XCTestCase {
    actor Runner: CommandRunning {
        let result: CommandResult
        private var invocations: [(String, [String])] = []

        init(_ result: CommandResult) {
            self.result = result
        }

        func run(
            _ launchPath: String,
            _ arguments: [String],
            timeout: TimeInterval?
        ) async -> CommandResult {
            invocations.append((launchPath, arguments))
            return result
        }

        func recordedInvocations() -> [(String, [String])] {
            invocations
        }
    }

    func testStartExecutesScutilWithArgumentVector() async {
        #if os(macOS)
        let runner = Runner(.init(stdout: "", stderr: "", exitCode: 0))
        let controller = VPNServiceController(runner: runner)

        let result = await controller.start(serviceID: "service id")
        XCTAssertEqual(result, .success)

        let invocations = await runner.recordedInvocations()
        XCTAssertEqual(invocations.count, 1)
        XCTAssertEqual(invocations[0].0, "/usr/sbin/scutil")
        XCTAssertEqual(invocations[0].1, ["--nc", "start", "service id"])
        #endif
    }

    func testStopReportsUnsupportedControl() async {
        #if os(macOS)
        let runner = Runner(
            .init(stdout: "", stderr: "Operation not supported", exitCode: 1)
        )
        let controller = VPNServiceController(runner: runner)

        let result = await controller.stop(serviceID: "vpn")
        XCTAssertEqual(result, .unsupported("Operation not supported"))
        #endif
    }
}
