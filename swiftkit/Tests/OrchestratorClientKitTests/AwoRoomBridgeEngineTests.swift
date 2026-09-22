import XCTest
@testable import OrchestratorClientKit
import InteropKit

final class AwoRoomBridgeEngineTests: XCTestCase {
    func testAttributionEngineTier1() {
        let room = BridgeRoomSummary(
            id: "room-123", planID: "plan-1", title: "Test Room", blueprintSlug: "bp",
            occupant: "worker", occupantHandle: "handle", workdir: "/tmp/work",
            canonicalWorkdir: "/private/tmp/work", state: "occupied", tenantID: "t-1", toolbelt: []
        )
        let origin = OriginRef(app: "agent-work-todo", roomID: "room-123", messageID: "m-1", replyTo: nil)
        let job = BridgeJobSummary(
            id: "job-1", title: "Test Job", state: "running", detailedPhase: .runningWorker,
            workdir: "/tmp/work", canonicalWorkdir: "/private/tmp/work", tenantID: "t-1",
            origin: origin, claimedBy: "handle", processID: 100, logPath: nil, since: Date(), progressRatio: nil
        )
        
        let result = AttributionEngine.attribute(rooms: [room], jobs: [job], blueprints: [:])
        
        XCTAssertEqual(result.attributed.count, 1)
        XCTAssertEqual(result.attributed[0].tier, .tier1OriginRef)
    }
    
    func testAttributionEngineTier2() {
        let room = BridgeRoomSummary(
            id: "room-123", planID: "plan-1", title: "Test Room", blueprintSlug: "bp",
            occupant: "worker", occupantHandle: "handle", workdir: "/tmp/work",
            canonicalWorkdir: "/private/tmp/work", state: "occupied", tenantID: "t-1", toolbelt: []
        )
        let job = BridgeJobSummary(
            id: "job-1", title: "Test Job", state: "running", detailedPhase: .runningWorker,
            workdir: "/tmp/work", canonicalWorkdir: "/private/tmp/work", tenantID: "t-1",
            origin: nil, claimedBy: "handle", processID: 100, logPath: nil, since: Date(), progressRatio: nil
        )
        
        let result = AttributionEngine.attribute(rooms: [room], jobs: [job], blueprints: [:])
        
        XCTAssertEqual(result.attributed.count, 1)
        XCTAssertEqual(result.attributed[0].tier, .tier2CanonicalWorkdir)
    }
}
