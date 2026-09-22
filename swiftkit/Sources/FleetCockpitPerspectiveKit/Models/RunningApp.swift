import Foundation

/// 실행 중인 함대 앱 한 줄. GUI는 NSWorkspace, CLI는 스냅샷 또는 프로세스 표.
public struct RunningApp: Sendable, Equatable, Identifiable, Codable {
    public var id: String { bundleId }
    public let name: String
    public let bundleId: String
    public let path: String
    public let pid: Int32

    public init(name: String, bundleId: String, path: String, pid: Int32) {
        self.name = name
        self.bundleId = bundleId
        self.path = path
        self.pid = pid
    }
}
