import Foundation

public struct AppPaths: Sendable {
    public var root: URL

    public init(root: URL) {
        self.root = root
    }

    public var storeFile: URL {
        root.appendingPathComponent("state.json", isDirectory: false)
    }

    public static var `default`: AppPaths {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AppPaths(root: base.appendingPathComponent("DatabaseViewer", isDirectory: true))
    }
}
