import XCTest
import AppKit
@testable import AppWindowKit

final class RoomWindowEngineEdgeCaseTests: XCTestCase {

    override func setUp() {
        super.setUp()
        RoomWindowEngine.resetParkedStoreForTesting()
    }

    override func tearDown() {
        RoomWindowEngine.resetParkedStoreForTesting()
        super.tearDown()
    }

    // MARK: - AppKit to AX 좌표계 변환 테스트

    func testAppKitToAXFrameConversion() {
        let primaryHeight: CGFloat = 1080

        // 1. 주 모니터 (원점 0, 0)
        let appKitPrimary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let axPrimary = RoomWindowEngine.axFrame(for: appKitPrimary, primaryScreenHeight: primaryHeight)
        XCTAssertEqual(axPrimary.origin.x, 0)
        XCTAssertEqual(axPrimary.origin.y, 0)
        XCTAssertEqual(axPrimary.width, 1920)
        XCTAssertEqual(axPrimary.height, 1080)

        // 2. 상단/우측 보조 모니터 (AppKit 기준 y = 100, 높이 900)
        // AX y = 1080 - 100 - 900 = 80
        let appKitSecondary = CGRect(x: 1920, y: 100, width: 1440, height: 900)
        let axSecondary = RoomWindowEngine.axFrame(for: appKitSecondary, primaryScreenHeight: primaryHeight)
        XCTAssertEqual(axSecondary.origin.x, 1920)
        XCTAssertEqual(axSecondary.origin.y, 80)
        XCTAssertEqual(axSecondary.width, 1440)
        XCTAssertEqual(axSecondary.height, 900)
    }

    // MARK: - 단일 화면 오프스크린 파킹 기하 검증

    func testSingleScreenOptimalOffscreenPointAX() {
        let singleScreenAX = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
        let offscreen = RoomWindowEngine.safeOffscreenPoint(axFrames: singleScreenAX, isStageManager: false, margin: 150)

        XCTAssertEqual(offscreen.x, 1920 + 150)
        XCTAssertEqual(offscreen.y, 1080 + 150)

        // 창 크기가 800x600인 경우에도 어떤 화면과도 교차하지 않아야 함
        let windowRect = CGRect(origin: offscreen, size: CGSize(width: 800, height: 600))
        for screen in singleScreenAX {
            XCTAssertTrue(screen.intersection(windowRect).isNull, "단일 화면 가시 영역과 절대 교차하지 않아야 합니다.")
        }
    }

    // MARK: - 듀얼 모니터(가로 배치) 누수 방어 검증

    func testHorizontalDualMonitorOffscreenPointNeverIntersectsAnyScreen() {
        let screenA = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let screenB = CGRect(x: 1920, y: 0, width: 2560, height: 1440)
        let screens = [screenA, screenB]

        let bbox = RoomWindowEngine.boundingBox(for: screens)
        XCTAssertEqual(bbox.origin.x, 0)
        XCTAssertEqual(bbox.origin.y, 0)
        XCTAssertEqual(bbox.maxX, 4480)
        XCTAssertEqual(bbox.maxY, 1440)

        let offscreen = RoomWindowEngine.safeOffscreenPoint(axFrames: screens, isStageManager: false, margin: 150)
        XCTAssertGreaterThanOrEqual(offscreen.x, 4480 + 150)
        XCTAssertGreaterThanOrEqual(offscreen.y, 1440 + 150)

        let windowRect = CGRect(origin: offscreen, size: CGSize(width: 1000, height: 800))
        for screen in screens {
            XCTAssertTrue(screen.intersection(windowRect).isNull, "듀얼 모니터 환경에서 어느 화면과도 교차하지 않아야 합니다.")
        }
    }

    // MARK: - 듀얼 모니터(세로 배치) 누수 방어 검증

    func testVerticalDualMonitorOffscreenPointNeverIntersectsAnyScreen() {
        let topScreen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let bottomScreen = CGRect(x: 0, y: 1080, width: 1920, height: 1080)
        let screens = [topScreen, bottomScreen]

        let bbox = RoomWindowEngine.boundingBox(for: screens)
        XCTAssertEqual(bbox.maxY, 2160)

        let offscreen = RoomWindowEngine.safeOffscreenPoint(axFrames: screens, isStageManager: false, margin: 200)
        XCTAssertGreaterThanOrEqual(offscreen.y, 2160 + 200)

        let windowRect = CGRect(origin: offscreen, size: CGSize(width: 600, height: 600))
        for screen in screens {
            XCTAssertTrue(screen.intersection(windowRect).isNull, "상하 듀얼 모니터 환경에서 어느 화면과도 교차하지 않아야 합니다.")
        }
    }

    // MARK: - 트리플 모니터(L자/비대칭 배치) 누수 방어 검증

    func testTripleMonitorAsymmetricOffscreenPointNeverIntersectsAnyScreen() {
        // Screen 1: 좌측 (-1920 ~ 0)
        let leftScreen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        // Screen 2: 중앙 주 모니터 (0 ~ 2560)
        let centerScreen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        // Screen 3: 우상단 서브 모니터 (2560 ~ 4480, y: -200)
        let rightTopScreen = CGRect(x: 2560, y: -200, width: 1920, height: 1080)

        let screens = [leftScreen, centerScreen, rightTopScreen]
        let bbox = RoomWindowEngine.boundingBox(for: screens)

        XCTAssertEqual(bbox.minX, -1920)
        XCTAssertEqual(bbox.minY, -200)
        XCTAssertEqual(bbox.maxX, 4480)
        XCTAssertEqual(bbox.maxY, 1440)

        let offscreen = RoomWindowEngine.safeOffscreenPoint(axFrames: screens, isStageManager: false)
        XCTAssertGreaterThanOrEqual(offscreen.x, 4480 + 150)
        XCTAssertGreaterThanOrEqual(offscreen.y, 1440 + 150)

        let windowRect = CGRect(origin: offscreen, size: CGSize(width: 1200, height: 900))
        for screen in screens {
            XCTAssertTrue(screen.intersection(windowRect).isNull, "트리플 모니터 환경에서 어느 화면과도 교차하지 않아야 합니다.")
        }
    }

    // MARK: - Stage Manager 활성화 환경 방어 검증

    func testStageManagerActiveExpandsOffscreenMargin() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900)]

        let normalPoint = RoomWindowEngine.safeOffscreenPoint(axFrames: screens, isStageManager: false, margin: 100)
        let stageManagerPoint = RoomWindowEngine.safeOffscreenPoint(axFrames: screens, isStageManager: true, margin: 100)

        // Stage Manager 활성화 시 마진이 300 이상으로 자동 확장되어야 함
        XCTAssertGreaterThan(stageManagerPoint.x, normalPoint.x)
        XCTAssertGreaterThan(stageManagerPoint.y, normalPoint.y)
        XCTAssertEqual(stageManagerPoint.x, 1440 + 300)
        XCTAssertEqual(stageManagerPoint.y, 900 + 300)
    }

    func testStageManagerClampingAvoidsLeftStripAndTopMenuBar() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

        // 1. 좌측 Stage Manager 사이드 스트립(x < 120) 내부로 침범한 좌표
        let stripInvadingPoint = CGPoint(x: 40, y: 400)
        let clampedFromStrip = RoomWindowEngine.clampAwayFromStageManagerStrip(
            point: stripInvadingPoint,
            targetScreenAX: screen,
            isStageManager: true
        )
        XCTAssertGreaterThanOrEqual(clampedFromStrip.x, 130, "좌측 사이드 스트립을 회피하여 안전 영역으로 클램핑되어야 합니다.")
        XCTAssertEqual(clampedFromStrip.y, 400)

        // 2. 상단 메뉴바(y < 32) 내부로 침범한 좌표
        let menuBarInvadingPoint = CGPoint(x: 300, y: 10)
        let clampedFromMenuBar = RoomWindowEngine.clampAwayFromStageManagerStrip(
            point: menuBarInvadingPoint,
            targetScreenAX: screen,
            isStageManager: true
        )
        XCTAssertEqual(clampedFromMenuBar.x, 300)
        XCTAssertGreaterThanOrEqual(clampedFromMenuBar.y, 42, "상단 메뉴바를 회피하여 안전 영역으로 클램핑되어야 합니다.")

        // 3. Stage Manager 비활성화 시에는 원본 좌표 유지
        let normalPoint = CGPoint(x: 40, y: 10)
        let unclamped = RoomWindowEngine.clampAwayFromStageManagerStrip(
            point: normalPoint,
            targetScreenAX: screen,
            isStageManager: false
        )
        XCTAssertEqual(unclamped, normalPoint)
    }

    // MARK: - 다중 모니터 누수 방어 safeCornerPinPoint 검증

    func testSafeCornerPinSelectsRightmostBottomScreen() {
        let screenA = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let screenB = CGRect(x: 1920, y: 0, width: 2560, height: 1440)
        let screens = [screenA, screenB]

        let pinPoint = RoomWindowEngine.safeCornerPinPoint(axFrames: screens, isStageManager: false)
        // 가장 우하단 스크린인 Screen B의 우하단 코너여야 함
        XCTAssertEqual(pinPoint.x, 4480 - 1)
        XCTAssertEqual(pinPoint.y, 1440 - 1)

        // Screen A 내부와는 교차하지 않아야 함
        XCTAssertFalse(screenA.contains(pinPoint))
    }

    // MARK: - 파킹 레지스트리 상태 원장 및 동시성 안전 검증

    func testParkedWindowStateStorageAndRetrieval() {
        XCTAssertEqual(RoomWindowEngine.parkedWindowsCount, 0)

        let state1 = RoomWindowEngine.ParkedWindowState(
            cgWindowID: 101,
            pid: 1234,
            originalPosition: CGPoint(x: 200, y: 150),
            originalSize: CGSize(width: 800, height: 600),
            roomID: "room-alpha"
        )
        let state2 = RoomWindowEngine.ParkedWindowState(
            cgWindowID: 102,
            pid: 5678,
            originalPosition: CGPoint(x: 400, y: 300),
            originalSize: CGSize(width: 1024, height: 768),
            roomID: "room-beta"
        )

        // 1. 저장 테스트
        let store = RoomWindowEngine.ParkedWindowStore()
        store.park(state1)
        store.park(state2)
        XCTAssertEqual(store.count, 2)
        XCTAssertEqual(store.peek(for: 101)?.pid, 1234)
        XCTAssertEqual(store.peek(for: 102)?.pid, 5678)

        // 2. 검색 및 상태 레코드 동등성 검증
        let retrieved1 = store.retrieve(for: 101)
        XCTAssertEqual(retrieved1, state1)
        XCTAssertEqual(store.count, 1)

        let retrieved2 = store.retrieve(for: 102)
        XCTAssertEqual(retrieved2, state2)
        XCTAssertEqual(store.count, 0)
    }

    func testEmergencyEvacuateAllCleansParkedStore() {
        // 비상 탈출 실행 시 안전하게 완료되고 파킹 저장소가 정리되는지 확인
        let result = RoomWindowEngine.emergencyEvacuateAll()
        XCTAssertGreaterThanOrEqual(result.unhiddenAppsCount, 0)
        XCTAssertGreaterThanOrEqual(result.unminimizedWindowsCount, 0)
        XCTAssertGreaterThanOrEqual(result.repositionedWindowsCount, 0)
        XCTAssertEqual(RoomWindowEngine.parkedWindowsCount, 0, "비상 탈출 후 파킹 저장소는 비워져야 합니다.")
    }

    // MARK: - 외장 모니터 언플러그 Self-Healing 기하 및 클램핑/캐스케이드 검증

    func testSelfHealWindowFrameWhenExternalMonitorUnplugged() {
        // 외장 모니터(2560x1440)에 위치했던 창 (x: 2400, y: 300, size: 1200x800)
        let originalWindow = CGRect(x: 2400, y: 300, width: 1200, height: 800)

        // 외장 모니터가 언플러그되어 MacBook 내장 1440x900 화면만 남음
        let mainScreenAX = CGRect(x: 0, y: 32, width: 1440, height: 868)
        let activeScreens = [mainScreenAX]

        let healed = RoomWindowEngine.selfHealWindowFrame(
            windowFrame: originalWindow,
            screenAXFrames: activeScreens,
            targetScreenAX: mainScreenAX,
            cascadeIndex: 0
        )

        // 1. 메인 화면 가시 영역 안으로 완전히 클램핑되어야 함
        XCTAssertGreaterThanOrEqual(healed.minX, mainScreenAX.minX + 10.0)
        XCTAssertGreaterThanOrEqual(healed.minY, mainScreenAX.minY + 10.0)
        XCTAssertLessThanOrEqual(healed.maxX, mainScreenAX.maxX - 10.0)
        XCTAssertLessThanOrEqual(healed.maxY, mainScreenAX.maxY - 10.0)

        // 2. 크기는 메인 화면 내에 수용 가능하므로 보존됨
        XCTAssertEqual(healed.width, 1200)
        XCTAssertEqual(healed.height, 800)
    }

    func testSelfHealOversizedWindowFrom4KToMacBookScreen() {
        // 4K 외장 모니터의 전체화면 창 (x: 1920, y: 0, size: 3840x2160)
        let oversizedWindow = CGRect(x: 1920, y: 0, width: 3840, height: 2160)

        // 단일 1440x900 화면으로 축소
        let mainScreenAX = CGRect(x: 0, y: 32, width: 1440, height: 868)
        let activeScreens = [mainScreenAX]

        let healed = RoomWindowEngine.selfHealWindowFrame(
            windowFrame: oversizedWindow,
            screenAXFrames: activeScreens,
            targetScreenAX: mainScreenAX,
            cascadeIndex: 0
        )

        // 1. 창 크기가 메인 화면 크기(마진 포함) 이내로 안전하게 축소되었는지 검증
        XCTAssertLessThanOrEqual(healed.width, mainScreenAX.width - 40)
        XCTAssertLessThanOrEqual(healed.height, mainScreenAX.height - 60)

        // 2. 위치가 메인 화면 경계 안으로 수용되었는지 검증
        XCTAssertGreaterThanOrEqual(healed.minX, mainScreenAX.minX + 10.0)
        XCTAssertGreaterThanOrEqual(healed.minY, mainScreenAX.minY + 10.0)
        XCTAssertLessThanOrEqual(healed.maxX, mainScreenAX.maxX - 10.0)
        XCTAssertLessThanOrEqual(healed.maxY, mainScreenAX.maxY - 10.0)
    }

    func testSelfHealPreservesAdequatelyVisibleWindow() {
        // 이미 정상 화면 안쪽에 잘 머무르고 있는 창 (x: 150, y: 100, size: 800x600)
        let safeWindow = CGRect(x: 150, y: 100, width: 800, height: 600)
        let mainScreenAX = CGRect(x: 0, y: 32, width: 1440, height: 868)
        let activeScreens = [mainScreenAX]

        let healed = RoomWindowEngine.selfHealWindowFrame(
            windowFrame: safeWindow,
            screenAXFrames: activeScreens,
            targetScreenAX: mainScreenAX,
            cascadeIndex: 0
        )

        // 정상 창은 불필요하게 위치나 크기가 변경되지 않고 그대로 보존되어야 함
        XCTAssertEqual(healed, safeWindow)
    }

    func testSelfHealCascadeProgressionForMultipleWindows() {
        let mainScreenAX = CGRect(x: 0, y: 32, width: 1440, height: 868)
        let activeScreens = [mainScreenAX]

        // 3개의 유실 창이 순차적으로 복원될 때의 캐스케이드 좌표
        let win1 = CGRect(x: 3000, y: 500, width: 600, height: 400)
        let win2 = CGRect(x: 3100, y: 600, width: 600, height: 400)
        let win3 = CGRect(x: 3200, y: 700, width: 600, height: 400)

        let h1 = RoomWindowEngine.selfHealWindowFrame(windowFrame: win1, screenAXFrames: activeScreens, targetScreenAX: mainScreenAX, cascadeIndex: 0)
        let h2 = RoomWindowEngine.selfHealWindowFrame(windowFrame: win2, screenAXFrames: activeScreens, targetScreenAX: mainScreenAX, cascadeIndex: 1)
        let h3 = RoomWindowEngine.selfHealWindowFrame(windowFrame: win3, screenAXFrames: activeScreens, targetScreenAX: mainScreenAX, cascadeIndex: 2)

        // 캐스케이드 오프셋(28pt씩 순차 증가) 검증
        XCTAssertEqual(h2.origin.x - h1.origin.x, 28.0)
        XCTAssertEqual(h2.origin.y - h1.origin.y, 28.0)
        XCTAssertEqual(h3.origin.x - h2.origin.x, 28.0)
        XCTAssertEqual(h3.origin.y - h2.origin.y, 28.0)

        // 모든 창이 안전하게 경계 내에 위치
        for h in [h1, h2, h3] {
            XCTAssertLessThanOrEqual(h.maxX, mainScreenAX.maxX - 10.0)
            XCTAssertLessThanOrEqual(h.maxY, mainScreenAX.maxY - 10.0)
        }
    }

    func testSelfHealBoundaryClampingAvoidsOverflow() {
        let mainScreenAX = CGRect(x: 0, y: 32, width: 1440, height: 868)
        let activeScreens = [mainScreenAX]

        // 큰 창이 높은 캐스케이드 인덱스(인덱스 7)를 받을 때 우측/하단으로 오버플로우되지 않는지 검증
        let largeWindow = CGRect(x: 3000, y: 2000, width: 1300, height: 800)
        let healed = RoomWindowEngine.selfHealWindowFrame(
            windowFrame: largeWindow,
            screenAXFrames: activeScreens,
            targetScreenAX: mainScreenAX,
            cascadeIndex: 7
        )

        XCTAssertLessThanOrEqual(healed.maxX, mainScreenAX.maxX - 10.0, "캐스케이드 오프셋이 적용되어도 우측 화면을 초과하지 않아야 합니다.")
        XCTAssertLessThanOrEqual(healed.maxY, mainScreenAX.maxY - 10.0, "캐스케이드 오프셋이 적용되어도 하단 화면을 초과하지 않아야 합니다.")
        XCTAssertGreaterThanOrEqual(healed.minX, mainScreenAX.minX + 10.0)
        XCTAssertGreaterThanOrEqual(healed.minY, mainScreenAX.minY + 10.0)
    }

    // MARK: - 절전 복귀(Sleep -> Wake) 및 좀비 GC 안전망 검증

    func testParkedWindowStoreZombiePruningDuringSleep() {
        let store = RoomWindowEngine.ParkedWindowStore()

        let state1 = RoomWindowEngine.ParkedWindowState(cgWindowID: 101, pid: 1001, originalPosition: CGPoint(x: 100, y: 100), originalSize: CGSize(width: 800, height: 600))
        let state2 = RoomWindowEngine.ParkedWindowState(cgWindowID: 102, pid: 1002, originalPosition: CGPoint(x: 200, y: 200), originalSize: CGSize(width: 800, height: 600))
        let state3 = RoomWindowEngine.ParkedWindowState(cgWindowID: 103, pid: 1003, originalPosition: CGPoint(x: 300, y: 300), originalSize: CGSize(width: 800, height: 600))

        store.park(state1)
        store.park(state2)
        store.park(state3)
        XCTAssertEqual(store.count, 3)

        // 잠자는 동안 PID 1002 프로세스가 종료(Crash/Kill)되었다고 가정
        let alivePIDs: Set<pid_t> = [1001, 1003]
        let pruned = store.pruneZombies(activePIDs: alivePIDs)

        XCTAssertEqual(pruned.count, 1)
        XCTAssertEqual(pruned.first?.cgWindowID, 102)
        XCTAssertEqual(pruned.first?.pid, 1002)

        // 생존 프로세스의 창만 저장소에 남아야 함
        XCTAssertEqual(store.count, 2)
        XCTAssertNotNil(store.peek(for: 101))
        XCTAssertNil(store.peek(for: 102))
        XCTAssertNotNil(store.peek(for: 103))
    }

    func testReconcileParkedWindowStatesForScreenChange() {
        let stateOnExternal = RoomWindowEngine.ParkedWindowState(
            cgWindowID: 201,
            pid: 5001,
            originalPosition: CGPoint(x: 2500, y: 400),
            originalSize: CGSize(width: 1000, height: 700)
        )
        let stateZombie = RoomWindowEngine.ParkedWindowState(
            cgWindowID: 202,
            pid: 9999, // 죽은 프로세스
            originalPosition: CGPoint(x: 2600, y: 500),
            originalSize: CGSize(width: 800, height: 600)
        )
        let stateOnMain = RoomWindowEngine.ParkedWindowState(
            cgWindowID: 203,
            pid: 5002,
            originalPosition: CGPoint(x: 100, y: 150),
            originalSize: CGSize(width: 800, height: 600)
        )

        let activePIDs: Set<pid_t> = [5001, 5002] // 9999는 사망
        let mainScreenAX = CGRect(x: 0, y: 32, width: 1440, height: 868)
        let screenAXFrames = [mainScreenAX]

        let result = RoomWindowEngine.reconcileParkedWindowStatesForScreenChange(
            states: [stateOnExternal, stateZombie, stateOnMain],
            activePIDs: activePIDs,
            screenAXFrames: screenAXFrames,
            targetScreenAX: mainScreenAX
        )

        // 1. 좀비 분리 검증
        XCTAssertEqual(result.prunedZombies.count, 1)
        XCTAssertEqual(result.prunedZombies.first?.cgWindowID, 202)

        // 2. 생존 목록 검증
        XCTAssertEqual(result.validStates.count, 2)

        // 3. 외장 모니터에 있던 201번 창은 메인 스크린으로 자동 셀프 힐링 계산되어야 함
        XCTAssertNotNil(result.healedTargetFrames[201])
        if let healed201 = result.healedTargetFrames[201] {
            XCTAssertLessThanOrEqual(healed201.maxX, mainScreenAX.maxX - 10.0)
            XCTAssertLessThanOrEqual(healed201.maxY, mainScreenAX.maxY - 10.0)
        }

        // 4. 메인 스크린에 이미 있던 203번 창은 힐링 대상(좌표 변경)이 아님
        XCTAssertNil(result.healedTargetFrames[203])
    }

    // MARK: - 동시성 스트레스 및 스레드 안전성 검증

    func testParkedWindowStoreConcurrentStress() {
        let store = RoomWindowEngine.ParkedWindowStore()
        let iterations = 100
        let queue = DispatchQueue(label: "test.parkedstore.concurrent", attributes: .concurrent)
        let group = DispatchGroup()

        for i in 0..<iterations {
            group.enter()
            queue.async {
                let winID = UInt32(1000 + i)
                let state = RoomWindowEngine.ParkedWindowState(
                    cgWindowID: winID,
                    pid: pid_t(2000 + (i % 5)),
                    originalPosition: CGPoint(x: CGFloat(i * 10), y: CGFloat(i * 10)),
                    originalSize: CGSize(width: 800, height: 600)
                )
                store.park(state)
                _ = store.peek(for: winID)
                store.updateOriginalFrame(for: winID, position: CGPoint(x: 50, y: 50), size: CGSize(width: 600, height: 400))
                group.leave()
            }
        }

        group.wait()
        XCTAssertEqual(store.count, iterations)

        // 동시 검색 및 회수
        let retrieveGroup = DispatchGroup()
        for i in 0..<iterations {
            retrieveGroup.enter()
            queue.async {
                let winID = UInt32(1000 + i)
                _ = store.retrieve(for: winID)
                retrieveGroup.leave()
            }
        }
        retrieveGroup.wait()
        XCTAssertEqual(store.count, 0)
    }

    // MARK: - 환경 관측기 생명주기 및 결과 DTO 검증

    func testEnvironmentObserversLifecycle() {
        RoomWindowEngine.installEnvironmentObservers()
        XCTAssertTrue(RoomWindowEngine.areEnvironmentObserversInstalled)

        // 다중 호출 멱등성
        RoomWindowEngine.installEnvironmentObservers()
        XCTAssertTrue(RoomWindowEngine.areEnvironmentObserversInstalled)

        RoomWindowEngine.removeEnvironmentObservers()
        XCTAssertFalse(RoomWindowEngine.areEnvironmentObserversInstalled)
    }

    func testReconciliationResultDTOs() {
        let wakeResult = RoomWindowEngine.WakeReconciliationResult(
            prunedZombieParkedCount: 2,
            reparkedWindowsCount: 3,
            healedOrphanedWindowsCount: 1
        )
        XCTAssertEqual(wakeResult.totalRemediatedCount, 6)

        let displayResult = RoomWindowEngine.DisplayChangeReconciliationResult(
            reparkedWindowsCount: 4,
            healedOrphanedWindowsCount: 2
        )
        XCTAssertEqual(displayResult.totalRemediatedCount, 6)
    }
}
