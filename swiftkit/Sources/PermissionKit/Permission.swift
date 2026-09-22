import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import Foundation
import LocalizationKit

/// The TCC permissions our menu-bar apps gate on, with a uniform
/// preflight → request → "open the right Settings pane" flow so no app has to
/// hand-roll `CGPreflightScreenCaptureAccess()` + an `NSAlert` + a `Privacy_*`
/// deep link again. The user-facing copy lives here (bilingual, in code — no
/// resource bundle, so nothing extra to package), which means a wording change
/// is a one-line edit that every adopting app picks up at once.
public enum Permission: Sendable, Hashable, CaseIterable, Codable {
    case screenRecording
    case accessibility
    case camera
    /// 마이크 — 카메라와 같은 AVFoundation 비동기 승인 모델.
    case microphone
    /// 입력 모니터링 — 프롬프트만으로는 TCC 행이 안 생겨서 이벤트 탭을 잠깐 올려야 한다
    /// (`PermissionBootstrap.requestInputMonitoring` 참고, Sequoia 실측).
    case inputMonitoring
    /// 전체 디스크 접근 — TCC.db 가 읽히면 허용으로 본다(시스템 프롬프트 API 없음).
    case fullDiskAccess
    /// 위치 — Wi-Fi SSID 등. 좌표 수집이 아니라 TCC 상태만 쓴다.
    case location
}

public extension Permission {
    /// 아직 물어보지 않았는가. 위치는 notDetermined, 나머지는 미허용이면 true 가 아니다
    /// (AX 등은 preflight 만으로는 undetermined 를 가릴 수 없다).
    nonisolated var isUndetermined: Bool {
        guard self == .location else { return false }
        return LocationAuthorization.isNotDetermined
    }

    /// Synchronous preflight — never shows a prompt. Safe on macOS 14+.
    /// `nonisolated`: TCC preflight APIs are process-wide and thread-safe; core/helpers
    /// (AXPermission, scanners) call this outside `@MainActor` without hopping.
    nonisolated var isGranted: Bool {
        switch self {
        case .screenRecording: return CGPreflightScreenCaptureAccess()
        case .accessibility:   return AXIsProcessTrusted()
        case .camera:          return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        case .microphone:      return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        // preflight 는 프롬프트를 띄우지 않는다 — listen 접근만 조회한다.
        case .inputMonitoring: return CGPreflightListenEventAccess()
        case .fullDiskAccess:  return Self.canReadUserTCCDatabase()
        case .location:
            return LocationAuthorization.isGranted
        }
    }

    /// 시작·주기 갱신용. FDA 는 Sequoia 에서 조회만으로 프롬프트가 반복될 수 있어
    /// 여기서는 답을 주지 않는다. 사용자가 FDA 를 물었을 때만 `isGranted` 를 쓴다.
    nonisolated var grantedIfSafeToProbe: Bool? {
        if self == .fullDiskAccess { return nil }
        return isGranted
    }

    /// 사용자 TCC.db 가 읽히면 FDA 보유. mac-permissions-manager 매트릭스와 같은 신호.
    ///
    /// ⚠️ 이 프로브는 다른 앱의 데이터 영역(`~/Library/Application Support/com.apple.TCC`)
    /// 을 건드린다. Sequoia 에서는 앱 데이터 보호가 걸려 "다른 앱의 데이터에 접근하려
    /// 합니다" 프롬프트가 뜰 수 있고, 그 답은 저장되지 않아 반복된다(실측: `TCCReader`
    /// 주석 참조). 앱 시작·주기 갱신 경로에서 부르지 말고, 사용자가 FDA 여부를 물었을
    /// 때만 부른다.
    nonisolated static func canReadUserTCCDatabase(
        home: String = NSHomeDirectory()
    ) -> Bool {
        let path = (home as NSString)
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        return FileManager.default.isReadableFile(atPath: path)
    }

    /// Trigger the system prompt and register the app in the TCC list. Camera's
    /// grant is asynchronous — prefer `ensureGranted` for it; this fires the
    /// prompt without awaiting.
    @MainActor func request() {
        switch self {
        case .screenRecording:
            CGRequestScreenCaptureAccess()
        case .accessibility:
            // Literal key = the documented "AXTrustedCheckOptionPrompt".
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .camera:
            AVCaptureDevice.requestAccess(for: .video) { _ in }
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        case .inputMonitoring:
            // 프롬프트 API 만으로는 TCC 에 client 행이 안 생긴다 — 부트스트랩이 이벤트 탭까지 올린다.
            PermissionBootstrap.requestInputMonitoring()
        case .fullDiskAccess:
            // 시스템 프롬프트 없음 — repair 가 tccutil reset + 설정 오픈으로 처리.
            break
        case .location:
            LocationAuthorization.request()
        }
    }

    /// Open the exact System Settings pane for this permission.
    ///
    /// 설정 앱이 이미 떠 있어도 해당 Privacy 앵커로 다시 라우팅한다.
    /// `NSWorkspace.open` 이 조용히 실패하는 경우(재서명 직후·포커스 경쟁)를
    /// `/usr/bin/open` 폴백으로 막는다 — “권한 다시 고치기” 가 설정으로 안 가는
    /// 실사용 실패를 여기서 끊는다.
    @MainActor func openSettings() {
        PrivacySettingsOpener.open(primaryURLString: settingsURLString)
    }

    /// One-line "선 권한 게이트" for the sync-preflightable permissions
    /// (screen recording, accessibility): returns `true` if granted, otherwise
    /// prompts, shows the standard alert, and returns `false`. Replaces the
    /// hand-rolled `guard CGPreflight… else { alert; return }` blocks.
    @discardableResult
    @MainActor func gate(appName: String, language: AppLanguage = .system) -> Bool {
        if isGranted { return true }
        request()
        presentDeniedAlert(appName: appName, language: language)
        return false
    }

    /// Async gate that also covers camera (which needs `requestAccess`): prompts
    /// on `.notDetermined`, shows the alert on a hard denial.
    ///
    /// - Parameter presentAlertOnDenial: 거부 시 표준 모달 경고를 띄울지. UI 가 없는 경로
    ///   (캡처 엔진·CLI·백그라운드 작업)에서는 **false** 로 줘야 한다 — 거기서 모달을 띄우면
    ///   호출이 사람 입력을 기다리며 멈춘다. 실측 2026-08-08: voice-scribe CaptureEngine 이
    ///   원시 API 를 이 API 로 치환하면서 "거부 시 조용히 false" 가 모달로 바뀌었다.
    @discardableResult
    @MainActor func ensureGranted(
        appName: String,
        language: AppLanguage = .system,
        presentAlertOnDenial: Bool = true
    ) async -> Bool {
        if isGranted { return true }
        // AVFoundation 계열(카메라·마이크)은 비동기 승인이라 await 로 받아야 첫 허용을 놓치지 않는다.
        if let mediaType = avMediaType {
            if AVCaptureDevice.authorizationStatus(for: mediaType) == .notDetermined,
               await AVCaptureDevice.requestAccess(for: mediaType) {
                return true
            }
        } else if self == .location {
            LocationAuthorization.request()
            try? await Task.sleep(nanoseconds: 400_000_000)
        } else {
            request()
        }
        // 프롬프트 직후 상태가 갱신되는 경로(손쉬운 사용 등)를 한 번 더 본다 —
        // 여기서 바로 false 를 내면 사용자가 방금 허용했는데도 거부로 보고한다.
        if isGranted { return true }
        if presentAlertOnDenial {
            presentDeniedAlert(appName: appName, language: language)
        }
        return false
    }

    /// AVFoundation 승인 모델을 쓰는 권한인가 — 그 계열만 `requestAccess` 를 await 한다.
    var avMediaType: AVMediaType? {
        switch self {
        case .camera: return .video
        case .microphone: return .audio
        default: return nil
        }
    }

    /// The standard localized "grant X permission" alert with an Open-Settings
    /// button that jumps straight to the right pane.
    ///
    /// Prefer `repair` first — this alert is only the last-mile “turn on the
    /// fresh list row” after we already cleared stale TCC for our bundle.
    @MainActor func presentDeniedAlert(appName: String, language: AppLanguage = .system) {
        let copy = strings(korean: Self.isKorean(language), appName: appName)
        let alert = NSAlert()
        alert.messageText = copy.title
        alert.informativeText = copy.body
        alert.addButton(withTitle: copy.openSettings)
        alert.addButton(withTitle: copy.close)
        if alert.runModal() == .alertFirstButtonReturn {
            openSettings()
        }
    }

    /// Residual-TCC tip for in-app banners (home callout, onboarding).
    public static func residualListGuidance(appName: String, language: AppLanguage = .system) -> String {
        residualGuidance(korean: isKorean(language), appName: appName)
    }

    /// **파악해서 처리**: 이 프로세스에 권한이 없으면
    /// 1) 우리 번들의 옛 TCC 항목을 `tccutil reset` 으로 지우고
    /// 2) 시스템 프롬프트로 현재 바이너리를 목록에 다시 등록한 뒤
    /// 3) 해당 설정 패널을 연다.
    ///
    /// 사용자가 “목록에 이미 켜져 있는데 왜 안 되지?” 하는 재서명 잔존을
    /// 앱이 직접 정리한다. 최종 ON 토글만 사용자 동작이 남는다(macOS 정책).
    @MainActor
    @discardableResult
    func repair(
        appName: String,
        bundleID: String? = Bundle.main.bundleIdentifier,
        openSettingsPane: Bool = true,
        language: AppLanguage = .system
    ) async -> PermissionRepairReport {
        let korean = Self.isKorean(language)
        if isGranted {
            return PermissionRepairReport(
                phase: .alreadyGranted,
                granted: true,
                resetAttempted: false,
                resetSucceeded: false,
                service: tccService,
                detail: korean ? "이미 이 앱에 권한이 있습니다." : "Already granted for this process."
            )
        }

        let service = tccService
        // FDA 는 시스템 프롬프트가 없지만 tccutil reset + 설정 오픈은 Screenshot 과 같은
        // “파악→처리” 경로로 지원한다(목록 재추가·토글은 사용자).
        let canAutoRepair = service.supportsLiveRepair || self == .fullDiskAccess

        // 설정을 먼저 연다. tccutil·request 가 지연/차단돼도 사용자는 스위치 화면을 본다.
        if openSettingsPane {
            openSettings()
        }

        guard canAutoRepair else {
            request()
            return PermissionRepairReport(
                phase: .unsupported,
                granted: isGranted,
                resetAttempted: false,
                resetSucceeded: false,
                service: service,
                detail: korean
                    ? "이 권한은 자동 정리를 지원하지 않습니다. 설정에서 허용해 주세요."
                    : "Automatic cleanup is not available for this permission. Enable it in Settings."
            )
        }

        var resetOK = false
        var resetAttempted = false
        if let bid = bundleID, !bid.isEmpty {
            resetAttempted = true
            // MainActor 를 막지 않도록 tccutil 은 백그라운드에서.
            resetOK = await Task.detached {
                TCCUtil.reset(service: service, bundleID: bid)
            }.value
        }

        // 리셋 직후 현재 바이너리를 목록에 다시 올린다(옛 csreq 줄과 분리).
        // FDA 는 request 가 no-op — 설정 패널에서 + / 토글.
        request()
        // 프롬프트/리셋 반영 한 박자 후 설정을 한 번 더 — 포커스 뺏긴 경우 복구.
        try? await Task.sleep(for: .milliseconds(200))
        if openSettingsPane {
            openSettings()
        }

        let grantedNow = isGranted
        if grantedNow {
            return PermissionRepairReport(
                phase: resetOK ? .clearedStaleAndPrompted : .promptOnly,
                granted: true,
                resetAttempted: resetAttempted,
                resetSucceeded: resetOK,
                service: service,
                detail: korean ? "권한이 허용되었습니다." : "Permission granted."
            )
        }

        let phase: PermissionRepairReport.Phase = resetOK ? .clearedStaleAndPrompted : .promptOnly
        let detail: String
        if self == .fullDiskAccess {
            if korean {
                detail = resetOK
                    ? "옛 전체 디스크 접근 항목을 지웠습니다. 열린 설정에서 \(appName) 을(를) 추가(+ )하고 스위치를 켜 주세요. 켜면 TCC 를 읽습니다."
                    : "열린 설정 › 전체 디스크 접근에서 \(appName) 스위치를 켜 주세요. 목록에 없으면 + 로 추가합니다."
            } else {
                detail = resetOK
                    ? "Cleared stale Full Disk Access. In Settings, add \(appName) with + and turn it on."
                    : "In Settings › Full Disk Access, turn on \(appName) (add with + if missing)."
            }
        } else if korean {
            if resetOK {
                detail = "옛 권한 항목을 지우고 이 빌드를 다시 등록했습니다. 열린 설정에서 \(appName) 스위치를 켜 주세요."
            } else {
                detail = "이 빌드용 권한을 다시 요청했습니다. 열린 설정에서 \(appName) 스위치를 켜 주세요."
            }
        } else {
            if resetOK {
                detail = "Cleared stale entries and re-registered this build. Turn on \(appName) in the Settings window that opened."
            } else {
                detail = "Re-requested permission for this build. Turn on \(appName) in the Settings window that opened."
            }
        }
        return PermissionRepairReport(
            phase: phase,
            granted: false,
            resetAttempted: resetAttempted,
            resetSucceeded: resetOK,
            service: service,
            detail: detail
        )
    }

    /// 거부 시 안내만 하지 않고 `repair` 를 먼저 돌린 뒤, 그래도 없으면 짧은 알림.
    @MainActor
    @discardableResult
    func gateAndRepair(
        appName: String,
        language: AppLanguage = .system
    ) async -> Bool {
        if isGranted { return true }
        let report = await repair(appName: appName, language: language)
        if report.granted { return true }
        // 최종 ON 은 사용자 토글 — 알림 본문은 repair detail 한 줄.
        let alert = NSAlert()
        alert.messageText = Self.isKorean(language)
            ? "\(appName) 권한을 켜 주세요"
            : "Turn on \(appName)"
        alert.informativeText = report.detail
        alert.addButton(withTitle: Self.isKorean(language) ? "설정 다시 열기" : "Open Settings again")
        alert.addButton(withTitle: Self.isKorean(language) ? "닫기" : "Close")
        if alert.runModal() == .alertFirstButtonReturn {
            openSettings()
        }
        return isGranted
    }
}

// MARK: - Owned copy + deep links (change once, applies everywhere)

private extension Permission {
    var settingsURLString: String { tccService.settingsURLString }

    static func isKorean(_ language: AppLanguage) -> Bool {
        switch language {
        case .korean:  return true
        case .english: return false
        case .system:  return Locale.current.language.languageCode?.identifier == "ko"
        }
    }

    struct Copy { let title, body, openSettings, close: String }

    /// 자동 정리 후에도 사용자가 토글만 켜야 할 때 짧게.
    static func residualGuidance(korean: Bool, appName: String) -> String {
        if korean {
            return "재서명·재설치 후 같은 이름 목록 줄은 옛 앱일 수 있어, 앱이 옛 항목을 지우고 이 빌드를 다시 등록합니다. 열린 설정에서 \(appName) 만 켜면 됩니다."
        }
        return "After re-sign/reinstall, same-name rows may be stale. The app clears them and re-registers this build — just enable \(appName) in the Settings pane that opens."
    }

    func strings(korean: Bool, appName: String) -> Copy {
        let open = korean ? "설정 열기" : "Open Settings"
        let close = korean ? "닫기" : "Close"
        let residual = Self.residualGuidance(korean: korean, appName: appName)
        switch self {
        case .screenRecording:
            return Copy(
                title: korean ? "화면 기록 권한이 필요합니다" : "Screen Recording permission required",
                body: korean
                    ? "\(appName)이(가) 화면을 캡처하려면 권한이 필요합니다.\n\n\(residual)"
                    : "\(appName) needs Screen Recording to capture the screen.\n\n\(residual)",
                openSettings: open, close: close)
        case .accessibility:
            return Copy(
                title: korean ? "손쉬운 사용 권한이 필요합니다" : "Accessibility permission required",
                body: korean
                    ? "\(appName)이(가) 키 입력을 관찰하려면 권한이 필요합니다.\n\n\(residual)"
                    : "\(appName) needs Accessibility to observe input.\n\n\(residual)",
                openSettings: open, close: close)
        case .camera:
            return Copy(
                title: korean ? "카메라 권한이 필요합니다" : "Camera permission required",
                body: korean
                    ? "\(appName)이(가) 카메라를 사용하려면 권한이 필요합니다.\n\n\(residual)"
                    : "\(appName) needs the camera.\n\n\(residual)",
                openSettings: open, close: close)
        case .microphone:
            return Copy(
                title: korean ? "마이크 권한이 필요합니다" : "Microphone permission required",
                body: korean
                    ? "\(appName)이(가) 마이크를 사용하려면 권한이 필요합니다.\n\n\(residual)"
                    : "\(appName) needs the microphone.\n\n\(residual)",
                openSettings: open, close: close)
        case .inputMonitoring:
            return Copy(
                title: korean ? "입력 모니터링 권한이 필요합니다" : "Input Monitoring permission required",
                body: korean
                    ? "\(appName)이(가) 키 입력을 가로채려면 입력 모니터링 권한이 필요합니다.\n\n\(residual)"
                    : "\(appName) needs Input Monitoring to observe key events.\n\n\(residual)",
                openSettings: open, close: close)
        case .fullDiskAccess:
            return Copy(
                title: korean ? "전체 디스크 접근이 필요합니다" : "Full Disk Access required",
                body: korean
                    ? "\(appName)이(가) 다른 앱의 권한(TCC)을 읽으려면 전체 디스크 접근이 필요합니다.\n\n\(residual)\n목록에 없으면 + 로 추가한 뒤 스위치를 켜 주세요."
                    : "\(appName) needs Full Disk Access to read other apps' TCC grants.\n\n\(residual)\nIf missing from the list, add it with +, then turn the switch on.",
                openSettings: open, close: close)
        case .location:
            return Copy(
                title: korean ? "위치 접근이 필요합니다" : "Location permission required",
                body: korean
                    ? "\(appName)이(가) Wi-Fi 이름을 읽으려면 위치 접근이 필요합니다. macOS 는 Wi-Fi 이름을 위치 정보로 다룹니다. 좌표는 쓰지 않습니다.\n\n\(residual)"
                    : "\(appName) needs Location to read the Wi-Fi name. macOS treats SSID as location. Coordinates are not used.\n\n\(residual)",
                openSettings: open, close: close)
        }
    }
}

/// Apple Events "Automation" isn't preflightable (there is no
/// `CGPreflight…`-style API): denial only surfaces when a send fails with `-1743`.
/// This groups the detection + the Settings deep link + the standard message
/// so the automation apps stop hand-rolling each one.
public enum Automation {
    /// stderr contains "-1743" / "Not authorized to send Apple events" when the
    /// user denied Automation for the target app.
    public static func isDenied(stderr: String) -> Bool {
        let s = stderr.lowercased()
        return s.contains("-1743") || s.contains("not authorized")
    }

    /// Same denial via Apple Events error number.
    public static func isDenied(automationErrorNumber number: Int?) -> Bool {
        number == -1743
    }

    @MainActor public static func openSettings() {
        PrivacySettingsOpener.open(
            primaryURLString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    /// A localized "automation was denied, here's where to fix it" line for the
    /// apps that surface it in a status banner rather than a modal alert.
    public static func deniedMessage(appName: String, language: AppLanguage = .system) -> String {
        let korean: Bool = {
            switch language {
            case .korean:  return true
            case .english: return false
            case .system:  return Locale.current.language.languageCode?.identifier == "ko"
            }
        }()
        return korean
            ? "\(appName)의 터미널 자동화 권한이 거부되었습니다. 시스템 설정 › 개인정보 보호 및 보안 › 자동화에서 허용한 뒤 다시 시도하세요."
            : "\(appName) was denied Automation. Allow it under System Settings › Privacy & Security › Automation, then try again."
    }
}
