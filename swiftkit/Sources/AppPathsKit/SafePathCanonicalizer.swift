import Foundation

// MARK: - Safe Path Canonicalizer Errors

public enum SafePathError: Error, Sendable, Equatable {
    case outsideBoundary(attempted: String, boundary: String)
    case unresolvablePath(String)
    case traversalDetected(String)
    case symlinkEscapeDetected(link: String, target: String)
}

// MARK: - Safe Path Canonicalizer

/// Docker/Kubernetes `filepath-securejoin` 및 POSIX `realpath` 철학을 결합한
/// 파일 시스템 샌드박스 경계 탈출(Directory Traversal & Symlink Escape) 방어 도구
public struct SafePathCanonicalizer: Sendable {

    /// 기준 디렉터리(`boundary`) 밖으로 탈출하지 않도록 상대 또는 절대 경로를 안전하게 해석
    ///
    /// - Parameters:
    ///   - boundary: 격리 기준 디렉터리 URL
    ///   - path: 검사 대상 경로 (상대 또는 절대)
    /// - Returns: 정규화 및 심볼릭 링크 해석이 완료된 안전한 절대 경로 URL
    /// - Throws: `SafePathError` (경계 탈출, 트래버설, 미해석 등)
    public static func resolveWithin(boundary: URL, path: String) throws -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let boundaryReal = try canonicalPath(for: boundary)
        guard !trimmed.isEmpty else { return boundaryReal }

        if trimmed.hasPrefix("/") {
            return try resolveAbsolutePath(trimmed, boundaryReal: boundaryReal)
        }
        return try resolveRelativePath(trimmed, boundaryReal: boundaryReal)
    }

    private static func resolveAbsolutePath(_ path: String, boundaryReal: URL) throws -> URL {
        let targetURL = URL(fileURLWithPath: path).standardizedFileURL
        let targetReal = try canonicalPath(for: targetURL)
        guard isPathPrefixMatch(child: targetReal.path, parent: boundaryReal.path) else {
            throw SafePathError.outsideBoundary(attempted: targetReal.path, boundary: boundaryReal.path)
        }
        return targetReal
    }

    private static func resolveRelativePath(_ path: String, boundaryReal: URL) throws -> URL {
        let normalizedRelativePath = try normalizeRelativeStack(path)
        let candidateURL = boundaryReal.appendingPathComponent(normalizedRelativePath)
        let resolvedReal = try canonicalPath(for: candidateURL)

        guard isPathPrefixMatch(child: resolvedReal.path, parent: boundaryReal.path) else {
            throw SafePathError.outsideBoundary(attempted: resolvedReal.path, boundary: boundaryReal.path)
        }
        return resolvedReal
    }

    private static func normalizeRelativeStack(_ path: String) throws -> String {
        var stack: [String] = []
        let parts = path.split(separator: "/")
        for part in parts {
            switch part {
            case ".", "":
                continue
            case "..":
                guard !stack.isEmpty else {
                    throw SafePathError.traversalDetected(path)
                }
                stack.removeLast()
            default:
                stack.append(String(part))
            }
        }
        return stack.joined(separator: "/")
    }

    /// 파일 또는 디렉터리가 주어진 boundary 내부에 안전하게 존재하는지 검증
    public static func isWithinBoundary(candidate: URL, boundary: URL) -> Bool {
        do {
            _ = try resolveWithin(boundary: boundary, path: candidate.path)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Internal Realpath Helpers

    /// POSIX `realpath`를 사용하여 심볼릭 링크가 완전히 풀린 물리적 경로 도출
    /// 대상이 아직 존재하지 않는 파일인 경우, 존재하는 가장 가까운 부모 디렉터리를 찾아 해석 후 결합
    public static func canonicalPath(for url: URL) throws -> URL {
        let standardized = url.standardizedFileURL
        let path = standardized.path

        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if realpath(path, &buffer) != nil {
            return URL(fileURLWithPath: cStringToString(buffer), isDirectory: isDirectory(path: path))
        }

        // 아직 존재하지 않는 파일인 경우: 부모 경로를 재귀적으로 추적하여 정규화
        var missingComponents: [String] = []
        var current = standardized

        while current.path != "/" && !FileManager.default.fileExists(atPath: current.path) {
            missingComponents.insert(current.lastPathComponent, at: 0)
            current = current.deletingLastPathComponent()
        }

        if realpath(current.path, &buffer) != nil {
            var resolved = URL(fileURLWithPath: cStringToString(buffer), isDirectory: true)
            for comp in missingComponents {
                resolved = resolved.appendingPathComponent(comp)
            }
            return resolved.standardizedFileURL
        }

        throw SafePathError.unresolvablePath(path)
    }

    /// child 경로가 parent 경로 내부(동일하거나 하위)에 있는지 판정
    private static func isPathPrefixMatch(child: String, parent: String) -> Bool {
        if child == parent { return true }
        let parentWithSlash = parent.hasSuffix("/") ? parent : parent + "/"
        return child.hasPrefix(parentWithSlash)
    }

    private static func isDirectory(path: String) -> Bool {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            return isDir.boolValue
        }
        return false
    }

    private static func cStringToString(_ buffer: [CChar]) -> String {
        let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
