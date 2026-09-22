import OnboardingKit
import SwiftUI

/// 체크리스트 한 행. 문구·액션은 앱이 넣는다. 보조 버튼은 `extraAction`.
public struct OnboardingRow: Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var done: Bool
    public var actionTitle: String?
    public var action: (() -> Void)?
    public var actionAccessibilityID: String?
    public var extraActionTitle: String?
    public var extraAction: (() -> Void)?

    public struct Action {
        public var title: String
        public var run: () -> Void
        public var accessibilityID: String?
        public init(
            title: String,
            run: @escaping () -> Void,
            accessibilityID: String? = nil
        ) {
            self.title = title
            self.run = run
            self.accessibilityID = accessibilityID
        }
    }

    public init(
        id: String,
        title: String,
        detail: String,
        done: Bool,
        primary: Action? = nil,
        extra: Action? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.done = done
        self.actionTitle = primary?.title
        self.action = primary?.run
        self.actionAccessibilityID = primary?.accessibilityID
        self.extraActionTitle = extra?.title
        self.extraAction = extra?.run
    }

    /// 하위호환 — 축을 직접 나열하는 옛 호출부(함대 온보딩 화면들)도 그대로
    /// 컴파일된다. 새 코드는 `primary:/extra:` 그룹 이니셜라이저로 쓴다.
    public init(
        id: String,
        title: String,
        detail: String,
        done: Bool,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        actionAccessibilityID: String? = nil,
        extraActionTitle: String? = nil,
        extraAction: (() -> Void)? = nil
    ) {
        self.init(
            id: id, title: title, detail: detail, done: done,
            primary: actionTitle.map { Action(title: $0, run: action ?? {}, accessibilityID: actionAccessibilityID) },
            extra: extraActionTitle.map { Action(title: $0, run: extraAction ?? {}, accessibilityID: nil) })
    }
}

/// 설정 온보딩 껍데기. 소개 카드는 `OnboardingIntroView`, 다단계는 `OnboardingWizardShell`.
///
/// 권장 기본값은 화면이 뜨기 전에 앱이 적용한다. 권한이 필요한 항목만 행 버튼을 단다.
/// 필수가 남으면 완료 버튼이 비활성이다.
public struct OnboardingChecklistView<FooterExtra: View>: View {
    public var title: String
    public var subtitle: String
    public var rows: [OnboardingRow]
    public var error: String?
    public var skipTitle: String
    public var finishEnabledTitle: String
    public var finishDisabledTitle: String
    public var canFinish: Bool
    public var onSkip: () -> Void
    public var onFinish: () -> Void
    public var skipAccessibilityID: String?
    public var finishAccessibilityID: String?
    public var containerAccessibilityID: String?
    public var footerExtra: FooterExtra

    public struct Copy {
        public var title: String
        public var subtitle: String
        public var skipTitle: String
        public var finishEnabledTitle: String
        public var finishDisabledTitle: String
        public init(
            title: String,
            subtitle: String,
            skipTitle: String,
            finishEnabledTitle: String,
            finishDisabledTitle: String
        ) {
            self.title = title
            self.subtitle = subtitle
            self.skipTitle = skipTitle
            self.finishEnabledTitle = finishEnabledTitle
            self.finishDisabledTitle = finishDisabledTitle
        }
    }

    public struct Finish {
        public var canFinish: Bool
        public var onSkip: () -> Void
        public var onFinish: () -> Void
        public init(
            canFinish: Bool,
            onSkip: @escaping () -> Void,
            onFinish: @escaping () -> Void
        ) {
            self.canFinish = canFinish
            self.onSkip = onSkip
            self.onFinish = onFinish
        }
    }

    public struct Accessibility {
        public var skipID: String?
        public var finishID: String?
        public var containerID: String?
        public init(
            skipID: String? = nil,
            finishID: String? = nil,
            containerID: String? = nil
        ) {
            self.skipID = skipID
            self.finishID = finishID
            self.containerID = containerID
        }
    }

    public init(
        copy: Copy,
        rows: [OnboardingRow],
        error: String? = nil,
        finish: Finish,
        accessibility: Accessibility = Accessibility(),
        @ViewBuilder footerExtra: () -> FooterExtra
    ) {
        self.title = copy.title
        self.subtitle = copy.subtitle
        self.rows = rows
        self.error = error
        self.skipTitle = copy.skipTitle
        self.finishEnabledTitle = copy.finishEnabledTitle
        self.finishDisabledTitle = copy.finishDisabledTitle
        self.canFinish = finish.canFinish
        self.onSkip = finish.onSkip
        self.onFinish = finish.onFinish
        self.skipAccessibilityID = accessibility.skipID
        self.finishAccessibilityID = accessibility.finishID
        self.containerAccessibilityID = accessibility.containerID
        self.footerExtra = footerExtra()
    }

    /// 하위호환 — 축을 직접 나열하고 푸터를 trailing closure 로 붙이는 옛 호출부
    /// (photo-classification-map 등 함대 온보딩 화면들)도 그대로 컴파일된다.
    public init(
        title: String,
        subtitle: String,
        rows: [OnboardingRow],
        error: String? = nil,
        skipTitle: String,
        finishEnabledTitle: String,
        finishDisabledTitle: String,
        canFinish: Bool,
        onSkip: @escaping () -> Void,
        onFinish: @escaping () -> Void,
        skipAccessibilityID: String? = nil,
        finishAccessibilityID: String? = nil,
        containerAccessibilityID: String? = nil,
        @ViewBuilder footerExtra: () -> FooterExtra
    ) {
        self.init(
            copy: Copy(
                title: title,
                subtitle: subtitle,
                skipTitle: skipTitle,
                finishEnabledTitle: finishEnabledTitle,
                finishDisabledTitle: finishDisabledTitle),
            rows: rows,
            error: error,
            finish: Finish(canFinish: canFinish, onSkip: onSkip, onFinish: onFinish),
            accessibility: Accessibility(
                skipID: skipAccessibilityID,
                finishID: finishAccessibilityID,
                containerID: containerAccessibilityID),
            footerExtra: footerExtra)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.largeTitle.bold())
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(rows) { row in
                    checklistRow(row)
                }
            }

            footerExtra

            if let error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)

            HStack {
                skipButton
                Spacer()
                finishButton
            }
        }
        .padding(40)
        .frame(maxWidth: 560, alignment: .leading)
        .modifier(OptionalAccessibilityIdentifier(containerAccessibilityID))
    }

    private var skipButton: some View {
        Button(skipTitle, action: onSkip)
            .modifier(OptionalAccessibilityIdentifier(skipAccessibilityID))
    }

    private var finishButton: some View {
        Button(canFinish ? finishEnabledTitle : finishDisabledTitle, action: onFinish)
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .disabled(!canFinish)
            .modifier(OptionalAccessibilityIdentifier(finishAccessibilityID))
    }

    private func checklistRow(_ row: OnboardingRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(row.done ? Color.green : Color.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.headline)
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            rowAction(row)
        }
    }

    @ViewBuilder
    private func rowAction(_ row: OnboardingRow) -> some View {
        if !row.done {
            HStack(spacing: 8) {
                if let title = row.actionTitle, let action = row.action {
                    Button(title, action: action)
                        .controlSize(.small)
                        .modifier(OptionalAccessibilityIdentifier(row.actionAccessibilityID))
                }
                if let title = row.extraActionTitle, let action = row.extraAction {
                    Button(title, action: action)
                        .controlSize(.small)
                }
            }
        }
    }
}

extension OnboardingChecklistView where FooterExtra == EmptyView {
    public init(
        copy: Copy,
        rows: [OnboardingRow],
        error: String? = nil,
        finish: Finish,
        accessibility: Accessibility = Accessibility()
    ) {
        self.init(
            copy: copy,
            rows: rows,
            error: error,
            finish: finish,
            accessibility: accessibility,
            footerExtra: { EmptyView() }
        )
    }

    /// 하위호환 — 문자열 축을 직접 나열하는 옛 호출부(함대 온보딩 화면들)도 그대로
    /// 컴파일된다. 새 코드는 `copy:/finish:` 그룹 이니셜라이저로 쓴다.
    public init(
        title: String,
        subtitle: String,
        rows: [OnboardingRow],
        error: String? = nil,
        skipTitle: String,
        finishEnabledTitle: String,
        finishDisabledTitle: String,
        canFinish: Bool,
        onSkip: @escaping () -> Void,
        onFinish: @escaping () -> Void,
        skipAccessibilityID: String? = nil,
        finishAccessibilityID: String? = nil,
        containerAccessibilityID: String? = nil
    ) {
        self.init(
            copy: Copy(
                title: title,
                subtitle: subtitle,
                skipTitle: skipTitle,
                finishEnabledTitle: finishEnabledTitle,
                finishDisabledTitle: finishDisabledTitle),
            rows: rows,
            error: error,
            finish: Finish(canFinish: canFinish, onSkip: onSkip, onFinish: onFinish),
            accessibility: Accessibility(
                skipID: skipAccessibilityID,
                finishID: finishAccessibilityID,
                containerID: containerAccessibilityID)
        )
    }
}
