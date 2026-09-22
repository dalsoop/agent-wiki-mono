import Foundation
import StateRootKit

/// `accounts.json` 의 위치 정본.
///
/// ai-cli-account-manager 가 쓰고 ai-cli-launcher 가 읽는다. 양쪽이 각자
/// 경로 문자열을 조립하면 한쪽만 옮겼을 때 조용히 빈 목록이 된다.
public enum AiCliAccountsFile {
    /// `~/Library/Application Support/AiCliAccountManager`
    public static func supportDirectory(home: String = StateRootKit.path("")) -> String {
        let base = NSSearchPathForDirectoriesInDomains(
            .applicationSupportDirectory, .userDomainMask, true
        ).first ?? (home + "/Library/Application Support")
        return base + "/AiCliAccountManager"
    }

    /// `<supportDirectory>/accounts.json`
    public static func path(home: String = StateRootKit.path("")) -> String {
        supportDirectory(home: home) + "/accounts.json"
    }

    /// 쓰기 측이 디렉터리를 보장할 때 쓴다.
    @discardableResult
    public static func ensureSupportDirectory(home: String = StateRootKit.path("")) -> String {
        let dir = supportDirectory(home: home)
        do { try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true) } catch { _ = error }
        return dir
    }
}

/// `accounts.json` 한 행의 **공유 부분** 스키마.
///
/// 읽기 전용 소비자(launcher 등)가 쓰는 부분 디코드 뷰다. 토큰은 이 파일에 없다 —
/// 자격증명은 Keychain / blob 저장소에 따로 있고 여기엔 메타만 있다.
public struct AiCliAccountRecord: Sendable, Codable, Equatable, Identifiable, AiCliAccountIdentifiable {
    public let id: UUID
    public let client: AiCliClient
    public let label: String
    public let kind: AiCliAccountKind
    public let sessionKey: String?
    /// `accounts.json` 의 `id` 를 실제로 디코드했는지.
    /// false 면 `id` 는 임시값이라 selector 로 쓸 수 없다.
    public let hasStableID: Bool

    enum CodingKeys: String, CodingKey { case id, client, label, kind, sessionKey }

    public init(
        id: UUID,
        client: AiCliClient,
        label: String,
        kind: AiCliAccountKind = .oauthSession,
        sessionKey: String? = nil,
        hasStableID: Bool = true
    ) {
        self.id = id
        self.client = client
        self.label = label
        self.kind = kind
        self.sessionKey = sessionKey
        self.hasStableID = hasStableID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID: UUID?
        do {
            decodedID = try c.decodeIfPresent(UUID.self, forKey: .id)
        } catch {
            decodedID = nil
        }
        self.id = decodedID ?? UUID()
        self.hasStableID = decodedID != nil
        self.client = try c.decode(AiCliClient.self, forKey: .client)
        self.label = try c.decode(String.self, forKey: .label)
        // 구 데이터는 kind 가 없을 수 있다 — OAuth 세션으로 본다.
        let kindVal: AiCliAccountKind?
        do {
            kindVal = try c.decodeIfPresent(AiCliAccountKind.self, forKey: .kind)
        } catch {
            kindVal = nil
        }
        self.kind = kindVal ?? .oauthSession

        let keyVal: String?
        do {
            keyVal = try c.decodeIfPresent(String.self, forKey: .sessionKey)
        } catch {
            keyVal = nil
        }
        self.sessionKey = keyVal
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(client, forKey: .client)
        try c.encode(label, forKey: .label)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(sessionKey, forKey: .sessionKey)
    }

    /// 계정 관리자 CLI 에 넘길 selector.
    /// id 가 있으면 uuid(동명 라벨과 무관하게 유일), 없으면 라벨로 폴백한다.
    public var selector: String { hasStableID ? id.uuidString : label }

    public var identityClient: AiCliClient { client }
    public var identityKind: AiCliAccountKind { kind }
    public var identitySessionKey: String? { sessionKey }
}

/// `accounts.json` 읽기 전용 접근자.
public struct AiCliAccountsReader: Sendable {
    private let path: String

    public init(path: String? = nil, home: String = StateRootKit.path("")) {
        self.path = path ?? AiCliAccountsFile.path(home: home)
    }

    /// 행 하나가 깨져도(예: 이 빌드가 모르는 client) 나머지를 살린다.
    /// 배열 통째 디코드로 두면 미래 클라이언트 한 줄이 계정 목록 전체를 날린다.
    private struct LenientRows: Decodable {
        let rows: [AiCliAccountRecord]

        private struct Wrapper: Decodable {
            let accounts: [Skippable]?
        }

        private struct Skippable: Decodable {
            let value: AiCliAccountRecord?
            init(from decoder: Decoder) throws {
                do {
                    value = try AiCliAccountRecord(from: decoder)
                } catch {
                    value = nil
                }
            }
        }

        init(from decoder: Decoder) throws {
            let wrapper = try Wrapper(from: decoder)
            rows = (wrapper.accounts ?? []).compactMap(\.value)
        }
    }

    /// 전체 계정. 파일이 없거나 깨지면 빈 배열.
    /// 개별 행이 해석되지 않으면 **그 행만** 버린다.
    public func all() -> [AiCliAccountRecord] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [] }
        return (try? JSONDecoder().decode(LenientRows.self, from: data))?.rows ?? []
    }

    /// selector(uuid / 정확한 라벨 / prefix) 로 1개 선택.
    ///
    /// 동명 라벨을 첫 항목으로 조용히 고르지 않는다 — 잘못된 계정으로 실행되는 사고가 된다.
    /// 라벨이 겹치면 uuid(또는 앞자리 prefix)로 특정해야 하며, 그 전엔 nil(모호)이다.
    public static func resolve(
        selector: String,
        in pool: [AiCliAccountRecord]
    ) -> AiCliAccountRecord? {
        // uuid 완전 일치가 최우선(유일 보장).
        if let byID = pool.first(where: {
            $0.hasStableID && $0.id.uuidString.caseInsensitiveCompare(selector) == .orderedSame
        }) {
            return byID
        }
        let byLabel = pool.filter { $0.label == selector }
        if byLabel.count == 1 { return byLabel.first }
        if byLabel.count > 1 { return nil }   // 동명 — 모호. uuid 로 특정할 것.
        let fuzzy = pool.filter {
            $0.label.localizedCaseInsensitiveContains(selector)
                || ($0.hasStableID && $0.id.uuidString.lowercased().hasPrefix(selector.lowercased()))
        }
        return fuzzy.count == 1 ? fuzzy.first : nil
    }

    public func resolve(selector: String) -> AiCliAccountRecord? {
        Self.resolve(selector: selector, in: all())
    }
}
