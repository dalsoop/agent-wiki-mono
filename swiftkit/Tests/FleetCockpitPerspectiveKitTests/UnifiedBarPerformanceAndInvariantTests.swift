import XCTest
@testable import FleetCockpitPerspectiveKit

final class UnifiedBarPerformanceAndInvariantTests: XCTestCase {
    
    // MARK: - 1. Zero-I/O Read Path 성능 검증 (<10μs/회)
    func testZeroIOReadPathPerformance() {
        let store = InvertedStateStore.shared
        
        let start = CFAbsoluteTimeGetCurrent()
        let iterations = 1000
        for _ in 0..<iterations {
            _ = store.currentRooms()
            _ = store.currentAgents()
            _ = store.currentAwoJobs()
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        // 1,000회 3개 메서드 호출(총 3,000회 메모리 락 통과)이 0.05초(50ms) 이내여야 함
        XCTAssertLessThan(elapsed, 0.05, "Zero-I/O read path must take less than 50ms for 1,000 iterations, took \(elapsed)s")
    }

    // MARK: - 2. 대량 로드 결정론적 귀속(Attribution) 검증
    func testAttributionDeterministicMassiveLoad() {
        var rooms: [ActiveRoomEntry] = []
        var jobs: [AwoJobEntry] = []
        
        for i in 1...50 {
            let workdir = "/tmp/repo/project-\(i % 10)"
            rooms.append(
                ActiveRoomEntry(
                    id: "room-\(i)",
                    planID: "plan-\(i)",
                    title: "Room #\(i)",
                    blueprintSlug: "slug-\(i % 5)",
                    occupant: "agent:worker-\(i)@macbook",
                    occupantHandle: "worker-\(i)",
                    workdir: workdir,
                    state: i % 3 == 0 ? "occupied" : "standby",
                    handoverState: "none",
                    tenantID: "tenant:personal"
                )
            )
        }
        
        for j in 1...150 {
            let workdir = "/tmp/repo/project-\(j % 10)"
            jobs.append(
                AwoJobEntry(
                    id: "job-\(j)",
                    title: "Pipeline Job \(j)",
                    state: j % 2 == 0 ? "running" : "queued",
                    tenantID: "tenant:personal",
                    workdir: workdir,
                    slug: "slug-\(j % 5)"
                )
            )
        }
        
        let start = CFAbsoluteTimeGetCurrent()
        let items1 = AttributionEngine.attribute(rooms: rooms, awoJobs: jobs)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        // 50개 룸과 150개 잡 매핑이 0.05초(50ms) 이내 완료되어야 함 (디버그 모드 허용치)
        XCTAssertLessThan(elapsed, 0.05, "Attribution of 50 rooms and 150 jobs must be < 50ms, took \(elapsed)s")
        XCTAssertEqual(items1.count, 50)
        
        // 동일 입력에 대한 2차 실행 결과가 1차와 100% 일치해야 함 (결정론성)
        let items2 = AttributionEngine.attribute(rooms: rooms, awoJobs: jobs)
        XCTAssertEqual(items1, items2, "Attribution must be 100% deterministic")
    }

    // MARK: - 3. Occupant 포맷 파싱 및 AWO 잡 카운트 집계 정합성
    func testOccupantAndSubjobAggregationIntegrity() {
        let room1 = ActiveRoomEntry(
            id: "r1",
            planID: "p1",
            title: "Task Alpha",
            blueprintSlug: "alpha",
            occupant: "agent:codex@macbook",
            occupantHandle: "codex",
            workdir: "/work/alpha",
            state: "occupied",
            handoverState: "none",
            tenantID: "tenant:1"
        )
        XCTAssertEqual(room1.shortOccupant, "codex")
        XCTAssertTrue(room1.isOccupied)

        let room2 = ActiveRoomEntry(
            id: "r2",
            planID: "p2",
            title: "Task Beta",
            blueprintSlug: "beta",
            occupant: "simple-user",
            occupantHandle: "simple",
            workdir: "/work/beta",
            state: "standby",
            handoverState: "none",
            tenantID: "tenant:1"
        )
        XCTAssertEqual(room2.shortOccupant, "simple-user")
        XCTAssertFalse(room2.isOccupied)
        
        let runningJobs = [
            AwoJobEntry(id: "j1", title: "Job 1", state: "running", workdir: "/work/alpha"),
            AwoJobEntry(id: "j2", title: "Job 2", state: "running", workdir: "/work/alpha"),
            AwoJobEntry(id: "j3", title: "Job 3", state: "queued", workdir: "/work/alpha")
        ]
        
        let items = AttributionEngine.attribute(rooms: [room1, room2], awoJobs: runningJobs)
        let alphaItem = items.first { $0.id == "room-r1" }
        XCTAssertNotNil(alphaItem)
        XCTAssertEqual(alphaItem?.subjobCount, 3)
        XCTAssertEqual(alphaItem?.runningSubjobCount, 2)
        XCTAssertEqual(alphaItem?.subjobString, "↳ 3 (2 run)")
        XCTAssertEqual(alphaItem?.statusDot, .running)
        
        let betaItem = items.first { $0.id == "room-r2" }
        XCTAssertNotNil(betaItem)
        XCTAssertEqual(betaItem?.subjobCount, 0)
        XCTAssertEqual(betaItem?.runningSubjobCount, 0)
        XCTAssertNil(betaItem?.subjobString)
        XCTAssertEqual(betaItem?.statusDot, .waiting)
    }

    // MARK: - 4. BarMode 전체 상태 전이 및 인덱스 정합성
    func testBarModeExhaustiveTransitionsAndBoundaries() {
        let modes = BarMode.allCases
        XCTAssertEqual(modes.count, 3)
        XCTAssertEqual(modes, [.appBar, .agentBar, .roomBar])
        
        for mode in modes {
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.systemImage.isEmpty)
            XCTAssertGreaterThanOrEqual(mode.shortcutIndex, 1)
            XCTAssertLessThanOrEqual(mode.shortcutIndex, 3)
            
            // next -> previous 순환 시 자기 자신으로 복귀해야 함
            XCTAssertEqual(mode.next().previous(), mode)
            XCTAssertEqual(mode.previous().next(), mode)
        }
    }

    // MARK: - 5. UnifiedBarItem 경계 조건 불변성
    func testUnifiedBarItemBoundaryConditions() {
        // 서브잡 0개
        let zero = UnifiedBarItem(id: "0", title: "Empty", icon: .symbol("circle"), subjobCount: 0, runningSubjobCount: 0)
        XCTAssertFalse(zero.hasSubjobs)
        XCTAssertNil(zero.subjobString)

        // 서브잡 1개 대기
        let singleQueued = UnifiedBarItem(id: "1", title: "Single", icon: .symbol("circle"), subjobCount: 1, runningSubjobCount: 0)
        XCTAssertTrue(singleQueued.hasSubjobs)
        XCTAssertEqual(singleQueued.subjobString, "↳ 1")

        // 서브잡 1개 실행 중
        let singleRunning = UnifiedBarItem(id: "2", title: "SingleRun", icon: .symbol("circle"), subjobCount: 1, runningSubjobCount: 1)
        XCTAssertTrue(singleRunning.hasSubjobs)
        XCTAssertEqual(singleRunning.subjobString, "↳ 1 (1 run)")

        // 대량 서브잡
        let massive = UnifiedBarItem(id: "3", title: "Massive", icon: .symbol("circle"), subjobCount: 99, runningSubjobCount: 42)
        XCTAssertTrue(massive.hasSubjobs)
        XCTAssertEqual(massive.subjobString, "↳ 99 (42 run)")
    }
}
