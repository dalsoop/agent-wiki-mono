import SwiftUI

/// 자격증명(사용자명/암호) 입력 시트 — 모든 앱이 사용자에게 요구할 때 쓰는 공용 프롬프트.
/// 에이전트가 앱을 켜고, 앱이 이 시트로 사용자에게 요구한다(터미널/getpass 아님).
public struct CredentialPromptSheet: View {
    public let title: String
    public let confirmTitle: String
    public let defaultUsername: String
    public let onSubmit: (String, String) -> Void
    @State private var username: String
    @State private var password = ""
    @Environment(\.dismiss) private var dismiss

    public init(title: String,
                defaultUsername: String,
                confirmTitle: String = "확인",
                onSubmit: @escaping (String, String) -> Void) {
        self.title = title
        self.defaultUsername = defaultUsername
        self.confirmTitle = confirmTitle
        self.onSubmit = onSubmit
        _username = State(initialValue: defaultUsername)
    }

    private var isValid: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Form {
                TextField("사용자", text: $username)
                SecureField("암호", text: $password)
            }
            HStack {
                Button("취소") { dismiss() }
                Spacer()
                Button(confirmTitle) {
                    onSubmit(username.trimmingCharacters(in: .whitespaces), password)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
