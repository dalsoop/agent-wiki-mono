import Foundation
import Observation

/// 한 번의 명시적 VPN start 성공을 나타내는 위조 불가능한 프로세스 내 소유권 epoch.
public struct VPNServiceOwnership: Hashable, Sendable {
    public let serviceID: String
    public let epochID: UUID

    init(serviceID: String, epochID: UUID = UUID()) {
        self.serviceID = serviceID
        self.epochID = epochID
    }
}

public struct VPNRecoveryContext: Equatable, Sendable {
    public let diagnosis: VPNConnectivityDiagnosis
    public let services: [VPNService]
    public let preferred: VPNServiceReference?
    public let selectedServiceID: String?
    public let message: String?

    public init(
        diagnosis: VPNConnectivityDiagnosis,
        services: [VPNService],
        preferred: VPNServiceReference?,
        selectedServiceID: String?,
        message: String?
    ) {
        self.diagnosis = diagnosis
        self.services = services
        self.preferred = preferred
        self.selectedServiceID = selectedServiceID
        self.message = message
    }
}

public enum VPNConnectivityPhase: Equatable, Sendable {
    case idle
    case diagnosing
    case connected(VPNConnectivityDiagnosis)
    case recovery(VPNRecoveryContext)
    case failed(VPNConnectivityDiagnosis)
}

@MainActor
@Observable
public final class VPNConnectivityModel {
    public let target: VPNTarget
    public var preferred: VPNServiceReference?
    public private(set) var phase: VPNConnectivityPhase = .idle
    public private(set) var appStartedServiceOwnerships:
        Set<VPNServiceOwnership> = []
    public var appStartedServiceIDs: Set<String> {
        Set(appStartedServiceOwnerships.map(\.serviceID))
    }

    /// Transfers exact app-start ownership epochs across a target/model handoff.
    ///
    /// Only epochs for the newly diagnosed VPN path are adopted. Callers must
    /// never synthesize ownership from a service ID.
    public func adoptServiceOwnerships(
        _ ownerships: Set<VPNServiceOwnership>,
        for diagnosis: VPNConnectivityDiagnosis
    ) {
        guard diagnosis.reachable,
              diagnosis.target == target,
              case .vpn(let service) = diagnosis.path
        else {
            return
        }
        appStartedServiceOwnerships.formUnion(
            ownerships.filter { $0.serviceID == service.id }
        )
    }

    /// Waits for every explicit connect/disconnect already queued on this model,
    /// then returns the exact ownership epochs produced by those side effects.
    public func settledServiceOwnerships()
        async -> Set<VPNServiceOwnership>
    {
        let pendingControls = controlTail
        await pendingControls?.value
        return appStartedServiceOwnerships
    }

    /// 최근 진단과 함께 읽은 시스템 VPN 목록. 설정 Picker와 복구 UI의 공용 snapshot이다.
    public var availableServices: [VPNService] { services }

    private let diagnoser: any VPNConnectivityDiagnosing
    private let inventory: any VPNServiceInventoryProviding
    private let controller: any VPNServiceControlling
    private var services: [VPNService] = []
    // Only arbitrates publication of observational phase/service results.
    @ObservationIgnored private var observationGeneration: UInt64 = 0
    @ObservationIgnored private var recoveryRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var autoRetryTask: Task<Void, Never>?
    // Explicit control operations form a non-cancelling FIFO chain.
    @ObservationIgnored private var controlTail: Task<Void, Never>?
    /// TTL cache: skip re-diagnosis if a recent result is still fresh
    @ObservationIgnored private var lastDiagnoseTime: TimeInterval = 0
    @ObservationIgnored private static let diagnoseTTL: TimeInterval = 5

    public init(
        target: VPNTarget,
        preferred: VPNServiceReference?,
        diagnoser: any VPNConnectivityDiagnosing = VPNTargetProbe(),
        inventory: any VPNServiceInventoryProviding = VPNSystemInventory(),
        controller: any VPNServiceControlling = VPNServiceController()
    ) {
        self.target = target
        self.preferred = preferred
        self.diagnoser = diagnoser
        self.inventory = inventory
        self.controller = controller
    }

    public func diagnose(force: Bool = false) async {
        // Skip re-diagnosis if a recent successful result is still fresh (avoids
        // redundant network probes when multiple entries on the same card diagnose
        // within the same auto-run cycle). Only cache connected/reachable states;
        // failed/recovery states must always re-probe to detect VPN coming back up.
        if !force {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastDiagnoseTime < Self.diagnoseTTL,
               case .connected = phase {
                return
            }
        }
        let generation = beginObservation()
        await diagnose(generation: generation)
        lastDiagnoseTime = ProcessInfo.processInfo.systemUptime
    }

    public func apply(_ diagnosis: VPNConnectivityDiagnosis) {
        let generation = beginObservation()
        publish(diagnosis)
        guard !diagnosis.reachable else {
            return
        }

        let inventory = self.inventory
        recoveryRefreshTask = Task { [weak self] in
            let availableServices = await inventory.services()
            guard !Task.isCancelled else {
                return
            }
            self?.completeRecoveryRefresh(
                diagnosis: diagnosis,
                services: availableServices,
                generation: generation
            )
        }
    }

    public func connect(serviceID: String) async {
        let previous = controlTail
        let current = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else {
                return
            }
            await self.performConnect(serviceID: serviceID)
        }
        controlTail = current
        await current.value
    }

    public func disconnect(serviceID: String) async {
        let previous = controlTail
        let current = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else {
                return
            }
            await self.performDisconnect(serviceID: serviceID)
        }
        controlTail = current
        await current.value
    }

    private func performConnect(serviceID: String) async {
        let availableServices = await inventory.services()

        guard let service = availableServices.first(where: { $0.id == serviceID }) else {
            await recoverFromControlFailure(
                "VPN service not found: \(serviceID)",
                authoritativeServices: availableServices
            )
            return
        }
        if service.isConnected {
            await postControlDiagnosis()
            return
        }

        let result = await controller.start(serviceID: serviceID)
        switch result {
        case .success:
            appStartedServiceOwnerships = appStartedServiceOwnerships.filter {
                $0.serviceID != serviceID
            }
            appStartedServiceOwnerships.insert(
                VPNServiceOwnership(serviceID: serviceID)
            )
            await postControlDiagnosis()
        case .cancelled:
            await recoverFromControlFailure(
                "cancelled by user",
                authoritativeServices: availableServices
            )
        case .unsupported(let message), .failed(let message):
            await recoverFromControlFailure(
                message,
                authoritativeServices: availableServices
            )
        }
    }

    private func performDisconnect(serviceID: String) async {
        let result = await controller.stop(serviceID: serviceID)
        switch result {
        case .success:
            appStartedServiceOwnerships = appStartedServiceOwnerships.filter {
                $0.serviceID != serviceID
            }
            await postControlDiagnosis()
        case .cancelled:
            await recoverFromControlFailure("cancelled by user")
        case .unsupported(let message), .failed(let message):
            await recoverFromControlFailure(message)
        }
    }

    private func postControlDiagnosis() async {
        // A completed side effect always gets a fresh diagnosis. A still-later
        // observation may supersede its publication, but cannot skip this work.
        let generation = beginObservation()
        await diagnose(generation: generation)
    }

    private func recoverFromControlFailure(
        _ message: String,
        authoritativeServices: [VPNService]? = nil
    ) async {
        let generation = beginObservation()
        phase = .diagnosing

        let diagnosis: VPNConnectivityDiagnosis
        let availableServices: [VPNService]
        if let authoritativeServices {
            diagnosis = await diagnoser.diagnose(target)
            availableServices = authoritativeServices
        } else {
            async let diagnosedTarget = diagnoser.diagnose(target)
            async let currentServices = inventory.services()
            (diagnosis, availableServices) = await (
                diagnosedTarget,
                currentServices
            )
        }

        guard isCurrentObservation(generation) else {
            return
        }
        services = availableServices
        publish(diagnosis, message: message)
    }

    private func diagnose(generation: UInt64) async {
        guard isCurrentObservation(generation) else {
            return
        }
        phase = .diagnosing
        async let diagnosis = diagnoser.diagnose(target)
        async let availableServices = inventory.services()
        let (diagnosisValue, servicesValue) = await (diagnosis, availableServices)
        guard isCurrentObservation(generation) else {
            return
        }
        services = servicesValue
        publish(diagnosisValue)
    }

    private func publish(
        _ diagnosis: VPNConnectivityDiagnosis,
        message: String? = nil
    ) {
        if diagnosis.reachable {
            autoRetryTask?.cancel()
            autoRetryTask = nil
            phase = .connected(diagnosis)
            return
        }

        phase = .recovery(
            recoveryContext(for: diagnosis, message: message)
        )

        // When the failure is a transient subprocess error (diagnosisUnavailable),
        // schedule an automatic re-diagnosis after a short delay. This prevents
        // the UI from permanently locking into recovery state due to a single
        // EBADF from Process.run() after sleep/wake.
        autoRetryTask?.cancel()
        autoRetryTask = nil
        if case .diagnosisUnavailable = diagnosis.failure {
            autoRetryTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10s
                guard !Task.isCancelled else { return }
                await self?.diagnose(force: true)
            }
        }
    }

    private func beginObservation() -> UInt64 {
        observationGeneration &+= 1
        recoveryRefreshTask?.cancel()
        recoveryRefreshTask = nil
        autoRetryTask?.cancel()
        autoRetryTask = nil
        return observationGeneration
    }

    private func isCurrentObservation(_ generation: UInt64) -> Bool {
        generation == observationGeneration
    }

    private func completeRecoveryRefresh(
        diagnosis: VPNConnectivityDiagnosis,
        services: [VPNService],
        generation: UInt64
    ) {
        guard isCurrentObservation(generation) else {
            return
        }
        self.services = services
        phase = .recovery(
            recoveryContext(for: diagnosis, message: nil)
        )
        recoveryRefreshTask = nil
    }

    private func recoveryContext(
        for diagnosis: VPNConnectivityDiagnosis,
        message: String?
    ) -> VPNRecoveryContext {
        VPNRecoveryContext(
            diagnosis: diagnosis,
            services: services,
            preferred: preferred,
            selectedServiceID: suggestedServiceID(),
            message: message
        )
    }

    private func suggestedServiceID() -> String? {
        guard let preferred else {
            return services.first?.id
        }

        if let serviceID = preferred.serviceID,
           services.contains(where: { $0.id == serviceID }) {
            return serviceID
        }

        let identifiers = [
            preferred.legacyIdentifier,
            preferred.displayName,
        ].compactMap { $0 }
        if let service = services.first(where: {
            identifiers.contains($0.id) || identifiers.contains($0.name)
        }) {
            return service.id
        }
        return services.first?.id
    }

}
