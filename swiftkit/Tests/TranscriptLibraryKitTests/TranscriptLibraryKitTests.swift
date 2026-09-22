import XCTest
@testable import TranscriptLibraryKit

final class TranscriptLibraryKitTests: XCTestCase {
    var tempDir: URL?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptLibraryKitTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDir = dir
    }

    override func tearDownWithError() throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testSessionCreationAndPersistence() throws {
        guard let tempDir else { return }
        let dbPath = tempDir.appendingPathComponent("transcripts.sqlite").path
        let db = try TranscriptDatabase(path: dbPath)
        let repository = TranscriptRepository(database: db)

        let sessionID = "sess_test_01"
        let created = try repository.createSession(
            sessionID: sessionID,
            agentID: "agent_primary",
            roomID: "room_alpha",
            title: "Autonomous Planning Session",
            metadata: ["source": "worker1", "priority": "high"]
        )

        XCTAssertEqual(created.sessionID, sessionID)
        XCTAssertEqual(created.agentID, "agent_primary")
        XCTAssertEqual(created.roomID, "room_alpha")
        XCTAssertEqual(created.title, "Autonomous Planning Session")
        XCTAssertEqual(created.totalTurns, 0)
        XCTAssertEqual(created.metadata["source"], "worker1")

        // Fetch back
        let fetched = try repository.fetchSession(sessionID: sessionID)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.sessionID, sessionID)
        XCTAssertEqual(fetched?.metadata["priority"], "high")

        // Close and reopen database to confirm disk durability
        db.close()
        let reopenedDb = try TranscriptDatabase(path: dbPath)
        let reopenedRepo = TranscriptRepository(database: reopenedDb)

        let persisted = try reopenedRepo.fetchSession(sessionID: sessionID)
        XCTAssertNotNil(persisted)
        XCTAssertEqual(persisted?.title, "Autonomous Planning Session")
        reopenedDb.close()
    }

    func testHundredTurnsAppendAndSlidingWindow() throws {
        let repository = try TranscriptRepository.inMemory()
        let sessionID = "sess_100_turns"

        try repository.createSession(
            sessionID: sessionID,
            agentID: "worker_agent",
            roomID: "room_ef02e62f",
            title: "Long Conversation Transcript"
        )

        let startTime = CFAbsoluteTimeGetCurrent()
        let turnCount = 100

        for i in 1...turnCount {
            let role: TranscriptRole = (i % 2 == 1) ? .user : .assistant
            let content = "Turn #\(i): Detailed message about system architecture and FastDiskIO integration step \(i)."
            let tokenCount = 15 + i

            let msg = try repository.appendMessage(
                sessionID: sessionID,
                role: role,
                content: content,
                tokenCount: tokenCount,
                metadata: ["turn": "\(i)"]
            )
            XCTAssertEqual(msg.turnIndex, i)
            XCTAssertEqual(msg.role, role)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let averagePerTurnMs = (elapsed / Double(turnCount)) * 1000.0

        // Verify session total turns
        let session = try repository.fetchSession(sessionID: sessionID)
        XCTAssertEqual(session?.totalTurns, turnCount)

        let totalRecorded = try repository.countTurns(sessionID: sessionID)
        XCTAssertEqual(totalRecorded, turnCount)

        // Verify sliding window fetch (limit: 10, chronological order)
        let recent10 = try repository.fetchRecentTurns(sessionID: sessionID, limit: 10, ascending: true)
        XCTAssertEqual(recent10.count, 10)
        XCTAssertEqual(recent10.first?.turnIndex, 91)
        XCTAssertEqual(recent10.last?.turnIndex, 100)

        // Verify sliding window fetch in descending order
        let recent10Desc = try repository.fetchRecentTurns(sessionID: sessionID, limit: 10, ascending: false)
        XCTAssertEqual(recent10Desc.count, 10)
        XCTAssertEqual(recent10Desc.first?.turnIndex, 100)
        XCTAssertEqual(recent10Desc.last?.turnIndex, 91)

        // Ensure performance stays fast
        XCTAssertLessThan(averagePerTurnMs, 5.0)
    }

    func testLineagePointerJumpAccuracy() throws {
        let repository = try TranscriptRepository.inMemory()
        let sessionID = "sess_lineage_test"

        try repository.createSession(
            sessionID: sessionID,
            agentID: "fact_miner",
            title: "Fact Extraction Dialogue"
        )

        var pointers: [LineagePointer] = []
        for i in 1...20 {
            let role: TranscriptRole = (i % 2 == 1) ? .user : .assistant
            let content = "Conversation turn \(i) presenting key hypothesis \(i)."
            let msg = try repository.appendMessage(
                sessionID: sessionID,
                role: role,
                content: content
            )
            pointers.append(msg.lineagePointer)
        }

        // Test pointer jump at turn 10 with default window size (2)
        let targetPointer = pointers[9] // 0-indexed -> turn 10
        XCTAssertEqual(targetPointer.turnIndex, 10)

        let context = try repository.jumpToSourceContext(pointer: targetPointer, windowSize: 2)
        XCTAssertEqual(context.targetMessage.turnIndex, 10)
        XCTAssertEqual(context.precedingMessages.count, 2)
        XCTAssertEqual(context.precedingMessages.map(\.turnIndex), [8, 9])
        XCTAssertEqual(context.followingMessages.count, 2)
        XCTAssertEqual(context.followingMessages.map(\.turnIndex), [11, 12])
        XCTAssertEqual(context.sessionMeta?.sessionID, sessionID)

        let chronological = context.chronologicalMessages
        XCTAssertEqual(chronological.count, 5)
        XCTAssertEqual(chronological.map(\.turnIndex), [8, 9, 10, 11, 12])

        // Edge case: first turn has no preceding turns
        let firstPointer = pointers[0]
        let firstContext = try repository.jumpToSourceContext(pointer: firstPointer, windowSize: 2)
        XCTAssertEqual(firstContext.targetMessage.turnIndex, 1)
        XCTAssertTrue(firstContext.precedingMessages.isEmpty)
        XCTAssertEqual(firstContext.followingMessages.map(\.turnIndex), [2, 3])

        // Edge case: last turn has no following turns
        let lastPointer = pointers[19]
        let lastContext = try repository.jumpToSourceContext(pointer: lastPointer, windowSize: 2)
        XCTAssertEqual(lastContext.targetMessage.turnIndex, 20)
        XCTAssertEqual(lastContext.precedingMessages.map(\.turnIndex), [18, 19])
        XCTAssertTrue(lastContext.followingMessages.isEmpty)
    }

    func testFTS5FullTextSearchAndScopedSearch() throws {
        let repository = try TranscriptRepository.inMemory()
        let sessionA = "sess_fts_a"
        let sessionB = "sess_fts_b"

        try repository.createSession(sessionID: sessionA, agentID: "agent_a", title: "Session A")
        try repository.createSession(sessionID: sessionB, agentID: "agent_b", title: "Session B")

        try repository.appendMessage(
            sessionID: sessionA,
            role: .user,
            content: "Quantum entanglement enables quantum teleportation protocols in laboratory environments."
        )
        try repository.appendMessage(
            sessionID: sessionA,
            role: .assistant,
            content: "Quantum states and classical communication channels are still strictly required to transmit measurement outcomes."
        )
        try repository.appendMessage(
            sessionID: sessionB,
            role: .user,
            content: "Quantum algorithms provide polynomial speedups for unstructured database search tasks."
        )

        // Global FTS search
        let globalResults = try repository.search(query: "quantum")
        XCTAssertEqual(globalResults.count, 3)

        // Scoped search on session A
        let scopedResultsA = try repository.search(query: "quantum", sessionID: sessionA)
        XCTAssertEqual(scopedResultsA.count, 2)
        XCTAssertTrue(scopedResultsA.allSatisfy { $0.sessionID == sessionA })

        // Scoped search on session B
        let scopedResultsB = try repository.search(query: "teleportation", sessionID: sessionB)
        XCTAssertTrue(scopedResultsB.isEmpty)

        // Detailed search verification with highlights
        let detailed = try repository.searchDetailed(query: "teleportation", sessionID: sessionA)
        XCTAssertEqual(detailed.count, 1)
        XCTAssertTrue(detailed[0].snippet.contains("<mark>teleportation</mark>"))
        XCTAssertEqual(detailed[0].message.role, .user)
    }

    func testAtomicAppendAndCascadeDeletion() throws {
        let repository = try TranscriptRepository.inMemory()
        let sessionID = "sess_cascade"

        try repository.createSession(sessionID: sessionID, agentID: "agent_cascade", title: "Cascade Test")
        try repository.appendMessage(sessionID: sessionID, role: .user, content: "Initial query")
        try repository.appendMessage(sessionID: sessionID, role: .assistant, content: "Initial response")

        XCTAssertEqual(try repository.countTurns(sessionID: sessionID), 2)

        // Delete session
        try repository.deleteSession(sessionID: sessionID)

        XCTAssertNil(try repository.fetchSession(sessionID: sessionID))
        XCTAssertEqual(try repository.countTurns(sessionID: sessionID), 0)

        // FTS search should also be cleared via triggers
        let searchResults = try repository.search(query: "Initial")
        XCTAssertTrue(searchResults.isEmpty)
    }

    func testAffectiveAndDualStateBindingAndQuery() throws {
        guard let tempDir else { return }
        let dbPath = tempDir.appendingPathComponent("transcripts_affect.sqlite").path
        let db = try TranscriptDatabase(path: dbPath)
        let repository = TranscriptRepository(database: db)

        let sessionID = "sess_affective_01"
        try repository.createSession(
            sessionID: sessionID,
            agentID: "agent_pc_alm",
            title: "Affective Homeostatic Dialogue"
        )

        // Turn 1: baseline calm turn
        let msg1 = try repository.appendMessage(
            sessionID: sessionID,
            role: .user,
            content: "Hello, system status check.",
            affect: HomeostaticAffectSnapshot(valence: 0.1, arousal: 0.05, homeostaticDelta: 0.02),
            dualState: DualStateSnapshot(lambdaValence: 0.01, lambdaArousal: 0.02, lambdaDeltaH: 0.01)
        )
        XCTAssertEqual(msg1.turnIndex, 1)

        // Turn 2: severe homeostatic error / perturbation
        let msg2 = try repository.appendMessage(
            sessionID: sessionID,
            role: .assistant,
            content: "Sudden constraint violation encountered in dual neuron.",
            affect: HomeostaticAffectSnapshot(valence: -0.75, arousal: 0.85, homeostaticDelta: 0.82),
            dualState: DualStateSnapshot(lambdaValence: 0.45, lambdaArousal: 0.60, lambdaDeltaH: 0.95)
        )
        XCTAssertEqual(msg2.turnIndex, 2)

        // Turn 3: negative perturbation (homeostatic deficit)
        let msg3 = try repository.appendMessage(
            sessionID: sessionID,
            role: .user,
            content: "Applying corrective predictive coding update.",
            affect: HomeostaticAffectSnapshot(valence: -0.60, arousal: 0.70, homeostaticDelta: -0.78),
            dualState: DualStateSnapshot(lambdaValence: 0.30, lambdaArousal: 0.40, lambdaDeltaH: 0.88)
        )
        XCTAssertEqual(msg3.turnIndex, 3)

        // Turn 4: minor perturbation
        let msg4 = try repository.appendMessage(
            sessionID: sessionID,
            role: .assistant,
            content: "Error converging, homeostatic equilibrium returning.",
            affect: HomeostaticAffectSnapshot(valence: 0.20, arousal: 0.15, homeostaticDelta: 0.08),
            dualState: DualStateSnapshot(lambdaValence: 0.05, lambdaArousal: 0.04, lambdaDeltaH: 0.09)
        )
        XCTAssertEqual(msg4.turnIndex, 4)

        // Turn 5: plain message with nil affect and nil dualState
        let msg5 = try repository.appendMessage(
            sessionID: sessionID,
            role: .user,
            content: "Equilibrium restored. Standing by."
        )
        XCTAssertEqual(msg5.turnIndex, 5)

        // 1. Verify exact field retrieval for Turn 2
        let fetchedTurn2 = try repository.fetchTurn(sessionID: sessionID, turnIndex: 2)
        XCTAssertNotNil(fetchedTurn2)
        XCTAssertEqual(fetchedTurn2?.affect?.valence, -0.75)
        XCTAssertEqual(fetchedTurn2?.affect?.arousal, 0.85)
        XCTAssertEqual(fetchedTurn2?.affect?.homeostaticDelta, 0.82)
        XCTAssertEqual(fetchedTurn2?.dualState?.lambdaValence, 0.45)
        XCTAssertEqual(fetchedTurn2?.dualState?.lambdaArousal, 0.60)
        XCTAssertEqual(fetchedTurn2?.dualState?.lambdaDeltaH, 0.95)

        // 2. Verify nil affect / dualState for Turn 5
        let fetchedTurn5 = try repository.fetchTurn(sessionID: sessionID, turnIndex: 5)
        XCTAssertNotNil(fetchedTurn5)
        XCTAssertNil(fetchedTurn5?.affect)
        XCTAssertNil(fetchedTurn5?.dualState)

        // 3. Fast affective turn extraction with minDeltaH threshold 0.5
        let startTime = CFAbsoluteTimeGetCurrent()
        let affectiveTurns = try repository.fetchAffectiveTurns(sessionID: sessionID, minDeltaH: 0.5)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        XCTAssertEqual(affectiveTurns.count, 2)
        XCTAssertEqual(affectiveTurns.map(\.turnIndex), [2, 3])
        XCTAssertLessThan(elapsedMs, 2.0)

        // 4. Persistence verification across database reopen
        db.close()
        let reopenedDb = try TranscriptDatabase(path: dbPath)
        let reopenedRepo = TranscriptRepository(database: reopenedDb)

        let reloadedTurns = try reopenedRepo.fetchAffectiveTurns(sessionID: sessionID, minDeltaH: 0.5)
        XCTAssertEqual(reloadedTurns.count, 2)
        XCTAssertEqual(reloadedTurns[0].affect?.valence, -0.75)
        XCTAssertEqual(reloadedTurns[0].dualState?.lambdaDeltaH, 0.95)
        XCTAssertEqual(reloadedTurns[1].affect?.valence, -0.60)
        XCTAssertEqual(reloadedTurns[1].dualState?.lambdaDeltaH, 0.88)

        reopenedDb.close()
    }
}
