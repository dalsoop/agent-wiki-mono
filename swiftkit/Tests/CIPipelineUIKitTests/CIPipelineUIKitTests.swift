import XCTest
@testable import CIPipelineUIKit

final class CIPipelineUIKitTests: XCTestCase {
    func testCIJobStatusParsing() {
        XCTAssertEqual(CIJobStatus(raw: "success"), .success)
        XCTAssertEqual(CIJobStatus(raw: "running"), .running)
        XCTAssertEqual(CIJobStatus(raw: "failed"), .failed)
        XCTAssertEqual(CIJobStatus(raw: "canceled"), .canceled)
        XCTAssertEqual(CIJobStatus(raw: "skipped"), .skipped)
        XCTAssertEqual(CIJobStatus(raw: "pending"), .pending)
        XCTAssertEqual(CIJobStatus(raw: "in_progress"), .running)
    }

    func testFormattedDuration() {
        let job1 = CIJobItem(id: "1", name: "build", stage: "build", status: .success, duration: 42)
        XCTAssertEqual(job1.formattedDuration, "42s")

        let job2 = CIJobItem(id: "2", name: "test", stage: "test", status: .running, duration: 856)
        XCTAssertEqual(job2.formattedDuration, "14m 16s")

        let job3 = CIJobItem(id: "3", name: "long", stage: "deploy", status: .success, duration: 3725)
        XCTAssertEqual(job3.formattedDuration, "1h 02m")
    }

    func testStageGrouping() {
        let jobs = [
            CIJobItem(id: "1", name: "sanity", stage: "sanity", status: .success),
            CIJobItem(id: "2", name: "lint", stage: "sanity", status: .success),
            CIJobItem(id: "3", name: "macos:build-tests", stage: "test", status: .running),
            CIJobItem(id: "4", name: "linux:test", stage: "test", status: .failed)
        ]

        let stages = CIPipelineStage.groupIntoStages(jobs: jobs)
        XCTAssertEqual(stages.count, 2)

        XCTAssertEqual(stages[0].name, "sanity")
        XCTAssertEqual(stages[0].jobs.count, 2)
        XCTAssertEqual(stages[0].status, .success)

        XCTAssertEqual(stages[1].name, "test")
        XCTAssertEqual(stages[1].jobs.count, 2)
        XCTAssertEqual(stages[1].status, .failed) // failed > running
    }
}
