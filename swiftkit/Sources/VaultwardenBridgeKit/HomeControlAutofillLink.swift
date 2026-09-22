import Foundation

/// Home Control 카드가 Vaultwarden Client에 자동 채우기 준비만 요청하는 무비밀 URL 계약.
/// 비밀번호·토큰은 이 링크에 절대 포함하지 않고, 두 앱 사이에는 카드 등록 ID와 Keychain 항목 ID만 흐른다.
public enum HomeControlAutofillLink {
    public static let vaultScheme = "vaultwarden-client"
    public static let vaultHost = "home-control-autofill"
    public static let homeControlScheme = "home-control-dashboard"
    public static let readyHost = "vault-autofill-ready"

    public struct Request: Equatable, Sendable {
        public let registrationID: UUID
        public let vaultItemID: String
        public let serverURL: URL
        /// Home Control이 만든 일회용 capability. 비밀번호·OAuth token이 아닌 locator 확인값이다.
        public let activationToken: String

        public init(registrationID: UUID, vaultItemID: String, serverURL: URL, activationToken: String) {
            self.registrationID = registrationID
            self.vaultItemID = vaultItemID
            self.serverURL = serverURL
            self.activationToken = activationToken
        }
    }

    public struct Ready: Equatable, Sendable {
        public let registrationID: UUID
        public let activationToken: String

        public init(registrationID: UUID, activationToken: String) {
            self.registrationID = registrationID
            self.activationToken = activationToken
        }
    }

    /// OAuth state와 별개인 앱 간 일회용 capability. UUID는 OS 난수원에서 생성되며 비밀값은 담지 않는다.
    public static func makeActivationToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    public static func requestURL(
        registrationID: UUID,
        vaultItemID: String,
        serverURL: URL,
        activationToken: String = makeActivationToken()
    ) -> URL? {
        guard !vaultItemID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              isValidActivationToken(activationToken),
              ["http", "https"].contains(serverURL.scheme?.lowercased() ?? ""),
              serverURL.host != nil,
              serverURL.user == nil,
              serverURL.password == nil
        else { return nil }
        var components = URLComponents()
        components.scheme = vaultScheme
        components.host = vaultHost
        components.queryItems = [
            URLQueryItem(name: "registration_id", value: registrationID.uuidString.lowercased()),
            URLQueryItem(name: "item_id", value: vaultItemID),
            URLQueryItem(name: "uri", value: serverURL.absoluteString),
            URLQueryItem(name: "activation_token", value: activationToken),
        ]
        return components.url
    }

    public static func request(from url: URL) -> Request? {
        guard url.scheme == vaultScheme, url.host == vaultHost,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let allowed = Set(["registration_id", "item_id", "uri", "activation_token"])
        let items = components.queryItems ?? []
        guard items.allSatisfy({ allowed.contains($0.name) }),
              Set(items.map(\.name)).count == items.count,
              let registrationValue = items.first(where: { $0.name == "registration_id" })?.value,
              let registrationID = UUID(uuidString: registrationValue),
              let itemID = items.first(where: { $0.name == "item_id" })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !itemID.isEmpty,
              let rawURL = items.first(where: { $0.name == "uri" })?.value,
              let serverURL = URL(string: rawURL),
              ["http", "https"].contains(serverURL.scheme?.lowercased() ?? ""),
              serverURL.host != nil,
              serverURL.user == nil,
              serverURL.password == nil,
              let activationToken = items.first(where: { $0.name == "activation_token" })?.value,
              isValidActivationToken(activationToken)
        else { return nil }
        return Request(
            registrationID: registrationID,
            vaultItemID: itemID,
            serverURL: serverURL,
            activationToken: activationToken
        )
    }

    public static func readyURL(
        registrationID: UUID,
        activationToken: String = makeActivationToken()
    ) -> URL {
        var components = URLComponents()
        components.scheme = homeControlScheme
        components.host = readyHost
        components.queryItems = [
            URLQueryItem(name: "registration_id", value: registrationID.uuidString.lowercased()),
            URLQueryItem(name: "activation_token", value: activationToken),
        ]
        return components.url!
    }

    public static func ready(from url: URL) -> Ready? {
        guard url.scheme == homeControlScheme, url.host == readyHost,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let items = components.queryItems ?? []
        let allowed = Set(["registration_id", "activation_token"])
        guard items.allSatisfy({ allowed.contains($0.name) }),
              Set(items.map(\.name)).count == items.count,
              let value = items.first(where: { $0.name == "registration_id" })?.value,
              let registrationID = UUID(uuidString: value),
              let activationToken = items.first(where: { $0.name == "activation_token" })?.value,
              isValidActivationToken(activationToken)
        else { return nil }
        return Ready(registrationID: registrationID, activationToken: activationToken)
    }

    public static func readyRegistrationID(from url: URL) -> UUID? {
        ready(from: url)?.registrationID
    }

    private static func isValidActivationToken(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9_-]{32,128}$", options: .regularExpression) != nil
    }
}
