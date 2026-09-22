import Foundation

public final class VirtualFileSystem: VirtualFileSystemProtocol {
    final class FileNode {
        var data: Data
        var createdAt: Date
        var modifiedAt: Date
        var attributes: [String: String]

        init(data: Data = Data(), attributes: [String: String] = [:]) {
            self.data = data
            let now = Date()
            self.createdAt = now
            self.modifiedAt = now
            self.attributes = attributes
        }

        func clone() -> FileNode {
            let cloned = FileNode(data: data, attributes: attributes)
            cloned.createdAt = createdAt
            cloned.modifiedAt = modifiedAt
            return cloned
        }
    }

    final class DirectoryNode {
        var children: [String: Node]
        var createdAt: Date
        var modifiedAt: Date
        var attributes: [String: String]

        init(attributes: [String: String] = [:]) {
            self.children = [:]
            let now = Date()
            self.createdAt = now
            self.modifiedAt = now
            self.attributes = attributes
        }

        func clone() -> DirectoryNode {
            let cloned = DirectoryNode(attributes: attributes)
            cloned.createdAt = createdAt
            cloned.modifiedAt = modifiedAt
            for (key, child) in children {
                cloned.children[key] = child.clone()
            }
            return cloned
        }
    }

    enum Node {
        case file(FileNode)
        case directory(DirectoryNode)

        func clone() -> Node {
            switch self {
            case .file(let fileNode):
                return .file(fileNode.clone())
            case .directory(let dirNode):
                return .directory(dirNode.clone())
            }
        }
    }

    let lock = NSLock()
    var root: DirectoryNode

    public init() {
        self.root = DirectoryNode()
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        self.root = DirectoryNode()
    }

    func findNode(components: [String]) -> Node? {
        var current = Node.directory(root)
        for component in components {
            guard case .directory(let dirNode) = current else {
                return nil
            }
            guard let next = dirNode.children[component] else {
                return nil
            }
            current = next
        }
        return current
    }

    func findDirectory(components: [String]) -> DirectoryNode? {
        guard let node = findNode(components: components) else {
            return nil
        }
        guard case .directory(let dirNode) = node else {
            return nil
        }
        return dirNode
    }

    func normalize(path: String) throws -> [String] {
        guard !path.isEmpty else {
            throw VirtualFileSystemError.invalidPath(path)
        }
        let clean = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var segments: [String] = []
        for part in clean.split(separator: "/") {
            if part.isEmpty || part == "." {
                continue
            }
            if part == ".." {
                guard !segments.isEmpty else {
                    throw VirtualFileSystemError.invalidPath(path)
                }
                segments.removeLast()
            } else {
                segments.append(String(part))
            }
        }
        return segments
    }

    public func fileExists(atPath path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let components = try? normalize(path: path) else {
            return false
        }
        if components.isEmpty {
            return true
        }
        return findNode(components: components) != nil
    }

    public func isDirectory(atPath path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let components = try? normalize(path: path) else {
            return false
        }
        if components.isEmpty {
            return true
        }
        guard let node = findNode(components: components) else {
            return false
        }
        if case .directory = node {
            return true
        }
        return false
    }
}
