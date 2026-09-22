import CommandKit
import Foundation
import SeatReaderKit
import Testing

@Suite("SeatReaderKit")
struct SeatReaderKitTests {
    @Test func seatsDecodesArray() async {
        let json = """
        [{"handle":"claude","kind":"worker","occupant":"claude","tier":"worker","dailyUSD":5}]
        """
        let runner = RecordingRunner(result: CommandResult(stdout: json, stderr: "", exitCode: 0))
        let client = SeatReaderClient(runner: runner, executablePath: "/fake/seat")
        let seats = await client.seats()
        #expect(seats.map(\.handle) == ["claude"])
        #expect(seats.first?.dailyUSD == 5)
        let args = await runner.lastArguments
        #expect(args == ["seats", "--json"])
    }

    @Test func seatDecodesSingleObject() async {
        let json = #"{"handle":"codex","occupant":"codex"}"#
        let runner = RecordingRunner(result: CommandResult(stdout: json, stderr: "", exitCode: 0))
        let client = SeatReaderClient(runner: runner, executablePath: "/fake/seat")
        let seat = await client.seat(handle: "codex")
        #expect(seat?.handle == "codex")
        let args = await runner.lastArguments
        #expect(args == ["seat", "codex", "--json"])
    }
}

private actor RecordingRunner: CommandRunning {
    let result: CommandResult
    private(set) var lastArguments: [String] = []

    init(result: CommandResult) { self.result = result }

    func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
        lastArguments = arguments
        return result
    }
}
