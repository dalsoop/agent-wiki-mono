import Foundation

/// 플러그인이 실행할 수 있는 **실재하는 CLI 서브커맨드 토큰**.
///
/// 왜 타입인가: `AppPlugin.actions` 가 `[String]` 이던 동안 `"secret.get"` 같은 점 찍힌
/// 가상 이름이 카탈로그에 실렸다. 소비자는 그 명령이 있다고 믿고 부르는데 argv 에는
/// 그런 서브커맨드가 없다 — 컴파일도 실행도 통과하고, 부르는 순간에야 틀린다.
/// `no-dotted-action-in-plugin` 린트가 그걸 텍스트로 잡아왔지만, 린트는 새 위반이
/// 들어온 **뒤에** 짖는다.
///
/// 이 타입은 `ExpressibleByStringLiteral` 을 **일부러 채택하지 않는다**. 그래서
/// `actions: ["secret.get"]` 은 린트 소견이 아니라 **컴파일 에러**가 된다. 토큰은
/// `PluginAction(validating:)` 를 통과해야만 만들어진다.
public struct PluginAction: Hashable, Sendable, CustomStringConvertible {
    /// 소유 CLI 의 argv 에 그대로 실리는 순정 서브커맨드 토큰.
    public let token: String

    public var description: String { token }

    /// 토큰이 서브커맨드로 성립하지 못하는 사유.
    public enum Invalid: Error, Equatable, CustomStringConvertible {
        case empty
        /// 점이 들어간 가상 이름(`secret.get`). 실제 argv 에 그런 토큰은 없다.
        case dotted(String)
        /// 공백이 들어가면 argv 한 칸이 아니라 두 칸이다.
        case whitespace(String)
        /// `-` 로 시작하면 서브커맨드가 아니라 플래그로 파싱된다.
        case looksLikeFlag(String)
        /// argv 토큰에 쓸 수 없는 문자.
        case unsupportedCharacter(String, Character)

        public var description: String {
            switch self {
            case .empty:
                return "빈 문자열은 서브커맨드가 아니다"
            case .dotted(let raw):
                return "'\(raw)' — 점 찍힌 가상 이름이다. 소유 CLI 에 실재하는 토큰"
                    + "(예: '\(raw.split(separator: ".").last.map(String.init) ?? raw)')을 쓴다"
            case .whitespace(let raw):
                return "'\(raw)' — 공백이 있으면 argv 한 칸이 아니다"
            case .looksLikeFlag(let raw):
                return "'\(raw)' — '-' 로 시작하면 서브커맨드가 아니라 플래그로 파싱된다"
            case .unsupportedCharacter(let raw, let ch):
                return "'\(raw)' — argv 토큰에 쓸 수 없는 문자 '\(ch)'"
            }
        }
    }

    /// argv 토큰으로 성립하는 문자: 영숫자와 `-`, `_`.
    /// 서브커맨드 이름에 실제로 쓰이는 글자만 통과시킨다.
    private static let allowedPunctuation: Set<Character> = ["-", "_"]

    private static func isSupported(_ ch: Character) -> Bool {
        guard ch.isASCII else { return false }
        if ch.isLetter { return true }
        if ch.isNumber { return true }
        return allowedPunctuation.contains(ch)
    }

    public init(validating raw: String) throws {
        guard !raw.isEmpty else { throw Invalid.empty }
        if raw.contains(".") { throw Invalid.dotted(raw) }
        if raw.contains(where: { $0.isWhitespace }) { throw Invalid.whitespace(raw) }
        if raw.hasPrefix("-") { throw Invalid.looksLikeFlag(raw) }
        if let bad = raw.first(where: { !Self.isSupported($0) }) {
            throw Invalid.unsupportedCharacter(raw, bad)
        }
        self.token = raw
    }

    /// 읽기 좋은 별칭 — `try PluginAction.subcommand("get")`.
    public static func subcommand(_ raw: String) throws -> PluginAction {
        try PluginAction(validating: raw)
    }

    /// CLI `capabilities --json` 처럼 **밖에서 들어온** 이름 목록을 받을 때 쓴다.
    /// 성립하지 않는 이름은 조용히 버리지 않고 `rejected` 로 돌려준다 — 카탈로그에
    /// 실리지 않은 이유를 부르는 쪽이 말할 수 있어야 한다.
    public static func partition(_ raws: [String])
        -> (accepted: [PluginAction], rejected: [(raw: String, reason: Invalid)])
    {
        var accepted: [PluginAction] = []
        var rejected: [(raw: String, reason: Invalid)] = []
        for raw in raws {
            do {
                accepted.append(try PluginAction(validating: raw))
            } catch let reason as Invalid {
                rejected.append((raw, reason))
            } catch {
                rejected.append((raw, .empty))
            }
        }
        return (accepted, rejected)
    }
}

extension PluginAction: Codable {
    /// 디코딩도 같은 문을 지난다 — JSON 카탈로그로 점 찍힌 이름이 우회해 들어오지 못한다.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        try self.init(validating: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(token)
    }
}
