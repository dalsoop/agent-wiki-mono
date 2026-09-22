import Foundation

/// 앱이 다른 앱 CLI 와 연동할 때 쓰는 유일한 표면.
/// 허브가 아니다. 제공자는 `--json` 으로 내고, 소비자는 여기 디코더만 부른다.
public enum AppCLIExchange {
    public enum ID {
        public static let tenantList = "app-cli-exchange.tenant.v1"
        public static let subscription = "app-cli-exchange.subscription.v1"
        public static let money = "app-cli-exchange.money.v1"

        public static let all: Set<String> = [tenantList, subscription, money]
    }

    /// `monthlyAmount` 등 호환 키를 받는 마지막 날. 다음날부터 거절한다.
    public static let legacyAmountCutoffDay = "2026-12-31"

    public static func requireKnownID(_ id: String) throws {
        guard ID.all.contains(id) else {
            throw AppCLIExchangeError.unknownID(id)
        }
    }

    public static func legacyMajorExpired(now: Date) -> Bool {
        CLIExchangeDay.fromISO(legacyAmountCutoffDay) < CLIExchangeDay.fromISO(
            CLIExchangeDay.addingDays(0, to: now)
        )
    }

    /// `capabilities.exchanges` 한 줄.
    public struct Advertised: Codable, Equatable, Sendable {
        public var id: String
        public var command: String
        public var result: String

        public init(id: String, command: String, result: String) {
            self.id = id
            self.command = command
            self.result = result
        }
    }

    public static func jsonData(from stdout: String) throws -> Data {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.firstIndex(where: { $0 == "{" || $0 == "[" }) {
            return Data(trimmed[start...].utf8)
        }
        throw AppCLIExchangeError.noJSON
    }

    public static func unwrap(_ stdout: String) throws -> Any {
        let object = try JSONSerialization.jsonObject(with: try jsonData(from: stdout))
        if let root = object as? [String: Any] {
            if let ok = root["ok"] as? Bool, !ok {
                let message = ((root["error"] as? [String: Any])?["message"] as? String) ?? "unknown"
                throw AppCLIExchangeError.remote(message: message)
            }
            if let result = root["result"] {
                return result
            }
            return root
        }
        return object
    }

    public static func objectRows(
        _ payload: Any,
        keys: [String] = ["rows", "subscriptions", "tenants"]
    ) throws -> [[String: Any]] {
        if let rows = payload as? [[String: Any]] {
            return rows
        }
        if let object = payload as? [String: Any] {
            for key in keys {
                if let rows = object[key] as? [[String: Any]] {
                    return rows
                }
            }
        }
        throw AppCLIExchangeError.missingRows(keys.joined(separator: "/"))
    }

    public static func tenants(from stdout: String) throws -> [TenantExchange] {
        let rows = try objectRows(try unwrap(stdout), keys: ["tenants", "rows"])
        let parsed = rows.compactMap { row -> TenantExchange? in
            guard let id = row["id"] as? String, !id.isEmpty else { return nil }
            return TenantExchange(
                id: id,
                displayName: (row["displayName"] as? String) ?? id,
                owner: (row["owner"] as? String) ?? "",
                slug: (row["slug"] as? String) ?? id
            )
        }
        if parsed.isEmpty && !rows.isEmpty {
            throw AppCLIExchangeError.undecodableRows("tenants")
        }
        return parsed
    }

    public static func accountBilling(
        from stdout: String,
        now: Date = Date(),
        sourceApp: String = "ai-cli-account-manager"
    ) throws -> [SubscriptionExchange] {
        let rows = try objectRows(try unwrap(stdout), keys: ["rows"])
        if rows.contains(where: { usesLegacyMajor($0) }), legacyMajorExpired(now: now) {
            throw AppCLIExchangeError.legacyAmount(cutoff: legacyAmountCutoffDay)
        }
        let parsed = rows.compactMap { row -> SubscriptionExchange? in
            guard let id = row["id"] as? String, !id.isEmpty else { return nil }
            let client = (row["client"] as? String) ?? "account"
            let label = (row["label"] as? String) ?? id
            let plan = row["plan"] as? String
            let name: String
            if let plan, !plan.isEmpty {
                name = "\(plan) (\(client))"
            } else {
                name = "\(client) · \(label)"
            }
            let currency = (row["currency"] as? String) ?? "USD"
            guard let amount = money(
                row["amount"],
                currency: currency,
                monthlyAmount: row["monthlyAmount"]
            ) else { return nil }
            let deal = [row["deal"] as? String, row["line"] as? String]
                .compactMap { $0 }
                .joined(separator: " ")
            return SubscriptionExchange(
                name: name,
                plan: plan,
                amount: amount,
                period: CLIExchangePeriod.parse(
                    raw: row["period"] as? String,
                    hint: deal
                ),
                nextBillingDate: (row["renewsAt"] as? String).map(CLIExchangeDay.fromISO)
                    ?? (row["nextBillingDate"] as? String),
                promoEndsOn: promoEnd(row, now: now),
                regularAmount: money(
                    row["regularAmount"],
                    currency: currency,
                    monthlyAmount: row["postPromoMonthlyAmount"]
                ),
                source: CLIExchangeSource(app: sourceApp, externalId: id)
            )
        }
        if parsed.isEmpty && !rows.isEmpty {
            throw AppCLIExchangeError.undecodableRows("account-billing")
        }
        return parsed
    }

    public static func moneyLedgerSubscriptions(
        from stdout: String,
        fallbackSource: String
    ) throws -> [SubscriptionExchange] {
        let rows = try objectRows(try unwrap(stdout), keys: ["subscriptions", "rows"])
        let parsed = rows.compactMap { row -> SubscriptionExchange? in
            guard let name = row["name"] as? String, !name.isEmpty else { return nil }
            let currency = ((row["amount"] as? [String: Any])?["currency"] as? String)
                ?? (row["currency"] as? String)
                ?? "KRW"
            guard let amount = money(row["amount"], currency: currency, monthlyAmount: nil)
            else { return nil }
            let sourceApp = (row["sourceApp"] as? String) ?? fallbackSource
            let externalID = (row["externalID"] as? String) ?? (row["id"] as? String)
            let source: CLIExchangeSource?
            if let externalID {
                source = CLIExchangeSource(app: sourceApp, externalId: externalID)
            } else {
                source = nil
            }
            let pays = (row["paymentCardID"] as? String)
                ?? (row["paymentAccountID"] as? String)
            return SubscriptionExchange(
                name: name,
                plan: row["plan"] as? String,
                amount: amount,
                period: CLIExchangePeriod.parse(raw: row["period"] as? String),
                status: row["status"] as? String,
                nextBillingDate: row["nextBillingDate"] as? String,
                promoEndsOn: row["promoEndsOn"] as? String,
                regularAmount: money(row["regularAmount"], currency: currency, monthlyAmount: nil),
                source: source,
                identity: CLIExchangeIdentity(pays: pays),
                note: row["note"] as? String
            )
        }
        if parsed.isEmpty && !rows.isEmpty {
            throw AppCLIExchangeError.undecodableRows("subscriptions")
        }
        return parsed
    }

    public static func money(
        _ raw: Any?,
        currency: String,
        monthlyAmount: Any?
    ) -> CLIExchangeMoney? {
        if let object = raw as? [String: Any], let minor = int64(object["minorUnits"]) {
            let code = (object["currency"] as? String) ?? currency
            return CLIExchangeMoney(
                minorUnits: minor,
                currency: code,
                formatted: object["formatted"] as? String
            )
        }
        if let major = double(raw) {
            return CLIExchangeMoney.fromMajor(major, currency: currency)
        }
        if let major = double(monthlyAmount) {
            return CLIExchangeMoney.fromMajor(major, currency: currency)
        }
        return nil
    }

    private static func usesLegacyMajor(_ row: [String: Any]) -> Bool {
        let hasMinor = ((row["amount"] as? [String: Any])?["minorUnits"]) != nil
        let hasMonthly = row["monthlyAmount"] != nil
        let amountIsMajorNumber = row["amount"] is Double || row["amount"] is Int
        let hasLegacyMajor = hasMonthly || amountIsMajorNumber
        return !hasMinor && hasLegacyMajor
    }

    private static func promoEnd(_ row: [String: Any], now: Date) -> String? {
        if let iso = row["promoEndsAt"] as? String, !iso.isEmpty {
            return CLIExchangeDay.fromISO(iso)
        }
        if let days = int(row["promoEndsInDays"]) {
            return CLIExchangeDay.addingDays(days, to: now)
        }
        return nil
    }

    private static func double(_ raw: Any?) -> Double? {
        if let n = raw as? Double { return n }
        if let n = raw as? Int { return Double(n) }
        if let s = raw as? String { return Double(s) }
        return nil
    }

    private static func int(_ raw: Any?) -> Int? {
        if let n = raw as? Int { return n }
        if let n = raw as? Double { return Int(n) }
        if let s = raw as? String { return Int(s) }
        return nil
    }

    private static func int64(_ raw: Any?) -> Int64? {
        if let n = raw as? Int64 { return n }
        if let n = raw as? Int { return Int64(n) }
        if let n = raw as? Double { return Int64(n) }
        return nil
    }
}

public enum AppCLIExchangeError: Error, Equatable, LocalizedError {
    case noJSON
    case remote(message: String)
    case missingRows(String)
    case undecodableRows(String)
    case unknownID(String)
    case legacyAmount(cutoff: String)

    public var errorDescription: String? {
        switch self {
        case .noJSON: return "JSON 이 없다"
        case .remote(let message): return message
        case .missingRows(let what): return "\(what) 행이 없다"
        case .undecodableRows(let what): return "\(what) 행을 읽지 못했다"
        case .unknownID(let id): return "모르는 교환 id: \(id)"
        case .legacyAmount(let cutoff): return "호환 금액 키는 \(cutoff) 까지만 받는다"
        }
    }
}

public struct CLIExchangeMoney: Codable, Equatable, Sendable {
    public var minorUnits: Int64
    public var currency: String
    public var formatted: String?

    public init(minorUnits: Int64, currency: String, formatted: String? = nil) {
        self.minorUnits = minorUnits
        self.currency = currency.uppercased()
        self.formatted = formatted
    }

    public var majorAmount: Double {
        Double(minorUnits) / pow(10.0, Double(Self.exponent(of: currency)))
    }

    public static func exponent(of currency: String) -> Int {
        switch currency.uppercased() {
        case "KRW", "JPY", "VND": return 0
        default: return 2
        }
    }

    public static func fromMajor(_ major: Double, currency: String) -> CLIExchangeMoney {
        let digits = exponent(of: currency)
        let scaled = (major * pow(10.0, Double(digits))).rounded()
        return CLIExchangeMoney(minorUnits: Int64(scaled), currency: currency)
    }
}

public enum CLIExchangePeriod: String, Codable, Sendable, CaseIterable {
    case monthly
    case yearly
    case oneTime = "one-time"

    public static func parse(raw: String?, hint: String = "") -> CLIExchangePeriod {
        switch (raw ?? "").lowercased() {
        case "monthly": return .monthly
        case "yearly", "year": return .yearly
        case "one-time", "onetime", "one_time": return .oneTime
        default:
            let text = hint.lowercased()
            if text.contains("yearly") || text.contains("/yr") || text.contains("연간")
                || text.contains("/년") {
                return .yearly
            }
            if text.contains("one-time") || text.contains("일시") || text.contains("1회") {
                return .oneTime
            }
            return .monthly
        }
    }
}

public enum CLIExchangeProjection: String, Codable, Sendable {
    case copy
    case move
}

public struct CLIExchangeSource: Codable, Equatable, Sendable {
    public var app: String
    public var externalId: String

    public init(app: String, externalId: String) {
        self.app = app
        self.externalId = externalId
    }

    public var key: String { "\(app)#\(externalId)" }
}

public struct CLIExchangeIdentity: Codable, Equatable, Sendable {
    public var signedInAs: String?
    public var pays: String?
    public var entitles: String?

    public init(signedInAs: String? = nil, pays: String? = nil, entitles: String? = nil) {
        self.signedInAs = signedInAs
        self.pays = pays
        self.entitles = entitles
    }
}

public struct TenantExchange: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var owner: String
    public var slug: String

    public init(id: String, displayName: String, owner: String, slug: String) {
        self.id = id
        self.displayName = displayName
        self.owner = owner
        self.slug = slug
    }
}

public struct SubscriptionExchange: Codable, Equatable, Sendable {
    public var name: String
    public var plan: String?
    public var amount: CLIExchangeMoney
    public var period: CLIExchangePeriod
    public var status: String?
    public var nextBillingDate: String?
    public var promoEndsOn: String?
    public var regularAmount: CLIExchangeMoney?
    public var tenantId: String?
    public var viewpoint: String?
    public var source: CLIExchangeSource?
    public var identity: CLIExchangeIdentity?
    public var note: String?

    public init(
        name: String,
        plan: String? = nil,
        amount: CLIExchangeMoney,
        period: CLIExchangePeriod,
        status: String? = nil,
        nextBillingDate: String? = nil,
        promoEndsOn: String? = nil,
        regularAmount: CLIExchangeMoney? = nil,
        tenantId: String? = nil,
        viewpoint: String? = nil,
        source: CLIExchangeSource? = nil,
        identity: CLIExchangeIdentity? = nil,
        note: String? = nil
    ) {
        self.name = name
        self.plan = plan
        self.amount = amount
        self.period = period
        self.status = status
        self.nextBillingDate = nextBillingDate
        self.promoEndsOn = promoEndsOn
        self.regularAmount = regularAmount
        self.tenantId = tenantId
        self.viewpoint = viewpoint
        self.source = source
        self.identity = identity
        self.note = note
    }
}

public enum CLIExchangeDay {
    public static func fromISO(_ iso: String) -> String {
        String(iso.prefix(10))
    }

    public static func addingDays(_ days: Int, to now: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now.addingTimeInterval(TimeInterval(days) * 86_400))
    }
}
