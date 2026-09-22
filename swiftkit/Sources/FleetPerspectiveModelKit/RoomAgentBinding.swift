import Foundation

/// `agent-work-todo room graph`가 확정한 Room–Agent 결속이다.
/// 제목·폴더·occupant 문자열로 추론한 값은 이 모델에 넣지 않는다.
public struct RoomAgentBinding: Sendable, Equatable, Codable {
    public let roomID: String
    public let tenantID: String?
    public let parentRoomID: String?
    public let identity: String
    public let sessionID: String
    public let paneID: String?
    public let paneTitle: String?
    public let paneFocused: Bool
    public let attention: String?
    public let roomSlug: String?

    public init(
        roomID: String,
        tenantID: String?,
        parentRoomID: String?,
        identity: String,
        sessionID: String,
        paneID: String?,
        paneTitle: String?,
        paneFocused: Bool,
        attention: String? = nil,
        roomSlug: String? = nil
    ) {
        self.roomID = Self.normalizedRoomID(roomID)
        self.tenantID = Self.nonEmpty(tenantID)
        self.parentRoomID = Self.nonEmpty(parentRoomID).map(Self.normalizedRoomID)
        self.identity = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.paneID = Self.nonEmpty(paneID)
        self.paneTitle = Self.nonEmpty(paneTitle)
        self.paneFocused = paneFocused
        self.attention = Self.nonEmpty(attention)
        self.roomSlug = Self.nonEmpty(roomSlug)
    }

    public var hasPane: Bool {
        paneID != nil
    }

    public static func normalizedRoomID(_ roomID: String) -> String {
        roomID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func normalizedTenantID(_ tenantID: String) -> String {
        let trimmed = tenantID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }
        return trimmed.hasPrefix("tenant:") ? trimmed : "tenant:\(trimmed)"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
