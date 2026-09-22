import Foundation

/// 개인정보 보존기간. Service Mailer 가 로컬로 갖고 있던 1095일(3년) 규칙을 Kit 으로 올린다.
/// 메일러 소스는 이 타입이 생기기 전 값을 유지하고, 신규 소비자는 여기만 본다.
public struct PIIRetentionPolicy: Sendable, Equatable, Codable {
    public var retentionDays: Int

    /// 개인정보보호법 보관 기간 기본값 — 3년.
    public static let legalRetentionDays = 1095
    public static let secondsPerDay: TimeInterval = 86_400
    public static let legalDefault = PIIRetentionPolicy(retentionDays: legalRetentionDays)

    public init(retentionDays: Int = PIIRetentionPolicy.legalRetentionDays) {
        self.retentionDays = max(0, retentionDays)
    }

    public func expirationDate(from createdAt: Date) -> Date {
        createdAt.addingTimeInterval(TimeInterval(retentionDays) * Self.secondsPerDay)
    }

    public func isExpired(createdAt: Date, now: Date = Date()) -> Bool {
        now >= expirationDate(from: createdAt)
    }

    /// `ada@example.com` → `a**@example.com`. 로컬 파트가 한 글자면 `*@domain`.
    public func maskEmail(_ email: String) -> String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let at = trimmed.firstIndex(of: "@") else { return maskName(trimmed) }
        let local = String(trimmed[..<at])
        let domain = String(trimmed[trimmed.index(after: at)...])
        let maskedLocal: String
        if local.count <= 1 {
            maskedLocal = "*"
        } else {
            maskedLocal = String(local.prefix(1)) + String(repeating: "*", count: local.count - 1)
        }
        return "\(maskedLocal)@\(domain)"
    }

    /// 첫 글자만 남기고 나머지를 `*` 로. 한 글자면 `*`.
    public func maskName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.count == 1 { return "*" }
        return String(trimmed.prefix(1)) + String(repeating: "*", count: trimmed.count - 1)
    }

    public func displayEmail(_ email: String, createdAt: Date?, now: Date = Date()) -> String {
        guard let createdAt, isExpired(createdAt: createdAt, now: now) else { return email }
        return maskEmail(email)
    }

    public func displayName(_ name: String, createdAt: Date?, now: Date = Date()) -> String {
        guard let createdAt, isExpired(createdAt: createdAt, now: now) else { return name }
        return maskName(name)
    }
}
