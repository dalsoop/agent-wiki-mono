import PermissionKit
import AppKit
import Foundation
import LocalizationKit
import SwiftUI

/// macOS 의 "파일 및 폴더 / 문서 폴더" TCC 게이트. 앱이 사용자 폴더(예: ~/Documents 하위
/// 워크스페이스)를 읽으면 시스템이 자동으로 프롬프트를 띄우고, 거부/재서명 후에는
/// 접근이 막힌다. 이건 `CGPreflight…` 같은 동기 프리플라이트 API 가 없어서 **실제 읽기를
/// 시도해** 판정한다. `Permission`(화면·손쉬운사용·카메라)과 달리 폴더 단위라 별도 타입.
///
/// 재사용 원칙은 `Permission` 과 같다 — 딥링크·문구를 여기 한곳에 두고, 채택 앱은
/// `FolderAccessOnboardingView` 를 게이트로 얹기만 한다.
public enum FolderAccess: Sendable {
    /// 이 경로를 실제로 나열할 수 있나(디렉터리 목록 시도). TCC 거부면 실패/빈 목록.
    public static func canAccess(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            // 경로가 아직 없으면 접근 문제로 단정하지 않는다(존재하지 않을 뿐).
            return true
        }
        // 존재하는 디렉터리인데 나열이 실패하면 TCC 로 막힌 것으로 본다.
        return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
    }

    /// 주어진 경로 중 하나라도 존재하는데 못 읽으면 막힌 상태(온보딩 필요).
    public static func isBlocked(anyOf paths: [String]) -> Bool {
        paths.contains { path in
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
            return exists && (try? FileManager.default.contentsOfDirectory(atPath: path)) == nil
        }
    }

    /// 시스템 설정 › 개인정보 보호 및 보안 › 파일 및 폴더.
    public static let settingsURLString = "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"

    @MainActor public static func openSettings() {
        PrivacySettingsOpener.open(primaryURLString: settingsURLString)
    }

    /// 폴더 접근을 **직접 부여**하는 가장 확실한 방법 — 사용자가 그 폴더를 고르면
    /// security-scoped 접근이 열려 TCC 프롬프트/설정 왕복을 건너뛴다. 고른 경로를 반환.
    @MainActor public static func grantByPicking(_ folder: String, prompt: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.directoryURL = URL(fileURLWithPath: folder)
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    static func isKorean(_ language: AppLanguage) -> Bool {
        switch language {
        case .korean:  return true
        case .english: return false
        case .system:  return Locale.current.language.languageCode?.identifier == "ko"
        }
    }
}

/// 첫 실행/거부 시 본 화면을 가리는 폴더 접근 온보딩. 설명 + 설정 열기 + 폴더 직접 선택 +
/// 다시 확인. 채택 앱: 접근이 막혔을 때 이 뷰를 오버레이하고, 부여되면 걷어낸다.
public struct FolderAccessOnboardingView: View {
    let appName: String
    let folder: String
    let language: AppLanguage
    var onRecheck: () -> Void
    var onPicked: ((String) -> Void)?

    public init(appName: String, folder: String, language: AppLanguage = .system,
                onPicked: ((String) -> Void)? = nil, onRecheck: @escaping () -> Void) {
        self.appName = appName; self.folder = folder; self.language = language
        self.onPicked = onPicked; self.onRecheck = onRecheck
    }

    private var korean: Bool { FolderAccess.isKorean(language) }

    public var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "folder.badge.person.crop")
                .font(.system(size: 44)).foregroundStyle(.orange)
            Text(korean ? "폴더 접근 권한이 필요합니다" : "Folder access required")
                .font(.title3).bold()
            Text(korean
                ? "\(appName)이(가) 워크스페이스 폴더를 읽어야 합니다. macOS 는 이 접근을 허용받은 앱에만 열어줍니다.\n\n대상: \(folder)"
                : "\(appName) needs to read your workspace folder. macOS only opens this to apps you've allowed.\n\nFolder: \(folder)")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)

            VStack(alignment: .leading, spacing: 8) {
                step(1, korean ? "‘폴더 선택해 허용’으로 워크스페이스 폴더를 고른다(가장 쉬움)" : "Pick the workspace folder via ‘Grant by choosing folder’ (easiest)")
                step(2, korean ? "또는 ‘시스템 설정 열기’ → 파일 및 폴더에서 \(appName) 을(를) 켠다" : "or ‘Open Settings’ → Files and Folders, enable \(appName)")
                step(3, korean ? "‘다시 확인’을 누른다" : "press ‘Re-check’")
            }.font(.callout)

            HStack(spacing: 10) {
                Button(korean ? "폴더 선택해 허용" : "Grant by choosing folder") {
                    if let picked = FolderAccess.grantByPicking(folder, prompt: korean ? "이 폴더 접근 허용" : "Allow access") {
                        onPicked?(picked); onRecheck()
                    }
                }.buttonStyle(.borderedProminent)
                Button(korean ? "시스템 설정 열기" : "Open Settings") { FolderAccess.openSettings() }
                Button(korean ? "다시 확인" : "Re-check", action: onRecheck)
            }
            Text(korean ? "설정에서 켠 경우 앱 재실행 후 반영되는 경우가 있습니다." : "If enabled in Settings, a relaunch may be needed.")
                .font(.caption2).foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").bold().frame(width: 18, height: 18)
                .background(Circle().fill(.orange.opacity(0.2)))
            Text(text)
        }
    }
}
