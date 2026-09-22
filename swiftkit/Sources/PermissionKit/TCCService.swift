import Foundation

/// macOS 개인정보 TCC 서비스 카탈로그 — **PermissionKit + mac-permissions-manager 공용 SSOT**.
///
/// - `tccDatabaseKey`: TCC.db `service` 컬럼 (`kTCCService…`)
/// - `tccutilName`: `/usr/bin/tccutil reset <name> [bundle]`
/// - `settingsURLString`: 시스템 설정 딥링크
///
/// 런타임 게이트(`Permission.screenRecording` 등)는 이 목록의 일부만 커버한다.
/// 매니저 UI·스캔은 전체 카탈로그를 쓴다.
public enum TCCService: String, Sendable, CaseIterable, Codable, Hashable {
    case screenRecording
    case accessibility
    case fullDiskAccess
    case camera
    case microphone
    case automation      // AppleEvents
    case inputMonitoring
    case contacts
    case calendars
    case reminders
    case photos
    case postEvent           // 키 입력·클릭 주입(손쉬운 사용과 별개 서비스)
    case desktopFolder
    case documentsFolder
    case downloadsFolder
    case location

    public init?(tccDatabaseKey: String) {
        guard let match = Self.allCases.first(where: { $0.tccDatabaseKey == tccDatabaseKey }) else {
            return nil
        }
        self = match
    }

    /// 예전 mac-permissions-manager `PermissionService(tccKey:)` 호환.
    public init?(tccKey: String) {
        self.init(tccDatabaseKey: tccKey)
    }

    /// TCC.db `service` 컬럼 값.
    public var tccDatabaseKey: String {
        switch self {
        case .screenRecording: return "kTCCServiceScreenCapture"
        case .accessibility: return "kTCCServiceAccessibility"
        case .fullDiskAccess: return "kTCCServiceSystemPolicyAllFiles"
        case .camera: return "kTCCServiceCamera"
        case .microphone: return "kTCCServiceMicrophone"
        case .automation: return "kTCCServiceAppleEvents"
        case .inputMonitoring: return "kTCCServiceListenEvent"
        case .contacts: return "kTCCServiceAddressBook"
        case .calendars: return "kTCCServiceCalendar"
        case .reminders: return "kTCCServiceReminders"
        case .photos: return "kTCCServicePhotos"
        case .postEvent: return "kTCCServicePostEvent"
        case .desktopFolder: return "kTCCServiceSystemPolicyDesktopFolder"
        case .documentsFolder: return "kTCCServiceSystemPolicyDocumentsFolder"
        case .downloadsFolder: return "kTCCServiceSystemPolicyDownloadsFolder"
        case .location: return "kTCCServiceLocation"
        }
    }

    /// `/usr/bin/tccutil` service 이름(DB 키와 다를 수 있음).
    public var tccutilName: String {
        switch self {
        case .screenRecording: return "ScreenCapture"
        case .accessibility: return "Accessibility"
        case .fullDiskAccess: return "SystemPolicyAllFiles"
        case .camera: return "Camera"
        case .microphone: return "Microphone"
        case .automation: return "AppleEvents"
        case .inputMonitoring: return "ListenEvent"
        case .contacts: return "AddressBook"
        case .calendars: return "Calendar"
        case .reminders: return "Reminders"
        case .photos: return "Photos"
        case .postEvent: return "PostEvent"
        case .desktopFolder: return "SystemPolicyDesktopFolder"
        case .documentsFolder: return "SystemPolicyDocumentsFolder"
        case .downloadsFolder: return "SystemPolicyDownloadsFolder"
        case .location: return "Location"
        }
    }

    /// 한국어 짧은 라벨(매니저 UI·CLI).
    public var labelKorean: String {
        switch self {
        case .screenRecording: return "화면 기록"
        case .accessibility: return "손쉬운 사용"
        case .fullDiskAccess: return "전체 디스크 접근"
        case .camera: return "카메라"
        case .microphone: return "마이크"
        case .automation: return "자동화(AppleEvents)"
        case .inputMonitoring: return "입력 모니터링"
        case .contacts: return "연락처"
        case .calendars: return "캘린더"
        case .reminders: return "미리 알림"
        case .photos: return "사진"
        case .postEvent: return "입력 이벤트 주입"
        case .desktopFolder: return "데스크탑 폴더"
        case .documentsFolder: return "문서 폴더"
        case .downloadsFolder: return "다운로드 폴더"
        case .location: return "위치"
        }
    }

    public var labelEnglish: String {
        switch self {
        case .screenRecording: return "Screen Recording"
        case .accessibility: return "Accessibility"
        case .fullDiskAccess: return "Full Disk Access"
        case .camera: return "Camera"
        case .microphone: return "Microphone"
        case .automation: return "Automation"
        case .inputMonitoring: return "Input Monitoring"
        case .contacts: return "Contacts"
        case .calendars: return "Calendars"
        case .reminders: return "Reminders"
        case .photos: return "Photos"
        case .postEvent: return "Post Event"
        case .desktopFolder: return "Desktop Folder"
        case .documentsFolder: return "Documents Folder"
        case .downloadsFolder: return "Downloads Folder"
        case .location: return "Location"
        }
    }

    /// 시스템 TCC.db(root)에 사는 서비스 — 읽기 가능성 판단용.
    public var isSystemScoped: Bool {
        switch self {
        // 2026-08-01 이 맥 실측: 시스템 db 에 Accessibility·ListenEvent·PostEvent·
        // ScreenCapture·SystemPolicyAllFiles 만 존재했다. 나머지는 user db 다.
        case .screenRecording, .accessibility, .fullDiskAccess, .inputMonitoring, .postEvent:
            return true
        default:
            return false
        }
    }

    /// 시스템 설정 개인정보 보호 딥링크.
    public var settingsURLString: String {
        let anchor: String
        switch self {
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        case .accessibility: anchor = "Privacy_Accessibility"
        case .fullDiskAccess: anchor = "Privacy_AllFiles"
        case .camera: anchor = "Privacy_Camera"
        case .microphone: anchor = "Privacy_Microphone"
        case .automation: anchor = "Privacy_Automation"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        case .contacts: anchor = "Privacy_Contacts"
        case .calendars: anchor = "Privacy_Calendars"
        case .reminders: anchor = "Privacy_Reminders"
        case .photos: anchor = "Privacy_Photos"
        case .postEvent: anchor = "Privacy_Accessibility"
        case .desktopFolder, .documentsFolder, .downloadsFolder:
            anchor = "Privacy_FilesAndFolders"
        case .location: anchor = "Privacy_LocationServices"
        }
        return "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
    }

    /// 앱 프로세스 안에서 `Permission.repair` 로 live 재등록까지 가능한가.
    public var supportsLiveRepair: Bool {
        switch self {
        case .screenRecording, .accessibility, .camera:
            return true
        default:
            return false
        }
    }

    /// 런타임 게이트 enum 으로 연결(가능하면).
    public var runtimePermission: Permission? {
        switch self {
        case .screenRecording: return .screenRecording
        case .accessibility: return .accessibility
        case .camera: return .camera
        case .microphone: return .microphone
        case .inputMonitoring: return .inputMonitoring
        case .fullDiskAccess: return .fullDiskAccess
        case .location: return .location
        default: return nil
        }
    }

    /// 시스템 설정 해당 패널 열기 — 앵커 하드코딩 대신 이 API 를 쓴다.
    @MainActor
    public func openSettings() {
        PrivacySettingsOpener.open(primaryURLString: settingsURLString)
    }
}

extension Permission {
    /// 이 런타임 게이트가 대응하는 TCC 카탈로그 항목.
    public var tccService: TCCService {
        switch self {
        case .screenRecording: return .screenRecording
        case .accessibility: return .accessibility
        case .camera: return .camera
        case .microphone: return .microphone
        case .inputMonitoring: return .inputMonitoring
        case .fullDiskAccess: return .fullDiskAccess
        case .location: return .location
        }
    }
}
