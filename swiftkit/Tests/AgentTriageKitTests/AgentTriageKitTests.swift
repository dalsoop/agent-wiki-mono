import Foundation
import Testing
@testable import AgentTriageKit

@Suite("AgentTriageKit Tests")
struct AgentTriageKitTests {
    @Test("영수증 저장 및 복원 테스트")
    func testReceiptStore() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = TriageReceiptStore(customDirectory: tempDir)
        let ctx = ExecutionContext(command: "echo test", workingDirectory: "/tmp")
        let receipt = TriageReceipt(
            artifactID: "proc-123",
            kind: .process,
            displayName: "echo test",
            recoveredCPU: 12.5,
            context: ctx
        )

        try await store.append(receipt)
        let loaded = await store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded.first?.artifactID == "proc-123")
        #expect(!(loaded.first?.isRevived ?? true))

        await store.markRevived(id: receipt.id)
        let revived = await store.loadAll()
        #expect(revived.first?.isRevived ?? false)
    }

    @Test("프로세스 부활 파이프라인 테스트")
    func testReviver() async throws {
        let ctx = ExecutionContext(command: "sleep 1", workingDirectory: "/tmp")
        let receipt = TriageReceipt(
            artifactID: "proc-999",
            kind: .process,
            displayName: "sleep 1",
            context: ctx
        )

        let res = await UniversalReviver.revive(receipt: receipt)
        switch res {
        case .processRevived(let newPID):
            #expect(newPID > 0)
        default:
            Issue.record("부활 실패")
        }
    }
}
