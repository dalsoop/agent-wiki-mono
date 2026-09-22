import BacklogClientKit
import BacklogKit
import CommandKit
import Foundation
import Testing

@Suite("BacklogClientKit")
struct BacklogClientKitTests {
    @Test func listDecodesArray() async throws {
        let testID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let item = try BacklogItem(
            id: testID,
            content: .init(
                slug: "raster-image-editor-swift",
                title: "i18n",
                description: "i18n support",
                source: "manual",
                kind: .feature
            ),
            scoring: .init(priority: .p0, impact: 5, effort: 1, status: .planned)
        )
        let json = String(data: try BacklogCodec.encode([item]), encoding: .utf8)!
        let runner = RecordingRunner(result: CommandResult(stdout: json, stderr: "", exitCode: 0))
        let client = BacklogClient(runner: runner, executablePath: "/fake/fbl")
        let items = await client.list(status: "planned")
        #expect(items.count == 1)
        #expect(items.first?.id == testID)
        #expect(items.first?.priority == .p0)
        let args = await runner.lastArguments
        #expect(args == ["list", "--json", "--status", "planned"])
    }

    @Test func updateStatusPassesFlags() async {
        let runner = RecordingRunner(result: CommandResult(stdout: "", stderr: "", exitCode: 0))
        let client = BacklogClient(runner: runner, executablePath: "/fake/fbl")
        let ok = await client.updateStatus(id: "abc", status: "done")
        #expect(ok)
        let args = await runner.lastArguments
        #expect(args == ["update-status", "abc", "--status", "done"])
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
