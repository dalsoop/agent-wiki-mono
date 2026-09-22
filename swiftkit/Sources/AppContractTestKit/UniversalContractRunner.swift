import Foundation

public enum ContractExecutionStatus: String, Sendable, Codable, Equatable {
    case passed
    case failed
    case skipped
}

public struct ContractExecutionResult: Sendable, Equatable {
    public let contractID: ContractID
    public let status: ContractExecutionStatus
    public let duration: TimeInterval
    public let message: String
    public let counterExample: String?

    public init(
        contractID: ContractID,
        status: ContractExecutionStatus,
        duration: TimeInterval,
        message: String,
        counterExample: String? = nil
    ) {
        self.contractID = contractID
        self.status = status
        self.duration = duration
        self.message = message
        self.counterExample = counterExample
    }

    public var isPass: Bool {
        status == .passed
    }
}

public struct UniversalContractRunSummary: Sendable, Equatable {
    public let targetName: String
    public let totalCount: Int
    public let passedCount: Int
    public let failedCount: Int
    public let duration: TimeInterval
    public let results: [ContractExecutionResult]

    public init(
        targetName: String,
        totalCount: Int,
        passedCount: Int,
        failedCount: Int,
        duration: TimeInterval,
        results: [ContractExecutionResult]
    ) {
        self.targetName = targetName
        self.totalCount = totalCount
        self.passedCount = passedCount
        self.failedCount = failedCount
        self.duration = duration
        self.results = results
    }

    public var isSuccess: Bool {
        failedCount == 0 && totalCount > 0
    }

    public func result(for contractID: ContractID) -> ContractExecutionResult? {
        results.first(where: { $0.contractID == contractID })
    }
}

public struct UniversalContractRunner: Sendable {
    public let registry: UniversalContractRegistry

    public init(registry: UniversalContractRegistry = .standard) {
        self.registry = registry
    }

    public func run(
        target: any UniversalContractTarget,
        contracts: [ContractID]
    ) -> UniversalContractRunSummary {
        let totalStart = DispatchTime.now().uptimeNanoseconds
        var results: [ContractExecutionResult] = []
        var passed = 0
        var failed = 0

        for contractID in contracts {
            let result = executeContract(contractID: contractID, target: target)
            results.append(result)
            if result.status == .passed {
                passed += 1
            } else {
                failed += 1
            }
        }

        let totalEnd = DispatchTime.now().uptimeNanoseconds
        let totalDuration = Double(totalEnd - totalStart) / 1_000_000_000.0

        return UniversalContractRunSummary(
            targetName: target.name,
            totalCount: contracts.count,
            passedCount: passed,
            failedCount: failed,
            duration: totalDuration,
            results: results
        )
    }

    public func runAsync(
        target: any UniversalContractTarget,
        contracts: [ContractID]
    ) async -> UniversalContractRunSummary {
        run(target: target, contracts: contracts)
    }

    private func executeContract(contractID: ContractID, target: any UniversalContractTarget) -> ContractExecutionResult {
        let itemStart = DispatchTime.now().uptimeNanoseconds
        guard let assertion = registry.assertion(for: contractID) else {
            let itemDuration = Double(DispatchTime.now().uptimeNanoseconds - itemStart) / 1_000_000_000.0
            return ContractExecutionResult(
                contractID: contractID,
                status: .failed,
                duration: itemDuration,
                message: "Contract '\(contractID.rawValue)' not registered in registry",
                counterExample: "UnregisteredContractID: \(contractID.rawValue)"
            )
        }

        do {
            let assertionResult = try assertion(target)
            let itemDuration = Double(DispatchTime.now().uptimeNanoseconds - itemStart) / 1_000_000_000.0
            let status: ContractExecutionStatus = assertionResult.isPassed ? .passed : .failed
            let counterExample = assertionResult.isPassed ? nil : assertionResult.counterExample
            return ContractExecutionResult(
                contractID: contractID,
                status: status,
                duration: itemDuration,
                message: assertionResult.message,
                counterExample: counterExample
            )
        } catch {
            let itemDuration = Double(DispatchTime.now().uptimeNanoseconds - itemStart) / 1_000_000_000.0
            return ContractExecutionResult(
                contractID: contractID,
                status: .failed,
                duration: itemDuration,
                message: "Execution threw unexpected error: \(error.localizedDescription)",
                counterExample: String(describing: error)
            )
        }
    }
}
