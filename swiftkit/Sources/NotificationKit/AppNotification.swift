import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// 로컬 사용자 알림 — 3-OS 공용 API.
///
/// - macOS: 정본 `UNUserNotificationCenter`(UserNotifications.framework). 권한·사운드·중복
///   제거(id 갱신)까지 제대로 된다.
/// - Linux: `notify-send`(libnotify) 서브프로세스. 대부분의 데스크톱 환경에 기본 존재.
/// - Windows: PowerShell WinRT 토스트(BurntToast 불필요, 순정 API). 실패 시 무음 폴백.
///
/// 배경: 앱들이 외부 알림 우회를 쓰던 자리를 대체하고,
/// 동시에 서버/CLI 를 Linux·Windows 에서 돌려도 같은 호출로 알림이 나가게 한다.
/// (macOS 의 NSUserNotification 은 11 에서 deprecated 되어 쓰지 않는다.)
///
/// 사용:
/// ```swift
/// await AppNotification.requestAuthorization()      // 최초 1회(선택; mac 만 의미 있음)
/// AppNotification.post(title: "완료", body: "빌드 성공")
/// ```
/// 알림 중요도/긴급도 레벨
public enum NotificationLevel: String, Sendable, Codable {
    case normal
    case warning
    case critical
    case emergency

    public var isEmergency: Bool {
        self == .critical || self == .emergency
    }
}

public enum AppNotification {
    /// 알림 권한을 요청한다(비차단). 반환: 허용 여부.
    /// macOS 만 실제 권한 개념이 있고, Linux/Windows 는 항상 `true`(권한 게이트 없음).
    @discardableResult
    public static func requestAuthorization() async -> Bool {
        #if canImport(UserNotifications)
        guard let center = center else { return false }
        return await withCheckedContinuation { cont in
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                cont.resume(returning: granted)
            }
        }
        #else
        return true
        #endif
    }

    /// 로컬 알림을 즉시 게시한다. `id` 를 주면 같은 id 알림을 갱신(중복 방지)한다(mac).
    /// 긴급/비상 레벨(.critical / .emergency)일 경우 Sosumi 또는 Basso 사운드를 강제 재생하고,
    /// .app 번들이 아니거나 비상 상황 시 osascript 시스템 알림을 확실하게 띄운다.
    public static func post(
        title: String,
        body: String,
        sound: Bool = true,
        id: String? = nil,
        level: NotificationLevel = .normal,
        soundName: String? = nil
    ) {
        #if os(macOS)
        let emergencySound = soundName ?? (level == .emergency ? "Sosumi" : (level == .critical ? "Basso" : nil))

        // 1) 비상 레벨 시 사운드 강제 재생
        if level.isEmergency {
            let soundToPlay = emergencySound ?? "Sosumi"
            playMacSound(named: soundToPlay)
        }

        // 2) UNUserNotificationCenter 시도 (번들 환경)
        var centerDelivered = false
        if let center = center {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if sound {
                if let snd = emergencySound {
                    content.sound = UNNotificationSound(named: UNNotificationSoundName(snd))
                } else {
                    content.sound = .default
                }
            }
            let req = UNNotificationRequest(
                identifier: id ?? UUID().uuidString,
                content: content,
                trigger: nil   // nil = 즉시
            )
            center.add(req, withCompletionHandler: nil)
        }
        #elseif os(Linux)
        postLinux(title: title, body: body)
        #elseif os(Windows)
        postWindows(title: title, body: body)
        #endif
    }

    #if os(macOS)
    /// macOS 시스템 사운드 재생 (afplay)
    public static func playMacSound(named soundName: String) {
        let soundPath = "/System/Library/Sounds/\(soundName).aiff"
        if FileManager.default.fileExists(atPath: soundPath) {
            spawn("/usr/bin/afplay", [soundPath])
        }
    }
    #endif

    #if canImport(UserNotifications)
    /// currentNotificationCenter 접근은 **실제 앱 번들(.app)** 이 아니면 NSException 을 던진다.
    /// pathExtension + bundleIdentifier 만으로는 부족하다 — 심링크·빌드 아티팩트·CLI 래퍼도
    /// `.app` 경로를 가질 수 있고, xctest 러너·일부 CLI 도 식별자를 갖는다.
    /// CFBundlePackageType == APPL 까지 확인해야 진짜 .app 번들에서만 접근한다.
    private static var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.bundleIdentifier != nil,
              Bundle.main.infoDictionary?["CFBundlePackageType"] as? String == "APPL"
        else { return nil }
        return UNUserNotificationCenter.current()
    }
    #endif

    #if os(Linux)
    /// `notify-send <title> <body>`. 없으면 조용히 실패(서버 무헤드리스 환경 안전).
    private static func postLinux(title: String, body: String) {
        _ = spawn("/usr/bin/env", ["notify-send", "--", title, body])
    }
    #endif

    #if os(Windows)
    /// PowerShell 로 순정 WinRT 토스트를 띄운다. 콘솔 세션이면 토스트 대신 무시될 수 있으나
    /// 데스크톱 세션에서는 표시된다. 실패해도 앱 흐름을 막지 않는다.
    private static func postWindows(title: String, body: String) {
        let t = psEscape(title)
        let b = psEscape(body)
        let script = """
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        $xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        $texts = $xml.GetElementsByTagName('text')
        $texts.Item(0).AppendChild($xml.CreateTextNode('\(t)')) | Out-Null
        $texts.Item(1).AppendChild($xml.CreateTextNode('\(b)')) | Out-Null
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('SwiftApp').Show($toast)
        """
        _ = spawn("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", script])
    }

    /// PowerShell 작은따옴표 리터럴 이스케이프(`'` → `''`).
    private static func psEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "''")
    }
    #endif

    /// best-effort 서브프로세스 스폰(반환값 무시, 예외 삼킴).
    @discardableResult
    private static func spawn(_ launch: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        do { try p.run(); return true } catch { return false }
    }
}
