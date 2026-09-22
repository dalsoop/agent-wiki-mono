import XCTest
import CryptoKit
@testable import HomeostasisEngineKit

final class SensorimotorShapeEngineTests: XCTestCase {
    private let engine = SensorimotorShapeEngine()

    func testTokenBlockPayloadHashComputation() {
        let payload = "deterministic_invariant_rule_content"
        let block = TokenBlock(shape: .deterministicFixed, payloadString: payload)

        let expectedHash = SHA256.hash(data: Data(payload.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        XCTAssertEqual(block.payloadHash, expectedHash)
    }

    func testEvaluateFitSuccessWhenShapeAndHashMatch() {
        let payload = "valid_native_swift_cli"
        let block = TokenBlock(shape: .nativeSwiftCli, payloadString: payload)
        let socket = InvariantSocket(
            id: "socket-swift-cli",
            name: "App Build Manager Socket",
            requiredShape: .nativeSwiftCli,
            baselineHash: block.payloadHash
        )

        XCTAssertTrue(engine.verifyFit(block: block, into: socket))

        let result = engine.evaluateFit(block: block, into: socket)
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.revertedHash, block.payloadHash)

        if case .clickedIn(let socketId, let restoredHash, let score, let deltaH, let boost) = result {
            XCTAssertEqual(socketId, "socket-swift-cli")
            XCTAssertEqual(restoredHash, block.payloadHash)
            XCTAssertEqual(score, 1.0)
            XCTAssertEqual(deltaH, 0.0)
            XCTAssertEqual(boost, 0.85)
        } else {
            XCTFail("Expected clickedIn result")
        }
    }

    func testEvaluateFitRejectsWhenShapeMismatches() {
        let payload = "unmanaged_script.sh"
        let block = TokenBlock(shape: .unmanagedShellScript, payloadString: payload)
        let socket = InvariantSocket(
            id: "socket-strict-cli",
            name: "Strict Swift CLI Socket",
            requiredShape: .nativeSwiftCli,
            baselineHash: "some_previous_hash"
        )

        XCTAssertFalse(engine.verifyFit(block: block, into: socket))

        let result = engine.evaluateFit(block: block, into: socket)
        XCTAssertFalse(result.isSuccess)
        XCTAssertEqual(result.revertedHash, "some_previous_hash")

        if case .collidedAndRejected(let socketId, let attemptedShape, let pain, let baseline) = result {
            XCTAssertEqual(socketId, "socket-strict-cli")
            XCTAssertEqual(attemptedShape, .unmanagedShellScript)
            XCTAssertEqual(pain, -0.85)
            XCTAssertEqual(baseline, "some_previous_hash")
        } else {
            XCTFail("Expected collidedAndRejected result")
        }
    }

    func testCuriosityNoveltyScoreHierarchy() {
        let novelScore = engine.curiosityNoveltyScore(for: .unknownNovelShape)
        let unmanagedScore = engine.curiosityNoveltyScore(for: .unmanagedShellScript)
        let fixedScore = engine.curiosityNoveltyScore(for: .deterministicFixed)

        XCTAssertEqual(novelScore, 0.75)
        XCTAssertEqual(unmanagedScore, 0.55)
        XCTAssertEqual(fixedScore, 0.20)
        XCTAssertGreaterThan(novelScore, unmanagedScore)
        XCTAssertGreaterThan(unmanagedScore, fixedScore)
    }
}
