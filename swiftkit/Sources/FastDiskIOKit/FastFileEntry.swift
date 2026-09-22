import Foundation

public struct FastFileEntry: Sendable, Equatable, Hashable {
    public let path: String
    public let name: String
    public let size: Int64
    public let modifiedAt: Date
    public let isDirectory: Bool
    public let inode: UInt64
    public let device: UInt64

    public var mtime: Date { modifiedAt }

    public init(
        path: String,
        name: String,
        size: Int64,
        modifiedAt: Date,
        isDirectory: Bool,
        inode: UInt64,
        device: UInt64
    ) {
        self.path = path
        self.name = name
        self.size = size
        self.modifiedAt = modifiedAt
        self.isDirectory = isDirectory
        self.inode = inode
        self.device = device
    }
}
