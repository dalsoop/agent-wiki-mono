import Foundation

/// Defines the conversational role of a transcript turn.
public enum TranscriptRole: String, Codable, Sendable, CaseIterable {
    case system
    case user
    case assistant
    case tool
}

/// Represents an agentic transcript session.
public struct TranscriptSession: Identifiable, Codable, Sendable, Equatable {
    public var id: String { sessionID }
    public let sessionID: String
    public let agentID: String
    public let roomID: String?
    public let title: String
    public let totalTurns: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let metadata: [String: String]

    public init(
        sessionID: String = UUID().uuidString,
        agentID: String,
        roomID: String? = nil,
        title: String,
        totalTurns: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.sessionID = sessionID
        self.agentID = agentID
        self.roomID = roomID
        self.title = title
        self.totalTurns = totalTurns
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }

    public func updating(
        totalTurns: Int? = nil,
        title: String? = nil,
        updatedAt: Date = Date(),
        metadata: [String: String]? = nil
    ) -> TranscriptSession {
        TranscriptSession(
            sessionID: self.sessionID,
            agentID: self.agentID,
            roomID: self.roomID,
            title: title ?? self.title,
            totalTurns: totalTurns ?? self.totalTurns,
            createdAt: self.createdAt,
            updatedAt: updatedAt,
            metadata: metadata ?? self.metadata
        )
    }
}

/// Biological homeostatic affect snapshot bound to a transcript turn.
public struct HomeostaticAffectSnapshot: Codable, Sendable, Equatable {
    public let valence: Double
    public let arousal: Double
    public let homeostaticDelta: Double

    public init(valence: Double, arousal: Double, homeostaticDelta: Double) {
        self.valence = valence
        self.arousal = arousal
        self.homeostaticDelta = homeostaticDelta
    }
}

/// Dual state snapshot capturing PC-ALM dual neuron variables.
public struct DualStateSnapshot: Codable, Sendable, Equatable {
    public let lambdaValence: Double
    public let lambdaArousal: Double
    public let lambdaDeltaH: Double

    public init(lambdaValence: Double, lambdaArousal: Double, lambdaDeltaH: Double) {
        self.lambdaValence = lambdaValence
        self.lambdaArousal = lambdaArousal
        self.lambdaDeltaH = lambdaDeltaH
    }
}

/// Represents a single conversational message turn within a transcript session.
public struct TranscriptMessage: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let sessionID: String
    public let turnIndex: Int
    public let role: TranscriptRole
    public let content: String
    public let tokenCount: Int
    public let createdAt: Date
    public let metadata: [String: String]
    public let affect: HomeostaticAffectSnapshot?
    public let dualState: DualStateSnapshot?

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        turnIndex: Int,
        role: TranscriptRole,
        content: String,
        tokenCount: Int = 0,
        createdAt: Date = Date(),
        metadata: [String: String] = [:],
        affect: HomeostaticAffectSnapshot? = nil,
        dualState: DualStateSnapshot? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.turnIndex = turnIndex
        self.role = role
        self.content = content
        self.tokenCount = tokenCount
        self.createdAt = createdAt
        self.metadata = metadata
        self.affect = affect
        self.dualState = dualState
    }

    /// Converts this message into its corresponding lineage pointer.
    public var lineagePointer: LineagePointer {
        LineagePointer(sessionID: sessionID, turnIndex: turnIndex, messageId: id)
    }
}

/// Payload input parameters for appending a conversational message turn.
public struct TranscriptMessagePayload: Sendable {
    public var id: String
    public var role: TranscriptRole
    public var content: String
    public var tokenCount: Int
    public var createdAt: Date
    public var metadata: [String: String]
    public var affect: HomeostaticAffectSnapshot?
    public var dualState: DualStateSnapshot?

    public init(
        id: String = UUID().uuidString,
        role: TranscriptRole,
        content: String,
        tokenCount: Int = 0,
        createdAt: Date = Date(),
        metadata: [String: String] = [:],
        affect: HomeostaticAffectSnapshot? = nil,
        dualState: DualStateSnapshot? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.tokenCount = tokenCount
        self.createdAt = createdAt
        self.metadata = metadata
        self.affect = affect
        self.dualState = dualState
    }
}

/// A lightweight pointer to track and jump directly to the exact source turn of a fact or memory.
public struct LineagePointer: Codable, Sendable, Equatable, Hashable {
    public let sessionID: String
    public let turnIndex: Int
    public let messageId: String

    public var messageID: String { messageId }

    public init(sessionID: String, turnIndex: Int, messageId: String) {
        self.sessionID = sessionID
        self.turnIndex = turnIndex
        self.messageId = messageId
    }
}

/// Context surrounding a specific turn, providing preceding and following messages for lineage reconstruction.
public struct TurnContext: Codable, Sendable, Equatable {
    public let targetMessage: TranscriptMessage
    public let precedingMessages: [TranscriptMessage]
    public let followingMessages: [TranscriptMessage]
    public let sessionMeta: TranscriptSession?

    public init(
        targetMessage: TranscriptMessage,
        precedingMessages: [TranscriptMessage] = [],
        followingMessages: [TranscriptMessage] = [],
        sessionMeta: TranscriptSession? = nil
    ) {
        self.targetMessage = targetMessage
        self.precedingMessages = precedingMessages
        self.followingMessages = followingMessages
        self.sessionMeta = sessionMeta
    }

    /// All messages in chronological order including preceding, target, and following.
    public var chronologicalMessages: [TranscriptMessage] {
        var all = precedingMessages
        all.append(targetMessage)
        all.append(contentsOf: followingMessages)
        return all.sorted { $0.turnIndex < $1.turnIndex }
    }
}

/// Encapsulates full-text search match details including highlight snippet.
public struct TranscriptSearchResult: Codable, Sendable, Equatable {
    public let message: TranscriptMessage
    public let snippet: String
    public let rank: Double

    public init(message: TranscriptMessage, snippet: String, rank: Double = 0.0) {
        self.message = message
        self.snippet = snippet
        self.rank = rank
    }
}
