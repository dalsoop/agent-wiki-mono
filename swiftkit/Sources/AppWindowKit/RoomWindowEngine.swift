import Foundation
#if os(macOS)
import AppKit
import ApplicationServices
import CoreGraphics

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(
    _ element: AXUIElement,
    _ windowID: UnsafeMutablePointer<CGWindowID>
) -> AXError
#endif
import RoomSeatKit

#if os(macOS)
/// AppKit 및 AXUIElement 기반 룸 윈도우 조율 엔진 (Tier 2 Surface)
public enum RoomWindowEngine {

    // MARK: - 권한 및 환경 진단

    /// Accessibility(손쉬운 사용) TCC 권한 허용 여부 점검 (macOS 15 Sequoia 호환)
    public static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// macOS Stage Manager(스테이지 매니저) 활성화 여부 감지
    public static var isStageManagerEnabled: Bool {
        UserDefaults.standard.persistentDomain(forName: "com.apple.WindowManager")?["GloballyEnabled"] as? Bool ?? false
    }

    /// 최적 오프스크린 파킹 좌표 (화면 우측 하단 1픽셀 코너, 하위 호환성 유지)
    public static func optimalHideCorner(for screen: NSScreen = NSScreen.main ?? NSScreen.screens[0]) -> CGPoint {
        let frame = screen.visibleFrame
        return CGPoint(x: frame.maxX - 1, y: frame.minY + 1)
    }

    // MARK: - 오프스크린 파킹 상태 원장 (비협조적 창 퇴거 및 복귀 추적)

    /// 오프스크린 파킹된 윈도우의 상태 레코드
    public struct ParkedWindowState: Sendable, Equatable, Codable {
        public let cgWindowID: UInt32
        public let pid: pid_t
        public var originalPosition: CGPoint
        public var originalSize: CGSize
        public let parkedAt: Date
        public let roomID: String?

        public init(
            cgWindowID: UInt32,
            pid: pid_t,
            originalPosition: CGPoint,
            originalSize: CGSize,
            parkedAt: Date = Date(),
            roomID: String? = nil
        ) {
            self.cgWindowID = cgWindowID
            self.pid = pid
            self.originalPosition = originalPosition
            self.originalSize = originalSize
            self.parkedAt = parkedAt
            self.roomID = roomID
        }

        public func updatingOriginal(position: CGPoint, size: CGSize) -> ParkedWindowState {
            ParkedWindowState(
                cgWindowID: cgWindowID,
                pid: pid,
                originalPosition: position,
                originalSize: size,
                parkedAt: parkedAt,
                roomID: roomID
            )
        }
    }

    public final class ParkedWindowStore: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [UInt32: ParkedWindowState] = [:]

        public init() {}

        public func park(_ state: ParkedWindowState) {
            lock.lock()
            defer { lock.unlock() }
            storage[state.cgWindowID] = state
        }

        public func retrieve(for windowID: UInt32) -> ParkedWindowState? {
            lock.lock()
            defer { lock.unlock() }
            return storage.removeValue(forKey: windowID)
        }

        public func peek(for windowID: UInt32) -> ParkedWindowState? {
            lock.lock()
            defer { lock.unlock() }
            return storage[windowID]
        }

        public func all() -> [ParkedWindowState] {
            lock.lock()
            defer { lock.unlock() }
            return Array(storage.values)
        }

        public func contains(windowID: UInt32) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return storage[windowID] != nil
        }

        public func remove(for windowID: UInt32) -> ParkedWindowState? {
            lock.lock()
            defer { lock.unlock() }
            return storage.removeValue(forKey: windowID)
        }

        public func removeAll() -> [ParkedWindowState] {
            lock.lock()
            defer { lock.unlock() }
            let values = Array(storage.values)
            storage.removeAll()
            return values
        }

        public func pruneZombies(activePIDs: Set<pid_t>) -> [ParkedWindowState] {
            lock.lock()
            defer { lock.unlock() }
            var pruned: [ParkedWindowState] = []
            let deadIDs = storage.filter { !activePIDs.contains($0.value.pid) }.map(\.key)
            for id in deadIDs {
                if let state = storage.removeValue(forKey: id) {
                    pruned.append(state)
                }
            }
            return pruned
        }

        public func updateOriginalFrame(for windowID: UInt32, position: CGPoint, size: CGSize) {
            lock.lock()
            defer { lock.unlock() }
            guard var state = storage[windowID] else { return }
            state.originalPosition = position
            state.originalSize = size
            storage[windowID] = state
        }

        public var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return storage.count
        }
    }

    private static let parkedStore = ParkedWindowStore()

    /// 공유 파킹 저장소 참조
    public static var sharedParkedStore: ParkedWindowStore {
        parkedStore
    }

    /// 현재 오프스크린 파킹된 창 수
    public static var parkedWindowsCount: Int {
        parkedStore.count
    }

    /// 현재 파킹된 모든 창 레코드 복사본
    public static var parkedWindowStates: [ParkedWindowState] {
        parkedStore.all()
    }

    /// 테스트 및 초기화용 파킹 저장소 비우기
    public static func resetParkedStoreForTesting() {
        _ = parkedStore.removeAll()
    }

    // MARK: - 다중 디스플레이 & Stage Manager 기하 연산

    /// AppKit 좌표계 Rect를 AX(Accessibility) 좌표계 Rect로 변환
    public static func axFrame(for appKitFrame: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: appKitFrame.origin.x,
            y: primaryScreenHeight - appKitFrame.origin.y - appKitFrame.size.height,
            width: appKitFrame.size.width,
            height: appKitFrame.size.height
        )
    }

    /// 주어진 AX 사각형 목록의 통합 바운딩 박스 (Union)
    public static func boundingBox(for rects: [CGRect]) -> CGRect {
        guard let first = rects.first else {
            return CGRect(x: 0, y: 0, width: 1440, height: 900)
        }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }

    /// 연결된 모든 화면의 AX 좌표계 통합 바운딩 박스 계산
    public static func screensBoundingBoxAX(screens: [NSScreen] = NSScreen.screens) -> CGRect {
        guard let primary = screens.first else {
            return CGRect(x: 0, y: 0, width: 1440, height: 900)
        }
        let primaryHeight = primary.frame.height
        let axFrames = screens.map { axFrame(for: $0.frame, primaryScreenHeight: primaryHeight) }
        return boundingBox(for: axFrames)
    }

    /// 다중 디스플레이 및 Stage Manager 환경에서 안전한 오프스크린 파킹 좌표 산출 (AX 좌표계)
    /// 모든 디스플레이의 가시 영역 및 Stage Manager 사이드 스트립을 완전히 벗어나는 안전 좌표
    public static func safeOffscreenPoint(
        axFrames: [CGRect],
        isStageManager: Bool = isStageManagerEnabled,
        margin: CGFloat = 150
    ) -> CGPoint {
        let bbox = boundingBox(for: axFrames)
        // Stage Manager가 활성화된 경우 제스처/사이드 스트립 간섭 방지를 위해 마진 확대
        let effectiveMargin = isStageManager ? max(margin, 300) : margin
        return CGPoint(
            x: bbox.maxX + effectiveMargin,
            y: bbox.maxY + effectiveMargin
        )
    }

    /// 다중 모니터 누수 방어 1픽셀 코너 핀 좌표 (AX 좌표계)
    /// 다른 화면과 겹치거나 인접 모니터로 누수되지 않는 최외곽 우하단 안전 코너 산출
    public static func safeCornerPinPoint(
        axFrames: [CGRect],
        isStageManager: Bool = isStageManagerEnabled
    ) -> CGPoint {
        guard !axFrames.isEmpty else {
            return CGPoint(x: 1439, y: 899)
        }
        // 가장 우측 하단에 위치한 스크린 탐색
        let sorted = axFrames.sorted { a, b in
            if a.maxX != b.maxX {
                return a.maxX > b.maxX
            }
            return a.maxY > b.maxY
        }
        guard let targetScreen = sorted.first else {
            return CGPoint(x: 1439, y: 899)
        }

        let pinPoint = CGPoint(x: targetScreen.maxX - 1, y: targetScreen.maxY - 1)

        // 이 핀 포인트가 다른 화면 내부에 포함되는지 (다중 모니터 누수) 검사
        let intersectsOther = axFrames.contains { rect in
            rect != targetScreen && rect.contains(pinPoint)
        }

        if intersectsOther {
            // 인접 화면과 교차 시 완전 오프스크린 좌표로 안전하게 fallback
            return safeOffscreenPoint(axFrames: axFrames, isStageManager: isStageManager)
        }

        return pinPoint
    }

    /// Stage Manager 활성화 시 안전한 경계선 클램핑 방어
    /// 좌측 스트립(0~120pt)과 상단 메뉴바(0~32pt) 침범을 원천 차단하고 우하단으로 클램핑
    public static func clampAwayFromStageManagerStrip(
        point: CGPoint,
        targetScreenAX: CGRect,
        isStageManager: Bool = isStageManagerEnabled
    ) -> CGPoint {
        guard isStageManager else { return point }
        var result = point
        let stripThreshold = targetScreenAX.minX + 120 // 좌측 Stage Manager 스트립 여유폭
        if result.x < stripThreshold {
            result.x = stripThreshold + 10
        }
        let menuBarThreshold = targetScreenAX.minY + 32 // 상단 메뉴바 여유폭
        if result.y < menuBarThreshold {
            result.y = menuBarThreshold + 10
        }
        return result
    }

    /// 최적 오프스크린 파킹 좌표 (AX 좌표계 기준 다중 디스플레이 & Stage Manager 방어)
    public static func optimalOffscreenPointAX(
        screens: [NSScreen] = NSScreen.screens,
        isStageManager: Bool = isStageManagerEnabled
    ) -> CGPoint {
        guard let primary = screens.first else {
            return CGPoint(x: 2000, y: 2000)
        }
        let primaryHeight = primary.frame.height
        let axFrames = screens.map { axFrame(for: $0.frame, primaryScreenHeight: primaryHeight) }
        return safeOffscreenPoint(axFrames: axFrames, isStageManager: isStageManager)
    }

    // MARK: - Self-Healing 외란 방어 및 화면 클램핑/캐스케이드

    /// 주어진 창 사각형이 현재 연결된 화면들 중 하나 이상에 충분한 비율로 가시 상태인지 판정
    public static func isWindowAdequatelyVisible(
        windowFrame: CGRect,
        screenAXFrames: [CGRect],
        minVisibleRatio: CGFloat = 0.3
    ) -> Bool {
        guard windowFrame.width >= 50 && windowFrame.height >= 50 else { return false }
        let totalArea = max(windowFrame.width * windowFrame.height, 1)
        let maxIntersectionArea = screenAXFrames.reduce(CGFloat.zero) { maxArea, screenRect in
            let inter = screenRect.intersection(windowFrame)
            guard !inter.isNull else { return maxArea }
            return max(maxArea, inter.width * inter.height)
        }
        return maxIntersectionArea >= 10000 && (maxIntersectionArea / totalArea) >= minVisibleRatio
    }

    /// 외장 모니터 언플러그나 해상도 축소로 화면 밖으로 밀려난 창 좌표를
    /// 현재 메인 화면 안쪽으로 자동 클램핑 및 캐스케이드하는 Self-Healing 기하 연산 (순수 함수)
    /// - Parameters:
    ///   - windowFrame: 창의 현재 또는 복귀 목표 사각형 (AX 좌표계)
    ///   - screenAXFrames: 현재 연결된 모든 화면의 가시 사각형 목록 (AX 좌표계)
    ///   - targetScreenAX: 클램핑 대상 메인 화면 가시 사각형 (AX 좌표계)
    ///   - cascadeIndex: 여러 창 복귀 시 겹침 방지를 위한 캐스케이드 인덱스
    ///   - minVisibleRatio: 정상 가시 영역 판정 최소 비율 (기본 30%)
    /// - Returns: 안전하게 메인 화면 안쪽으로 클램핑 및 캐스케이드된 사각형
    public static func selfHealWindowFrame(
        windowFrame: CGRect,
        screenAXFrames: [CGRect],
        targetScreenAX: CGRect,
        cascadeIndex: Int = 0,
        minVisibleRatio: CGFloat = 0.3
    ) -> CGRect {
        // 1. 이미 정상 화면 내에 충분히 가시적인 경우 원본 좌표 그대로 보존
        if isWindowAdequatelyVisible(windowFrame: windowFrame, screenAXFrames: screenAXFrames, minVisibleRatio: minVisibleRatio) {
            return windowFrame
        }

        // 2. 화면 축소 및 언플러그 대응 Self-Healing 클램핑
        // 2.1 창 크기 보정 (메인 화면보다 크면 화면 안으로 축소, 최소 400x300 보장)
        let maxWidth = max(targetScreenAX.width - 40, 400)
        let maxHeight = max(targetScreenAX.height - 60, 300)
        let healedWidth = min(max(windowFrame.width, 400), maxWidth)
        let healedHeight = min(max(windowFrame.height, 300), maxHeight)

        // 2.2 캐스케이드 오프셋 계산 (8단계 순환, 28pt 간격)
        let cascadeStep = CGFloat(cascadeIndex % 8) * 28.0

        // 기본 시작 위치: 메인 화면 상단/좌측 여백 + 캐스케이드 오프셋
        var originX = targetScreenAX.minX + 30.0 + cascadeStep
        var originY = targetScreenAX.minY + 30.0 + cascadeStep

        // 2.3 화면 우측/하단 초과 시 경계 안쪽으로 클램핑
        if originX + healedWidth > targetScreenAX.maxX - 10.0 {
            originX = max(targetScreenAX.minX + 10.0, targetScreenAX.maxX - healedWidth - 10.0)
        }
        if originY + healedHeight > targetScreenAX.maxY - 10.0 {
            originY = max(targetScreenAX.minY + 10.0, targetScreenAX.maxY - healedHeight - 10.0)
        }

        return CGRect(x: originX, y: originY, width: healedWidth, height: healedHeight)
    }

    /// 화면 변경에 따른 파킹 레코드 정합성 검증 및 셀프 힐링 목표 프레임 산출 (순수 함수)
    public static func reconcileParkedWindowStatesForScreenChange(
        states: [ParkedWindowState],
        activePIDs: Set<pid_t>,
        screenAXFrames: [CGRect],
        targetScreenAX: CGRect
    ) -> (
        validStates: [ParkedWindowState],
        prunedZombies: [ParkedWindowState],
        healedTargetFrames: [UInt32: CGRect]
    ) {
        var validStates: [ParkedWindowState] = []
        var prunedZombies: [ParkedWindowState] = []
        var healedTargetFrames: [UInt32: CGRect] = [:]

        for (index, state) in states.enumerated() {
            guard activePIDs.contains(state.pid) else {
                prunedZombies.append(state)
                continue
            }
            validStates.append(state)

            let originalFrame = CGRect(origin: state.originalPosition, size: state.originalSize)
            let healed = selfHealWindowFrame(
                windowFrame: originalFrame,
                screenAXFrames: screenAXFrames,
                targetScreenAX: targetScreenAX,
                cascadeIndex: index
            )
            if healed != originalFrame {
                healedTargetFrames[state.cgWindowID] = healed
            }
        }

        return (validStates, prunedZombies, healedTargetFrames)
    }

    // MARK: - 오프스크린 파킹 및 복귀 (비협조적 앱 방어)

    /// 윈도우의 현재 AX 위치 및 크기 조회
    public static func getWindowFrame(axWindow: AXUIElement) -> (origin: CGPoint, size: CGSize)? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        var posRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef) == .success,
              let posRef, CFGetTypeID(posRef) == AXValueGetTypeID() else {
            return nil
        }
        AXValueGetValue(unsafeDowncast(posRef, to: AXValue.self), .cgPoint, &origin)

        var sizeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let sizeRef, CFGetTypeID(sizeRef) == AXValueGetTypeID() {
            AXValueGetValue(unsafeDowncast(sizeRef, to: AXValue.self), .cgSize, &size)
        }
        return (origin, size)
    }

    /// 윈도우의 AX 위치 설정
    @discardableResult
    public static func setWindowPosition(axWindow: AXUIElement, position: CGPoint) -> Bool {
        var pos = position
        guard let posVal = AXValueCreate(.cgPoint, &pos) else { return false }
        return AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posVal) == .success
    }

    /// 윈도우의 AX 크기 설정
    @discardableResult
    public static func setWindowSize(axWindow: AXUIElement, size: CGSize) -> Bool {
        var sz = size
        guard let sizeVal = AXValueCreate(.cgSize, &sz) else { return false }
        return AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeVal) == .success
    }

    /// 비협조적 창(Chrome, Electron, 모달 팝업 등)을 오프스크린 파킹 좌표로 강제 퇴거
    @discardableResult
    public static func parkUncooperativeWindow(
        _ axWindow: AXUIElement,
        windowID: UInt32,
        pid: pid_t,
        roomID: String? = nil,
        screens: [NSScreen] = NSScreen.screens,
        isStageManager: Bool = isStageManagerEnabled
    ) -> Bool {
        guard let frame = getWindowFrame(axWindow: axWindow) else {
            return false
        }

        // 이미 파킹되어 있지 않다면 원래 위치/크기 저장
        if parkedStore.peek(for: windowID) == nil {
            let state = ParkedWindowState(
                cgWindowID: windowID,
                pid: pid,
                originalPosition: frame.origin,
                originalSize: frame.size,
                parkedAt: Date(),
                roomID: roomID
            )
            parkedStore.park(state)
        }

        let offscreenPoint = optimalOffscreenPointAX(screens: screens, isStageManager: isStageManager)
        return setWindowPosition(axWindow: axWindow, position: offscreenPoint)
    }

    /// 오프스크린 파킹된 창을 원래 위치로 복귀 (화면 축소/언플러그 시 자동 클램핑 및 캐스케이드)
    @discardableResult
    public static func restoreParkedWindow(
        _ axWindow: AXUIElement,
        windowID: UInt32,
        screens: [NSScreen] = NSScreen.screens,
        cascadeIndex: Int = 0
    ) -> Bool {
        guard let state = parkedStore.retrieve(for: windowID) else {
            return false
        }

        let primaryHeight = screens.first?.frame.height ?? 900
        let axFrames = screens.map { axFrame(for: $0.frame, primaryScreenHeight: primaryHeight) }
        let mainScreen = NSScreen.main ?? screens.first
        let mainVisible = mainScreen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let mainAX = axFrame(for: mainVisible, primaryScreenHeight: primaryHeight)

        let targetFrame = selfHealWindowFrame(
            windowFrame: CGRect(origin: state.originalPosition, size: state.originalSize),
            screenAXFrames: axFrames,
            targetScreenAX: mainAX,
            cascadeIndex: cascadeIndex
        )

        let posRestored = setWindowPosition(axWindow: axWindow, position: targetFrame.origin)
        if targetFrame.size.width > 50 && targetFrame.size.height > 50 {
            _ = setWindowSize(axWindow: axWindow, size: targetFrame.size)
        }

        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        return posRestored
    }

    /// 특정 룸의 파킹된 창 일괄 복귀
    @discardableResult
    public static func restoreParkedWindows(
        roomID: String,
        screens: [NSScreen] = NSScreen.screens
    ) -> Int {
        var restoredCount = 0
        let allParked = parkedStore.all().filter { $0.roomID == roomID }
        for (index, parked) in allParked.enumerated() {
            let appElement = AXUIElementCreateApplication(parked.pid)
            var windowsRef: AnyObject?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement] else {
                continue
            }
            for axWin in windows {
                if restoreParkedWindow(axWin, windowID: parked.cgWindowID, screens: screens, cascadeIndex: index) {
                    restoredCount += 1
                    break
                }
            }
        }
        return restoredCount
    }

    // MARK: - 1-프레임 원자적 트랜잭션

    /// 1-프레임 원자적 윈도우 업데이트 트랜잭션 래퍼 (깜빡임/스파이크 제로화)
    public static func withAtomicWindowUpdate<T>(_ body: () throws -> T) rethrows -> T {
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        defer {
            NSAnimationContext.endGrouping()
        }
        return try body()
    }

    // MARK: - 핀포인트 포커스 승격

    /// 핀포인트 3단계 원자적 포커스 활성화 (D0 플리커 원천 소거)
    /// 순서: D1 Main/Focused 주입 -> D1 AXRaise -> app.activate
    @discardableResult
    public static func pinpointFocusWindow(
        _ axWindow: AXUIElement,
        pid: pid_t
    ) -> Bool {
        AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(axWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        let raiseResult = AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        activateAppProcess(pid)
        return raiseResult == .success
    }

    private static func activateAppProcess(_ pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private static func matchesWindowTarget(title: String, currentTitle: String, isSingle: Bool) -> Bool {
        if title.isEmpty { return true }
        if isSingle { return true }
        return currentTitle.contains(title)
    }

    private static func restoreAndRaiseAXWindow(
        _ axWindow: AXUIElement,
        winIdent: WindowIdentity,
        totalWindowsCount: Int
    ) -> Bool {
        var titleRef: AnyObject?
        let _ = AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
        let currentTitle = titleRef as? String ?? ""

        guard matchesWindowTarget(
            title: winIdent.title,
            currentTitle: currentTitle,
            isSingle: totalWindowsCount == 1
        ) else { return false }

        // 오프스크린 파킹된 창인 경우 원래 위치/크기로 자동 복구
        if parkedStore.peek(for: winIdent.cgWindowID) != nil {
            restoreParkedWindow(axWindow, windowID: winIdent.cgWindowID)
        }

        var minRef: AnyObject?
        if AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minRef) == .success,
           let isMin = minRef as? Bool, isMin {
            AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        return true
    }

    private static func restoreAXWindows(
        for winIdent: WindowIdentity,
        appElement: AXUIElement
    ) -> Bool {
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return false
        }
        for axWindow in windows where restoreAndRaiseAXWindow(axWindow, winIdent: winIdent, totalWindowsCount: windows.count) {
            return true
        }
        return false
    }

    // MARK: - 룸 창 활성화 및 비활성화

    /// 룸 활성화 시 해당 룸 소속 창들을 전면(AXRaise)으로 올리고 활성화 (DAG 위상 정렬 순서)
    @discardableResult
    public static func activateRoomWindows(
        roomID: String,
        tenantID: String? = nil,
        policy: RoomWindowPolicy = .default
    ) -> Int {
        let snapshot = RoomWindowManager.loadSnapshot(roomID: roomID, tenantID: tenantID)
        guard !snapshot.windows.isEmpty else { return 0 }

        var raisedCount = 0
        var activatedPIDs = Set<pid_t>()

        let orderedWindows = snapshot.dag.topologicalOrder()

        for winIdent in orderedWindows {
            let pid = winIdent.pid
            let appElement = AXUIElementCreateApplication(pid)

            if restoreAXWindows(for: winIdent, appElement: appElement) {
                raisedCount += 1
            }

            guard !activatedPIDs.contains(pid) else { continue }
            activateAppProcess(pid)
            activatedPIDs.insert(pid)
        }

        return raisedCount
    }

    /// 룸 비활성화 시 해당 룸 소속 창들을 역위상 정렬(D2 -> D1 -> D0)로 은닉
    @discardableResult
    public static func deactivateRoomWindows(
        roomID: String,
        tenantID: String? = nil,
        policy: RoomWindowPolicy = .default
    ) -> Int {
        let snapshot = RoomWindowManager.loadSnapshot(roomID: roomID, tenantID: tenantID)
        guard !snapshot.windows.isEmpty else { return 0 }

        var hiddenCount = 0
        let reverseOrdered = snapshot.dag.reverseTopologicalOrder()
        var hiddenPIDs = Set<pid_t>()

        for winIdent in reverseOrdered {
            guard winIdent.scope != .globalSticky else { continue }

            let pid = winIdent.pid
            let app = NSRunningApplication(processIdentifier: pid)
            let appElement = AXUIElementCreateApplication(pid)
            var windowsRef: AnyObject?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement] else {
                continue
            }

            if windows.count <= 1 && !hiddenPIDs.contains(pid) {
                if let app = app, !app.isHidden {
                    let hideSuccess = app.hide()
                    // 비협조적 앱: app.hide()가 거부/무시되거나 여전히 가시 상태인 경우 오프스크린 파킹
                    if !hideSuccess || !app.isHidden {
                        if let firstWindow = windows.first {
                            parkUncooperativeWindow(firstWindow, windowID: winIdent.cgWindowID, pid: pid, roomID: roomID)
                        }
                    }
                    hiddenPIDs.insert(pid)
                    hiddenCount += 1
                }
                continue
            }

            for axWindow in windows {
                var titleRef: AnyObject?
                let _ = AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
                let currentTitle = titleRef as? String ?? ""
                guard matchesWindowTarget(
                    title: winIdent.title,
                    currentTitle: currentTitle,
                    isSingle: windows.count == 1
                ) else { continue }

                switch policy.deactivationAction {
                case .hide, .minimize:
                    let minResult = AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
                    if minResult != .success {
                        // 모달 팝업, Electron 등 최소화 거부/미지원 비협조적 창: 오프스크린 파킹으로 강제 퇴거
                        parkUncooperativeWindow(axWindow, windowID: winIdent.cgWindowID, pid: pid, roomID: roomID)
                    }
                    hiddenCount += 1
                case .none:
                    break
                }
            }
        }

        return hiddenCount
    }

    // MARK: - Strict Baseline 집행

    /// 스트릭트 베이스라인 집행
    @discardableResult
    public static func enforceStrictBaseline(
        activeRoomID: String,
        activeBundleIDs: Set<String>,
        globalStickyBundleIDs: Set<String> = ["com.tinyspeck.slackmacgap", "com.1password.1password", "com.apple.finder"],
        tenantID: String? = nil
    ) -> (raised: Int, stashed: Int) {
        guard isAccessibilityTrusted else {
            return (0, 0)
        }

        return withAtomicWindowUpdate {
            let raised = activateRoomWindows(roomID: activeRoomID, tenantID: tenantID)
            var stashed = 0
            let runningApps = NSWorkspace.shared.runningApplications

            for app in runningApps where app.activationPolicy == .regular {
                guard let bid = app.bundleIdentifier,
                      !globalStickyBundleIDs.contains(bid),
                      !activeBundleIDs.contains(bid),
                      !app.isHidden else {
                    continue
                }

                let hideOk = app.hide()
                if !hideOk || !app.isHidden {
                    // 비협조적 앱: AX 창 목록을 순회하여 오프스크린 파킹으로 강제 퇴거
                    let appElement = AXUIElementCreateApplication(app.processIdentifier)
                    var windowsRef: AnyObject?
                    if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                       let windows = windowsRef as? [AXUIElement] {
                        for (idx, axWin) in windows.enumerated() {
                            let pseudoID = UInt32(bitPattern: app.processIdentifier) ^ UInt32(idx)
                            parkUncooperativeWindow(axWin, windowID: pseudoID, pid: app.processIdentifier, roomID: nil)
                        }
                    }
                }
                stashed += 1
            }

            return (raised, stashed)
        }
    }

    /// 특정 룸의 windows.json에 등록된 창들의 bundleID 목록 조회
    public static func loadRegisteredBundleIDs(roomID: String, tenantID: String? = nil) -> Set<String> {
        let snapshot = RoomWindowManager.loadSnapshot(roomID: roomID, tenantID: tenantID)
        return Set(snapshot.windows.map(\.bundleID).filter { !$0.isEmpty })
    }

    // MARK: - 좀비 GC & 비상 탈출

    /// 사망한 프로세스의 창 레코드를 windows.json에서 제거
    @discardableResult
    public static func pruneZombieWindows(
        roomID: String,
        tenantID: String? = nil,
        runningPIDs: Set<pid_t>? = nil
    ) throws -> Int {
        let activePIDs = runningPIDs ?? Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        return try RoomWindowManager.pruneZombieWindows(
            roomID: roomID,
            tenantID: tenantID,
            activePIDs: activePIDs
        )
    }

    /// 긴급 창 복구 결과 구조체
    public struct EvacuateResult: Sendable, Equatable {
        public let unhiddenAppsCount: Int
        public let unminimizedWindowsCount: Int
        public let repositionedWindowsCount: Int

        public init(
            unhiddenAppsCount: Int,
            unminimizedWindowsCount: Int,
            repositionedWindowsCount: Int
        ) {
            self.unhiddenAppsCount = unhiddenAppsCount
            self.unminimizedWindowsCount = unminimizedWindowsCount
            self.repositionedWindowsCount = repositionedWindowsCount
        }

        public var totalCount: Int {
            unhiddenAppsCount + unminimizedWindowsCount + repositionedWindowsCount
        }
    }

    /// 모든 숨겨진 앱 및 창 비상 복구:
    /// - `app.unhide()`로 숨겨진 앱 표시
    /// - `kAXMinimizedAttribute = false`로 최소화 창 복귀
    /// - 오프스크린/코너 파킹 좌표 창 주 화면 중앙 캐스케이드 재배치
    /// - 최상위 `AXRaise` 수행
    @discardableResult
    public static func emergencyEvacuateAll() -> EvacuateResult {
        var unhiddenAppsCount = 0
        var unminimizedWindowsCount = 0
        var repositionedWindowsCount = 0

        let runningApps = NSWorkspace.shared.runningApplications
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        let screenAXFrames = NSScreen.screens.map { screen -> CGRect in
            let f = screen.frame
            return CGRect(
                x: f.origin.x,
                y: primaryScreenHeight - f.origin.y - f.height,
                width: f.width,
                height: f.height
            )
        }
        let mainScreen = NSScreen.main ?? NSScreen.screens.first
        let mainVisible = mainScreen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let mainAXVisible = CGRect(
            x: mainVisible.origin.x,
            y: primaryScreenHeight - mainVisible.origin.y - mainVisible.height,
            width: mainVisible.width,
            height: mainVisible.height
        )

        for app in runningApps where app.activationPolicy == .regular {
            if app.isHidden {
                app.unhide()
                unhiddenAppsCount += 1
            }

            guard isAccessibilityTrusted else { continue }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: AnyObject?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement] else {
                continue
            }

            for axWindow in windows {
                // 1. 최소화 해제
                var minRef: AnyObject?
                if AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minRef) == .success,
                   let isMin = minRef as? Bool, isMin {
                    AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                    unminimizedWindowsCount += 1
                }

                // 2. 오프스크린 / 코너 파킹 좌표 검사 및 중앙 캐스케이드 재배치
                var origin = CGPoint.zero
                var size = CGSize.zero
                var posRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef) == .success,
                   let posRef, CFGetTypeID(posRef) == AXValueGetTypeID() {
                    AXValueGetValue(unsafeDowncast(posRef, to: AXValue.self), .cgPoint, &origin)
                }
                var sizeRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success,
                   let sizeRef, CFGetTypeID(sizeRef) == AXValueGetTypeID() {
                    AXValueGetValue(unsafeDowncast(sizeRef, to: AXValue.self), .cgSize, &size)
                }

                let winRect = CGRect(origin: origin, size: size)
                let maxVisibleIntersectionArea = screenAXFrames.reduce(CGFloat.zero) { maxArea, screenRect in
                    let inter = screenRect.intersection(winRect)
                    guard !inter.isNull else { return maxArea }
                    return max(maxArea, inter.width * inter.height)
                }

                // 가시 영역이 100x100 픽셀 미만이거나 극소(코너 1x1 등) 파킹된 경우
                let isOffscreenOrCorner = maxVisibleIntersectionArea < 10000 || winRect.width < 50 || winRect.height < 50

                if isOffscreenOrCorner {
                    let cascadeOffset = CGFloat(repositionedWindowsCount % 10) * 28.0
                    let targetWidth = max(size.width, 640)
                    let targetHeight = max(size.height, 480)
                    var newOrigin = CGPoint(
                        x: mainAXVisible.midX - targetWidth / 2 + cascadeOffset,
                        y: mainAXVisible.midY - targetHeight / 2 + cascadeOffset
                    )
                    if let posVal = AXValueCreate(.cgPoint, &newOrigin) {
                        AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posVal)
                    }
                    if size.width < 50 || size.height < 50 {
                        var newSize = CGSize(width: targetWidth, height: targetHeight)
                        if let sizeVal = AXValueCreate(.cgSize, &newSize) {
                            AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeVal)
                        }
                    }
                    repositionedWindowsCount += 1
                }

                // 3. 최상위 AXRaise
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
            }
        }

        // 4. 오프스크린 파킹 저장소 초기화
        let evacuatedParked = parkedStore.removeAll()
        if repositionedWindowsCount == 0 && !evacuatedParked.isEmpty {
            repositionedWindowsCount = evacuatedParked.count
        }

        return EvacuateResult(
            unhiddenAppsCount: unhiddenAppsCount,
            unminimizedWindowsCount: unminimizedWindowsCount,
            repositionedWindowsCount: repositionedWindowsCount
        )
    }

    /// 모든 숨겨진 창 일괄 원복 (하위 호환성 유지)
    @discardableResult
    public static func emergencyEvacuateAllHiddenWindows() -> Int {
        emergencyEvacuateAll().unhiddenAppsCount
    }

    // MARK: - 절전 복귀(Sleep/Wake) 및 디스플레이 외란 방어

    /// 절전 복귀 정합성 결과 구조체
    public struct WakeReconciliationResult: Sendable, Equatable {
        public let prunedZombieParkedCount: Int
        public let reparkedWindowsCount: Int
        public let healedOrphanedWindowsCount: Int

        public init(
            prunedZombieParkedCount: Int,
            reparkedWindowsCount: Int,
            healedOrphanedWindowsCount: Int
        ) {
            self.prunedZombieParkedCount = prunedZombieParkedCount
            self.reparkedWindowsCount = reparkedWindowsCount
            self.healedOrphanedWindowsCount = healedOrphanedWindowsCount
        }

        public var totalRemediatedCount: Int {
            prunedZombieParkedCount + reparkedWindowsCount + healedOrphanedWindowsCount
        }
    }

    /// 화면 변경 정합성 결과 구조체
    public struct DisplayChangeReconciliationResult: Sendable, Equatable {
        public let reparkedWindowsCount: Int
        public let healedOrphanedWindowsCount: Int

        public init(
            reparkedWindowsCount: Int,
            healedOrphanedWindowsCount: Int
        ) {
            self.reparkedWindowsCount = reparkedWindowsCount
            self.healedOrphanedWindowsCount = healedOrphanedWindowsCount
        }

        public var totalRemediatedCount: Int {
            reparkedWindowsCount + healedOrphanedWindowsCount
        }
    }

    /// Mac이 Sleep(잠자기) 상태에서 Wake(깨어남)할 때 오프스크린 파킹 창들이 허공으로 유실되지 않도록 보장하는 안전망 처리
    @discardableResult
    public static func handleWakeFromSleep(
        screens: [NSScreen] = NSScreen.screens
    ) -> WakeReconciliationResult {
        let activePIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        let prunedZombies = parkedStore.pruneZombies(activePIDs: activePIDs)
        let reparkedCount = reconcileParkedWindows(screens: screens)
        let healedCount = selfHealOrphanedWindows(screens: screens)

        return WakeReconciliationResult(
            prunedZombieParkedCount: prunedZombies.count,
            reparkedWindowsCount: reparkedCount,
            healedOrphanedWindowsCount: healedCount
        )
    }

    /// 외장 모니터 핫플러그/언플러그 또는 해상도 변경 시 일괄 정합성 동기화
    @discardableResult
    public static func handleScreenParametersChanged(
        screens: [NSScreen] = NSScreen.screens
    ) -> DisplayChangeReconciliationResult {
        let reparkedCount = reconcileParkedWindows(screens: screens)
        let healedCount = selfHealOrphanedWindows(screens: screens)

        return DisplayChangeReconciliationResult(
            reparkedWindowsCount: reparkedCount,
            healedOrphanedWindowsCount: healedCount
        )
    }

    /// 화면 구성 변경 후 파킹된 창들이 안전 오프스크린 좌표에 위치하도록 재정렬 (허공 유실 방지)
    @discardableResult
    public static func reconcileParkedWindows(
        screens: [NSScreen] = NSScreen.screens,
        isStageManager: Bool = isStageManagerEnabled
    ) -> Int {
        guard isAccessibilityTrusted else { return 0 }
        let allParked = parkedStore.all()
        guard !allParked.isEmpty else { return 0 }

        let targetOffscreen = optimalOffscreenPointAX(screens: screens, isStageManager: isStageManager)
        var reparkedCount = 0

        for parked in allParked {
            let appElement = AXUIElementCreateApplication(parked.pid)
            var windowsRef: AnyObject?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement] else {
                continue
            }
            for axWin in windows {
                var wid: CGWindowID = 0
                let status = _AXUIElementGetWindow(axWin, &wid)
                guard status == .success, wid != 0, wid == parked.cgWindowID else { continue }
                if let frame = getWindowFrame(axWindow: axWin) {
                    if abs(frame.origin.x - targetOffscreen.x) > 10 || abs(frame.origin.y - targetOffscreen.y) > 10 {
                        if setWindowPosition(axWindow: axWin, position: targetOffscreen) {
                            reparkedCount += 1
                        }
                    }
                }
            }
        }
        return reparkedCount
    }

    /// 외장 모니터 분리 등으로 화면 밖으로 밀려난 일반 가시 창들을 메인 스크린으로 자동 클램핑/캐스케이드
    @discardableResult
    public static func selfHealOrphanedWindows(
        screens: [NSScreen] = NSScreen.screens
    ) -> Int {
        guard isAccessibilityTrusted else { return 0 }
        guard let primary = screens.first else { return 0 }

        let primaryHeight = primary.frame.height
        let screenAXFrames = screens.map { axFrame(for: $0.frame, primaryScreenHeight: primaryHeight) }
        let mainScreen = NSScreen.main ?? primary
        let mainVisible = mainScreen.visibleFrame
        let targetScreenAX = axFrame(for: mainVisible, primaryScreenHeight: primaryHeight)

        let runningApps = NSWorkspace.shared.runningApplications
        var healedCount = 0

        for app in runningApps where app.activationPolicy == .regular {
            guard !app.isHidden else { continue }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: AnyObject?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement] else {
                continue
            }

            for axWin in windows {
                var minRef: AnyObject?
                if AXUIElementCopyAttributeValue(axWin, kAXMinimizedAttribute as CFString, &minRef) == .success,
                   let isMin = minRef as? Bool, isMin {
                    continue
                }

                guard let frame = getWindowFrame(axWindow: axWin) else { continue }
                let winRect = CGRect(origin: frame.origin, size: frame.size)

                // 파킹 저장소에 등록된 오프스크린 창은 제외
                let isParked = parkedStore.all().contains { $0.pid == app.processIdentifier }
                if isParked && (winRect.origin.x > targetScreenAX.maxX || winRect.origin.y > targetScreenAX.maxY) {
                    continue
                }

                let healed = selfHealWindowFrame(
                    windowFrame: winRect,
                    screenAXFrames: screenAXFrames,
                    targetScreenAX: targetScreenAX,
                    cascadeIndex: healedCount
                )

                if healed != winRect {
                    setWindowPosition(axWindow: axWin, position: healed.origin)
                    if healed.size != winRect.size {
                        setWindowSize(axWindow: axWin, size: healed.size)
                    }
                    AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
                    healedCount += 1
                }
            }
        }

        return healedCount
    }

    // MARK: - 화면 변경 및 절전 복귀 관측 안전망

    nonisolated(unsafe) private static var didWakeObserver: (any NSObjectProtocol)?
    nonisolated(unsafe) private static var screensDidWakeObserver: (any NSObjectProtocol)?
    nonisolated(unsafe) private static var screenParamsObserver: (any NSObjectProtocol)?
    private static let observerLock = NSLock()

    /// 절전 복귀(Sleep -> Wake) 및 화면 구성 변경 알림 관측기 설치
    public static func installEnvironmentObservers() {
        observerLock.lock()
        defer { observerLock.unlock() }

        guard didWakeObserver == nil else { return }

        // 1. NSWorkspace.didWakeNotification
        didWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            _ = handleWakeFromSleep()
        }

        // 2. NSWorkspace.screensDidWakeNotification
        screensDidWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            _ = handleWakeFromSleep()
        }

        // 3. NSApplication.didChangeScreenParametersNotification
        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            _ = handleScreenParametersChanged()
        }
    }

    /// 환경 관측기 해제
    public static func removeEnvironmentObservers() {
        observerLock.lock()
        defer { observerLock.unlock() }

        if let obs = didWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            didWakeObserver = nil
        }
        if let obs = screensDidWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            screensDidWakeObserver = nil
        }
        if let obs = screenParamsObserver {
            NotificationCenter.default.removeObserver(obs)
            screenParamsObserver = nil
        }
    }

    /// 환경 관측기 설치 여부
    public static var areEnvironmentObserversInstalled: Bool {
        observerLock.lock()
        defer { observerLock.unlock() }
        return didWakeObserver != nil
    }

    nonisolated(unsafe) private static var isTerminationTrapInstalled = false
    nonisolated(unsafe) private static var sigintSource: (any DispatchSourceSignal)?
    nonisolated(unsafe) private static var sigtermSource: (any DispatchSourceSignal)?

    public static func installTerminationTrap() {
        installEnvironmentObservers()
        guard !isTerminationTrapInstalled else { return }
        isTerminationTrapInstalled = true

        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        intSource.setEventHandler {
            _ = emergencyEvacuateAll()
            exit(130)
        }
        intSource.resume()
        sigintSource = intSource

        let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termSource.setEventHandler {
            _ = emergencyEvacuateAll()
            exit(143)
        }
        termSource.resume()
        sigtermSource = termSource
    }
}
#endif
