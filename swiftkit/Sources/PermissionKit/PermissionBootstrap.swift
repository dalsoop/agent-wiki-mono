import AppKit
import CoreGraphics
import Foundation
import IOKit.hid

/// 관리 앱이 대상 앱을 열 때 전달하는 1회성 권한 등록 요청.
/// TCC는 요청한 앱만 목록에 올릴 수 있으므로, 중앙 관리 앱이 아닌 대상 번들에서 실행한다.
///
/// ## 앱 채택 계약 (fleet SSOT)
/// 1. `Package.swift` GUI 타깃: `PermissionKit` (+ 보통 `SingleInstanceKit`)
/// 2. `init` / `applicationDidFinishLaunching`:
///    - `if !PermissionBootstrap.isRequested { SingleInstance.exitIfAlreadyRunning() }`
///    - `runIfRequested(appName:)` 호출 — **true 면 전체 UI/파이프라인 스킵**
/// 3. SwiftUI body: `if PermissionBootstrap.isRequested { Color.clear… } else { 본문 }`
/// 4. `Packaging/Info.plist` `MacPermissionsRequired` 는 **런타임 게이트와 동일**
///    (과대 선언 금지 — inputMonitoring 등 목록 안 뜨는 거짓 갭 원인)
/// 5. 등록 실행은 **NSWorkspace 로 .app 번들** 을 연다(바이너리 직접 exec 금지)
public enum PermissionBootstrap {
    public static let argumentPrefix = "--permission-bootstrap="

    /// 기존 인스턴스가 실행 중이어도, 권한 등록 전용 실행은 잠시 허용해야 한다.
    public static var isRequested: Bool {
        requestedService(from: CommandLine.arguments) != nil
    }

    /// CLI/테스트용: argv 에서 서비스 식별자 추출.
    public static func requestedService(from arguments: [String]) -> String? {
        guard let argument = arguments.first(where: { $0.hasPrefix(argumentPrefix) }) else {
            return nil
        }
        let service = String(argument.dropFirst(argumentPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return service.isEmpty ? nil : service
    }

    /// Only these service identifiers have a real target-app registration
    /// implementation. The manager uses this before presenting an action so a
    /// user never presses a button that silently does nothing.
    public static func supportsRegistration(service: String) -> Bool {
        switch service {
        case "accessibility", "screenRecording", "inputMonitoring": true
        default: false
        }
    }

    /// 등록 전용 실행: 권한 요청을 보낸 뒤(설정 목록 행 생성) 짧게 대기하고 종료한다.
    ///
    /// - Returns: bootstrap 인자를 처리했으면 `true`. 호출 앱은 전체 UI/탭 설치를
    ///   건너뛰어야 한다(Lecture Tools 실측: InputTap·오버레이가 끼면 ListenEvent
    ///   행이 안 생기거나 즉시 terminate 와 경합한다).
    ///
    /// `repair`(tccutil reset) 는 등록 전용 경로에서 **쓰지 않는다**.
    @MainActor @discardableResult
    public static func runIfRequested(appName: String) -> Bool {
        guard let service = requestedService(from: CommandLine.arguments) else { return false }
        guard supportsRegistration(service: service) else { return true }
        // 액세서리 정책이면 일부 시스템 프롬프트/목록 등록이 약해진다.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApp.activate()

        Task { @MainActor in
            // 런 루프·윈도우 서버 준비.
            try? await Task.sleep(for: .milliseconds(500))
            requestRegistration(for: service)
            // TCC 기록 여유 — ListenEvent + event-tap 반영에 여유.
            try? await Task.sleep(for: .milliseconds(2800))
            NSApplication.shared.terminate(nil)
        }
        return true
    }

    /// 순수 요청 분기 — `runIfRequested` 와 동일 MainActor 컨텍스트.
    @MainActor
    public static func requestRegistration(for service: String) {
        switch service {
        case "accessibility":
            Permission.accessibility.request()
        case "screenRecording":
            Permission.screenRecording.request()
        case "inputMonitoring":
            requestInputMonitoring()
        default:
            break
        }
    }

    /// Input Monitoring(ListenEvent) 목록 행 생성.
    ///
    /// 1) `IOHIDRequestAccess` / `CGRequestListenEventAccess`
    /// 2) CGEventTap 을 run loop 에 잠깐 올려 TCC 가 client 행을 쓰게 한다.
    ///    create 직후 invalidate 만 하면 Sequoia 에서 행이 안 생기는 실측
    ///    (Lecture Tools system TCC 에 Accessibility/ScreenCapture 만 있고
    ///    ListenEvent 부재).
    @MainActor
    public static func requestInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        _ = CGRequestListenEventAccess()

        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        )
        // defaultTap: 실제 탭 설치 경로. listenOnly 만으로는 목록 미생성 사례 있음.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in
                // 통과만 — 목록 등록 부작용용 프로브.
                Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else {
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        // TCC 기록 기회 — MainActor run loop 가 돌아야 한다.
        CFRunLoopRunInMode(.defaultMode, 0.8, false)
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        CFMachPortInvalidate(tap)
    }
}
