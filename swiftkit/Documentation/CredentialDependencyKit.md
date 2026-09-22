# CredentialDependencyKit

자격증명을 주는 쪽과 받는 쪽을 앱과 공급자에 무관하게 연결하는 Foundation-only Swift 패키지다.
실제 비밀은 `CredentialSecret`에만 존재하며 이 타입은 `Codable`이 아니므로 설정·상태 JSON에
직렬화할 수 없다.

## 계약

- `CredentialProviding`: 안전한 카드 메타데이터 목록과 locator 기반 비밀 해석.
- `CredentialConsuming`: 해석된 비밀을 지정된 전달 방식으로 한 번 소비.
- `CredentialDependencyCatalog`: provider, credential, consumer, authorization, binding 그래프.
- `CredentialDependencyPolicy`: 기본 거부, 만료·비활성·끊어진 참조·전달 방식 검증.
- `CredentialDependencyBroker`: 권한을 먼저 판정하고 통과한 뒤에만 provider를 호출한다.
- `ProcessCredentialConsumer`: argv를 금지하고 stdin/env만 허용하며 stdout/stderr의 비밀을 마스킹한다.

```swift
let catalog = CredentialDependencyCatalog(
    providers: [provider.descriptor],
    credentials: [credential],
    consumers: [consumer.descriptor],
    authorizations: [authorization],
    bindings: [binding]
)
let broker = CredentialDependencyBroker(
    catalog: catalog,
    providers: [provider],
    consumers: [consumer]
)
let result = try await broker.deliver(bindingID: binding.id)
```

Vaultwarden·Infisical·Keychain 어댑터는 각 앱의 인증·세션 수명주기와 함께 두고 이 공통 계약을
구현한다. 앱이 늘어나도 provider/consumer 사이의 쌍별 브리지를 새로 만들 필요가 없다.
