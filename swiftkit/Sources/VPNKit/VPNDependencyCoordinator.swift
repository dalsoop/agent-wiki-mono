import Foundation

/// 대상에 도달하는 실제 경로와 그 경로를 사용하는 리소스의 수명을 조율한다.
///
/// 성공 진단이 `.vpn(service:)`인 경우에만 시스템 VPN 서비스 ID를 역인덱스한다.
/// 직접 경로와 식별되지 않은 터널도 대상 연결성 감시에는 참여하지만 자동 연결 해제
/// 대상은 아니다. 마지막 리소스가 해제될 때는 앱이 시작했다고 등록한 서비스만 중지한다.
@MainActor
public final class VPNDependencyCoordinator {
    public struct Config: Sendable {
        /// 마지막 의존 리소스가 해제되면 앱이 시작한 VPN도 중지할지 여부.
        public var autoDisconnectWhenIdle: Bool
        /// 대상 연결성 재진단 주기(초). 0 이하면 자동 감시를 시작하지 않는다.
        public var pollSeconds: Double

        public init(
            autoDisconnectWhenIdle: Bool = false,
            pollSeconds: Double = 6
        ) {
            self.autoDisconnectWhenIdle = autoDisconnectWhenIdle
            self.pollSeconds = pollSeconds
        }
    }

    private struct Dependency {
        let target: VPNTarget
        var diagnosis: VPNConnectivityDiagnosis
        var ownerships: Set<VPNServiceOwnership>
        let registrationID: UInt64
    }

    private struct TargetSnapshot {
        let target: VPNTarget
        var resources: [String]
    }

    private let diagnoser: any VPNConnectivityDiagnosing
    private let controller: any VPNServiceControlling
    public var config: Config

    /// 리소스 ID → 실제 연결 경로와 앱 소유 서비스 정보.
    private var dependencies: [String: Dependency] = [:]
    /// 실제 시스템 VPN 서비스 ID → 현재 그 경로를 쓰는 리소스 ID.
    private var dependentsByServiceID: [String: Set<String>] = [:]
    /// 등록/해제가 await 중 발생하면 이전 진단 결과를 버리기 위한 revision.
    private var dependencyRevision: UInt64 = 0
    /// 겹친 검사 중 가장 최신 검사만 상태를 게시하기 위한 generation.
    private var connectivityCheckGeneration: UInt64 = 0
    /// 같은 서비스에 대한 중복 stop 요청을 막는다.
    private var stoppingServiceIDs: Set<String> = []
    /// 성공 stop이 소비한 소유권 epoch는 stale snapshot으로 재사용할 수 없다.
    private var retiredOwnerships: Set<VPNServiceOwnership> = []
    private var nextRegistrationID: UInt64 = 0
    private var monitor: Task<Void, Never>?

    /// 재진단에서도 대상에 도달할 수 없을 때 정리할 리소스를 소비 앱에 알린다.
    public var onConnectivityLost:
        (@MainActor (_ target: VPNTarget, _ resources: [String]) -> Void)?

    /// 재진단에서 도달 가능한 새 경로를 적용했을 때 소비 앱에 알린다.
    public var onConnectivityPathChanged:
        (@MainActor (
            _ target: VPNTarget,
            _ resources: [String],
            _ diagnosis: VPNConnectivityDiagnosis
        ) -> Void)?

    public init(
        diagnoser: any VPNConnectivityDiagnosing = VPNTargetProbe(),
        controller: any VPNServiceControlling = VPNServiceController(),
        config: Config = Config()
    ) {
        self.diagnoser = diagnoser
        self.controller = controller
        self.config = config
    }

    /// `VPNConnectivityModel`의 명시적 start 성공 epoch를 실제 경로와 연결한다.
    public func register(
        diagnosis: VPNConnectivityDiagnosis,
        resource: String,
        ownedServiceOwnerships: Set<VPNServiceOwnership>
    ) {
        guard diagnosis.reachable else {
            return
        }

        if let previous = dependencies[resource] {
            removeFromServiceIndex(
                resource: resource,
                diagnosis: previous.diagnosis
            )
        }

        nextRegistrationID &+= 1
        dependencies[resource] = Dependency(
            target: diagnosis.target,
            diagnosis: diagnosis,
            ownerships: ownedServiceOwnerships,
            registrationID: nextRegistrationID
        )
        addToServiceIndex(resource: resource, diagnosis: diagnosis)
        dependencyRevision &+= 1
    }

    /// 리소스 등록을 해제하고, 마지막 실제 사용자가 떠난 앱 소유 VPN만 선택적으로 중지한다.
    public func release(resource: String) async {
        guard let dependency = dependencies.removeValue(forKey: resource)
        else {
            return
        }

        removeFromServiceIndex(
            resource: resource,
            diagnosis: dependency.diagnosis
        )
        dependencyRevision &+= 1

        guard config.autoDisconnectWhenIdle,
              case .vpn(let service) = dependency.diagnosis.path,
              dependency.ownerships.contains(where: {
                  $0.serviceID == service.id
                      && !retiredOwnerships.contains($0)
              }),
              dependentsByServiceID[service.id] == nil,
              stoppingServiceIDs.insert(service.id).inserted
        else {
            return
        }

        let registrationCutoff = nextRegistrationID
        let result = await controller.stop(serviceID: service.id)
        if result == .success {
            let completionCutoff = nextRegistrationID
            retiredOwnerships.formUnion(
                dependency.ownerships.filter {
                    $0.serviceID == service.id
                }
            )
            retireOwnerships(
                for: service.id,
                registeredThrough: completionCutoff
            )
            connectivityCheckGeneration &+= 1
            await reconcileRegistrations(
                afterSuccessfulStopOf: service.id,
                registeredAfter: registrationCutoff,
                registeredThrough: completionCutoff
            )
        }
        stoppingServiceIDs.remove(service.id)
    }

    /// 실제 시스템 VPN 서비스 ID를 현재 사용하는 리소스 목록.
    public func resources(for serviceID: String) -> [String] {
        Array(dependentsByServiceID[serviceID] ?? []).sorted()
    }

    public func startMonitoring() {
        stopMonitoring()
        guard config.pollSeconds > 0 else {
            return
        }

        monitor = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                let nanoseconds = UInt64(
                    max(0, self.config.pollSeconds) * 1_000_000_000
                )
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return
                }
                guard !Task.isCancelled else {
                    return
                }
                await self.checkConnectivity()
            }
        }
    }

    public func stopMonitoring() {
        monitor?.cancel()
        monitor = nil
    }

    /// 각 추적 대상의 현재 경로를 다시 진단한다.
    ///
    /// 다른 VPN, 직접 경로, 식별되지 않은 터널 중 무엇이든 도달 가능하면 리소스를
    /// 유지하고 역인덱스만 새 실제 경로로 바꾼다. 최신 재진단에서도 도달 불가능할
    /// 때만 추적을 먼저 제거하고 `onConnectivityLost`를 한 번 호출한다.
    public func checkConnectivity() async {
        guard !dependencies.isEmpty else {
            return
        }

        connectivityCheckGeneration &+= 1
        let checkGeneration = connectivityCheckGeneration
        let revision = dependencyRevision
        let snapshots = targetSnapshots()

        for snapshot in snapshots {
            let diagnosis = await diagnoser.diagnose(snapshot.target)
            guard !Task.isCancelled,
                  checkGeneration == connectivityCheckGeneration,
                  revision == dependencyRevision
            else {
                return
            }

            let currentResources = snapshot.resources.filter { resource in
                dependencies[resource]?.target == snapshot.target
            }
            guard !currentResources.isEmpty else {
                continue
            }

            if diagnosis.reachable {
                update(
                    resources: currentResources,
                    with: diagnosis
                )
            } else {
                removeLost(
                    resources: currentResources,
                    target: snapshot.target
                )
            }
        }
    }

    private func targetSnapshots() -> [TargetSnapshot] {
        var snapshots: [TargetSnapshot] = []
        for resource in dependencies.keys.sorted() {
            guard let dependency = dependencies[resource] else {
                continue
            }
            if let index = snapshots.firstIndex(where: {
                $0.target == dependency.target
            }) {
                snapshots[index].resources.append(resource)
            } else {
                snapshots.append(
                    TargetSnapshot(
                        target: dependency.target,
                        resources: [resource]
                    )
                )
            }
        }
        return snapshots
    }

    private func update(
        resources: [String],
        with diagnosis: VPNConnectivityDiagnosis
    ) {
        var pathChangedResources: [String] = []
        var target: VPNTarget?
        for resource in resources.sorted() {
            guard var dependency = dependencies[resource],
                  dependency.diagnosis != diagnosis
            else {
                continue
            }
            let pathChanged = dependency.diagnosis.path != diagnosis.path
            removeFromServiceIndex(
                resource: resource,
                diagnosis: dependency.diagnosis
            )
            dependency.diagnosis = diagnosis
            dependencies[resource] = dependency
            addToServiceIndex(resource: resource, diagnosis: diagnosis)
            if pathChanged {
                target = target ?? dependency.target
                pathChangedResources.append(resource)
            }
        }
        if let target, !pathChangedResources.isEmpty {
            onConnectivityPathChanged?(
                target,
                pathChangedResources,
                diagnosis
            )
        }
    }

    private func reconcileRegistrations(
        afterSuccessfulStopOf serviceID: String,
        registeredAfter registrationCutoff: UInt64,
        registeredThrough completionCutoff: UInt64
    ) async {
        while let target = firstTargetUsingStoppedService(
            serviceID,
            registeredAfter: registrationCutoff,
            registeredThrough: completionCutoff
        ) {
            let diagnosis = await diagnoser.diagnose(target)
            let resources = resourcesUsingStoppedService(
                serviceID,
                target: target,
                registeredAfter: registrationCutoff,
                registeredThrough: completionCutoff
            )
            guard !resources.isEmpty else {
                continue
            }

            if isReachableAlternate(
                diagnosis.path,
                stoppedServiceID: serviceID,
                reachable: diagnosis.reachable
            ) {
                update(resources: resources, with: diagnosis)
            } else {
                removeLost(resources: resources, target: target)
            }
            dependencyRevision &+= 1
        }
    }

    private func firstTargetUsingStoppedService(
        _ serviceID: String,
        registeredAfter registrationCutoff: UInt64,
        registeredThrough completionCutoff: UInt64
    ) -> VPNTarget? {
        for resource in dependencies.keys.sorted() {
            guard let dependency = dependencies[resource],
                  dependency.registrationID > registrationCutoff,
                  dependency.registrationID <= completionCutoff,
                  diagnosis(
                    dependency.diagnosis,
                    usesServiceID: serviceID
                  )
            else {
                continue
            }
            return dependency.target
        }
        return nil
    }

    private func resourcesUsingStoppedService(
        _ serviceID: String,
        target: VPNTarget,
        registeredAfter registrationCutoff: UInt64,
        registeredThrough completionCutoff: UInt64
    ) -> [String] {
        dependencies.keys.sorted().filter { resource in
            guard let dependency = dependencies[resource] else {
                return false
            }
            return dependency.registrationID > registrationCutoff
                && dependency.registrationID <= completionCutoff
                && dependency.target == target
                && diagnosis(
                    dependency.diagnosis,
                    usesServiceID: serviceID
                )
        }
    }

    private func retireOwnerships(
        for serviceID: String,
        registeredThrough completionCutoff: UInt64
    ) {
        for dependency in dependencies.values
        where dependency.registrationID <= completionCutoff
        && diagnosis(dependency.diagnosis, usesServiceID: serviceID) {
            retiredOwnerships.formUnion(
                dependency.ownerships.filter {
                    $0.serviceID == serviceID
                }
            )
        }
    }

    private func diagnosis(
        _ diagnosis: VPNConnectivityDiagnosis,
        usesServiceID serviceID: String
    ) -> Bool {
        guard case .vpn(let service) = diagnosis.path else {
            return false
        }
        return service.id == serviceID
    }

    private func isReachableAlternate(
        _ path: VPNPath,
        stoppedServiceID: String,
        reachable: Bool
    ) -> Bool {
        guard reachable else {
            return false
        }
        switch path {
        case .direct, .unidentifiedTunnel:
            return true
        case .vpn(let service):
            return service.id != stoppedServiceID
        case .unavailable:
            return false
        }
    }

    private func removeLost(
        resources: [String],
        target: VPNTarget
    ) {
        let sortedResources = resources.sorted()
        for resource in sortedResources {
            guard let dependency = dependencies.removeValue(
                forKey: resource
            ) else {
                continue
            }
            removeFromServiceIndex(
                resource: resource,
                diagnosis: dependency.diagnosis
            )
        }
        onConnectivityLost?(target, sortedResources)
    }

    private func addToServiceIndex(
        resource: String,
        diagnosis: VPNConnectivityDiagnosis
    ) {
        guard case .vpn(let service) = diagnosis.path else {
            return
        }
        dependentsByServiceID[service.id, default: []].insert(resource)
    }

    private func removeFromServiceIndex(
        resource: String,
        diagnosis: VPNConnectivityDiagnosis
    ) {
        guard case .vpn(let service) = diagnosis.path else {
            return
        }
        dependentsByServiceID[service.id]?.remove(resource)
        if dependentsByServiceID[service.id]?.isEmpty == true {
            dependentsByServiceID[service.id] = nil
        }
    }
}
