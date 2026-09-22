import PermissionKit
import LocalizationKit
import SwiftUI

/// Reusable Full Disk Access guidance. The adopting app owns status refresh and
/// completion state; PermissionKit owns the Settings link and bilingual copy.
public struct FullDiskAccessOnboardingView: View {
    private let appName: String
    private let isRequired: Bool
    private let status: FullDiskAccessStatus
    private let language: AppLanguage
    private let onLater: () -> Void
    private let onRecheck: () -> Void
    private let onComplete: () -> Void

    @State private var didDetectStatusChange = false

    public init(
        appName: String,
        isRequired: Bool,
        status: FullDiskAccessStatus,
        language: AppLanguage = .system,
        onLater: @escaping () -> Void,
        onRecheck: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.appName = appName
        self.isRequired = isRequired
        self.status = status
        self.language = language
        self.onLater = onLater
        self.onRecheck = onRecheck
        self.onComplete = onComplete
    }

    private var korean: Bool {
        switch language {
        case .korean: true
        case .english: false
        case .system: Locale.current.language.languageCode?.identifier == "ko"
        }
    }

    private var isLikelyGranted: Bool { status == .likelyGranted }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: isLikelyGranted ? "checkmark.shield.fill" : "externaldrive.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(isLikelyGranted ? .green : .orange)
                .symbolRenderingMode(.hierarchical)

            Text(korean ? "전체 디스크 접근" : "Full Disk Access")
                .font(.title2.bold())

            Text(requirementText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            statusRow

            HStack(spacing: 10) {
                Button(korean ? "시스템 설정 열기" : "Open System Settings") {
                    FullDiskAccess.openSettings()
                }
                .buttonStyle(.borderedProminent)

                Button(korean ? "다시 확인" : "Re-check", action: onRecheck)
                    .buttonStyle(.bordered)
            }

            if didDetectStatusChange {
                Button(korean ? "앱 다시 열기" : "Relaunch App") {
                    FullDiskAccess.relaunch()
                }
                .buttonStyle(.bordered)
            }

            if isLikelyGranted {
                Button(korean ? "완료" : "Complete", action: onComplete)
                    .buttonStyle(.borderedProminent)
            } else if !isRequired {
                Button(korean ? "나중에" : "Later", action: onLater)
                    .buttonStyle(.link)
            }

            Text(korean
                ? "macOS는 이 권한의 정확한 상태를 제공하지 않아, 보호 폴더 읽기 결과로 추정합니다."
                : "macOS does not expose the exact authorization state, so this status is inferred by reading a protected folder.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(width: 430)
        .onChange(of: status) { oldStatus, newStatus in
            if oldStatus != newStatus {
                didDetectStatusChange = true
            }
        }
    }

    private var requirementText: String {
        if korean {
            return isRequired
                ? "\(appName)의 핵심 기능을 사용하려면 전체 디스크 접근 권한이 필요합니다."
                : "\(appName)의 더 완전한 결과를 위해 전체 디스크 접근 권한을 선택적으로 허용할 수 있습니다."
        }
        return isRequired
            ? "\(appName) requires Full Disk Access for its core functionality."
            : "Full Disk Access is optional and lets \(appName) provide more complete results."
    }

    private var statusText: String {
        switch status {
        case .likelyGranted:
            korean ? "상태: 허용된 것으로 보임" : "Status: likely granted"
        case .likelyDenied:
            korean ? "상태: 차단된 것으로 보임" : "Status: likely denied"
        case .unknown:
            korean ? "상태: 확인할 수 없음" : "Status: unknown"
        }
    }

    private var statusColor: Color {
        switch status {
        case .likelyGranted: .green
        case .likelyDenied: .orange
        case .unknown: .secondary
        }
    }

    private var statusRow: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
