import Foundation

/// `~/.ssh/config` 의 Host 항목 하나.
public struct SSHHost: Sendable, Equatable, Identifiable {
    public let alias: String        // 대표 별칭(첫 패턴)
    public let aliases: [String]    // 모든 별칭
    public let hostName: String?
    public let user: String?
    public let port: Int?
    public let identityFile: String?

    public init(alias: String, aliases: [String], hostName: String?, user: String?,
                port: Int?, identityFile: String?) {
        self.alias = alias; self.aliases = aliases; self.hostName = hostName
        self.user = user; self.port = port; self.identityFile = identityFile
    }

    public var id: String { alias }

    /// 표시용 "user@hostname:port"(정보가 있을 때만).
    public var displayTarget: String {
        var s = ""
        if let user, !user.isEmpty { s += user + "@" }
        s += hostName ?? alias
        if let port, port != 22 { s += ":\(port)" }
        return s
    }
}

/// `~/.ssh/config` 를 읽어 Host 목록으로. 접속은 `ssh <별칭>`(config 가 나머지 해석).
public struct SSHConfig: Sendable {
    public let path: String
    public init(path: String = NSHomeDirectory() + "/.ssh/config") { self.path = path }

    /// config 를 읽어 Host 목록(없으면 빈 배열).
    public func load() -> [SSHHost] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return Self.parse(text)
    }

    // MARK: - 순수 (테스트 대상)

    /// 와일드카드(`*`,`?`,`!`)가 아닌 실제 별칭인가.
    static func isConcrete(_ pattern: String) -> Bool {
        !pattern.isEmpty && !pattern.contains("*") && !pattern.contains("?") && !pattern.hasPrefix("!")
    }

    /// config 텍스트 → Host 목록. 와일드카드만인 블록은 건너뜀.
    public static func parse(_ text: String) -> [SSHHost] {
        var result: [SSHHost] = []
        var patterns: [String] = []
        var hostName: String?, user: String?, identity: String?
        var port: Int?

        func flush() {
            let concrete = patterns.filter(isConcrete)
            if let primary = concrete.first {
                result.append(SSHHost(alias: primary, aliases: concrete, hostName: hostName,
                                      user: user, port: port, identityFile: identity))
            }
            patterns = []; hostName = nil; user = nil; port = nil; identity = nil
        }

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            // "키 값" 또는 "키=값".
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "=" })
                .map(String.init).filter { !$0.isEmpty }
            guard let key = parts.first else { continue }
            let value = parts.dropFirst()

            switch key.lowercased() {
            case "host":
                flush()
                patterns = Array(value)
            case "hostname": hostName = value.first
            case "user":     user = value.first
            case "port":     port = value.first.flatMap { Int($0) }
            case "identityfile": identity = value.first
            default: break
            }
        }
        flush()
        return result
    }

    /// config 별칭 접속 argv(config 가 host/user/port/키 해석).
    public static func command(alias: String) -> [String] { ["ssh", alias] }

    /// 수동 접속: `[user@]host[:port]` → argv. 잘못되면 nil.
    public static func manualCommand(_ destination: String) -> [String]? {
        let d = destination.trimmingCharacters(in: .whitespaces)
        guard !d.isEmpty, !d.contains(" ") else { return nil }
        var userHost = d
        var port: Int?
        // 마지막 ":" 뒤가 숫자면 포트(IPv6 는 미지원 — 단순).
        if let colon = d.lastIndex(of: ":") {
            let maybePort = String(d[d.index(after: colon)...])
            if let p = Int(maybePort), !maybePort.isEmpty {
                port = p; userHost = String(d[..<colon])
            }
        }
        guard !userHost.isEmpty, !userHost.hasSuffix("@") else { return nil }
        var args = ["ssh"]
        if let port { args += ["-p", String(port)] }
        args.append(userHost)
        return args
    }
}
