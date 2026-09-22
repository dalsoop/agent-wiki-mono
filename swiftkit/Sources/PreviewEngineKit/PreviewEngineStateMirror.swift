import Foundation
import StateMirrorKit

/// 미리보기 스튜디오의 실시간 런타임 상태를 미러링하는 어댑터
public struct PreviewEngineStateMirror: Sendable {
    public static let slug = "document-preview-inspector-studio"

    public struct StatePayload: Codable, Sendable {
        public let activeDocumentPath: String?
        public let activeFormat: String?
        public let openTabsCount: Int
        public let lastAction: String
        public let timestamp: Date

        public init(
            activeDocumentPath: String?,
            activeFormat: String?,
            openTabsCount: Int,
            lastAction: String,
            timestamp: Date = Date()
        ) {
            self.activeDocumentPath = activeDocumentPath
            self.activeFormat = activeFormat
            self.openTabsCount = openTabsCount
            self.lastAction = lastAction
            self.timestamp = timestamp
        }
    }

    public static func emit(payload: StatePayload) {
        StateMirror.publish(app: slug, payload)
    }
}
