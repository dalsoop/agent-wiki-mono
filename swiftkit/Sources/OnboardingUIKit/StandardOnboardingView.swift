import OnboardingKit
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// 470개 앱 공용 표준 온보딩 화면.
///
/// 권한 요청 항목(Full Disk Access, Accessibility 등)과 앱 소개 카드, 체크리스트를
/// 선언형 DTO로 주입받아 단 한 줄로 렌더링한다:
///
/// ```swift
/// StandardOnboardingView(items: [
///     .defaults(done: defaultsApplied),
///     .required(done: requiredDone, onAction: onEnableRequired)
/// ], onComplete: onFinished)
/// ```
public struct StandardOnboardingView: View {
    public var title: String
    public var subtitle: String
    public var items: [OnboardingItem]
    public var features: [OnboardingFeature]
    public var note: String?
    public var skipTitle: String
    public var finishEnabledTitle: String
    public var finishDisabledTitle: String
    public var onSkip: (@MainActor @Sendable () -> Void)?
    public var onComplete: @MainActor @Sendable () -> Void

    public var containerAccessibilityID: String?
    public var skipAccessibilityID: String?
    public var finishAccessibilityID: String?

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        items: [OnboardingItem] = [],
        features: [OnboardingFeature] = [],
        note: String? = nil,
        skipTitle: String? = nil,
        finishEnabledTitle: String? = nil,
        finishDisabledTitle: String? = nil,
        containerAccessibilityID: String? = nil,
        skipAccessibilityID: String? = nil,
        finishAccessibilityID: String? = nil,
        onSkip: (@MainActor @Sendable () -> Void)? = nil,
        onComplete: @escaping @MainActor @Sendable () -> Void
    ) {
        let defaultTitle = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "App"

        self.title = title ?? defaultTitle
        self.subtitle = subtitle ?? OnboardingUIKitL10n.string("onboarding.subtitle.default")
        self.items = items
        self.features = features
        self.note = note
        self.skipTitle = skipTitle ?? OnboardingUIKitL10n.string("onboarding.button.skip")
        self.finishEnabledTitle = finishEnabledTitle ?? OnboardingUIKitL10n.string("onboarding.button.start")
        self.finishDisabledTitle = finishDisabledTitle ?? OnboardingUIKitL10n.string("onboarding.button.required_disabled")
        self.containerAccessibilityID = containerAccessibilityID
        self.skipAccessibilityID = skipAccessibilityID
        self.finishAccessibilityID = finishAccessibilityID
        self.onSkip = onSkip
        self.onComplete = onComplete
    }

    /// 단 한 줄 표준 초기화자
    public init(
        items: [OnboardingItem],
        onComplete: @escaping @MainActor @Sendable () -> Void
    ) {
        self.init(
            title: nil,
            subtitle: nil,
            items: items,
            features: [],
            note: nil,
            onSkip: nil,
            onComplete: onComplete
        )
    }

    /// 앱 소개 카드 전용 초기화자
    public init(
        title: String? = nil,
        subtitle: String? = nil,
        features: [OnboardingFeature],
        note: String? = nil,
        onComplete: @escaping @MainActor @Sendable () -> Void
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            items: [],
            features: features,
            note: note,
            onSkip: nil,
            onComplete: onComplete
        )
    }

    /// 필수 항목이 모두 완료되었는지 여부
    public var canFinish: Bool {
        items.filter { $0.required && !$0.done }.isEmpty
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection

            if !features.isEmpty {
                featuresSection
            }

            if !items.isEmpty {
                checklistSection
            }

            if let note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            footerSection
        }
        .padding(40)
        .frame(maxWidth: 580, alignment: .leading)
        .modifier(OptionalAccessibilityIdentifier(containerAccessibilityID))
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle.bold())
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(features) { feature in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: feature.symbol)
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(.headline)
                        Text(feature.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(items) { item in
                checklistRow(item)
            }
        }
    }

    private func checklistRow(_ item: OnboardingItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon(for: item)

            VStack(alignment: .leading, spacing: 2) {
                if let title = item.title, !title.isEmpty {
                    Text(title)
                        .font(.headline)
                }
                if let detail = item.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            rowAction(item)
        }
    }

    @ViewBuilder
    private func statusIcon(for item: OnboardingItem) -> some View {
        if item.done {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.green)
                .font(.title3)
        } else if item.required {
            Image(systemName: "circle")
                .foregroundStyle(Color.secondary)
                .font(.title3)
        } else {
            Image(systemName: "circle.dashed")
                .foregroundStyle(Color.secondary)
                .font(.title3)
        }
    }

    @ViewBuilder
    private func rowAction(_ item: OnboardingItem) -> some View {
        if !item.done {
            if let actionTitle = item.actionTitle, let action = item.action {
                Button(actionTitle) {
                    action()
                }
                .controlSize(.small)
            }
        } else {
            Text(OnboardingUIKitL10n.string("onboarding.status.granted"))
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    private var footerSection: some View {
        HStack {
            if let onSkip {
                Button(skipTitle, action: onSkip)
                    .modifier(OptionalAccessibilityIdentifier(skipAccessibilityID))
            }

            Spacer()

            Button(canFinish ? finishEnabledTitle : finishDisabledTitle, action: onComplete)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .disabled(!canFinish)
                .modifier(OptionalAccessibilityIdentifier(finishAccessibilityID))
        }
    }
}
