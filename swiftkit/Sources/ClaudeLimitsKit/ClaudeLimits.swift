import Foundation
import LocalAuthentication
import Security

// MARK: - 서버 진짜 rate-limit (claude-monitor 방식) — 앱 공용 SSOT
//
// 우선순위:
// 1) /v1/messages 최소 ping → anthropic-ratelimit-unified-* 헤더
// 2) /api/oauth/usage (OAuth, 강하게 rate-limit 됨)
// 3) ~/.claude.json cachedUsageUtilization (Claude Code 가 남긴 로컬 캐시)
//
// 일부 org 는 messages 에 OAuth 를 막아 403 oauth_not_allowed_for_organization.
// 그때는 2→3 으로 폴백한다.

/// Anthropic unified rate-limit 스냅샷.
public struct ServerLimits: Sendable, Equatable, Codable {
    public let fiveHourUtilization: Double   // 0.0–1.0
    public let fiveHourReset: Date
    public let sevenDayUtilization: Double
    public let sevenDayReset: Date
    public let status: String                // allowed / allowed_warning / rejected / cached …
    public let fetchedAt: Date
    /// 데이터 출처 (ui/debug 용).
    public let source: String

    public init(
        fiveHourUtilization: Double,
        fiveHourReset: Date,
        sevenDayUtilization: Double,
        sevenDayReset: Date,
        status: String,
        fetchedAt: Date,
        source: String = "messages"
    ) {
        self.fiveHourUtilization = fiveHourUtilization
        self.fiveHourReset = fiveHourReset
        self.sevenDayUtilization = sevenDayUtilization
        self.sevenDayReset = sevenDayReset
        self.status = status
        self.fetchedAt = fetchedAt
        self.source = source
    }

    /// 두 창(5h/7d) 중 더 소진된 쪽의 사용률(0.0–1.0).
    public var maxUtilization: Double { max(fiveHourUtilization, sevenDayUtilization) }

    /// headroom = 100 − max(5h%, 7d%).
    public var headroomPercent: Int {
        max(0, 100 - Int((maxUtilization * 100).rounded()))
    }
}

public enum ServerLimitsError: Error, CustomStringConvertible, Sendable {
    case noCredentials
    case badResponse(String)

    public var description: String {
        switch self {
        case .noCredentials: return "no Claude Code OAuth credentials (Keychain/.credentials.json)"
        case .badResponse(let s): return "bad response: \(s)"
        }
    }
}

/// Claude Code 의 OAuth 자격증명으로 unified rate-limit 을 조회한다.
public struct ServerLimitsProbe {
    /// ~/.claude/.credentials.json → Keychain("Claude Code-credentials") 순으로 accessToken 을 찾는다.
    /// 파일 정본이 있으면 headless CLI가 잠긴 Keychain을 건드리지 않는다.
    public static func accessToken(allowKeychain: Bool = true) -> String? {
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/.claude/.credentials.json")
        do {
            let data = try Data(contentsOf: url)
            if let token = parseToken(data) {
                return token
            }
        } catch {}
        guard allowKeychain else { return nil }
        if let data = keychainItem(service: "Claude Code-credentials"),
           let token = parseToken(data) {
            return token
        }
        return nil
    }

    private static func keychainItem(service: String) -> Data? {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            // CLI/백그라운드 probe에서 Keychain 인증 UI를 기다리면 weekly refresh가
            // 무기한 멈춘다. 접근 불가면 즉시 파일 fallback으로 넘어간다.
            kSecUseAuthenticationContext as String: context,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    private static func parseToken(_ data: Data) -> String? {
        guard let obj = ClaudeJSON.object(from: data),
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        return token
    }

    /// 0–1 또는 0–100 스케일 정규화.
    private static func normalizeUtil(_ v: Double) -> Double {
        let x = v > 1.5 ? v / 100 : v
        return max(0, min(1, x))
    }

    /// 최소 비용 ping / oauth usage / 로컬 캐시 순.
    public static func fetch(
        token: String? = nil,
        allowKeychainFallback: Bool = true
    ) async throws -> ServerLimits {
        guard let token = token ?? accessToken(allowKeychain: allowKeychainFallback) else {
            throw ServerLimitsError.noCredentials
        }

        // 1) messages 헤더
        do {
            return try await fetchFromMessages(token: token)
        } catch {
            // 2) oauth usage (live token 과 같을 때만 — 계정 혼동 방지)
            if token == accessToken(allowKeychain: allowKeychainFallback) {
                do {
                    return try await fetchFromOAuthUsage(token: token)
                } catch {}
            }
            // 3) Claude Code 로컬 캐시 (live 계정)
            if token == accessToken(allowKeychain: allowKeychainFallback),
               let cached = readLocalUsageCache() {
                return cached
            }
            throw error
        }
    }

    // MARK: - 1) messages ping

    private static func fetchFromMessages(token: String) async throws -> ServerLimits {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Claude Code 정체성 — OAuth 풀 라우팅에 system 문구가 필요하다는 보고 반영.
        req.setValue("claude-code-20250219,oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("cli", forHTTPHeaderField: "x-app")
        req.setValue("claude-cli/2.1.75 (external, cli)", forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1,
            "system": "You are Claude Code, Anthropic's official CLI for Claude.",
            "messages": [["role": "user", "content": "1"]],
        ])
        req.timeoutInterval = 20

        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw ServerLimitsError.badResponse("no HTTP response")
        }
        func header(_ name: String) -> String? {
            http.value(forHTTPHeaderField: name)
        }
        guard let u5 = header("anthropic-ratelimit-unified-5h-utilization").flatMap(Double.init),
              let r5 = header("anthropic-ratelimit-unified-5h-reset").flatMap(Double.init),
              let u7 = header("anthropic-ratelimit-unified-7d-utilization").flatMap(Double.init),
              let r7 = header("anthropic-ratelimit-unified-7d-reset").flatMap(Double.init)
        else {
            throw ServerLimitsError.badResponse("missing unified rate-limit headers (HTTP \(http.statusCode))")
        }
        return ServerLimits(
            fiveHourUtilization: normalizeUtil(u5),
            fiveHourReset: Date(timeIntervalSince1970: r5),
            sevenDayUtilization: normalizeUtil(u7),
            sevenDayReset: Date(timeIntervalSince1970: r7),
            status: header("anthropic-ratelimit-unified-status") ?? "unknown",
            fetchedAt: Date(),
            source: "messages"
        )
    }

    // MARK: - 2) /api/oauth/usage

    private static func fetchFromOAuthUsage(token: String) async throws -> ServerLimits {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("cli", forHTTPHeaderField: "x-app")
        req.setValue("claude-cli/2.1.75 (external, cli)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw ServerLimitsError.badResponse("oauth usage HTTP \(code)")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = parseUsageObject(obj) else {
            throw ServerLimitsError.badResponse("oauth usage parse failed")
        }
        return limits
    }

    /// usage JSON 또는 cachedUsageUtilization.utilization 형태 파싱.
    private static func parseUsageObject(_ root: [String: Any]) -> ServerLimits? {
        // 직접 five_hour / seven_day
        let util = (root["utilization"] as? [String: Any]) ?? root
        guard let five = util["five_hour"] as? [String: Any] ?? util["fiveHour"] as? [String: Any],
              let seven = util["seven_day"] as? [String: Any] ?? util["sevenDay"] as? [String: Any]
        else { return nil }

        let u5raw = (five["utilization"] as? Double) ?? (five["utilization"] as? Int).map(Double.init)
        let u7raw = (seven["utilization"] as? Double) ?? (seven["utilization"] as? Int).map(Double.init)
        guard let u5raw, let u7raw else { return nil }

        let r5 = parseISODate(five["resets_at"] as? String ?? five["resetsAt"] as? String)
            ?? Date().addingTimeInterval(5 * 3600)
        let r7 = parseISODate(seven["resets_at"] as? String ?? seven["resetsAt"] as? String)
            ?? Date().addingTimeInterval(7 * 86400)

        return ServerLimits(
            fiveHourUtilization: normalizeUtil(u5raw),
            fiveHourReset: r5,
            sevenDayUtilization: normalizeUtil(u7raw),
            sevenDayReset: r7,
            status: "cached",
            fetchedAt: Date(),
            source: "oauth-usage"
        )
    }

    // MARK: - 3) ~/.claude.json 캐시

    /// Claude Code 가 남긴 로컬 usage 캐시. live 계정 전용.
    public static func readLocalUsageCache(
        path: String = NSHomeDirectory() + "/.claude.json"
    ) -> ServerLimits? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let root = ClaudeJSON.object(from: data),
              let wrap = root["cachedUsageUtilization"] as? [String: Any]
        else { return nil }

        let fetchedAt: Date = {
            if let ms = wrap["fetchedAtMs"] as? Double {
                return Date(timeIntervalSince1970: ms / 1000)
            }
            if let ms = wrap["fetchedAtMs"] as? Int {
                return Date(timeIntervalSince1970: Double(ms) / 1000)
            }
            return Date()
        }()

        guard let util = wrap["utilization"] as? [String: Any],
              let limits = parseUsageObject(util) else { return nil }

        // source 를 local-cache 로 덮어쓴 값 반환
        return ServerLimits(
            fiveHourUtilization: limits.fiveHourUtilization,
            fiveHourReset: limits.fiveHourReset,
            sevenDayUtilization: limits.sevenDayUtilization,
            sevenDayReset: limits.sevenDayReset,
            status: "local-cache",
            fetchedAt: fetchedAt,
            source: "claude.json"
        )
    }

    private static func parseISODate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: raw) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: raw)
    }
}
