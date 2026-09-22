import SwiftUI

/// 다단계 온보딩 껍데기. 페이지 본문은 앱이 넣는다.
public struct OnboardingWizardShell<Content: View>: View {
    public struct Header {
        public var title: String
        public var subtitle: String
        public var pageIndex: Int?
        public var pageCount: Int?
        public var error: String?
        public var showsHeader: Bool
        public init(
            title: String,
            subtitle: String = "",
            pageIndex: Int? = nil,
            pageCount: Int? = nil,
            error: String? = nil,
            showsHeader: Bool = true
        ) {
            self.title = title
            self.subtitle = subtitle
            self.pageIndex = pageIndex
            self.pageCount = pageCount
            self.error = error
            self.showsHeader = showsHeader
        }
    }

    public struct Chrome {
        public var skipTitle: String?
        public var backTitle: String?
        public var nextTitle: String?
        public var finishTitle: String
        public var showsFinish: Bool
        public var showsFooter: Bool
        public init(
            skipTitle: String? = nil,
            backTitle: String? = nil,
            nextTitle: String? = nil,
            finishTitle: String,
            showsFinish: Bool = true,
            showsFooter: Bool = true
        ) {
            self.skipTitle = skipTitle
            self.backTitle = backTitle
            self.nextTitle = nextTitle
            self.finishTitle = finishTitle
            self.showsFinish = showsFinish
            self.showsFooter = showsFooter
        }
    }

    public struct Gates {
        public var canGoBack: Bool
        public var canAdvance: Bool
        public var canFinish: Bool
        public init(
            canGoBack: Bool = true,
            canAdvance: Bool = true,
            canFinish: Bool = true
        ) {
            self.canGoBack = canGoBack
            self.canAdvance = canAdvance
            self.canFinish = canFinish
        }
    }

    public struct Actions {
        public var onSkip: (() -> Void)?
        public var onBack: (() -> Void)?
        public var onNext: (() -> Void)?
        public var onFinish: () -> Void
        public init(
            onSkip: (() -> Void)? = nil,
            onBack: (() -> Void)? = nil,
            onNext: (() -> Void)? = nil,
            onFinish: @escaping () -> Void
        ) {
            self.onSkip = onSkip
            self.onBack = onBack
            self.onNext = onNext
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

    public var header: Header
    public var chrome: Chrome
    public var gates: Gates
    public var actions: Actions
    public var accessibility: Accessibility
    public var content: Content

    public var title: String { header.title }
    public var subtitle: String { header.subtitle }
    public var pageIndex: Int? { header.pageIndex }
    public var pageCount: Int? { header.pageCount }
    public var error: String? { header.error }
    public var skipTitle: String? { chrome.skipTitle }
    public var backTitle: String? { chrome.backTitle }
    public var nextTitle: String? { chrome.nextTitle }
    public var finishTitle: String { chrome.finishTitle }
    public var canGoBack: Bool { gates.canGoBack }
    public var canAdvance: Bool { gates.canAdvance }
    public var canFinish: Bool { gates.canFinish }
    public var showsFinish: Bool { chrome.showsFinish }
    public var showsHeader: Bool { header.showsHeader }
    public var showsFooter: Bool { chrome.showsFooter }
    public var onSkip: (() -> Void)? { actions.onSkip }
    public var onBack: (() -> Void)? { actions.onBack }
    public var onNext: (() -> Void)? { actions.onNext }
    public var onFinish: () -> Void { actions.onFinish }
    public var skipAccessibilityID: String? { accessibility.skipID }
    public var finishAccessibilityID: String? { accessibility.finishID }
    public var containerAccessibilityID: String? { accessibility.containerID }

    public init(
        header: Header,
        chrome: Chrome,
        gates: Gates = Gates(),
        actions: Actions,
        accessibility: Accessibility = Accessibility(),
        @ViewBuilder content: () -> Content
    ) {
        self.header = header
        self.chrome = chrome
        self.gates = gates
        self.actions = actions
        self.accessibility = accessibility
        self.content = content()
    }

    /// 하위호환 — 문자열 축을 직접 나열하는 옛 호출부(함대 온보딩 화면들)도 그대로
    /// 컴파일된다. 새 코드는 `header:/chrome:/actions:` 그룹 이니셜라이저로 쓴다.
    /// 둘 다 같은 저장 프로퍼티에 쓴다(그룹형 쪽 디폴트 없음 — 모호성 없게).
    public init(
        title: String,
        subtitle: String = "",
        pageIndex: Int? = nil,
        pageCount: Int? = nil,
        error: String? = nil,
        skipTitle: String? = nil,
        backTitle: String? = nil,
        nextTitle: String? = nil,
        finishTitle: String,
        canGoBack: Bool = true,
        canAdvance: Bool = true,
        canFinish: Bool = true,
        showsFinish: Bool = true,
        showsHeader: Bool = true,
        showsFooter: Bool = true,
        onSkip: (() -> Void)? = nil,
        onBack: (() -> Void)? = nil,
        onNext: (() -> Void)? = nil,
        onFinish: @escaping () -> Void,
        skipAccessibilityID: String? = nil,
        finishAccessibilityID: String? = nil,
        containerAccessibilityID: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            header: Header(
                title: title,
                subtitle: subtitle,
                pageIndex: pageIndex,
                pageCount: pageCount,
                error: error,
                showsHeader: showsHeader
            ),
            chrome: Chrome(
                skipTitle: skipTitle,
                backTitle: backTitle,
                nextTitle: nextTitle,
                finishTitle: finishTitle,
                showsFinish: showsFinish,
                showsFooter: showsFooter
            ),
            gates: Gates(canGoBack: canGoBack, canAdvance: canAdvance, canFinish: canFinish),
            actions: Actions(onSkip: onSkip, onBack: onBack, onNext: onNext, onFinish: onFinish),
            accessibility: Accessibility(
                skipID: skipAccessibilityID,
                finishID: finishAccessibilityID,
                containerID: containerAccessibilityID
            ),
            content: content
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                headerBar
                Divider()
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
            if showsFooter {
                Divider()
                footer
            }
        }
        .modifier(OptionalAccessibilityIdentifier(containerAccessibilityID))
    }

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Spacer(minLength: 8)
                if let pageIndex, let pageCount, pageCount > 0 {
                    Text("\(pageIndex + 1) / \(pageCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let pageIndex, let pageCount, pageCount > 0 {
                ProgressView(value: Double(pageIndex + 1), total: Double(pageCount))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let skipTitle, let onSkip {
                Button(skipTitle, action: onSkip)
                    .modifier(OptionalAccessibilityIdentifier(skipAccessibilityID))
            }
            if let backTitle, let onBack {
                Button(backTitle, action: onBack)
                    .disabled(!canGoBack)
            }
            Spacer()
            if let nextTitle, let onNext, !showsFinish {
                Button(nextTitle, action: onNext)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .disabled(!canAdvance)
            } else {
                Button(finishTitle, action: onFinish)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .disabled(!canFinish)
                    .modifier(OptionalAccessibilityIdentifier(finishAccessibilityID))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}
