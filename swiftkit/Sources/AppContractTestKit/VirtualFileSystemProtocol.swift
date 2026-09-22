import Foundation

public enum VirtualFileSystemError: Error, Equatable, Sendable {
    case invalidPath(String)
    case fileNotFound(String)
    case directoryNotFound(String)
    case alreadyExists(String)
    case notADirectory(String)
    case isDirectory(String)
    case cannotRemoveRoot
    case stringEncodingFailed
}

public protocol VirtualFileSystemProtocol {
    func fileExists(atPath path: String) -> Bool
    func isDirectory(atPath path: String) -> Bool
    func createDirectory(atPath path: String, withIntermediateDirectories: Bool) throws
    func createFile(atPath path: String, contents: Data?, attributes: [String: String]) throws
    func writeFile(atPath path: String, data: Data, createIntermediateDirectories: Bool) throws
    func readFile(atPath path: String) throws -> Data
    func removeItem(atPath path: String) throws
    func copyItem(atPath srcPath: String, toPath dstPath: String) throws
    func moveItem(atPath srcPath: String, toPath dstPath: String) throws
    func contentsOfDirectory(atPath path: String) throws -> [String]
    func subpaths(atPath path: String) throws -> [String]
    func fileSize(atPath path: String) throws -> Int
    func reset()
}

extension VirtualFileSystemProtocol {
    public func writeString(atPath path: String, content: String, createIntermediateDirectories: Bool = true) throws {
        guard let data = content.data(using: .utf8) else {
            throw VirtualFileSystemError.stringEncodingFailed
        }
        try writeFile(atPath: path, data: data, createIntermediateDirectories: createIntermediateDirectories)
    }

    public func readString(atPath path: String) throws -> String {
        let data = try readFile(atPath: path)
        guard let string = String(data: data, encoding: .utf8) else {
            throw VirtualFileSystemError.stringEncodingFailed
        }
        return string
    }
}
