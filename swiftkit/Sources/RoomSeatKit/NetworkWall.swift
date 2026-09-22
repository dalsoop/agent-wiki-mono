import Foundation

/// 방 네트워크 벽. 옛 JSON `true`/`false` 는 그대로 읽는다.
public enum NetworkWall: Equatable, Sendable {
    case closed
    case allow(domains: [String])
    case open

    public var modeName: String {
        switch self {
        case .closed: return "closed"
        case .allow: return "allow"
        case .open: return "open"
        }
    }

    public var allowedDomains: [String] {
        switch self {
        case .allow(let domains): return domains
        case .closed, .open: return []
        }
    }

    public var deniedDomains: [String] {
        switch self {
        case .closed: return ["*"]
        case .open, .allow: return []
        }
    }

    public var allowLocalBinding: Bool {
        switch self {
        case .open: return true
        case .closed, .allow: return false
        }
    }

    public var isFullyOpen: Bool {
        if case .open = self { return true }
        return false
    }

    public var isClosed: Bool {
        if case .closed = self { return true }
        return false
    }

    /// 정확 일치 또는 `*.example.com` 접미사.
    public func allows(host: String) -> Bool {
        switch self {
        case .open:
            return true
        case .closed:
            return false
        case .allow(let domains):
            return Self.host(host, matches: domains)
        }
    }

    public func intersection(_ child: NetworkWall) -> NetworkWall {
        switch (self, child) {
        case (.closed, _), (_, .closed):
            return .closed
        case (.open, let other):
            return other
        case (let other, .open):
            return other
        case (.allow(let parentDomains), .allow(let childDomains)):
            let kept = childDomains.filter { Self.host($0, matches: parentDomains) }
            return .allow(domains: kept)
        }
    }

    /// 자식이 부모보다 넓은가. 부모가 닫혀 있는데 자식이 열리거나, allow 목록이 부모를 넘으면 true.
    public static func childExceedsParent(child: NetworkWall, parent: NetworkWall) -> Bool {
        switch (parent, child) {
        case (_, .closed):
            return false
        case (.open, _):
            return false
        case (.closed, .open), (.closed, .allow):
            return true
        case (.allow, .open):
            return true
        case (.allow(let parentDomains), .allow(let childDomains)):
            return childDomains.contains { !host($0, matches: parentDomains) }
        }
    }

    public static func parse(_ raw: Any?) -> NetworkWall? {
        if raw == nil { return nil }
        if let flag = raw as? Bool {
            return flag ? .open : .closed
        }
        if let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? .open : .closed
        }
        if let name = raw as? String {
            switch name {
            case "open": return .open
            case "closed": return .closed
            default: return nil
            }
        }
        guard let object = raw as? [String: Any] else { return nil }
        let mode = object["mode"] as? String
        let domains = object["domains"] as? [String] ?? []
        switch mode {
        case "open": return .open
        case "closed": return .closed
        case "allow", .none:
            return .allow(domains: domains)
        default:
            return nil
        }
    }

    public static func host(_ host: String, matches patterns: [String]) -> Bool {
        let name = normalizedHost(host)
        guard !name.isEmpty else { return false }
        for pattern in patterns {
            let needle = normalizedHost(pattern)
            if needle.hasPrefix("*.") {
                let suffix = String(needle.dropFirst(1))
                if name.hasSuffix(suffix), name != String(suffix.dropFirst()) {
                    return true
                }
            } else if name == needle {
                return true
            }
        }
        return false
    }

    public static func normalizedHost(_ raw: String) -> String {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasPrefix("[") {
            if let close = host.firstIndex(of: "]") {
                host = String(host[host.index(after: host.startIndex)..<close])
            }
        } else if let colon = host.lastIndex(of: ":"),
                  host[host.index(after: colon)...].allSatisfy(\.isNumber) {
            host = String(host[..<colon])
        }
        return host
    }
}

extension NetworkWall: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = value ? .open : .closed
    }
}

extension NetworkWall: Codable {
    enum CodingKeys: String, CodingKey {
        case mode
        case domains
        case allowedDomains
        case deniedDomains
        case allowLocalBinding
    }

    private struct ObjectWire: Decodable {
        var mode: String?
        var domains: [String]?
        var allowedDomains: [String]?
        var deniedDomains: [String]?
        var allowLocalBinding: Bool?
    }

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .closed
            return
        }
        guard let flag = try? single.decode(Bool.self) else {
            guard let name = try? single.decode(String.self) else {
                let wire = try single.decode(ObjectWire.self)
                switch wire.mode ?? "allow" {
                case "open":
                    self = .open
                case "closed":
                    self = .closed
                default:
                    let d = wire.allowedDomains ?? wire.domains ?? []
                    if d.isEmpty && wire.mode != "allow" {
                        self = .closed
                    } else {
                        self = .allow(domains: d)
                    }
                }
                return
            }
            switch name {
            case "open":
                self = .open
            case "closed":
                self = .closed
            default:
                throw DecodingError.dataCorruptedError(
                    in: single,
                    debugDescription: "unknown NetworkWall \(name)"
                )
            }
            return
        }
        self = flag ? .open : .closed
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .closed:
            var container = encoder.singleValueContainer()
            try container.encode(false)
        case .open:
            var container = encoder.singleValueContainer()
            try container.encode(true)
        case .allow(let domains):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("allow", forKey: .mode)
            try container.encode(domains, forKey: .domains)
            try container.encode(domains, forKey: .allowedDomains)
        }
    }
}
