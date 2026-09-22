@testable import VPNKit

actor SequenceDiagnoser: VPNConnectivityDiagnosing {
    private var values: [VPNConnectivityDiagnosis]

    init(_ values: [VPNConnectivityDiagnosis]) {
        precondition(!values.isEmpty)
        self.values = values
    }

    func diagnose(_ target: VPNTarget) async -> VPNConnectivityDiagnosis {
        if values.count == 1 {
            return values[0]
        }
        return values.removeFirst()
    }
}

actor RecordingDiagnoser: VPNConnectivityDiagnosing {
    private let value: VPNConnectivityDiagnosis
    private var targets: [VPNTarget] = []

    init(_ value: VPNConnectivityDiagnosis) {
        self.value = value
    }

    func diagnose(_ target: VPNTarget) async -> VPNConnectivityDiagnosis {
        targets.append(target)
        return value
    }

    func diagnosisCount() -> Int {
        targets.count
    }
}

actor SequenceInventory: VPNServiceInventoryProviding {
    private var values: [[VPNService]]

    init(_ values: [[VPNService]]) {
        precondition(!values.isEmpty)
        self.values = values
    }

    func services() async -> [VPNService] {
        if values.count == 1 {
            return values[0]
        }
        return values.removeFirst()
    }
}

actor ControlledDiagnoser: VPNConnectivityDiagnosing {
    private struct Pending {
        let id: Int
        let continuation: CheckedContinuation<VPNConnectivityDiagnosis, Never>
    }

    private var nextID = 0
    private var pending: [Pending] = []

    func diagnose(_ target: VPNTarget) async -> VPNConnectivityDiagnosis {
        await withCheckedContinuation { continuation in
            pending.append(Pending(id: nextID, continuation: continuation))
            nextID += 1
        }
    }

    func requestCount() -> Int {
        nextID
    }

    @discardableResult
    func resume(
        requestID: Int,
        with diagnosis: VPNConnectivityDiagnosis
    ) -> Bool {
        guard let index = pending.firstIndex(where: { $0.id == requestID }) else {
            return false
        }
        let request = pending.remove(at: index)
        request.continuation.resume(returning: diagnosis)
        return true
    }
}

actor ControlledInventory: VPNServiceInventoryProviding {
    private struct Pending {
        let id: Int
        let continuation: CheckedContinuation<[VPNService], Never>
    }

    private var nextID = 0
    private var pending: [Pending] = []

    func services() async -> [VPNService] {
        await withCheckedContinuation { continuation in
            pending.append(Pending(id: nextID, continuation: continuation))
            nextID += 1
        }
    }

    func requestCount() -> Int {
        nextID
    }

    @discardableResult
    func resume(requestID: Int, with services: [VPNService]) -> Bool {
        guard let index = pending.firstIndex(where: { $0.id == requestID }) else {
            return false
        }
        let request = pending.remove(at: index)
        request.continuation.resume(returning: services)
        return true
    }
}

actor RecordingController: VPNServiceControlling {
    private let startResult: VPNControlResult
    private let stopResult: VPNControlResult
    private var started: [String] = []
    private var stopped: [String] = []

    init(
        startResult: VPNControlResult = .success,
        stopResult: VPNControlResult = .success
    ) {
        self.startResult = startResult
        self.stopResult = stopResult
    }

    func start(serviceID: String) async -> VPNControlResult {
        started.append(serviceID)
        return startResult
    }

    func stop(serviceID: String) async -> VPNControlResult {
        stopped.append(serviceID)
        return stopResult
    }

    func startedServices() -> [String] {
        started
    }

    func stoppedServices() -> [String] {
        stopped
    }
}

enum RecordedControlAction: Equatable, Sendable {
    case start(String)
    case stop(String)
}

actor ControlledController: VPNServiceControlling {
    private struct Pending {
        let id: Int
        let continuation: CheckedContinuation<VPNControlResult, Never>
    }

    private var actions: [RecordedControlAction] = []
    private var pending: [Pending] = []

    func start(serviceID: String) async -> VPNControlResult {
        await enqueue(.start(serviceID))
    }

    func stop(serviceID: String) async -> VPNControlResult {
        await enqueue(.stop(serviceID))
    }

    func actionCount() -> Int {
        actions.count
    }

    func recordedActions() -> [RecordedControlAction] {
        actions
    }

    @discardableResult
    func resume(requestID: Int, with result: VPNControlResult) -> Bool {
        guard let index = pending.firstIndex(where: { $0.id == requestID }) else {
            return false
        }
        let request = pending.remove(at: index)
        request.continuation.resume(returning: result)
        return true
    }

    private func enqueue(_ action: RecordedControlAction) async -> VPNControlResult {
        let id = actions.count
        actions.append(action)
        return await withCheckedContinuation { continuation in
            pending.append(Pending(id: id, continuation: continuation))
        }
    }
}
