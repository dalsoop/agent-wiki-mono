import XCTest
@testable import VPNKit

@MainActor
final class VPNDependencyCoordinatorTests: XCTestCase {
    func testRegistersActualServiceFromDiagnosis() {
        let coordinator = makeCoordinator()
        let actual = connectedService(id: "actual", interface: "utun5")

        coordinator.register(
            diagnosis: reachableDiagnosis(path: .vpn(service: actual)),
            resource: "pve",
            ownedServiceOwnerships: []
        )

        XCTAssertEqual(coordinator.resources(for: "actual"), ["pve"])
    }

    func testDirectAndUnidentifiedPathsDoNotCreateServiceDependencies() {
        let coordinator = makeCoordinator()

        coordinator.register(
            diagnosis: reachableDiagnosis(path: .direct(interface: "en0")),
            resource: "direct",
            ownedServiceOwnerships: []
        )
        coordinator.register(
            diagnosis: reachableDiagnosis(
                path: .unidentifiedTunnel(interface: "utun9")
            ),
            resource: "unidentified",
            ownedServiceOwnerships: []
        )

        XCTAssertTrue(coordinator.resources(for: "en0").isEmpty)
        XCTAssertTrue(coordinator.resources(for: "utun9").isEmpty)
    }

    func testPreexistingVPNWithoutOwnershipEpochIsNeverStopped() async {
        let controller = RecordingController()
        let coordinator = makeCoordinator(
            controller: controller,
            autoDisconnect: true
        )
        let vpn = connectedService(id: "preexisting", interface: "utun5")
        coordinator.register(
            diagnosis: reachableDiagnosis(path: .vpn(service: vpn)),
            resource: "mount",
            ownedServiceOwnerships: []
        )

        await coordinator.release(resource: "mount")

        let stopped = await controller.stoppedServices()
        XCTAssertTrue(stopped.isEmpty)
    }

    func testUnrelatedOwnershipEpochCannotStopPreexistingVPN() async {
        let controller = RecordingController()
        let coordinator = makeCoordinator(
            controller: controller,
            autoDisconnect: true
        )
        let vpn = connectedService(id: "preexisting", interface: "utun5")
        coordinator.register(
            diagnosis: reachableDiagnosis(path: .vpn(service: vpn)),
            resource: "mount",
            ownedServiceOwnerships: [ownership("arbitrary-service-id")]
        )

        await coordinator.release(resource: "mount")

        let stopped = await controller.stoppedServices()
        XCTAssertTrue(stopped.isEmpty)
    }

    func testDisconnectsOwnedVPNOnlyAfterLastResource() async {
        let controller = RecordingController()
        let coordinator = makeCoordinator(
            controller: controller,
            autoDisconnect: true
        )
        let vpn = connectedService(id: "owned", interface: "utun5")
        let diagnosis = reachableDiagnosis(path: .vpn(service: vpn))
        coordinator.register(
            diagnosis: diagnosis,
            resource: "mount-a",
            ownedServiceOwnerships: [ownership("owned")]
        )
        coordinator.register(
            diagnosis: diagnosis,
            resource: "mount-b",
            ownedServiceOwnerships: [ownership("owned")]
        )

        await coordinator.release(resource: "mount-a")
        var stopped = await controller.stoppedServices()
        XCTAssertTrue(stopped.isEmpty)

        await coordinator.release(resource: "mount-b")
        stopped = await controller.stoppedServices()
        XCTAssertEqual(stopped, ["owned"])
    }

    func testDoesNotDisconnectOwnedVPNWhenAutoDisconnectIsDisabled() async {
        let controller = RecordingController()
        let coordinator = makeCoordinator(controller: controller)
        let vpn = connectedService(id: "owned", interface: "utun5")
        coordinator.register(
            diagnosis: reachableDiagnosis(path: .vpn(service: vpn)),
            resource: "mount",
            ownedServiceOwnerships: [ownership("owned")]
        )

        await coordinator.release(resource: "mount")

        let stopped = await controller.stoppedServices()
        XCTAssertTrue(stopped.isEmpty)
    }

    func testSuccessfulAutoStopRetiresExactOwnershipEpoch() async {
        let controller = RecordingController()
        let coordinator = makeCoordinator(
            controller: controller,
            autoDisconnect: true
        )
        let service = connectedService(id: "owned", interface: "utun5")
        let diagnosis = reachableDiagnosis(path: .vpn(service: service))
        let firstEpoch = ownership(service.id)

        coordinator.register(
            diagnosis: diagnosis,
            resource: "first",
            ownedServiceOwnerships: [firstEpoch]
        )
        await coordinator.release(resource: "first")

        coordinator.register(
            diagnosis: diagnosis,
            resource: "externally-reconnected",
            ownedServiceOwnerships: [firstEpoch]
        )
        await coordinator.release(resource: "externally-reconnected")

        let stopped = await controller.stoppedServices()
        XCTAssertEqual(stopped, ["owned"])
    }

    func testSuccessfulStopRetiresEveryEpochOnReleasedDependency() async {
        let controller = RecordingController()
        let coordinator = makeCoordinator(
            controller: controller,
            autoDisconnect: true
        )
        let service = connectedService(id: "owned", interface: "utun5")
        let diagnosis = reachableDiagnosis(path: .vpn(service: service))
        let firstEpoch = ownership(service.id)
        let secondEpoch = ownership(service.id)
        let ownerships: Set<VPNServiceOwnership> = [
            firstEpoch,
            secondEpoch,
        ]

        coordinator.register(
            diagnosis: diagnosis,
            resource: "first",
            ownedServiceOwnerships: ownerships
        )
        await coordinator.release(resource: "first")

        coordinator.register(
            diagnosis: diagnosis,
            resource: "stale-replay",
            ownedServiceOwnerships: ownerships
        )
        await coordinator.release(resource: "stale-replay")

        let stopped = await controller.stoppedServices()
        XCTAssertEqual(stopped, ["owned"])
    }

    func testNewExplicitStartEpochCanOwnServiceAfterRetiredEpoch() async {
        let controller = RecordingController()
        let coordinator = makeCoordinator(
            controller: controller,
            autoDisconnect: true
        )
        let service = connectedService(id: "owned", interface: "utun5")
        let diagnosis = reachableDiagnosis(path: .vpn(service: service))
        let firstEpoch = VPNServiceOwnership(serviceID: service.id)

        coordinator.register(
            diagnosis: diagnosis,
            resource: "first",
            ownedServiceOwnerships: [firstEpoch]
        )
        await coordinator.release(resource: "first")

        coordinator.register(
            diagnosis: diagnosis,
            resource: "externally-reconnected",
            ownedServiceOwnerships: [firstEpoch]
        )
        await coordinator.release(resource: "externally-reconnected")

        let secondEpoch = VPNServiceOwnership(serviceID: service.id)
        coordinator.register(
            diagnosis: diagnosis,
            resource: "explicitly-restarted",
            ownedServiceOwnerships: [secondEpoch]
        )
        await coordinator.release(resource: "explicitly-restarted")

        let stopped = await controller.stoppedServices()
        XCTAssertEqual(stopped, ["owned", "owned"])
        XCTAssertNotEqual(firstEpoch, secondEpoch)
    }

    func testDroppedVPNKeepsResourceWhenDirectPathWorks() async {
        let alternate = reachableDiagnosis(path: .direct(interface: "en0"))
        let coordinator = makeCoordinator(
            diagnoser: SequenceDiagnoser([alternate])
        )
        let original = connectedService(id: "original", interface: "utun5")
        coordinator.register(
            diagnosis: reachableDiagnosis(path: .vpn(service: original)),
            resource: "mount",
            ownedServiceOwnerships: []
        )
        var lostCount = 0
        coordinator.onConnectivityLost = { _, _ in lostCount += 1 }

        await coordinator.checkConnectivity()

        XCTAssertEqual(lostCount, 0)
        XCTAssertTrue(coordinator.resources(for: "original").isEmpty)
    }

    func testDroppedVPNRemapsResourceToAlternateVPN() async {
        let alternate = connectedService(id: "alternate", interface: "utun7")
        let coordinator = makeCoordinator(
            diagnoser: SequenceDiagnoser([
                reachableDiagnosis(path: .vpn(service: alternate)),
            ])
        )
        let original = connectedService(id: "original", interface: "utun5")
        coordinator.register(
            diagnosis: reachableDiagnosis(path: .vpn(service: original)),
            resource: "mount",
            ownedServiceOwnerships: []
        )
        var lostCount = 0
        coordinator.onConnectivityLost = { _, _ in lostCount += 1 }

        await coordinator.checkConnectivity()

        XCTAssertEqual(lostCount, 0)
        XCTAssertTrue(coordinator.resources(for: "original").isEmpty)
        XCTAssertEqual(coordinator.resources(for: "alternate"), ["mount"])
    }

    func testAcceptedAlternatePathNotifiesExactResourcesAndDiagnosis() async {
        let alternate = reachableDiagnosis(
            path: .direct(interface: "en0")
        )
        let coordinator = makeCoordinator(
            diagnoser: SequenceDiagnoser([alternate])
        )
        let original = connectedService(id: "original", interface: "utun5")
        let originalDiagnosis = reachableDiagnosis(
            path: .vpn(service: original)
        )
        coordinator.register(
            diagnosis: originalDiagnosis,
            resource: "mount-b",
            ownedServiceOwnerships: []
        )
        coordinator.register(
            diagnosis: originalDiagnosis,
            resource: "mount-a",
            ownedServiceOwnerships: []
        )
        var changes: [(VPNTarget, [String], VPNConnectivityDiagnosis)] = []
        coordinator.onConnectivityPathChanged = {
            changes.append(($0, $1, $2))
        }

        await coordinator.checkConnectivity()

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.0, originalDiagnosis.target)
        XCTAssertEqual(changes.first?.1, ["mount-a", "mount-b"])
        XCTAssertEqual(changes.first?.2, alternate)
    }

    func testSamePathRediagnosisDoesNotNotifyPathChanged() async {
        let original = reachableDiagnosis(
            path: .direct(interface: "en0")
        )
        let refreshed = VPNConnectivityDiagnosis(
            target: original.target,
            reachable: true,
            path: original.path,
            failure: nil,
            checkedAt: Date(timeIntervalSince1970: 2)
        )
        let coordinator = makeCoordinator(
            diagnoser: SequenceDiagnoser([refreshed])
        )
        coordinator.register(
            diagnosis: original,
            resource: "mount",
            ownedServiceOwnerships: []
        )
        var changeCount = 0
        coordinator.onConnectivityPathChanged = { _, _, _ in
            changeCount += 1
        }

        await coordinator.checkConnectivity()

        XCTAssertEqual(changeCount, 0)
    }

    func testStaleAlternateDiagnosisDoesNotNotifyAfterReregistration() async {
        let diagnoser = ControlledDiagnoser()
        let coordinator = makeCoordinator(diagnoser: diagnoser)
        let original = connectedService(id: "original", interface: "utun5")
        coordinator.register(
            diagnosis: reachableDiagnosis(path: .vpn(service: original)),
            resource: "mount",
            ownedServiceOwnerships: []
        )
        var changeCount = 0
        coordinator.onConnectivityPathChanged = { _, _, _ in
            changeCount += 1
        }

        let check = Task { await coordinator.checkConnectivity() }
        await waitForDiagnosisRequests(diagnoser, count: 1)
        coordinator.register(
            diagnosis: reachableDiagnosis(path: .direct(interface: "en0")),
            resource: "mount",
            ownedServiceOwnerships: []
        )
        let resumed = await diagnoser.resume(
            requestID: 0,
            with: reachableDiagnosis(
                path: .unidentifiedTunnel(interface: "utun9")
            )
        )
        XCTAssertTrue(resumed)
        await check.value

        XCTAssertEqual(changeCount, 0)
    }

    func testOverlappingAlternateChecksOnlyNotifyNewestGeneration() async {
        let diagnoser = ControlledDiagnoser()
        let coordinator = makeCoordinator(diagnoser: diagnoser)
        let original = connectedService(id: "original", interface: "utun5")
        let originalDiagnosis = reachableDiagnosis(
            path: .vpn(service: original)
        )
        coordinator.register(
            diagnosis: originalDiagnosis,
            resource: "mount",
            ownedServiceOwnerships: []
        )
        var changes: [(VPNTarget, [String], VPNConnectivityDiagnosis)] = []
        coordinator.onConnectivityPathChanged = {
            changes.append(($0, $1, $2))
        }

        let first = Task { await coordinator.checkConnectivity() }
        await waitForDiagnosisRequests(diagnoser, count: 1)
        let second = Task { await coordinator.checkConnectivity() }
        await waitForDiagnosisRequests(diagnoser, count: 2)
        let newestDiagnosis = reachableDiagnosis(
            path: .direct(interface: "en0")
        )
        let resumedSecond = await diagnoser.resume(
            requestID: 1,
            with: newestDiagnosis
        )
        XCTAssertTrue(resumedSecond)
        await second.value
        let resumedFirst = await diagnoser.resume(
            requestID: 0,
            with: reachableDiagnosis(
                path: .unidentifiedTunnel(interface: "utun9")
            )
        )
        XCTAssertTrue(resumedFirst)
        await first.value

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.0, originalDiagnosis.target)
        XCTAssertEqual(changes.first?.1, ["mount"])
        XCTAssertEqual(changes.first?.2, newestDiagnosis)
    }

    func testDroppedVPNKeepsResourceWhenUnidentifiedTunnelWorks() async {
        let alternate = reachableDiagnosis(
            path: .unidentifiedTunnel(interface: "utun9")
        )
        let coordinator = makeCoordinator(
            diagnoser: SequenceDiagnoser([alternate])
        )
        let original = connectedService(id: "original", interface: "utun5")
        coordinator.register(
            diagnosis: reachableDiagnosis(path: .vpn(service: original)),
            resource: "mount",
            ownedServiceOwnerships: []
        )
        var lostCount = 0
        coordinator.onConnectivityLost = { _, _ in lostCount += 1 }

        await coordinator.checkConnectivity()

        XCTAssertEqual(lostCount, 0)
        XCTAssertTrue(coordinator.resources(for: "original").isEmpty)
    }

    func testTotalTargetLossNotifiesAllResourcesOnceAndClearsTracking() async {
        let coordinator = makeCoordinator()
        let original = connectedService(id: "original", interface: "utun5")
        let diagnosis = reachableDiagnosis(path: .vpn(service: original))
        coordinator.register(
            diagnosis: diagnosis,
            resource: "mount-b",
            ownedServiceOwnerships: []
        )
        coordinator.register(
            diagnosis: diagnosis,
            resource: "mount-a",
            ownedServiceOwnerships: []
        )
        var losses: [(VPNTarget, [String])] = []
        coordinator.onConnectivityLost = { losses.append(($0, $1)) }

        await coordinator.checkConnectivity()
        await coordinator.checkConnectivity()

        XCTAssertEqual(losses.count, 1)
        XCTAssertEqual(losses.first?.0, diagnosis.target)
        XCTAssertEqual(losses.first?.1, ["mount-a", "mount-b"])
        XCTAssertTrue(coordinator.resources(for: "original").isEmpty)
    }

    func testStaleFailedDiagnosisCannotTearDownReregisteredResource() async {
        let diagnoser = ControlledDiagnoser()
        let coordinator = makeCoordinator(diagnoser: diagnoser)
        let original = connectedService(id: "original", interface: "utun5")
        coordinator.register(
            diagnosis: reachableDiagnosis(path: .vpn(service: original)),
            resource: "mount",
            ownedServiceOwnerships: []
        )
        var lostCount = 0
        coordinator.onConnectivityLost = { _, _ in lostCount += 1 }

        let check = Task { await coordinator.checkConnectivity() }
        await waitForDiagnosisRequests(diagnoser, count: 1)
        coordinator.register(
            diagnosis: reachableDiagnosis(path: .direct(interface: "en0")),
            resource: "mount",
            ownedServiceOwnerships: []
        )
        let resumed = await diagnoser.resume(
            requestID: 0,
            with: unreachableDiagnosis()
        )
        XCTAssertTrue(resumed)
        await check.value

        XCTAssertEqual(lostCount, 0)
        XCTAssertTrue(coordinator.resources(for: "original").isEmpty)
    }

    func testOverlappingFailedChecksDoNotDuplicateConnectivityLoss() async {
        let diagnoser = ControlledDiagnoser()
        let coordinator = makeCoordinator(diagnoser: diagnoser)
        let original = connectedService(id: "original", interface: "utun5")
        coordinator.register(
            diagnosis: reachableDiagnosis(path: .vpn(service: original)),
            resource: "mount",
            ownedServiceOwnerships: []
        )
        var lostCount = 0
        coordinator.onConnectivityLost = { _, _ in lostCount += 1 }

        let first = Task { await coordinator.checkConnectivity() }
        await waitForDiagnosisRequests(diagnoser, count: 1)
        let second = Task { await coordinator.checkConnectivity() }
        await waitForDiagnosisRequests(diagnoser, count: 2)
        let resumedSecond = await diagnoser.resume(
            requestID: 1,
            with: unreachableDiagnosis()
        )
        XCTAssertTrue(resumedSecond)
        await second.value
        let resumedFirst = await diagnoser.resume(
            requestID: 0,
            with: unreachableDiagnosis()
        )
        XCTAssertTrue(resumedFirst)
        await first.value

        XCTAssertEqual(lostCount, 1)
    }

    func testRegistrationDuringStopRediagnosesAndPreservesDirectPath() async {
        let controller = ControlledController()
        let diagnoser = ControlledDiagnoser()
        let coordinator = makeCoordinator(
            diagnoser: diagnoser,
            controller: controller,
            autoDisconnect: true
        )
        let owned = connectedService(id: "owned", interface: "utun5")
        let original = reachableDiagnosis(path: .vpn(service: owned))
        let alternate = reachableDiagnosis(
            path: .direct(interface: "en0")
        )
        coordinator.register(
            diagnosis: original,
            resource: "first",
            ownedServiceOwnerships: [ownership("owned")]
        )
        var lostCount = 0
        coordinator.onConnectivityLost = { _, _ in lostCount += 1 }
        var changes: [(VPNTarget, [String], VPNConnectivityDiagnosis)] = []
        coordinator.onConnectivityPathChanged = {
            changes.append(($0, $1, $2))
        }

        let release = Task {
            await coordinator.release(resource: "first")
        }
        await waitForControlActions(controller, count: 1)
        coordinator.register(
            diagnosis: original,
            resource: "new",
            ownedServiceOwnerships: [ownership("owned")]
        )
        let resumedStop = await controller.resume(
            requestID: 0,
            with: .success
        )
        XCTAssertTrue(resumedStop)
        await waitForDiagnosisRequests(diagnoser, count: 1)
        let resumedDiagnosis = await diagnoser.resume(
            requestID: 0,
            with: alternate
        )
        XCTAssertTrue(resumedDiagnosis)
        await release.value

        XCTAssertEqual(lostCount, 0)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.0, original.target)
        XCTAssertEqual(changes.first?.1, ["new"])
        XCTAssertEqual(changes.first?.2, alternate)
        XCTAssertTrue(coordinator.resources(for: "owned").isEmpty)
        let actions = await controller.recordedActions()
        XCTAssertEqual(actions, [.stop("owned")])
    }

    func testRegistrationDuringStopCannotRemainOnStoppedService() async {
        let controller = ControlledController()
        let diagnoser = ControlledDiagnoser()
        let coordinator = makeCoordinator(
            diagnoser: diagnoser,
            controller: controller,
            autoDisconnect: true
        )
        let owned = connectedService(id: "owned", interface: "utun5")
        let original = reachableDiagnosis(path: .vpn(service: owned))
        coordinator.register(
            diagnosis: original,
            resource: "first",
            ownedServiceOwnerships: [ownership("owned")]
        )
        var losses: [[String]] = []
        coordinator.onConnectivityLost = { _, resources in
            losses.append(resources)
        }

        let release = Task {
            await coordinator.release(resource: "first")
        }
        await waitForControlActions(controller, count: 1)
        coordinator.register(
            diagnosis: original,
            resource: "new",
            ownedServiceOwnerships: [ownership("owned")]
        )
        let resumedStop = await controller.resume(
            requestID: 0,
            with: .success
        )
        XCTAssertTrue(resumedStop)
        await waitForDiagnosisRequests(diagnoser, count: 1)
        let resumedDiagnosis = await diagnoser.resume(
            requestID: 0,
            with: original
        )
        XCTAssertTrue(resumedDiagnosis)
        await release.value

        XCTAssertEqual(losses, [["new"]])
        XCTAssertTrue(coordinator.resources(for: "owned").isEmpty)
        let actions = await controller.recordedActions()
        XCTAssertEqual(actions, [.stop("owned")])
    }

    func testOverlappingFinalReleasesDoNotDuplicateOwnedStop() async {
        let controller = ControlledController()
        let coordinator = makeCoordinator(
            controller: controller,
            autoDisconnect: true
        )
        let owned = connectedService(id: "owned", interface: "utun5")
        let diagnosis = reachableDiagnosis(path: .vpn(service: owned))
        coordinator.register(
            diagnosis: diagnosis,
            resource: "first",
            ownedServiceOwnerships: [ownership("owned")]
        )

        let firstRelease = Task {
            await coordinator.release(resource: "first")
        }
        await waitForControlActions(controller, count: 1)
        coordinator.register(
            diagnosis: diagnosis,
            resource: "second",
            ownedServiceOwnerships: [ownership("owned")]
        )
        await coordinator.release(resource: "second")

        let actionsBeforeCompletion = await controller.recordedActions()
        XCTAssertEqual(actionsBeforeCompletion, [.stop("owned")])
        let resumed = await controller.resume(
            requestID: 0,
            with: .success
        )
        XCTAssertTrue(resumed)
        await firstRelease.value
        let actions = await controller.recordedActions()
        XCTAssertEqual(actions, [.stop("owned")])
    }

    private func makeCoordinator(
        diagnoser: any VPNConnectivityDiagnosing = SequenceDiagnoser([
            unreachableDiagnosis(),
        ]),
        controller: any VPNServiceControlling = RecordingController(),
        autoDisconnect: Bool = false
    ) -> VPNDependencyCoordinator {
        VPNDependencyCoordinator(
            diagnoser: diagnoser,
            controller: controller,
            config: .init(
                autoDisconnectWhenIdle: autoDisconnect,
                pollSeconds: 0
            )
        )
    }

    private func ownership(_ serviceID: String) -> VPNServiceOwnership {
        VPNServiceOwnership(serviceID: serviceID)
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
}
