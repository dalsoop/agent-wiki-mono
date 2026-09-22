import Foundation
import Testing
@testable import GujoStoreOpsCore

@Suite("ServiceOpsContext")
struct ServiceOpsContextTests {
    @Test("hub READY round-trip survives iso8601 decode")
    func hubReadyRoundTrip() throws {
        // 격리: 테스트 전용 디렉터리로 바꾸지 않고, 기존 파일 백업 후 복구
        let url = ServiceOpsContext.fileURL
        let dir = ServiceOpsContext.directory
        let backup = try? Data(contentsOf: url)
        defer {
            if let backup {
                do {
                    try backup.write(to: url, options: .atomic)
                } catch {
                    Issue.record("restore backup failed: \(error)")
                }
            } else {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    Issue.record("cleanup context file failed: \(error)")
                }
            }
        }

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        ServiceOpsContext.recordHub(ready: true)
        #expect(ServiceOpsContext.hubReadyWithin(minutes: 30))
        #expect(ServiceOpsContext.load().lastHubReady == true)
        #expect(ServiceOpsContext.load().lastHubReadyAt != nil)

        ServiceOpsContext.recordHub(ready: false)
        // ready=false 는 lastHubReadyAt 을 지우지 않지만 lastHubReady=false → within false
        #expect(!ServiceOpsContext.hubReadyWithin(minutes: 30))
    }
}
