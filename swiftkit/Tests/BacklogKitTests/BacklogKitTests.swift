import BacklogKit
import CommandKit
import Foundation
import Testing

@Suite("BacklogKit")
struct BacklogKitTests {
    @Test func itemCreationAndValidation() throws {
        let item = try BacklogItem(
            content: .init(
                slug: "test-app",
                title: "Fix crash on launch",
                description: "App crashes when launching with empty cache",
                source: "manual",
                kind: .defect
            ),
            scoring: .init(priority: .p0, impact: 5, effort: 1, status: .inProgress)
        )
        #expect(item.slug == "test-app")
        #expect(item.kind == .defect)
        #expect(item.priority == .p0)
        #expect(item.status == .inProgress)
    }

    @Test func sourceAcceptsDocumentedForms() {
        #expect(BacklogItem.isValid(source: "manual"))
        #expect(BacklogItem.isValid(source: "session-2026-09-06-room-fix"))
        #expect(BacklogItem.isValid(source: "session"))
        #expect(BacklogItem.isValid(source: "feedback:abcdef"))
        #expect(BacklogItem.isValid(source: "evaluation:app-alpha"))
    }

    @Test func sourceRejectsInvalidForms() {
        #expect(!BacklogItem.isValid(source: ""))
        #expect(!BacklogItem.isValid(source: "has space"))
        #expect(!BacklogItem.isValid(source: "feedback:"))
        #expect(!BacklogItem.isValid(source: "evaluation:Bad Slug"))
        #expect(!BacklogItem.isValid(source: "대문자슬러그"))
    }

    @Test func itemCreationAcceptsSessionSource() throws {
        let item = try BacklogItem(
            content: .init(
                slug: "test-app",
                title: "Fix intake ladder",
                description: "Session-sourced defect",
                source: "session-2026-09-06-room-fix"
            )
        )
        #expect(item.source == "session-2026-09-06-room-fix")
    }

    @Test func invalidSourceErrorNamesValueAndAllowedFormats() {
        do {
            _ = try BacklogItem(
                content: .init(
                    slug: "test-app",
                    title: "t",
                    description: "d",
                    source: "has space"
                )
            )
            Issue.record("source 검증을 통과하면 안 됩니다")
        } catch let error as BacklogError {
            guard case let .invalidField(field) = error else {
                Issue.record("invalidField 가 아닌 BacklogError 입니다: \(error)")
                return
            }
            #expect(field.contains("has space"))
            #expect(field.contains("session-2026-09-06-room-fix"))
            #expect(field.contains("feedback:ID"))
        } catch {
            Issue.record("BacklogError 가 아닌 오류입니다: \(error)")
        }
    }

    @Test func storeCRUDAndAppSummary() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("backlogkit-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = BacklogStore(portfolioRoot: tempDir)
        let item1 = try store.add(
            slug: "app-alpha",
            title: "Urgent Bug",
            description: "Bug description",
            source: "manual",
            kind: .defect,
            priority: .p0
        )
        _ = try store.add(
            slug: "app-alpha",
            title: "New Feature",
            description: "Feature description",
            source: "manual",
            kind: .feature,
            priority: .p2
        )
        _ = try store.add(
            slug: "app-beta",
            title: "Beta Feature",
            description: "Beta description",
            source: "manual",
            kind: .feature,
            priority: .p1
        )

        let all = try store.list()
        #expect(all.count == 3)

        let defects = try store.list(kind: .defect)
        #expect(defects.count == 1)
        #expect(defects.first?.id == item1.id)

        let features = try store.list(kind: .feature)
        #expect(features.count == 2)

        let summaries = try store.listAppSummaries()
        #expect(summaries.count == 2)
        let alphaSummary = summaries.first { $0.slug == "app-alpha" }
        #expect(alphaSummary?.openCount == 2)
        #expect(alphaSummary?.defectCount == 1)
        #expect(alphaSummary?.p0DefectCount == 1)

        // Claim
        let claimed = try store.claim(id: item1.id, agent: "agent:test@macbook")
        #expect(claimed.claimedBy == "agent:test@macbook")
        #expect(claimed.claimIsActive())

        // Release
        let released = try store.release(id: item1.id)
        #expect(released.claimedBy == nil)
    }

    @Test func clientSubprocessMock() async {
        let json = """
        [
          {
            "id": "00000000-0000-0000-0000-000000000001",
            "title": "Bug",
            "slug": "app-a",
            "description": "d",
            "source": "manual",
            "kind": "defect",
            "status": "in-progress",
            "priority": "P0",
            "impact": 5,
            "effort": 1,
            "createdAt": "2026-09-05T12:00:00.000Z",
            "updatedAt": "2026-09-05T12:00:00.000Z"
          }
        ]
        """
        let runner = RecordingRunner(result: CommandResult(stdout: json, stderr: "", exitCode: 0))
        let client = BacklogClient(runner: runner, executablePath: "/fake/bin")
        let items = await client.list(status: "in-progress", kind: "defect")
        #expect(items.count == 1)
        #expect(items.first?.kind == .defect)
        #expect(items.first?.priority == .p0)

        let ok = await client.updateStatus(id: "test-id", status: "done")
        #expect(ok)
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
