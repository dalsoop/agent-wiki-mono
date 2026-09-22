import Foundation

public struct RepositoryAgentWorkerDoneReceipt: Codable, Sendable, Equatable {
    public static let schemaVersion = "knowledge-base-wiki.repository-agent-worker-done.v1"
    public static let objectType = "repository-agent-worker-done"

    public let schemaVersion: String
    public let canonicalTaskId: String
    public let runtimeTaskId: String
    public let dispatchId: String
    public let bindingObjectId: String
    public let worker: String
    public let result: String
    public let occurredAt: Date

    public init(event: RepositoryAgentAdapterEvent, bindingObjectId: String) throws {
        guard event.event == .workerDone else {
            throw RepositoryAgentOrchestrationError.invalidEvent("worker_done event required")
        }
        self.schemaVersion = Self.schemaVersion
        self.canonicalTaskId = event.canonicalTaskId
        self.runtimeTaskId = event.runtimeTaskId
        self.dispatchId = event.dispatchId
        self.bindingObjectId = bindingObjectId
        self.worker = event.worker ?? ""
        self.result = event.result ?? ""
        self.occurredAt = event.occurredAt
    }

    public func json() throws -> String {
        String(decoding: try RepositoryAgentOrchestration.encoder.encode(self), as: UTF8.self)
    }

    public static func decode(body: String) -> Self? {
        guard let data = body.data(using: .utf8) else { return nil }
        return try? RepositoryAgentOrchestration.decoder.decode(Self.self, from: data)
    }
}

public struct RepositoryAgentWorkerFailureReceipt: Codable, Sendable, Equatable {
    public static let schemaVersion = "knowledge-base-wiki.repository-agent-worker-failure.v1"
    public static let objectType = "repository-agent-worker-failure"
    public static let maxMessageUTF8Bytes = 4_096

    public let schemaVersion: String
    public let canonicalTaskId: String
    public let runtimeTaskId: String
    public let dispatchId: String
    public let bindingObjectId: String
    public let worker: String
    public let exitCode: Int32
    public let message: String
    public let failedAt: Date

    public struct Draft: Sendable, Equatable {
        public var canonicalTaskId: String
        public var runtimeTaskId: String
        public var dispatchId: String
        public var bindingObjectId: String
        public var worker: String
        public var exitCode: Int32
        public var message: String
        public var failedAt: Date
    }

    public init(_ draft: Draft) {
        self.schemaVersion = Self.schemaVersion
        self.canonicalTaskId = draft.canonicalTaskId
        self.runtimeTaskId = draft.runtimeTaskId
        self.dispatchId = draft.dispatchId
        self.bindingObjectId = draft.bindingObjectId
        self.worker = draft.worker
        self.exitCode = draft.exitCode
        self.message = draft.message
        self.failedAt = draft.failedAt
    }

    public func json() throws -> String {
        String(decoding: try RepositoryAgentOrchestration.encoder.encode(self), as: UTF8.self)
    }

    public static func decode(body: String) -> Self? {
        guard let data = body.data(using: .utf8) else { return nil }
        return try? RepositoryAgentOrchestration.decoder.decode(Self.self, from: data)
    }
}
