import Foundation

extension VirtualFileSystem {
    public func copyItem(atPath srcPath: String, toPath dstPath: String) throws {
        let data = try readFile(atPath: srcPath)
        try writeFile(atPath: dstPath, data: data, createIntermediateDirectories: true)
    }

    public func moveItem(atPath srcPath: String, toPath dstPath: String) throws {
        try copyItem(atPath: srcPath, toPath: dstPath)
        try removeItem(atPath: srcPath)
    }

    public func contentsOfDirectory(atPath path: String) throws -> [String] {
        lock.lock()
        defer { lock.unlock() }

        let components = try normalize(path: path)
        guard let node = findNode(components: components) else {
            throw VirtualFileSystemError.directoryNotFound(path)
        }
        guard case .directory(let dirNode) = node else {
            throw VirtualFileSystemError.notADirectory(path)
        }
        return Array(dirNode.children.keys).sorted()
    }

    public func subpaths(atPath path: String) throws -> [String] {
        lock.lock()
        defer { lock.unlock() }

        let components = try normalize(path: path)
        guard let node = findNode(components: components) else {
            throw VirtualFileSystemError.directoryNotFound(path)
        }
        guard case .directory(let dirNode) = node else {
            throw VirtualFileSystemError.notADirectory(path)
        }

        var results: [String] = []
        collectSubpaths(from: dirNode, prefix: "", results: &results)
        return results.sorted()
    }

    private func collectSubpaths(from dir: DirectoryNode, prefix: String, results: inout [String]) {
        for (name, child) in dir.children {
            let currentPath = prefix.isEmpty ? name : "\(prefix)/\(name)"
            results.append(currentPath)
            if case .directory(let subDir) = child {
                collectSubpaths(from: subDir, prefix: currentPath, results: &results)
            }
        }
    }

    public func fileSize(atPath path: String) throws -> Int {
        lock.lock()
        defer { lock.unlock() }

        let components = try normalize(path: path)
        guard let node = findNode(components: components) else {
            throw VirtualFileSystemError.fileNotFound(path)
        }
        guard case .file(let fileNode) = node else {
            throw VirtualFileSystemError.isDirectory(path)
        }
        return fileNode.data.count
    }
}
