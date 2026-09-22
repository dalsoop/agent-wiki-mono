import Foundation
import InteropKit
import MoneyLedgerKit
import os

/// 플래그/위치인자 스캐너 — repo 관례상 swift-argument-parser 없이 손으로 짠다.
public struct ArgScanner {
    public private(set) var positionals: [String] = []
    private var options: [String: [String]] = [:]
    private var flags: Set<String> = []

    /// 앱이 아는 이름 목록을 준 경우에 한해, 모르는 `--옵션` 을 모아 둔다.
    ///
    /// 왜 필요한가(실측 2026-08-11): `business-projects client set 달숲
    /// --registration-number 5558889999` 가 **"갱신" 을 찍고 아무것도 저장하지 않았다.**
    /// 실제 이름은 `--reg-no` 였는데, 모르는 옵션이라 조용히 무시된 것이다. 게다가 값
    /// `5558889999` 는 위치인자로 흘러들어 거래처 해석까지 오염시킬 수 있었다.
    /// 세금계산서 필수 항목을 채우는 자리라, 사람은 "됐다" 를 보고 다음 단계로 간다.
    public private(set) var unknownOptions: [String] = []

    public init(_ arguments: [String], valueFlags: Set<String>, knownFlags: Set<String>? = nil) {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard argument.hasPrefix("--") else {
                positionals.append(argument)
                index += 1
                continue
            }
            let name = String(argument.dropFirst(2))
            if valueFlags.contains(name), index + 1 < arguments.count {
                options[name, default: []].append(arguments[index + 1])
                index += 2
                continue
            }
            if let knownFlags, !knownFlags.contains(name), !valueFlags.contains(name) {
                unknownOptions.append(argument)
                if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
                    index += 2
                    continue
                }
            }
            flags.insert(name)
            index += 1
        }
    }

    public func value(_ name: String) -> String? { options[name]?.last }
    public func has(_ name: String) -> Bool { flags.contains(name) }
}

/// 출력 채널 — 테스트가 stdout 을 캡처할 수 있게 주입식으로.
/// 캡처 버퍼는 락 안에 두어 `@unchecked` 없이 Sendable 이다(async 명령 경로를 건너다닌다).
public final class CLIOutput: Sendable {
    private struct Captured {
        var standardOut: [String] = []
        var standardError: [String] = []
    }

    private let captured = OSAllocatedUnfairLock(initialState: Captured())
    private let passthrough: Bool

    public init(passthrough: Bool = true) {
        self.passthrough = passthrough
    }

    public var standardOut: [String] { captured.withLock { $0.standardOut } }
    public var standardError: [String] { captured.withLock { $0.standardError } }

    public func out(_ line: String) {
        captured.withLock { $0.standardOut.append(line) }
        if passthrough { print(line) }  // allow:debug CLI 정규 stdout 경로(테스트는 passthrough=false 로 캡처)
    }

    public func err(_ line: String) {
        captured.withLock { $0.standardError.append(line) }
        if passthrough { FileHandle.standardError.write(Data((line + "\n").utf8)) }
    }

    public func okJSON(_ object: Any) {
        let data = (try? Envelope.okObject(object)) ?? Data("{\"ok\":true}".utf8)
        out(String(data: data, encoding: .utf8) ?? "{}")
    }

    public func okJSON<T: Codable>(_ value: T) {
        let data = (try? Envelope.ok(value)) ?? Data("{\"ok\":true}".utf8)
        out(String(data: data, encoding: .utf8) ?? "{}")
    }

    public func failJSON(_ message: String) {
        let data = (try? Envelope.failObject(message)) ?? Data("{\"ok\":false}".utf8)
        out(String(data: data, encoding: .utf8) ?? "{}")
    }
}

/// 사용법 오류(exit 64) 와 실행 실패(exit 1) 구분.
public struct UsageError: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// `--business <id|상호>` 해석 — sub add 와 같은 규칙(id 접두사 → 상호 대소문자 무시 일치).
/// tx · import · report 가 같은 해석을 쓴다. `none` 은 귀속 해제(nil).
/// 없는 사업체는 LedgerStoreError.notFound 로 exit 1 — 조용히 무시하면 귀속이 새는 자리다.
enum BusinessArgument {
    static let noneKeyword = "none"

    static func resolve(store: LedgerStore, scanner: ArgScanner) async throws -> BusinessProfile? {
        guard let reference = scanner.value("business") else { return nil }
        return try await resolve(store: store, reference: reference)
    }

    static func resolve(store: LedgerStore, reference: String) async throws -> BusinessProfile? {
        guard reference.lowercased() != noneKeyword else { return nil }
        return try await store.resolveBusiness(reference)
    }

    static func resolveID(store: LedgerStore, scanner: ArgScanner) async throws -> String? {
        try await resolve(store: store, scanner: scanner)?.id
    }

    static func resolveID(store: LedgerStore, reference: String) async throws -> String? {
        try await resolve(store: store, reference: reference)?.id
    }
}

enum CLIFormat {
    static func amountObject(minor: Int64, currency: String) -> [String: Any] {
        [
            "minorUnits": minor,
            "currency": currency,
            "formatted": MoneyAmount.format(minor: minor, currency: currency),
        ]
    }

    static func accountObject(_ account: MoneyAccount) -> [String: Any] {
        var object: [String: Any] = [
            "id": account.id,
            "name": account.name,
            "bank": account.bank,
            "last4": account.last4,
            "currency": account.currency,
            "archived": account.archived,
            "vaultLinked": account.vaultNoteRef != nil,
        ]
        object.setIfPresent("type", account.accountType?.rawValue)
        object.setIfPresent("initialBalance", account.initialBalanceMinor.map { amountObject(minor: $0, currency: account.currency) })
        object.setIfPresent("purpose", account.purpose)
        object.setIfPresent("note", account.note)
        object.setIfPresent("vaultNoteRef", account.vaultNoteRef)
        return object
    }

    static func cardObject(_ card: MoneyCard) -> [String: Any] {
        var object: [String: Any] = [
            "id": card.id,
            "name": card.name,
            "issuer": card.issuer,
            "last4": card.last4,
            "archived": card.archived,
            "vaultLinked": card.vaultNoteRef != nil,
        ]
        object.setIfPresent("linkedAccountID", card.linkedAccountID)
        object.setIfPresent("billingDay", card.billingDay)
        object.setIfPresent("note", card.note)
        object.setIfPresent("vaultNoteRef", card.vaultNoteRef)
        return object
    }

    static func subscriptionObject(_ sub: MoneySubscription) -> [String: Any] {
        var object: [String: Any] = [
            "id": sub.id,
            "name": sub.name,
            "amount": amountObject(minor: sub.amountMinor, currency: sub.currency),
            "period": sub.period.rawValue,
            "status": sub.status.rawValue,
            "archived": sub.archived,
        ]
        object.setIfPresent("nextBillingDate", sub.nextBillingDate)
        object.setIfPresent("paymentCardID", sub.paymentCardID)
        object.setIfPresent("paymentAccountID", sub.paymentAccountID)
        object.setIfPresent("businessID", sub.businessID)
        object.setIfPresent("sourceApp", sub.sourceApp)
        object.setIfPresent("externalID", sub.externalID)
        object.setIfPresent("externalKey", sub.externalKey)
        object.setIfPresent("promoEndsOn", sub.promoEndsOn)
        object.setIfPresent("regularAmount", sub.regularAmountMinor.map { amountObject(minor: $0, currency: sub.currency) })
        object.setIfPresent("note", sub.note)
        return object
    }

    static func transactionObject(_ tx: MoneyTransaction) -> [String: Any] {
        var object: [String: Any] = [
            "id": tx.id,
            "date": tx.date,
            "amount": amountObject(minor: tx.amountMinor, currency: tx.currency),
            "description": tx.description,
        ]
        object.setIfPresent("kind", tx.kind?.rawValue)
        object.setIfPresent("time", tx.time)
        object.setIfPresent("accountID", tx.accountID)
        object.setIfPresent("cardID", tx.cardID)
        object.setIfPresent("businessID", tx.businessID)
        object.setIfPresent("category", tx.category)
        object.setIfPresent("memo", tx.memo)
        object.setIfPresent("balanceAfter", tx.balanceAfterMinor.map { amountObject(minor: $0, currency: tx.currency) })
        object.setIfPresent("importBatchID", tx.importBatchID)
        return object
    }

    static func shortID(_ id: String) -> String { String(id.prefix(8)) }
}

/// stdin 에서 비밀값 읽기 — 비밀은 argv 에 절대 싣지 않는다(ps/히스토리 노출).
/// 읽기 실패(닫힌 stdin 등)는 "입력 없음" 과 같은 결과라 nil 로 접는다 — 호출부가 사용법 오류로 안내한다.
func readSecretFromStdin() -> String? {
    let data: Data?
    do {
        data = try FileHandle.standardInput.readToEnd()
    } catch {
        return nil
    }
    guard let data, !data.isEmpty else { return nil }
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

extension Dictionary where Key == String, Value == Any {
    mutating func setIfPresent(_ key: String, _ value: Any?) {
        guard let value else { return }
        self[key] = value
    }
}

