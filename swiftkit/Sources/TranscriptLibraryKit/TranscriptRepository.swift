import Foundation
import FastDiskIOKit

/// Domain errors for transcript operations.
public enum TranscriptError: Error, LocalizedError, Sendable {
    case sessionNotFound(String)
    case messageNotFound(String)
    case turnNotFound(sessionID: String, turnIndex: Int)
    case emptyQuery
    case databaseError(String)

    public var errorDescription: String? {
        switch self {
        case .sessionNotFound(let id):
            return "Transcript session not found: \(id)"
        case .messageNotFound(let id):
            return "Transcript message not found: \(id)"
        case .turnNotFound(let sessionID, let turn):
            return "Turn \(turn) not found in session \(sessionID)"
        case .emptyQuery:
            return "Search query cannot be empty"
        case .databaseError(let msg):
            return "Transcript database failure: \(msg)"
        }
    }
}

/// High-performance repository managing transcript sessions, turns, sliding windows,
/// fact lineage pointers, and full-text search.
public final class TranscriptRepository: Sendable {
    public let database: TranscriptDatabase

    /// Initializes repository with the specified database.
    public init(database: TranscriptDatabase) {
        self.database = database
    }

    /// Convenience initializer creating an in-memory repository for test and ephemeral workloads.
    public static func inMemory() throws -> TranscriptRepository {
        let db = try TranscriptDatabase.inMemory()
        return TranscriptRepository(database: db)
    }

    // MARK: - Session Management

    /// Creates a new transcript session.
    @discardableResult
    public func createSession(
        sessionID: String = UUID().uuidString,
        agentID: String,
        roomID: String? = nil,
        title: String,
        totalTurns: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        metadata: [String: String] = [:]
    ) throws -> TranscriptSession {
        let session = TranscriptSession(
            sessionID: sessionID,
            agentID: agentID,
            roomID: roomID,
            title: title,
            totalTurns: totalTurns,
            createdAt: createdAt,
            updatedAt: updatedAt,
            metadata: metadata
        )

        let metaJSON = encodeMetadata(metadata)
        let sql = """
        INSERT INTO sessions (session_id, agent_id, room_id, title, total_turns, created_at, updated_at, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        try database.run(sql: sql, binds: [
            session.sessionID,
            session.agentID,
            session.roomID,
            session.title,
            session.totalTurns,
            session.createdAt.timeIntervalSince1970,
            session.updatedAt.timeIntervalSince1970,
            metaJSON
        ])
        return session
    }

    /// Fetches a session by ID.
    public func fetchSession(sessionID: String) throws -> TranscriptSession? {
        let sql = "SELECT * FROM sessions WHERE session_id = ? LIMIT 1;"
        let rows = try database.query(sql: sql, binds: [sessionID])
        guard let row = rows.first else { return nil }
        return parseSession(from: row)
    }

    /// Lists sessions ordered by most recently updated.
    public func listSessions(limit: Int = 50, offset: Int = 0) throws -> [TranscriptSession] {
        let sql = "SELECT * FROM sessions ORDER BY updated_at DESC LIMIT ? OFFSET ?;"
        let rows = try database.query(sql: sql, binds: [limit, offset])
        return rows.compactMap { parseSession(from: $0) }
    }

    /// Deletes a session and cascades turn messages.
    public func deleteSession(sessionID: String) throws {
        try database.run(sql: "DELETE FROM sessions WHERE session_id = ?;", binds: [sessionID])
    }

    /// Returns the number of turns recorded for a given session.
    public func countTurns(sessionID: String) throws -> Int {
        let sql = "SELECT COUNT(*) as count FROM transcript_messages WHERE session_id = ?;"
        let rows = try database.query(sql: sql, binds: [sessionID])
        return rows.first?.int(for: "count") ?? 0
    }

    // MARK: - Message & Turn Appending

    /// Appends a new conversational message turn to a session atomically.
    /// Increments session's total_turns and updates updated_at.
    @discardableResult
    public func appendMessage(
        sessionID: String,
        role: TranscriptRole,
        content: String,
        tokenCount: Int = 0,
        metadata: [String: String] = [:],
        affect: HomeostaticAffectSnapshot? = nil,
        dualState: DualStateSnapshot? = nil
    ) throws -> TranscriptMessage {
        try appendMessage(
            sessionID: sessionID,
            payload: TranscriptMessagePayload(
                role: role,
                content: content,
                tokenCount: tokenCount,
                metadata: metadata,
                affect: affect,
                dualState: dualState
            )
        )
    }

    /// Appends a turn with an explicit message payload.
    @discardableResult
    public func appendMessage(
        sessionID: String,
        payload: TranscriptMessagePayload
    ) throws -> TranscriptMessage {
        try database.withTransaction {
            guard let session = try fetchSession(sessionID: sessionID) else {
                throw TranscriptError.sessionNotFound(sessionID)
            }

            let nextTurnIndex = session.totalTurns + 1
            let message = TranscriptMessage(
                id: payload.id,
                sessionID: sessionID,
                turnIndex: nextTurnIndex,
                role: payload.role,
                content: payload.content,
                tokenCount: payload.tokenCount,
                createdAt: payload.createdAt,
                metadata: payload.metadata,
                affect: payload.affect,
                dualState: payload.dualState
            )

            try insertMessage(message)

            let updateSessionSql = """
            UPDATE sessions 
            SET total_turns = total_turns + 1, updated_at = ? 
            WHERE session_id = ?;
            """
            try database.run(sql: updateSessionSql, binds: [payload.createdAt.timeIntervalSince1970, sessionID])
            return message
        }
    }

    /// Fetches a single message by ID.
    public func fetchMessage(id: String) throws -> TranscriptMessage? {
        let sql = "SELECT * FROM transcript_messages WHERE id = ? LIMIT 1;"
        let rows = try database.query(sql: sql, binds: [id])
        guard let row = rows.first else { return nil }
        return parseMessage(from: row)
    }

    /// Fetches a specific turn within a session.
    public func fetchTurn(sessionID: String, turnIndex: Int) throws -> TranscriptMessage? {
        let sql = "SELECT * FROM transcript_messages WHERE session_id = ? AND turn_index = ? LIMIT 1;"
        let rows = try database.query(sql: sql, binds: [sessionID, turnIndex])
        guard let row = rows.first else { return nil }
        return parseMessage(from: row)
    }

    /// Deletes a specific message.
    public func deleteMessage(id: String) throws {
        try database.run(sql: "DELETE FROM transcript_messages WHERE id = ?;", binds: [id])
    }

    // MARK: - Internal Row Parsers

    private func insertMessage(_ message: TranscriptMessage) throws {
        let metaJSON = encodeMetadata(message.metadata)
        let sql = """
        INSERT INTO transcript_messages (
            id, session_id, turn_index, role, content, token_count, created_at, metadata,
            valence, arousal, delta_h, lambda_valence, lambda_arousal, lambda_h
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        let valence: Double? = message.affect?.valence
        let arousal: Double? = message.affect?.arousal
        let deltaH: Double? = message.affect?.homeostaticDelta
        let lambdaValence: Double? = message.dualState?.lambdaValence
        let lambdaArousal: Double? = message.dualState?.lambdaArousal
        let lambdaH: Double? = message.dualState?.lambdaDeltaH

        try database.run(sql: sql, binds: [
            message.id,
            message.sessionID,
            message.turnIndex,
            message.role.rawValue,
            message.content,
            message.tokenCount,
            message.createdAt.timeIntervalSince1970,
            metaJSON,
            valence,
            arousal,
            deltaH,
            lambdaValence,
            lambdaArousal,
            lambdaH
        ])
    }

    func parseSession(from row: FastSQLiteRow) -> TranscriptSession? {
        guard let sessionID = row.string(for: "session_id"),
              let agentID = row.string(for: "agent_id"),
              let title = row.string(for: "title") else {
            return nil
        }
        let roomID = row.string(for: "room_id")
        let totalTurns = row.int(for: "total_turns") ?? 0
        let createdAtSec = row.double(for: "created_at") ?? 0
        let updatedAtSec = row.double(for: "updated_at") ?? 0
        let metaString = row.string(for: "metadata") ?? "{}"
        let metadata = decodeMetadata(metaString)

        return TranscriptSession(
            sessionID: sessionID,
            agentID: agentID,
            roomID: roomID,
            title: title,
            totalTurns: totalTurns,
            createdAt: Date(timeIntervalSince1970: createdAtSec),
            updatedAt: Date(timeIntervalSince1970: updatedAtSec),
            metadata: metadata
        )
    }

    func parseMessage(from row: FastSQLiteRow) -> TranscriptMessage? {
        guard let id = row.string(for: "id"),
              let sessionID = row.string(for: "session_id"),
              let turnIndex = row.int(for: "turn_index"),
              let roleStr = row.string(for: "role"),
              let content = row.string(for: "content") else {
            return nil
        }
        let role = TranscriptRole(rawValue: roleStr) ?? .user
        let tokenCount = row.int(for: "token_count") ?? 0
        let createdAtSec = row.double(for: "created_at") ?? 0
        let metaString = row.string(for: "metadata") ?? "{}"
        let metadata = decodeMetadata(metaString)

        let affect: HomeostaticAffectSnapshot?
        if let valVal = row["valence"], !valVal.isNull,
           let valence = row.double(for: "valence"),
           let arousal = row.double(for: "arousal"),
           let deltaH = row.double(for: "delta_h") {
            affect = HomeostaticAffectSnapshot(valence: valence, arousal: arousal, homeostaticDelta: deltaH)
        } else {
            affect = nil
        }

        let dualState: DualStateSnapshot?
        if let lamVal = row["lambda_h"], !lamVal.isNull,
           let lambdaH = row.double(for: "lambda_h") {
            let lambdaValence = row.double(for: "lambda_valence") ?? 0.0
            let lambdaArousal = row.double(for: "lambda_arousal") ?? 0.0
            dualState = DualStateSnapshot(lambdaValence: lambdaValence, lambdaArousal: lambdaArousal, lambdaDeltaH: lambdaH)
        } else {
            dualState = nil
        }

        return TranscriptMessage(
            id: id,
            sessionID: sessionID,
            turnIndex: turnIndex,
            role: role,
            content: content,
            tokenCount: tokenCount,
            createdAt: Date(timeIntervalSince1970: createdAtSec),
            metadata: metadata,
            affect: affect,
            dualState: dualState
        )
    }

    func encodeMetadata(_ dict: [String: String]) -> String {
        guard !dict.isEmpty else { return "{}" }
        do {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{}"
        }
    }

    func decodeMetadata(_ str: String) -> [String: String] {
        guard let data = str.data(using: .utf8), !str.isEmpty, str != "{}" else {
            return [:]
        }
        var metadataMap: [String: String] = [:]
        do {
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: String] {
                metadataMap = obj
            }
        } catch {
            metadataMap.removeAll()
        }
        return metadataMap
    }
}
