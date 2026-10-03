import Foundation
import WikiLedgerKit

public enum LawExhibitError: Error, Equatable, CustomStringConvertible {
    case conflictingBytes(String)
    case notFound(String)

    public var description: String {
        switch self {
        case .conflictingBytes(let sha): return "같은 이름의 증거물에 다른 바이트: \(sha)"
        case .notFound(let sha): return "증거물 없음(로컬): \(sha)"
        }
    }
}

/// 증거물(원자료 바이트) — 이름이 곧 sha256. 한 번 쓰면 바꾸지 않는다(가림만 예외, 가림 작업이 맡는다).
/// 근거: docs/business-rules.md "용어"(증거물), docs/architecture.md "agent-law"(증거물 위치).
extension LawStore {
    /// `exhibits/<앞 2자>/<sha256>` 에 덮어쓰기 없이 둔다. 같은 바이트면 멱등.
    @discardableResult
    public func putExhibit(_ data: Data) throws -> String {
        let sha = LawHash.sha256Hex(data)
        let url = exhibitURL(sha256: sha)
        if let present = try? Data(contentsOf: url) {
            guard present == data else { throw LawExhibitError.conflictingBytes(sha) }
            return sha
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try data.write(to: url, options: [.withoutOverwriting])
        } catch {
            if let present = try? Data(contentsOf: url), present == data { return sha }
            throw error
        }
        return sha
    }

    public func exhibit(sha256: String) throws -> Data {
        guard LawHash.isContentID(sha256),
              let data = try? Data(contentsOf: exhibitURL(sha256: sha256)) else {
            throw LawExhibitError.notFound(sha256)
        }
        return data
    }
}
