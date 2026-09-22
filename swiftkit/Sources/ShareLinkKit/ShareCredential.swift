import CredentialBrokerKit
import Foundation

/// 공유 저장소 접근키를 담는 **카드**.
///
/// 키를 앱 설정에 두지 않는다 — 설정 파일은 백업·동기화·화면 공유로 새어 나간다.
/// 카드(키체인)에 두고 앱에는 카드 이름만 남긴다. 여러 앱이 같은 카드를 가리키면
/// 한 번만 적어 넣고 다 같이 쓴다 — 그게 이 계층을 공용으로 둔 이유다.
public enum ShareCredential {

    /// 앱들이 기본으로 가리키는 카드 이름. 저장소 하나를 여럿이 공유하는 게 보통이다.
    public static let defaultProfile = "share-storage"

    public static let accessKeyField = "access_key_id"
    public static let secretKeyField = "secret_access_key"

    /// 카드가 없을 때 사용자에게 물어볼 내용.
    ///
    /// 터미널이 아니라 **앱 안 프롬프트**로 뜬다 — 자격증명 요구는 앱이 화면에서 해야 한다.
    public static func spec(
        profile: String = defaultProfile,
        reason: String = ""
    ) -> CredentialSpec {
        CredentialSpec(
            profile: profile,
            title: "공유 저장소 접근키",
            reason: reason.isEmpty ? "캡처를 올려 링크를 만들려면 저장소 접근키가 필요합니다." : reason,
            steps: [
                CredentialStep(text: "저장소 콘솔에서 이 버킷에 쓰기 권한이 있는 접근키를 만든다."),
                CredentialStep(text: "Access Key ID 와 Secret Access Key 를 아래에 붙여 넣는다."),
                CredentialStep(text: "Secret 은 발급 화면을 벗어나면 다시 볼 수 없으니 지금 복사한다."),
            ],
            fields: [
                CredentialField(key: accessKeyField, label: "Access Key ID", secret: false),
                CredentialField(key: secretKeyField, label: "Secret Access Key", secret: true),
            ],
            storage: .keychain,
            meta: ["source": "share-link-kit"]
        )
    }

    /// 카드에서 꺼낸 값이 쓸 만한지. 한쪽만 있으면 서명이 조용히 실패한다.
    public static func keys(from fields: [String: String]) -> (access: String, secret: String)? {
        let access = fields[accessKeyField]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let secret = fields[secretKeyField]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !access.isEmpty, !secret.isEmpty else { return nil }
        return (access, secret)
    }
}
