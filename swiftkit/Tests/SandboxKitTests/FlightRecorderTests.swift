import Foundation
@testable import SandboxKit
import XCTest

final class FlightRecorderTests: XCTestCase {
    var tempHome: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("flight-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempHome, FileManager.default.fileExists(atPath: tempHome.path) {
            try? FileManager.default.removeItem(at: tempHome)
        }
        try super.tearDownWithError()
    }

    func testFlightRecorder_AutoRecordsExecution() throws {
        let ctx = try SandboxContext.allocate(tenant: "acme-test", homeDirectory: tempHome.path)
        defer { try? ctx.teardown() }

        let result = try SandboxRunner.run(
            executable: "/bin/echo",
            arguments: ["hello", "flight", "recorder"],
            context: ctx,
            applySeatbelt: false
        )

        XCTAssertTrue(result.isSuccess)
        let history = try FlightRecorder.readHistory(context: ctx)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].stepIndex, 1)
        XCTAssertEqual(history[0].executable, "/bin/echo")
        XCTAssertEqual(history[0].arguments, ["hello", "flight", "recorder"])
        XCTAssertEqual(history[0].stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello flight recorder")
        XCTAssertEqual(history[0].exitCode, 0)
        XCTAssertGreaterThan(history[0].durationMs, 0)
    }

    func testFlightRecorder_ReplayTimeTravel() throws {
        let ctx = try SandboxContext.allocate(tenant: "replay-test", homeDirectory: tempHome.path)
        defer { try? ctx.teardown() }

        _ = try SandboxRunner.run(executable: "/bin/echo", arguments: ["step 1"], context: ctx, applySeatbelt: false)
        _ = try SandboxRunner.run(executable: "/bin/echo", arguments: ["step 2"], context: ctx, applySeatbelt: false)
        _ = try SandboxRunner.run(executable: "/bin/echo", arguments: ["step 3"], context: ctx, applySeatbelt: false)

        let allHistory = try FlightRecorder.readHistory(context: ctx)
        XCTAssertEqual(allHistory.count, 3)

        let replayed = try FlightRecorder.replay(upToStep: 2, context: ctx)
        XCTAssertEqual(replayed.count, 2)
        XCTAssertEqual(replayed[0].arguments, ["step 1"])
        XCTAssertEqual(replayed[1].arguments, ["step 2"])
    }
}
