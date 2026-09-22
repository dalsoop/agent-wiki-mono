import SwiftUI

/// 소개 카드 한 장. 문구는 앱이 넣는다.
public struct OnboardingFeature: Identifiable {
    public var id: String
    public var symbol: String
    public var title: String
    public var detail: String

    public init(id: String? = nil, symbol: String, title: String, detail: String) {
        self.id = id ?? "\(symbol)|\(title)"
        self.symbol = symbol
        self.title = title
        self.detail = detail
    }
}

/// 기능 카드 + 시작하기. 필수 설정 체크리스트는 `OnboardingChecklistView`.
public struct OnboardingIntroView<Note: View>: View {
    public var title: String
    public var subtitle: String
    public var features: [OnboardingFeature]
    public var startTitle: String
    public var onStart: () -> Void
    public var skipTitle: String?
    public var onSkip: (() -> Void)?
    public var startAccessibilityID: String?
    public var skipAccessibilityID: String?
    public var containerAccessibilityID: String?
    public var note: Note

    public struct Copy {
        public var title: String
        public var subtitle: String
        public var startTitle: String
        public var skipTitle: String?
        public init(
            title: String,
            subtitle: String,
            startTitle: String,
            skipTitle: String? = nil
        ) {
            self.title = title
            self.subtitle = subtitle
            self.startTitle = startTitle
            self.skipTitle = skipTitle
        }
    }

    public struct Actions {
        public var onStart: () -> Void
        public var onSkip: (() -> Void)?
        public init(onStart: @escaping () -> Void, onSkip: (() -> Void)? = nil) {
            self.onStart = onStart
            self.onSkip = onSkip
        }
    }

    public struct Accessibility {
        public var startID: String?
        public var skipID: String?
        public var containerID: String?
        public init(
            startID: String? = nil,
            skipID: String? = nil,
            containerID: String? = nil
        ) {
            self.startID = startID
            self.skipID = skipID
            self.containerID = containerID
        }
    }

    public init(
        copy: Copy,
        features: [OnboardingFeature],
        actions: Actions,
        accessibility: Accessibility = Accessibility(),
        @ViewBuilder note: () -> Note
    ) {
        self.title = copy.title
        self.subtitle = copy.subtitle
        self.features = features
        self.startTitle = copy.startTitle
        self.onStart = actions.onStart
        self.skipTitle = copy.skipTitle
        self.onSkip = actions.onSkip
        self.startAccessibilityID = accessibility.startID
        self.skipAccessibilityID = accessibility.skipID
        self.containerAccessibilityID = accessibility.containerID
        self.note = note()
    }

    /// 하위호환 — 문자열 축을 직접 나열하는 옛 호출부(함대 온보딩 화면들)도 그대로
    /// 컴파일된다. 새 코드는 `copy:/actions:` 그룹 이니셜라이저로 쓴다.
    /// `note:` 는 함대 호출부의 순서(features 뒤·startTitle 앞)를 그대로 따른다.
    public init(
        title: String,
        subtitle: String,
        features: [OnboardingFeature],
        @ViewBuilder note: () -> Note,
        startTitle: String,
        onStart: @escaping () -> Void,
        skipTitle: String? = nil,
        onSkip: (() -> Void)? = nil,
        startAccessibilityID: String? = nil,
        skipAccessibilityID: String? = nil,
        containerAccessibilityID: String? = nil
    ) {
        self.init(
            copy: Copy(title: title, subtitle: subtitle, startTitle: startTitle, skipTitle: skipTitle),
            features: features,
            actions: Actions(onStart: onStart, onSkip: onSkip),
            accessibility: Accessibility(
                startID: startAccessibilityID,
                skipID: skipAccessibilityID,
                containerID: containerAccessibilityID),
            note: note)
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.largeTitle.bold())
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(features) { feature in
                        featureRow(feature)
                    }
                }
                note
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 40)
            Spacer(minLength: 0)
            HStack {
                if let skipTitle, let onSkip {
                    Button(skipTitle, action: onSkip)
                        .modifier(OptionalAccessibilityIdentifier(skipAccessibilityID))
                }
                Spacer()
                Button(startTitle, action: onStart)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .modifier(OptionalAccessibilityIdentifier(startAccessibilityID))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 28)
        }
        .modifier(OptionalAccessibilityIdentifier(containerAccessibilityID))
    }

    private func featureRow(_ feature: OnboardingFeature) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if !feature.symbol.isEmpty {
                Image(systemName: feature.symbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title).font(.headline)
                Text(feature.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension OnboardingIntroView where Note == EmptyView {
    public init(
        copy: Copy,
        features: [OnboardingFeature],
        actions: Actions,
        accessibility: Accessibility = Accessibility()
    ) {
        self.init(
            copy: copy,
            features: features,
            actions: actions,
            accessibility: accessibility,
            note: { EmptyView() }
        )
    }

    /// 하위호환 — `note:` 없이 쓰는 옛 평형 호출부(함대 온보딩 화면 다수)용.
    public init(
        title: String,
        subtitle: String,
        features: [OnboardingFeature],
        startTitle: String,
        onStart: @escaping () -> Void,
        skipTitle: String? = nil,
        onSkip: (() -> Void)? = nil,
        startAccessibilityID: String? = nil,
        skipAccessibilityID: String? = nil,
        containerAccessibilityID: String? = nil
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            features: features,
            note: { EmptyView() },
            startTitle: startTitle,
            onStart: onStart,
            skipTitle: skipTitle,
            onSkip: onSkip,
            startAccessibilityID: startAccessibilityID,
            skipAccessibilityID: skipAccessibilityID,
            containerAccessibilityID: containerAccessibilityID)
    }
}

extension OnboardingIntroView where Note == Text {
    public init(
        copy: Copy,
        features: [OnboardingFeature],
        note: String,
        actions: Actions,
        accessibility: Accessibility = Accessibility()
    ) {
        self.init(
            copy: copy,
            features: features,
            actions: actions,
            accessibility: accessibility,
            note: { Text(note) }
        )
    }
}

extension OnboardingIntroView where Note == Text {
    /// 하위호환 — `note:` 에 문자열을 넘기는 옛 평형 호출부(함대 온보딩 화면 다수)용.
    /// 축 순서는 함대 호출부(features 뒤·startTitle 앞)를 그대로 따른다.
    public init(
        title: String,
        subtitle: String,
        features: [OnboardingFeature],
        note: String,
        startTitle: String,
        onStart: @escaping () -> Void,
        skipTitle: String? = nil,
        onSkip: (() -> Void)? = nil,
        startAccessibilityID: String? = nil,
        skipAccessibilityID: String? = nil,
        containerAccessibilityID: String? = nil
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            features: features,
            note: { Text(note) },
            startTitle: startTitle,
            onStart: onStart,
            skipTitle: skipTitle,
            onSkip: onSkip,
            startAccessibilityID: startAccessibilityID,
            skipAccessibilityID: skipAccessibilityID,
            containerAccessibilityID: containerAccessibilityID)
    }
}
