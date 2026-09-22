import XCTest
@testable import GenerativeImageMetaKit

final class GenerativeImageMetaKitTests: XCTestCase {
    func testRoundTripPromptAndSystemOnJPEG() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gmeta-\(UUID().uuidString).jpg")
        try GenerativeImageMetaIO.writeMinimalJPEG(to: url)
        let written = GenerativeImageMeta(
            prompt: "tiny pixel art RPG sprite",
            systemUsed: "grok-4.5",
            systemVersion: "2026-08",
            promptWriter: "ledger"
        )
        try GenerativeImageMetaIO.write(meta: written, to: url)
        let read = try XCTUnwrap(GenerativeImageMetaIO.read(from: url))
        XCTAssertEqual(read.prompt, written.prompt)
        XCTAssertEqual(read.systemUsed, written.systemUsed)
        XCTAssertEqual(read.digitalSourceType, .trainedAlgorithmicMedia)
        try GenerativeImageMetaIO.requirePromptAndSystem(at: url, prompt: "tiny pixel art RPG sprite")
    }

    func testBareJPEGIsRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gmeta-bare-\(UUID().uuidString).jpg")
        try GenerativeImageMetaIO.writeMinimalJPEG(to: url)
        XCTAssertNil(GenerativeImageMetaIO.read(from: url))
        XCTAssertThrowsError(try GenerativeImageMetaIO.requirePromptAndSystem(at: url, prompt: "anything")) { error in
            XCTAssertEqual(error as? GenerativeImageMetaError, .missingMetadata)
        }
    }

    func testVideoSidecarRoundTripRequiresModel() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gmeta-vid-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let mp4 = dir.appendingPathComponent("clip.mp4")
        try Data("mp4".utf8).write(to: mp4)
        XCTAssertNil(GenerativeMediaSidecar.read(nextTo: mp4))
        try GenerativeMediaSidecar.write(
            GenerativeMediaSidecar(
                prompt: "slow camera pan",
                systemUsed: "h3",
                provider: "gpu-h3",
                aspect: "16:9",
                durationSeconds: 5
            ),
            nextTo: mp4
        )
        let read = try XCTUnwrap(GenerativeMediaSidecar.read(nextTo: mp4))
        XCTAssertEqual(read.systemUsed, "h3")
        XCTAssertEqual(read.provider, "gpu-h3")
        try GenerativeMediaSidecar.requirePromptAndSystem(at: mp4, prompt: "slow camera pan", model: "h3")
        XCTAssertThrowsError(try GenerativeMediaSidecar.requirePromptAndSystem(at: mp4, prompt: "slow camera pan", model: "other"))
    }
}
