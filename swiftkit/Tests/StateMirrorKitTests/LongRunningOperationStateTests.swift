import Foundation
import XCTest
@testable import StateMirrorKit

final class LongRunningOperationStateTests: XCTestCase {
    private struct FixtureState: Decodable, Sendable {
        let value: String
    }

    func testFractionUsesRealDenominatorAndClampsCompleted() {
        let state = LongRunningOperationState(
            status: .running,
            operation: "graphify-update",
            phase: "extracting",
            completed: 12,
            total: 10,
            unit: "files",
            currentTarget: "/repo",
            report: .init(startedAt: "2026-07-23T00:00:00Z", message: "12/10")
        )
        XCTAssertEqual(state.completed, 10)
        XCTAssertEqual(state.fractionCompleted, 1)
    }

    func testFractionIsNilWithoutPositiveTotal() {
        let state = LongRunningOperationState(
            status: .running,
            operation: "graphify-update",
            phase: "preparing",
            currentTarget: "/repo"
        )
        XCTAssertNil(state.fractionCompleted)
    }

    func testReadDecodesTypedEnvelopeFromExplicitURL() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("mirror.json")
        try """
        {
          "app":"KnowledgeGraphStudio",
          "updatedAt":"2026-07-23T00:00:00Z",
          "state":{"value":"ready"}
        }
        """.write(to: url, atomically: true, encoding: .utf8)
        let envelope = try StateMirror.read(url: url, as: FixtureState.self)
        XCTAssertEqual(envelope.app, "KnowledgeGraphStudio")
        XCTAssertEqual(envelope.state.value, "ready")
    }

    func testReadDistinguishesMissingAndMalformedFiles() throws {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(
            try StateMirror.read(url: missingURL, as: FixtureState.self)
        ) { XCTAssertEqual($0 as? StateMirrorReadError, .missing(missingURL.path)) }

        let malformedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: malformedURL) }
        try "not json".write(to: malformedURL, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(
            try StateMirror.read(url: malformedURL, as: FixtureState.self)
        ) { XCTAssertTrue(($0 as? StateMirrorReadError).map {
            if case .malformed = $0 { return true }
            return false
        } ?? false) }
    }
}
