// PermissionCore — **AppKit 없는** 권한 게이트 코어.
//
// 왜 갈랐나: CLI 가 확장 승인 상태를 알아야 해서 PermissionKit 을 가져왔더니, AppKit 이
// 딸려 들어와 **CLI 프로세스가 종료되지 않았다**(실측 2026-08-11: `facts --json` 이 main
// runloop 에서 대기). 이 함대에 이미 기록된 dual-entry hang 과 같은 함정이다.
// 판정·파싱은 여기(코어), 화면을 여는 동작은 PermissionKit 에 둔다.

import CommandKit
import Foundation
import LocalizationKit

/// A macOS System Extension gate, in the same spirit as `Permission` — but a
/// system extension's grant is a *user-only* action (Login Items & Extensions +
/// admin auth) that no API can perform, so this type provides status + the right
/// Settings deep link + standard bilingual copy, and a reusable onboarding view
/// (`SystemExtensionOnboardingView`). Any app that ships a `.systemextension`
/// adopts the same first-run flow instead of hand-rolling it.
public struct SystemExtension: Sendable, Equatable {
    public let bundleID: String
    public let displayName: String
    public init(bundleID: String, displayName: String) {
        self.bundleID = bundleID
        self.displayName = displayName
    }

    public enum ApprovalState: Sendable, Equatable {
        /// 아직 `systemextensionsctl` 을 안 읽음. 미설치와 같지 않다 —
        /// 기본값을 `.notInstalled` 로 두면 기동마다 권한 창이 툭 뜬다.
        case unprobed
        case notInstalled        // 목록에 없음(미요청/제거)
        case waitingForApproval  // [activated waiting for user]
        case enabled             // [activated enabled] — 사용 준비 완료
        case other(String)

        public var isReady: Bool { self == .enabled }
        public var isProbed: Bool { self != .unprobed }
        public var showsOnboarding: Bool {
            switch self {
            case .unprobed, .enabled: return false
            case .notInstalled, .waitingForApproval, .other: return true
            }
        }
    }

    /// `systemextensionsctl list`(비권한) 출력을 파싱해 이 확장의 승인 상태를 낸다.
    public func status(runner: (String, [String]) -> String = SystemExtension.shell) -> ApprovalState {
        let out = runner("/usr/bin/systemextensionsctl", ["list"])
        let lines = out.split(whereSeparator: { $0 == "\n" }).filter { $0.contains(bundleID) }
        guard !lines.isEmpty else { return .notInstalled }

        // 한 확장에 **여러 줄**이 남는다. 새 빌드로 교체할 때마다 옛 항목이
        // `[terminated waiting to uninstall on reboot]` 로 쌓이기 때문이다.
        // 첫 줄만 보면 그 옛 줄을 읽고 "승인 필요" 로 오판한다 — 확장이 enabled 이고 VPN 이
        // 붙어 있는데도 온보딩 화면이 떴다(실측 2026-08-10). 우선순위로 판정한다.
        if lines.contains(where: { $0.lowercased().contains("activated enabled") }) { return .enabled }
        if lines.contains(where: { $0.lowercased().contains("waiting for user") }) { return .waitingForApproval }
        // 살아 있는 항목이 없으면(전부 terminated/uninstall 대기) 재활성화가 필요하다 = 미설치와 같다.
        if lines.allSatisfy({ $0.lowercased().contains("terminated") }) { return .notInstalled }
        if let line = lines.first, let o = line.lastIndex(of: "["), let c = line.lastIndex(of: "]"), o < c {
            return .other(String(line[line.index(after: o)..<c]))
        }
        return .other("unknown")
    }

    /// 앱 번들이 들고 있는 확장 버전과 **지금 활성인** 버전이 다르면, 새 빌드는 아직 안 돈다.
    /// macOS 는 옛 provider 프로세스가 살아 있는 동안 교체를 미루고 재부팅 때 정리한다.
    /// 이 상태를 알려주지 않으면 "고쳤는데 그대로" 를 겪는다(실측 2026-08-10).
    public struct VersionState: Sendable, Equatable {
        public let bundled: String?
        public let activated: String?
        public init(bundled: String?, activated: String?) {
            self.bundled = bundled
            self.activated = activated
        }
        /// 번들 버전과 활성 버전이 다르다 = 새 확장이 아직 적용되지 않았다.
        public var replacementPending: Bool {
            guard let bundled, let activated else { return false }
            return bundled != activated
        }
    }

    /// 번들 안 확장의 `CFBundleVersion`.
    public func bundledVersion(appBundlePath: String = Bundle.main.bundlePath,
                               read: (String) -> Data? = { FileManager.default.contents(atPath: $0) })
        -> String? {
        let plist = (appBundlePath as NSString)
            .appendingPathComponent("Contents/Library/SystemExtensions/\(bundleID).systemextension")
            + "/Contents/Info.plist"
        guard let data = read(plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any] else { return nil }
        return info["CFBundleVersion"] as? String
    }

    /// `systemextensionsctl list` 관측 결과 — 버전을 읽었는가, 애초에 없는가, 줄은 있는데
    /// 못 읽었는가. `unreadable` 은 출력 포맷 변화를 뜻한다: 이때 `activatedVersion` 이
    /// 조용히 nil 을 돌려 "최신"으로 위장하면 교체 감지가 죽는다(2026-08-25 실측 — 호출측은
    /// 이 값을 보고 보수적으로 행동해야 한다).
    public enum ActivatedProbe: Sendable, Equatable {
        case version(String)
        case absent
        case unreadable
    }

    /// `systemextensionsctl list` 에서 **enabled 로 표시된** 줄의 빌드 버전을 관측한다.
    /// 정규 포맷 `(0.1.0/1786369741)` 의 괄호를 먼저 보고, 괄호가 사라진 포맷 변화에도
    /// `/빌드` 토큰 폴백으로 버전을 살린다. 둘 다 실패하면 `.unreadable`.
    public func activatedProbe(runner: (String, [String]) -> String = SystemExtension.shell) -> ActivatedProbe {
        let out = runner("/usr/bin/systemextensionsctl", ["list"])
        for line in out.split(whereSeparator: { $0 == "\n" })
        where line.contains(bundleID) && line.lowercased().contains("activated enabled") {
            if let open = line.firstIndex(of: "("),
               let close = line[line.index(after: open)...].firstIndex(of: ")") {
                let inner = line[line.index(after: open)..<close]   // "0.1.0/1786369741"
                if let slash = inner.lastIndex(of: "/"), slash < inner.index(before: inner.endIndex) {
                    return .version(String(inner[inner.index(after: slash)...]))
                }
            }
            for token in line.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
                if let slash = token.lastIndex(of: "/"), slash < token.index(before: token.endIndex),
                   token[token.index(after: slash)...].allSatisfy({ $0.isNumber }) {
                    return .version(String(token[token.index(after: slash)...]))
                }
            }
            return .unreadable
        }
        return .absent
    }

    /// `systemextensionsctl list` 에서 **enabled 로 표시된** 줄의 빌드 버전.
    public func activatedVersion(runner: (String, [String]) -> String = SystemExtension.shell) -> String? {
        switch activatedProbe(runner: runner) {
        case .version(let v): return v
        case .absent, .unreadable: return nil
        }
    }

    public func versionState(appBundlePath: String = Bundle.main.bundlePath,
                             runner: (String, [String]) -> String = SystemExtension.shell) -> VersionState {
        VersionState(bundled: bundledVersion(appBundlePath: appBundlePath),
                     activated: activatedVersion(runner: runner))
    }

    /// 승인 화면 딥링크 후보. **앞이 더 깊다** — 네트워크 확장 목록까지 바로 가고,
    /// 안 열리면 한 단계씩 얕은 화면으로 물러난다.
    ///
    /// 왜 후보 목록인가: `com.apple.LoginItems-Settings.extension` 만 열면 "로그인 항목 및
    /// 확장 프로그램" 최상단에 떨어져서, 사용자가 **네트워크 확장 항목을 스스로 찾아
    /// 들어가야** 한다(백로그 800CD2C1: "한 단 부족"). 반대로 깊은 딥링크는 macOS 버전에
    /// 따라 무시되므로 하나만 쓰면 아무 화면도 안 뜨는 회귀가 난다. 그래서 순서대로 시도한다.
    ///
    /// 앵커 문자열의 정본은 `LoginItemsSettings` 다 — 같은 화면을 가리키는 두 목록이
    /// 각자 문자열을 들고 있으면 macOS 가 앵커를 바꾸는 날 한쪽만 고쳐진다.
    /// 여기서는 그 정본에 네트워크 확장 필터만 얹는다.
    public static let settingsURLCandidates: [String] = [
        LoginItemsSettings.settingsURLString + networkExtensionFilter,
        "x-apple.systempreferences:com.apple.ExtensionsPreferences" + networkExtensionFilter,
        LoginItemsSettings.settingsURLString,
        "x-apple.systempreferences:com.apple.preference.security",
    ]

    /// "네트워크 확장" 항목까지 한 단 더 들어가는 질의. macOS 버전에 따라 무시된다.
    static let networkExtensionFilter =
        "?extensionPointIdentifier=com.apple.system_extension.network_extension"

    /// 딥링크가 통째로 실패했을 때 사람이 손으로 갈 경로.
    public func manualNavigationHint(language: AppLanguage = .system) -> String {
        Self.isKorean(language)
            ? "설정이 자동으로 열리지 않았습니다 — 시스템 설정 › 일반 › 로그인 항목 및 확장 프로그램 › 네트워크 확장에서 \(displayName)을(를) 켜세요."
            : "Settings did not open automatically — go to System Settings › General › Login Items & Extensions › Network Extensions and enable \(displayName)."
    }

    // MARK: 표준 안내 문구(한 곳에서 바꾸면 모든 앱 반영)

    public struct Copy: Sendable {
        public let title, body, oneTime, openButton: String
        /// "여기 눌러 → 이거 켜기 → Touch ID" 3단계. 배너 한 줄로는 사용자가 어디서
        /// 무엇을 켜야 하는지 모른다 — vpn-wireguard 가 자기 화면에 따로 갖고 있던 안내를
        /// 공용으로 올린 것(백로그 45873825: 같은 안내가 앱 안에 3벌 있었다).
        public let steps: [String]
        /// 시트에서 실제로 보게 될 행의 라벨(토글 미리보기용) — 앱이 문구를 하드코딩하지 않게.
        public let mockRowLabel: String
    }

    public func copy(language: AppLanguage = .system) -> Copy {
        let korean = Self.isKorean(language)
        return korean
            ? Copy(title: "시스템 확장 승인이 필요합니다",
                   body: "\(displayName)이(가) 동작하려면 시스템 확장을 한 번 승인해야 합니다. 시스템 설정 › 일반 › 로그인 항목 및 확장 프로그램 › 네트워크 확장에서 \(displayName)을(를) 켜고 관리자 인증(Touch ID)을 하세요.",
                   oneTime: "승인은 최초 1회뿐입니다. 이후엔 앱이 자동으로 동작합니다.",
                   openButton: "확장 승인하기 (설정 열기)",
                   steps: [
                       "아래 버튼으로 시스템 설정을 엽니다",
                       "‘네트워크 확장’ 목록에서 \(displayName) 을(를) 켭니다",
                       "Touch ID(또는 암호)로 승인하면 끝입니다",
                   ],
                   mockRowLabel: displayName)
            : Copy(title: "System extension approval required",
                   body: "\(displayName) needs a one-time system extension approval. Turn it on under System Settings › General › Login Items & Extensions › Network Extensions and authenticate (Touch ID).",
                   oneTime: "You only approve once — after that the app works automatically.",
                   openButton: "Approve extension (Open Settings)",
                   steps: [
                       "Open System Settings with the button below",
                       "Turn on \(displayName) under ‘Network Extensions’",
                       "Authenticate with Touch ID (or your password)",
                   ],
                   mockRowLabel: displayName)
    }

    /// 화면 쪽(PermissionKit)도 같은 판정을 써야 하므로 공개한다 — 모듈이 갈렸다.
    public static func isKorean(_ language: AppLanguage) -> Bool {
        switch language {
        case .korean: return true
        case .english: return false
        case .system: return Locale.current.language.languageCode?.identifier == "ko"
        }
    }

    /// 실행은 `CommandKitSync` 에 맡긴다 — 여기서 Process 를 직접 굴리지 않는다.
    ///
    /// 옛 구현은 stdout 만 `readDataToEndOfFile()` 로 빨고 stderr 파이프는 만들어만 두고
    /// **드레인하지 않았다.** 자식이 stderr 로 64KB(파이프 버퍼)를 넘기면 그 write 에서
    /// 영원히 막히고, 30초 뒤 `terminate()` 가 출력을 잘라낸다 — `systemextensionsctl`
    /// 이 조용한 날에는 안 터지고 시끄러운 날에만 터져서, 확장이 `enabled` 인데
    /// `.notInstalled` 로 읽히는 재현 어려운 회귀가 된다.
    /// `CommandKitSync.run` 은 두 파이프를 각자 드레인하고 EOF 를 기다린다.
    public static let shell: @Sendable (String, [String]) -> String = { path, args in
        CommandKitSync.run(path, args, timeout: 30).stdout
    }
}
