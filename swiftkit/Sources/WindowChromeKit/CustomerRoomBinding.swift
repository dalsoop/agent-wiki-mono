import Foundation
import StateRootKit

/// 외부 고객용 단일 룸 바인딩 컨텍스트 (No-Wizard, No-Switching)
public struct CustomerRoomBinding: Sendable, Equatable {
    public let appSlug: String
    public let roomID: String
    public let storageURL: URL

    public init(appSlug: String, roomID: String = StateRootKit.defaultRoomID) {
        self.appSlug = appSlug
        self.roomID = roomID
        self.storageURL = StateRootKit.customerAppStorageURL(slug: appSlug, roomID: roomID)
    }

    /// 첫 기동 시 디렉터리를 0-overhead로 자동 프로비저닝
    @discardableResult
    public func ensureStorage() -> URL {
        StateRootKit.ensureCustomerRoomStorage(slug: appSlug, roomID: roomID)
    }
}
