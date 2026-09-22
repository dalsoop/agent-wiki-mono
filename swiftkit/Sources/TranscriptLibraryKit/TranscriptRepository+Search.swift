import Foundation
import FastDiskIOKit

extension TranscriptRepository {
    // MARK: - Sliding Windows & Affective Retrieval

    /// Fetches the most recent turns within a session using `idx_transcript_session_turn` index.
    /// Default returns messages in natural chronological order (oldest to newest among the window).
    public func fetchRecentTurns(sessionID: String, limit: Int = 20, ascending: Bool = true) throws -> [TranscriptMessage] {
        let sql = """
        SELECT id, session_id, turn_index, role, content, token_count, created_at, metadata,
               valence, arousal, delta_h, lambda_valence, lambda_arousal, lambda_h
        FROM transcript_messages
        WHERE session_id = ?
        ORDER BY turn_index DESC
        LIMIT ?;
        """
        let rows = try database.query(sql: sql, binds: [sessionID, limit])
        let messages = rows.compactMap { parseMessage(from: $0) }
        return ascending ? messages.reversed() : messages
    }

    /// Fetches conversational turns exhibiting homeostatic perturbation or error above the specified threshold.
    /// Utilizes `idx_transcript_affect` for sub-0.1ms retrieval.
    public func fetchAffectiveTurns(
        sessionID: String,
        minDeltaH: Double = 0.0,
        limit: Int = 50
    ) throws -> [TranscriptMessage] {
        let threshold = abs(minDeltaH)
        let sql: String
        let binds: [Any?]

        if threshold > 0.0 {
            sql = """
            SELECT id, session_id, turn_index, role, content, token_count, created_at, metadata,
                   valence, arousal, delta_h, lambda_valence, lambda_arousal, lambda_h
            FROM transcript_messages
            WHERE session_id = ? AND (delta_h >= ? OR delta_h <= ?)
            ORDER BY turn_index ASC
            LIMIT ?;
            """
            binds = [sessionID, threshold, -threshold, limit]
        } else {
            sql = """
            SELECT id, session_id, turn_index, role, content, token_count, created_at, metadata,
                   valence, arousal, delta_h, lambda_valence, lambda_arousal, lambda_h
            FROM transcript_messages
            WHERE session_id = ? AND (delta_h != 0.0 OR valence != 0.0 OR arousal != 0.0)
            ORDER BY turn_index ASC
            LIMIT ?;
            """
            binds = [sessionID, limit]
        }

        let rows = try database.query(sql: sql, binds: binds)
        return rows.compactMap { parseMessage(from: $0) }
    }

    /// Jumps directly to the source context of a lineage pointer, returning the target message
    /// along with preceding and following context turns.
    public func jumpToSourceContext(pointer: LineagePointer, windowSize: Int = 2) throws -> TurnContext {
        let targetMessage: TranscriptMessage
        if !pointer.messageId.isEmpty, let msg = try fetchMessage(id: pointer.messageId) {
            targetMessage = msg
        } else if let msg = try fetchTurn(sessionID: pointer.sessionID, turnIndex: pointer.turnIndex) {
            targetMessage = msg
        } else {
            throw TranscriptError.turnNotFound(sessionID: pointer.sessionID, turnIndex: pointer.turnIndex)
        }

        let targetTurn = targetMessage.turnIndex
        let sessionID = targetMessage.sessionID

        let minTurn = max(0, targetTurn - windowSize)
        let precedingSql = """
        SELECT id, session_id, turn_index, role, content, token_count, created_at, metadata,
               valence, arousal, delta_h, lambda_valence, lambda_arousal, lambda_h
        FROM transcript_messages
        WHERE session_id = ? AND turn_index >= ? AND turn_index < ?
        ORDER BY turn_index ASC;
        """
        let precedingRows = try database.query(sql: precedingSql, binds: [sessionID, minTurn, targetTurn])
        let precedingMessages = precedingRows.compactMap { parseMessage(from: $0) }

        let maxTurn = targetTurn + windowSize
        let followingSql = """
        SELECT id, session_id, turn_index, role, content, token_count, created_at, metadata,
               valence, arousal, delta_h, lambda_valence, lambda_arousal, lambda_h
        FROM transcript_messages
        WHERE session_id = ? AND turn_index > ? AND turn_index <= ?
        ORDER BY turn_index ASC;
        """
        let followingRows = try database.query(sql: followingSql, binds: [sessionID, targetTurn, maxTurn])
        let followingMessages = followingRows.compactMap { parseMessage(from: $0) }

        let session = try fetchSession(sessionID: sessionID)

        return TurnContext(
            targetMessage: targetMessage,
            precedingMessages: precedingMessages,
            followingMessages: followingMessages,
            sessionMeta: session
        )
    }

    // MARK: - Full-Text Search (FTS5)

    /// Performs full-text search across transcript turns using the FTS5 virtual table.
    public func search(
        query: String,
        sessionID: String? = nil,
        limit: Int = 20
    ) throws -> [TranscriptMessage] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranscriptError.emptyQuery
        }

        let sql: String
        let binds: [Any?]
        if let sessionID {
            sql = """
            SELECT m.id, m.session_id, m.turn_index, m.role, m.content, m.token_count, m.created_at, m.metadata,
                   m.valence, m.arousal, m.delta_h, m.lambda_valence, m.lambda_arousal, m.lambda_h
            FROM fts_transcript f
            JOIN transcript_messages m ON f.message_id = m.id
            WHERE fts_transcript MATCH ? AND m.session_id = ?
            ORDER BY bm25(fts_transcript)
            LIMIT ?;
            """
            binds = [trimmed, sessionID, limit]
        } else {
            sql = """
            SELECT m.id, m.session_id, m.turn_index, m.role, m.content, m.token_count, m.created_at, m.metadata,
                   m.valence, m.arousal, m.delta_h, m.lambda_valence, m.lambda_arousal, m.lambda_h
            FROM fts_transcript f
            JOIN transcript_messages m ON f.message_id = m.id
            WHERE fts_transcript MATCH ?
            ORDER BY bm25(fts_transcript)
            LIMIT ?;
            """
            binds = [trimmed, limit]
        }

        let rows = try database.query(sql: sql, binds: binds)
        return rows.compactMap { parseMessage(from: $0) }
    }

    /// Performs full-text search with highlight snippets and BM25 rank score.
    public func searchDetailed(
        query: String,
        sessionID: String? = nil,
        limit: Int = 20
    ) throws -> [TranscriptSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranscriptError.emptyQuery
        }

        let sql: String
        let binds: [Any?]
        if let sessionID {
            sql = """
            SELECT m.id, m.session_id, m.turn_index, m.role, m.content, m.token_count, m.created_at, m.metadata,
                   m.valence, m.arousal, m.delta_h, m.lambda_valence, m.lambda_arousal, m.lambda_h,
                   highlight(fts_transcript, 3, '<mark>', '</mark>') AS snippet,
                   bm25(fts_transcript) AS rank
            FROM fts_transcript f
            JOIN transcript_messages m ON f.message_id = m.id
            WHERE fts_transcript MATCH ? AND m.session_id = ?
            ORDER BY rank
            LIMIT ?;
            """
            binds = [trimmed, sessionID, limit]
        } else {
            sql = """
            SELECT m.id, m.session_id, m.turn_index, m.role, m.content, m.token_count, m.created_at, m.metadata,
                   m.valence, m.arousal, m.delta_h, m.lambda_valence, m.lambda_arousal, m.lambda_h,
                   highlight(fts_transcript, 3, '<mark>', '</mark>') AS snippet,
                   bm25(fts_transcript) AS rank
            FROM fts_transcript f
            JOIN transcript_messages m ON f.message_id = m.id
            WHERE fts_transcript MATCH ?
            ORDER BY rank
            LIMIT ?;
            """
            binds = [trimmed, limit]
        }

        let rows = try database.query(sql: sql, binds: binds)
        return rows.compactMap { row in
            guard let msg = parseMessage(from: row) else { return nil }
            let snippet = row.string(for: "snippet") ?? msg.content
            let rank = row.double(for: "rank") ?? 0.0
            return TranscriptSearchResult(message: msg, snippet: snippet, rank: rank)
        }
    }
}
