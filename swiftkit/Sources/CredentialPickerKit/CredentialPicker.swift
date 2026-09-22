import AgentVaultClientKit
import SwiftUI

/// 소비 앱의 자격 설정 화면 정본.
///
/// 이 뷰에는 `SecureField` 가 없다 — 그게 요점이다. 새 자격 등록은 Agent Vault 에서만 하고
/// 앱은 **카드를 고르기만** 한다 (#28 D1/D2). 앱이 저장하는 값은 카드 ID 하나다.
@MainActor
public struct CredentialPicker: View {
    @Bindable private var model: CredentialPickerModel
    private let title: String
    private let onSelect: (String) -> Void

    public init(
        model: CredentialPickerModel,
        title: String = "자격",
        onSelect: @escaping (String) -> Void = { _ in }
    ) {
        self.model = model
        self.title = title
        self.onSelect = onSelect
    }

    public var body: some View {
        Section {
            switch model.state {
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Agent Vault에서 자격을 읽는 중…")
                        .foregroundStyle(.secondary)
                }
            case .vaultUnavailable(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("credential-picker-vault-unavailable")
                Text("Agent Vault가 설치·실행 중인지 확인하세요. 이 앱에 비밀을 직접 넣는 경로는 없습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Label(message, systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
            case .ready(let matching, let total):
                picker(matching: matching, total: total)
            }
        } header: {
            Label(title, systemImage: "lock.shield")
        } footer: {
            Text("비밀은 Agent Vault에만 있습니다. 이 앱은 카드 ID만 저장하고, 필요할 때 vault에서 받아 씁니다.")
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private func picker(matching: Int, total: Int) -> some View {
        if matching == 0 && model.selectedID.isEmpty {
            Label("조건에 맞는 카드가 없습니다", systemImage: "tray")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("credential-picker-empty")
            newCredentialButton
        } else {
            if total > 40 {
                TextField("검색", text: $model.searchText)
                    .accessibilityIdentifier("credential-picker-search")
            }
            Picker(selection: $model.selectedID) {
                Text("선택 안 함").tag("")
                ForEach(model.visibleCards) { card in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(card.name)
                        // 같은 이름 카드가 여럿이라 host/account 가 없으면 못 고른다.
                        if !card.subtitle.isEmpty {
                            Text(card.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(card.id)
                }
            } label: {
                Text("카드")
            }
            .accessibilityIdentifier("credential-picker")
            .onChange(of: model.selectedID) { _, newValue in
                onSelect(AgentVaultCard.Pin(rawValue: newValue).rawValue)
            }

            statusRow
            newCredentialButton
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        if let card = model.selectedCard {
            HStack {
                Label(
                    card.secretStored == true ? "비밀 준비됨" : "비밀 미설정 — Agent Vault에서 채우세요",
                    systemImage: card.secretStored == true ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(card.secretStored == true ? Color.green : Color.secondary)
                Spacer()
                Text(card.providerID).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var newCredentialButton: some View {
        if let url = model.newCredentialURL {
            Link(destination: url) {
                Label("Agent Vault에 새 자격 만들기", systemImage: "plus.circle")
            }
            .accessibilityIdentifier("credential-picker-new")
        }
    }
}
