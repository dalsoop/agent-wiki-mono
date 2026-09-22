import AppKit
import Foundation

/// 시스템 설정(개인정보 보호) 딥링크 오픈 SSOT.
///
/// `NSWorkspace.shared.open` 만 쓰면 이미 System Settings 가 떠 있거나 포커스
/// 경쟁이 있을 때 앵커 이동이 안 되거나 조용히 실패하는 경우가 있다.
/// `/usr/bin/open` 폴백 + System Settings 활성화로 “버튼 눌렀는데 설정이 안 뜸”
/// 을 줄인다.
///
/// 앱은 앵커 문자열을 하드코딩하지 말고 `TCCService.settingsURLString` /
/// `FullDiskAccess.settingsURLString` 을 넘긴다.
public enum PrivacySettingsOpener {
    /// - Parameter primaryURLString: 예 `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`
    @MainActor
    public static func open(primaryURLString: String) {
        let candidates = urlCandidates(from: primaryURLString)
        var opened = false
        for raw in candidates {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) {
                opened = true
                break
            }
        }
        if !opened, let first = candidates.first {
            openViaCLI(first)
            opened = true
        }
        // 이미 떠 있어도 앞으로 가져온다. 딥링크만으로는 포커스가 안 오는 경우 대비.
        activateSystemSettings()
        // CLI 폴백을 한 번 더 — NSWorkspace 가 true 를 줘도 앵커가 무시되는 경우.
        if let first = candidates.first {
            openViaCLI(first)
        }
        _ = opened
    }

    /// classic `preference.security` ↔ modern `settings.PrivacySecurity.extension` 교차 후보.
    /// 테스트·진단에서 후보 목록을 읽을 수 있게 public.
    public static func urlCandidates(from primary: String) -> [String] {
        var out: [String] = [primary]
        let classic = "com.apple.preference.security"
        let modern = "com.apple.settings.PrivacySecurity.extension"
        if primary.contains(classic) {
            out.append(primary.replacingOccurrences(of: classic, with: modern))
        } else if primary.contains(modern) {
            out.append(primary.replacingOccurrences(of: modern, with: classic))
        }
        // 중복 제거, 순서 유지
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    private static func openViaCLI(_ urlString: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [urlString]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    @MainActor
    private static func activateSystemSettings() {
        let ids = ["com.apple.systempreferences", "com.apple.Settings"]
        for bid in ids {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
            if let app = apps.first {
                // macOS 14+: activate() without deprecated IgnoringOtherApps flag.
                app.activate()
                return
            }
        }
        // 아직 안 떠 있으면 앱 자체로 한 번 연다(딥링크가 곧 이을 수 있음).
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
    }
}
