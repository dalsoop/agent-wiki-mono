import Foundation

public enum LongRunningOperationStatus: String, Codable, Sendable {
    case idle
    case running
    case succeeded
    case failed
}

public struct LongRunningOperationState: Codable, Equatable, Sendable {
    public let status: LongRunningOperationStatus
    public let operation: String?
    public let phase: String?
    public let completed: Int?
    public let total: Int?
    public let unit: String?
    public let currentTarget: String?
    public let startedAt: String?
    public let finishedAt: String?
    public let message: String?
    public let error: String?

    public struct Report: Sendable, Equatable {
        public var startedAt: String?
        public var finishedAt: String?
        public var message: String?
        public var error: String?

        public init(
            startedAt: String? = nil,
            finishedAt: String? = nil,
            message: String? = nil,
            error: String? = nil
        ) {
            self.startedAt = startedAt
            self.finishedAt = finishedAt
            self.message = message
            self.error = error
        }
    }

    public init(
        status: LongRunningOperationStatus,
        operation: String? = nil,
        phase: String? = nil,
        completed: Int? = nil,
        total: Int? = nil,
        unit: String? = nil,
        currentTarget: String? = nil,
        report: Report = Report()
    ) {
        self.status = status
        self.operation = operation
        self.phase = phase
        if let total, total > 0 {
            self.total = total
            self.completed = min(max(completed ?? 0, 0), total)
        } else {
            self.total = nil
            self.completed = nil
        }
        self.unit = unit
        self.currentTarget = currentTarget
        self.startedAt = report.startedAt
        self.finishedAt = report.finishedAt
        self.message = report.message
        self.error = report.error
    }

    public static let idle = LongRunningOperationState(status: .idle)

    public var fractionCompleted: Double? {
        guard let completed, let total, total > 0 else { return nil }
        return Double(completed) / Double(total)
    }
}
