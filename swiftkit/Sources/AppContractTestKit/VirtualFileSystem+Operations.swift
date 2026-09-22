import Foundation

extension VirtualFileSystem {
    public func createDirectory(atPath path: String, withIntermediateDirectories: Bool = true) throws {
        lock.lock()
        defer { lock.unlock() }

        let components = try normalize(path: path)
        if components.isEmpty {
            return
        }

        var current = root
        for (index, component) in components.enumerated() {
            let isLast = index == components.count - 1
            if let existing = current.children[component] {
                guard case .directory(let dir) = existing else {
                    throw VirtualFileSystemError.notADirectory(path)
                }
                guard !isLast || withIntermediateDirectories else {
                    throw VirtualFileSystemError.alreadyExists(path)
                }
                current = dir
            } else {
                guard isLast || withIntermediateDirectories else {
                    throw VirtualFileSystemError.directoryNotFound(path)
                }
                let newDir = DirectoryNode()
                current.children[component] = .directory(newDir)
                current = newDir
            }
        }
    }

    public func createFile(atPath path: String, contents: Data? = nil, attributes: [String: String] = [:]) throws {
        lock.lock()
        defer { lock.unlock() }

        let components = try normalize(path: path)
        guard let fileName = components.last else {
            throw VirtualFileSystemError.invalidPath(path)
        }
        let dirComponents = Array(components.dropLast())

        guard let parentDir = findDirectory(components: dirComponents) else {
            throw VirtualFileSystemError.directoryNotFound(path)
        }

        if parentDir.children[fileName] != nil {
            throw VirtualFileSystemError.alreadyExists(path)
        }

        let fileNode = FileNode(data: contents ?? Data(), attributes: attributes)
        parentDir.children[fileName] = .file(fileNode)
    }

    public func writeFile(atPath path: String, data: Data, createIntermediateDirectories: Bool = true) throws {
        lock.lock()
        defer { lock.unlock() }

        let components = try normalize(path: path)
        guard let fileName = components.last else {
            throw VirtualFileSystemError.invalidPath(path)
        }
        let dirComponents = Array(components.dropLast())

        if createIntermediateDirectories {
            try createDirectoryUnsafe(components: dirComponents)
        }

        guard let parentDir = findDirectory(components: dirComponents) else {
            throw VirtualFileSystemError.directoryNotFound(path)
        }

        if let existing = parentDir.children[fileName] {
            switch existing {
            case .file(let fileNode):
                fileNode.data = data
                fileNode.modifiedAt = Date()
            case .directory:
                throw VirtualFileSystemError.isDirectory(path)
            }
        } else {
            let fileNode = FileNode(data: data)
            parentDir.children[fileName] = .file(fileNode)
        }
    }

    public func readFile(atPath path: String) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        let components = try normalize(path: path)
        guard let node = findNode(components: components) else {
            throw VirtualFileSystemError.fileNotFound(path)
        }
        guard case .file(let fileNode) = node else {
            throw VirtualFileSystemError.isDirectory(path)
        }
        return fileNode.data
    }

    public func removeItem(atPath path: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let components = try normalize(path: path)
        guard let targetName = components.last else {
            throw VirtualFileSystemError.cannotRemoveRoot
        }
        let dirComponents = Array(components.dropLast())

        guard let parentDir = findDirectory(components: dirComponents) else {
            throw VirtualFileSystemError.fileNotFound(path)
        }
        guard parentDir.children.removeValue(forKey: targetName) != nil else {
            throw VirtualFileSystemError.fileNotFound(path)
        }
    }

    private func createDirectoryUnsafe(components: [String]) throws {
        var current = root
        for component in components {
            if let existing = current.children[component] {
                switch existing {
                case .directory(let dir):
                    current = dir
                case .file:
                    throw VirtualFileSystemError.notADirectory(component)
                }
            } else {
                let newDir = DirectoryNode()
                current.children[component] = .directory(newDir)
                current = newDir
            }
        }
    }
}
