import Foundation
import LocalizationKit

public struct LocalGujoWebCheck: Equatable, Sendable {
    public let statusCode: Int?
    public let errorMessage: String?

    public init(statusCode: Int?, errorMessage: String?) {
        self.statusCode = statusCode
        self.errorMessage = errorMessage
    }

    public var isReachable: Bool {
        guard let statusCode else { return false }
        return (200..<500).contains(statusCode)
    }
}

public enum LocalGujoWebState: Equatable, Sendable {
    case unknown
    case reachable
    case unavailable
}

public struct LocalGujoWebStatus: Equatable, Sendable {
    public let state: LocalGujoWebState
    public let url: URL?
    public let message: String

    public init(state: LocalGujoWebState, url: URL?, message: String) {
        self.state = state
        self.url = url
        self.message = message
    }

    public static let unknown = LocalGujoWebStatus(state: .unknown, url: nil, message: CLILocalization.string("session.msg.not_checked"))
}

public struct LocalGujoWebProbe: Sendable {
    public static let defaultCandidates: [URL] = ServiceEndpoints.gujoWebCandidates

    private let candidates: [URL]
    private let checker: @Sendable (URL) async -> LocalGujoWebCheck

    public init(candidates: [URL] = LocalGujoWebProbe.defaultCandidates) {
        self.candidates = candidates
        self.checker = { url in
            await LocalGujoWebProbe.check(url: url)
        }
    }

    public init(candidates: [URL], checker: @escaping @Sendable (URL) async -> LocalGujoWebCheck) {
        self.candidates = candidates
        self.checker = checker
    }

    public func detect() async -> LocalGujoWebStatus {
        var lastMessage = "응답하는 로컬 Gujo 웹을 찾지 못했습니다"
        for candidate in candidates {
            let result = await checker(candidate)
            if result.isReachable {
                let code = result.statusCode.map(String.init) ?? "응답"
                let message = CLILocalization.format(
                    "LocalGujoWebProbe.message", candidate.absoluteString, String(code))
                return LocalGujoWebStatus(state: .reachable, url: candidate, message: message)
            }
            if let error = result.errorMessage, !error.isEmpty {
                lastMessage = "\(candidate.absoluteString): \(error)"
            }
        }
        return LocalGujoWebStatus(state: .unavailable, url: nil, message: lastMessage)
    }

    private static func check(url: URL) async -> LocalGujoWebCheck {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = ServiceEndpoints.probeTimeout

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return LocalGujoWebCheck(statusCode: (response as? HTTPURLResponse)?.statusCode, errorMessage: nil)
        } catch {
            return LocalGujoWebCheck(statusCode: nil, errorMessage: error.localizedDescription)
        }
    }
}
