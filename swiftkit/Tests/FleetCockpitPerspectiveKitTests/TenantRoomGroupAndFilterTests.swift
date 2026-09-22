import XCTest
@testable import FleetCockpitPerspectiveKit

final class TenantRoomGroupAndFilterTests: XCTestCase {

    func testElectronAndAppHelperExclusion() {
        // 1. 데스크톱 앱 공백 포함 경로 및 GUI 번들 실행
        let grokDesktop = "/Applications/Grok Bot.app/Contents/MacOS/Grok Bot --hidden"
        XCTAssertTrue(HostAgentLineageExtractor.isAppOrHelperProcess(grokDesktop))
        XCTAssertEqual(HostAgentLineageExtractor.detectRole(grokDesktop), .other)

        let chatGPTApp = "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT"
        XCTAssertTrue(HostAgentLineageExtractor.isAppOrHelperProcess(chatGPTApp))
        XCTAssertEqual(HostAgentLineageExtractor.detectRole(chatGPTApp), .other)

        // 2. Electron Renderer / GPU / Crashpad 헬퍼
        let renderer = "/Applications/Slack.app/Contents/Frameworks/Slack Helper (Renderer).app"
            + "/Contents/MacOS/Slack Helper (Renderer) --type=renderer"
        XCTAssertTrue(HostAgentLineageExtractor.isAppOrHelperProcess(renderer))
        XCTAssertEqual(HostAgentLineageExtractor.detectRole(renderer), .other)

        let gpuProcess = "/Applications/VSCode.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper --type=gpu-process"
        XCTAssertTrue(HostAgentLineageExtractor.isAppOrHelperProcess(gpuProcess))
        XCTAssertEqual(HostAgentLineageExtractor.detectRole(gpuProcess), .other)

        // 3. 실제 CLI 에이전트는 올바르게 감지
        let realClaude = "/usr/local/bin/claude --dangerously-skip-permissions"
        XCTAssertFalse(HostAgentLineageExtractor.isAppOrHelperProcess(realClaude))
        XCTAssertEqual(HostAgentLineageExtractor.detectRole(realClaude), .claude)

        let realAgy = "agy -p '테넌트 도메인'"
        XCTAssertFalse(HostAgentLineageExtractor.isAppOrHelperProcess(realAgy))
        XCTAssertEqual(HostAgentLineageExtractor.detectRole(realAgy), .agy)
    }

    func testTransientCLICommandsExcludedFromSubagents() {
        let parentPID: Int32 = 1000
        let childrenMap: [Int32: [ProcessRecord]] = [
            1000: [
                ProcessRecord(pid: 1001, ppid: 1000, tty: nil, command: "git status"),
                ProcessRecord(pid: 1002, ppid: 1000, tty: nil, command: "ps -axww"),
                ProcessRecord(pid: 1003, ppid: 1000, tty: nil, command: "swift test"),
                ProcessRecord(pid: 1004, ppid: 1000, tty: nil, command: "node /path/to/worker-subagent.js")
            ]
        ]

        var subPIDs: [Int32] = []
        HostAgentLineageExtractor.collectSubagents(ppid: parentPID, childrenMap: childrenMap, into: &subPIDs)

        // git, ps, swift는 임시 CLI이므로 배제되고 worker-subagent만 포함되어야 함
        XCTAssertEqual(subPIDs, [1004])
    }

    func testRoomTitleResolverDeterministicLadder() {
        // 1. 방 전용 task 최우선
        let t1 = RoomTitleResolver.resolveTitle(
            roomDict: ["task": "FleetDock 3계층 도메인 설계"],
            planTitle: "상주 지휘 — 대화형 세션",
            blueprintSlug: "fleetdock-ux-architecture",
            occupantHandle: "🦊 불꽃 여우"
        )
        XCTAssertEqual(t1, "FleetDock 3계층 도메인 설계")

        // 2. blueprintSlug 파싱 + occupantHandle 결합
        let t2 = RoomTitleResolver.resolveTitle(
            roomDict: [:],
            planTitle: "상주 지휘 — 대화형 세션",
            blueprintSlug: "fleetdock-ux-architecture",
            occupantHandle: "🦊 불꽃 여우"
        )
        XCTAssertEqual(t2, "Fleetdock Ux Architecture (🦊 불꽃 여우)")

        // 3. occupantHandle 단독
        let t3 = RoomTitleResolver.resolveTitle(
            roomDict: [:],
            planTitle: "상주 지휘 — 대화형 세션",
            blueprintSlug: "",
            occupantHandle: "🦊 불꽃 여우"
        )
        XCTAssertEqual(t3, "🦊 불꽃 여우의 방")

        // 4. occupant 단독
        let t4 = RoomTitleResolver.resolveTitle(
            roomDict: [:],
            planTitle: "상주 지휘 — 대화형 세션",
            blueprintSlug: "",
            occupantHandle: "",
            occupant: "agent:worker1@jeonghans-macbook-pro"
        )
        XCTAssertEqual(t4, "worker1의 방")
    }

    func testTenantRoomGroupDataStructure() {
        let personal = TenantContext(slug: "personal")
        XCTAssertEqual(personal.slug, "personal")
        XCTAssertEqual(personal.logicalID, "tenant:personal")
        XCTAssertEqual(personal.symbol, "person.fill")
        XCTAssertEqual(personal.colorHex, "#5E5CE6")

        let room1 = ActiveRoomEntry(
            id: "room-1",
            planID: "plan-1",
            title: "방 1",
            blueprintSlug: "slug-1",
            occupant: "agent:fox@host",
            occupantHandle: "🦊",
            workdir: "/repo",
            state: "occupied",
            handoverState: "none",
            tenantID: "tenant:personal"
        )

        let barItem = UnifiedBarItem(
            id: "room-room-1",
            title: "방 1",
            subtitle: "🦊",
            icon: .symbol("person.2.fill"),
            statusDot: .running
        )

        let group = TenantRoomGroup(tenant: personal, rooms: [room1], barItems: [barItem])
        XCTAssertEqual(group.activeOccupantCount, 1)
        XCTAssertEqual(group.rooms.count, 1)
        XCTAssertEqual(group.barItems.count, 1)
    }
}
