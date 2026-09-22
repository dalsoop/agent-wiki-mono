import AppKit
import LocalizationKit
import SwiftUI

/// Screenshot 급 **파악→처리** 권한 UI — 모든 채택 앱이 같은 패턴으로 쓴다.
///
/// - 미허용이면 자동으로 `Permission.repair` (tccutil 옛 항목 정리 → 재등록 → 설정 오픈)
/// - 사용자에게 단계 안내 대신 **처리 상태** 와 토글 대기만 표시
/// - 허용되면 본문은 숨기고 선택적으로 작은 배지만
public struct PermissionRepairPanel: View {
    public let permission: Permission
    public let appName: String
    public var language: AppLanguage
    /// 나타날 때 자동 repair (세션당 1회).
    public var autoRepairOnAppear: Bool
    /// 허용된 뒤에도 초록 배지 유지.
    public var showGrantedBadge: Bool

    @State private var granted: Bool?
    @State private var repairing = false
    @State private var detail: String?
    @State private var didAuto = false

    public init(
        permission: Permission,
        appName: String,
        language: AppLanguage = .system,
        autoRepairOnAppear: Bool = false,
        showGrantedBadge: Bool = false
    ) {
        self.permission = permission
        self.appName = appName
        self.language = language
        self.autoRepairOnAppear = autoRepairOnAppear
        self.showGrantedBadge = showGrantedBadge
    }

    private var korean: Bool {
        switch language {
        case .korean: return true
        case .english: return false
        case .system: return Locale.current.language.languageCode?.identifier == "ko"
        }
    }

    private var title: String {
        switch permission {
        case .screenRecording: return korean ? "화면 기록을 연결하는 중" : "Connecting Screen Recording"
        case .accessibility: return korean ? "손쉬운 사용을 연결하는 중" : "Connecting Accessibility"
        case .camera: return korean ? "카메라를 연결하는 중" : "Connecting Camera"
        case .microphone: return korean ? "마이크를 연결하는 중" : "Connecting Microphone"
        case .inputMonitoring: return korean ? "입력 모니터링을 연결하는 중" : "Connecting Input Monitoring"
        case .fullDiskAccess: return korean ? "전체 디스크 접근을 연결하는 중" : "Connecting Full Disk Access"
        case .location: return korean ? "위치 접근을 연결하는 중" : "Connecting Location"
        }
    }

    private var bodyHint: String {
        korean
            ? "이 빌드에 \(permission.tccService.labelKorean) 권한이 없습니다. 옛 설치·다른 서명 항목이 있으면 앱이 지우고 다시 등록합니다."
            : "This build lacks \(permission.tccService.labelEnglish). Stale same-name rows are cleared and this build is re-registered."
    }

    private var waitingToggle: String {
        korean
            ? "설정 창에서 \(appName) 스위치만 켜 주세요. 켜면 이 안내가 사라집니다."
            : "Turn on only \(appName) in Settings. This panel disappears when granted."
    }

    private var fixLabel: String { korean ? "권한 다시 고치기" : "Fix permission again" }
    private var openLabel: String { korean ? "설정 다시 열기" : "Open Settings again" }
    private var recheckLabel: String { korean ? "다시 확인" : "Check again" }
    private var statusLabel: String { korean ? "처리 상태" : "Status" }
    private var repairingLabel: String {
        korean ? "옛 권한 정리 · 이 빌드 재등록 중…" : "Clearing stale permission · re-registering…"
    }
    private var grantedLabel: String {
        korean
            ? "\(permission.tccService.labelKorean) 허용됨"
            : "\(permission.tccService.labelEnglish) allowed"
    }

    public var body: some View {
        Group {
            if granted == true {
                if showGrantedBadge {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill").font(.caption2)
                        Text(grantedLabel).font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
                }
            } else {
                callout
            }
        }
        .task {
            refresh()
            if autoRepairOnAppear, granted != true {
                await runRepair(auto: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private var callout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.14))
                        .frame(width: 40, height: 40)
                    if repairing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: iconName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(bodyHint)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(statusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(detail ?? repairingLabel)
                    .font(.caption)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !repairing, granted != true {
                    Text(waitingToggle)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.orange.opacity(0.08))
            )

            HStack(spacing: 8) {
                Button {
                    // 즉시 설정 화면 — 사용자는 “고치기 = 설정 열기” 로 이해한다.
                    // repair 의 tccutil/request 는 그 다음(비차단).
                    permission.openSettings()
                    Task { await runRepair(auto: false) }
                } label: {
                    Text(fixLabel).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(repairing)
                .accessibilityIdentifier("permission-repair-fix")

                Button {
                    permission.openSettings()
                } label: {
                    Text(openLabel)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(repairing)
                .accessibilityIdentifier("permission-repair-open-settings")

                Button {
                    refresh()
                } label: {
                    Text(recheckLabel)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(repairing)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.28), lineWidth: 1)
        )
    }

    private var iconName: String {
        switch permission {
        case .screenRecording: return "rectangle.dashed.badge.record"
        case .accessibility: return "accessibility"
        case .camera: return "camera"
        case .microphone: return "mic"
        case .inputMonitoring: return "keyboard"
        case .fullDiskAccess: return "externaldrive.badge.person.crop"
        case .location: return "location"
        }
    }

    private func refresh() {
        granted = permission.isGranted
    }

    private func runRepair(auto: Bool) async {
        if permission.isGranted {
            granted = true
            detail = nil
            return
        }
        if repairing { return }
        if auto, didAuto { return }
        if auto { didAuto = true }
        // 자동/수동 모두: 정리 전에 설정 패널을 먼저 연다(토글 대기 UX).
        permission.openSettings()
        repairing = true
        detail = repairingLabel
        let report = await permission.repair(appName: appName, language: language)
        detail = report.detail
        repairing = false
        refresh()
    }
}

/// 여러 권한을 세로로 쌓는다. 미허용만 패널, 전부 허용이면 빈 뷰(또는 배지).
public struct PermissionRepairStack: View {
    public let permissions: [Permission]
    public let appName: String
    public var language: AppLanguage
    public var autoRepairOnAppear: Bool

    public init(
        permissions: [Permission],
        appName: String,
        language: AppLanguage = .system,
        autoRepairOnAppear: Bool = false
    ) {
        self.permissions = permissions
        self.appName = appName
        self.language = language
        self.autoRepairOnAppear = autoRepairOnAppear
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(permissions, id: \.self) { p in
                if !p.isGranted {
                    PermissionRepairPanel(
                        permission: p,
                        appName: appName,
                        language: language,
                        autoRepairOnAppear: autoRepairOnAppear
                    )
                }
            }
        }
    }
}

