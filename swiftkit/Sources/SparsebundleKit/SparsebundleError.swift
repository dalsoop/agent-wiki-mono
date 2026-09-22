import Foundation

/// Sparsebundle 가상 디스크 조작 중 발생하는 오류
public enum SparsebundleError: LocalizedError, Sendable, Equatable {
    case createFailed(String)
    case attachFailed(String)
    case detachFailed(String)
    case mountPointNotFound(String)
    case invalidURL(URL)
    case compactFailed(String)

    public var errorDescription: String? {
        switch self {
        case .createFailed(let reason):
            return "Failed to create sparsebundle: \(reason)"
        case .attachFailed(let reason):
            return "Failed to attach sparsebundle: \(reason)"
        case .detachFailed(let reason):
            return "Failed to detach sparsebundle: \(reason)"
        case .mountPointNotFound(let reason):
            return "Mount point not found: \(reason)"
        case .invalidURL(let url):
            return "Invalid sparsebundle URL: \(url.path)"
        case .compactFailed(let reason):
            return "Failed to compact sparsebundle: \(reason)"
        }
    }
}
