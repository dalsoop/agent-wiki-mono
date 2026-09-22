import Foundation

/// 로그인 웹 주소 **수리 워크플로** — 스캔·제안·초안. 저장 정본이 아니다.
///
/// 읽기: `VaultItem.loginURIs` / `needsLoginURI`
/// 쓰기: `VaultSession.save` (cipher `login.uris` 만 PUT)
/// 일괄 채움: `VaultSession.fillLoginURIs`
///
/// 브랜드 맵은 휴리스틱일 뿐 Bitwarden 원본이 아니다.
public enum VaultURIPipeline {
    /// 원본은 그대로 두고, 같은 서비스의 다른 주소를 최대 4개까지 채운다.
    /// 로그인 호스트 · 경로 없는 origin · 사이트 루트 · `www.` 루트.
    public static let maxAutoURIs = 4
    /// 확장 규칙이 바뀌면 올린다. 항목 커스텀 필드 `vw.uri` 가 이보다 낮으면 다시 채운다.
    public static let schemaVersion = 3
    /// 이 앱이 웹 주소를 관리한다는 증거. 공식 클라이언트 커스텀 필드로 보인다.
    public static let ledgerFieldName = "vw.uri"

    /// 같은 계정으로 들어가는 인접 호스트. 추측 브랜드가 아니라 계정 동치만.
    static let relatedHosts: [String: [String]] = [
        "apple.com": ["https://icloud.com"],
        "icloud.com": ["https://apple.com"],
        "microsoft.com": ["https://login.live.com"],
        "live.com": ["https://login.microsoftonline.com"],
    ]

    public struct Row: Sendable, Equatable, Identifiable {
        public var id: String { itemID }
        public var itemID: String
        public var itemName: String
        /// 비어 있으면 규칙 밖 — 대기리스트. 에이전트가 `uri set` 한다.
        public var proposedURI: String
        public var reason: String
        public var fillable: Bool { !VaultURIPipeline.normalizedURIList(proposedURI).isEmpty }

        public init(itemID: String, itemName: String, proposedURI: String, reason: String) {
            self.itemID = itemID
            self.itemName = itemName
            self.proposedURI = proposedURI
            self.reason = reason
        }
    }

    public struct Snapshot: Sendable, Equatable {
        public var loginCount: Int
        public var presentCount: Int
        public var rows: [Row]

        public var missingCount: Int { rows.count }
        public var fillableCount: Int { rows.filter(\.fillable).count }
        public var blockedCount: Int { rows.filter { !$0.fillable }.count }
        public var waitlistCount: Int { blockedCount }
        public var waitlistRows: [Row] { rows.filter { !$0.fillable } }

        public init(loginCount: Int = 0, presentCount: Int = 0, rows: [Row] = []) {
            self.loginCount = loginCount
            self.presentCount = presentCount
            self.rows = rows
        }
    }

    public struct FillResult: Sendable, Equatable {
        public var changed: Int
        public var failed: [String]
        public var aborted: String?

        public init(changed: Int = 0, failed: [String] = [], aborted: String? = nil) {
            self.changed = changed
            self.failed = failed
            self.aborted = aborted
        }
    }

    public static func isBlankURI(_ raw: String) -> Bool {
        VaultItem.isBlankLoginURI(raw)
    }

    public static func resolvedURIs(of item: VaultItem) -> [String] {
        item.loginURIs
    }

    public static func loginNeedsURI(_ item: VaultItem) -> Bool {
        item.needsLoginURI
    }

    /// 규칙으로 못 채움 — 자동 apply 대상이 아니다. 에이전트가 `uri set` 한다.
    public static func isWaitlist(_ item: VaultItem) -> Bool {
        loginNeedsURI(item) && proposeFill(for: item) == nil
    }

    /// 들어오는 값이 비면 서버에 있던 URI 를 지치지 않는다.
    public static func mergedURIs(incoming: [String], existing: [String]) -> [String] {
        let next = incoming.filter { !isBlankURI($0) }
        if !next.isEmpty { return next }
        return existing.filter { !isBlankURI($0) }
    }

    public static func scan(items: [VaultItem]) -> Snapshot {
        let logins = items.filter { !$0.deleted && ($0.type == 0 || $0.type == 1) }
        let missing = logins.filter(loginNeedsURI)
        let rows: [Row] = missing.map { item -> Row in
            if let fill = proposeFill(for: item) {
                return Row(itemID: item.id, itemName: item.name, proposedURI: fill.uri, reason: fill.reason)
            }
            return Row(
                itemID: item.id,
                itemName: item.name,
                proposedURI: "",
                reason: "에이전트 대기 — 규칙에 없음"
            )
        }
        .sorted { $0.itemName.localizedCaseInsensitiveCompare($1.itemName) == .orderedAscending }
        return Snapshot(
            loginCount: logins.count,
            presentCount: logins.count - missing.count,
            rows: rows
        )
    }

    public static func normalizedURI(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return trimmed }
        if trimmed.contains("://") { return trimmed }
        return "https://\(trimmed)"
    }

    /// 줄바꿈·쉼표·세미콜론으로 나눈 주소 목록. 중복은 버린다.
    public static func normalizedURIList(_ raw: String) -> [String] {
        let chunks = raw
            .replacingOccurrences(of: ",", with: "\n")
            .replacingOccurrences(of: ";", with: "\n")
            .components(separatedBy: .newlines)
        var seen = Set<String>()
        var out: [String] = []
        for chunk in chunks {
            let piece = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !isBlankURI(piece) else { continue }
            let value = normalizedURI(piece)
            let key = value.lowercased()
            if seen.insert(key).inserted { out.append(value) }
        }
        return out
    }
}
