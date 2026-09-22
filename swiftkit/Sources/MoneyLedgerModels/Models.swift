import Foundation

// Ledger 제품군 공용 도메인 모델.
// 저장은 sqlite payload BLOB(JSON) — 필드 추가는 옵셔널로만 한다(기존 원장과의 하위 호환).
// 금액은 전부 최소단위 Int64(KRW 15000 = ₩15,000 / USD 1599 = $15.99) — 원장은 정확히 더해져야
// 하므로 Double 을 저장 경로에 두지 않는다(파생 리포트 값만 Double 허용).

/// 결제 주기.
public enum BillingPeriod: String, Codable, Sendable, CaseIterable {
    case monthly
    case yearly
    case oneTime
    case unknown

    public func label(korean: Bool) -> String {
        switch self {
        case .monthly: korean ? "월간" : "monthly"
        case .yearly: korean ? "연간" : "yearly"
        case .oneTime: korean ? "1회성" : "one-time"
        case .unknown: korean ? "미정" : "unknown"
        }
    }
}

/// 구독 상태.
public enum SubscriptionStatus: String, Codable, Sendable, CaseIterable {
    case active
    case paused
    case cancelled

    public func label(korean: Bool) -> String {
        switch self {
        case .active: korean ? "활성" : "active"
        case .paused: korean ? "일시중지" : "paused"
        case .cancelled: korean ? "해지" : "cancelled"
        }
    }
}

/// 계좌 자산 유형.
public enum MoneyAccountType: String, Codable, Sendable, CaseIterable {
    case checking
    case savings
    case cash
    case investment
    case realEstate
    case loan

    public var isAsset: Bool {
        self != .loan
    }

    public var isLiability: Bool {
        self == .loan
    }

    public func label(korean: Bool) -> String {
        switch self {
        case .checking: korean ? "입출금" : "checking"
        case .savings: korean ? "예적금" : "savings"
        case .cash: korean ? "현금" : "cash"
        case .investment: korean ? "투자" : "investment"
        case .realEstate: korean ? "부동산" : "realEstate"
        case .loan: korean ? "대출" : "loan"
        }
    }
}

/// 은행 계좌. 전체 계좌번호는 저장하지 않는다 — 별칭+끝4자리로 식별하고,
/// 전체 번호가 필요하면 Vaultwarden Secure Note 참조(vaultNoteRef)로 연결한다.
public struct MoneyAccount: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var bank: String
    public var last4: String
    public var currency: String
    public var accountType: MoneyAccountType?
    public var initialBalanceMinor: Int64?
    /// 기초잔액 별칭 (initialBalanceMinor 와 상호 호환).
    public var openingBalanceMinor: Int64? {
        get { initialBalanceMinor }
        set { initialBalanceMinor = newValue }
    }
    public var purpose: String?
    public var note: String?
    /// Vaultwarden Secure Note 이름(ledger/<scope>/account/<id>). 값 자체는 로컬에 없다.
    public var vaultNoteRef: String?
    public var archived: Bool
    public var createdAt: Date
    public var updatedAt: Date?

    /// Init-only grouping — stored fields stay flat for payload JSON.
    public struct Identity: Sendable, Equatable {
        public var name: String
        public var bank: String
        public var last4: String
        public var currency: String

        public init(name: String, bank: String, last4: String = "", currency: String = "KRW") {
            self.name = name
            self.bank = bank
            self.last4 = last4
            self.currency = currency
        }
    }

    public init(
        id: String = UUID().uuidString.lowercased(),
        identity: Identity,
        accountType: MoneyAccountType? = nil,
        initialBalanceMinor: Int64? = nil,
        purpose: String? = nil,
        note: String? = nil,
        vaultNoteRef: String? = nil,
        archived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = identity.name
        self.bank = identity.bank
        self.last4 = identity.last4
        self.currency = MoneyAmount.normalizedCurrency(identity.currency)
        self.accountType = accountType
        self.initialBalanceMinor = initialBalanceMinor
        self.purpose = purpose
        self.note = note
        self.vaultNoteRef = vaultNoteRef
        self.archived = archived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(
        id: String = UUID().uuidString.lowercased(),
        identity: Identity,
        accountType: MoneyAccountType? = nil,
        initialBalanceMinor: Int64? = nil,
        purpose: String? = nil,
        note: String? = nil,
        vaultNoteRef: String? = nil,
        archived: Bool = false
    ) {
        self.init(
            id: id,
            identity: identity,
            accountType: accountType,
            initialBalanceMinor: initialBalanceMinor,
            purpose: purpose,
            note: note,
            vaultNoteRef: vaultNoteRef,
            archived: archived,
            createdAt: .now,
            updatedAt: nil
        )
    }

    public init(
        name: String,
        bank: String,
        last4: String = "",
        currency: String = "KRW",
        accountType: MoneyAccountType? = nil,
        initialBalanceMinor: Int64? = nil,
        purpose: String? = nil,
        note: String? = nil
    ) {
        self.init(
            identity: Identity(name: name, bank: bank, last4: last4, currency: currency),
            accountType: accountType,
            initialBalanceMinor: initialBalanceMinor,
            purpose: purpose,
            note: note
        )
    }

    public init(
        name: String,
        bank: String,
        currency: String = "KRW",
        accountType: MoneyAccountType? = nil,
        openingBalanceMinor: Int64?
    ) {
        self.init(
            identity: Identity(name: name, bank: bank, currency: currency),
            accountType: accountType,
            initialBalanceMinor: openingBalanceMinor
        )
    }

    public init(
        id: String,
        name: String,
        bank: String,
        last4: String = "",
        currency: String = "KRW"
    ) {
        self.init(
            id: id,
            identity: Identity(name: name, bank: bank, last4: last4, currency: currency)
        )
    }
}

/// 카드(신용/체크). 전체 카드번호 비저장 원칙은 계좌와 같다.
public struct MoneyCard: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var issuer: String
    public var last4: String
    /// 결제(출금) 계좌 연결 — MoneyAccount.id.
    public var linkedAccountID: String?
    /// 매월 결제일(1~31). 말일 결제 카드도 있으니 표기 정보로만 쓴다.
    public var billingDay: Int?
    public var note: String?
    public var vaultNoteRef: String?
    public var archived: Bool
    public var createdAt: Date
    public var updatedAt: Date?

    /// Init-only grouping — stored fields stay flat for payload JSON.
    public struct Identity: Sendable, Equatable {
        public var name: String
        public var issuer: String
        public var last4: String

        public init(name: String, issuer: String, last4: String = "") {
            self.name = name
            self.issuer = issuer
            self.last4 = last4
        }
    }

    public init(
        id: String = UUID().uuidString.lowercased(),
        identity: Identity,
        linkedAccountID: String? = nil,
        billingDay: Int? = nil,
        note: String? = nil,
        vaultNoteRef: String? = nil,
        archived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = identity.name
        self.issuer = identity.issuer
        self.last4 = identity.last4
        self.linkedAccountID = linkedAccountID
        self.billingDay = billingDay
        self.note = note
        self.vaultNoteRef = vaultNoteRef
        self.archived = archived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(
        id: String = UUID().uuidString.lowercased(),
        identity: Identity,
        linkedAccountID: String? = nil,
        billingDay: Int? = nil,
        note: String? = nil,
        vaultNoteRef: String? = nil,
        archived: Bool = false,
        createdAt: Date
    ) {
        self.init(
            id: id,
            identity: identity,
            linkedAccountID: linkedAccountID,
            billingDay: billingDay,
            note: note,
            vaultNoteRef: vaultNoteRef,
            archived: archived,
            createdAt: createdAt,
            updatedAt: nil
        )
    }

    public init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        issuer: String,
        last4: String = "",
        linkedAccountID: String? = nil,
        billingDay: Int? = nil,
        note: String? = nil
    ) {
        self.init(
            id: id,
            identity: Identity(name: name, issuer: issuer, last4: last4),
            linkedAccountID: linkedAccountID,
            billingDay: billingDay,
            note: note
        )
    }
}

/// 구독(정기 결제). 금액은 최소단위 — 리포트의 월환산만 Double.
public struct MoneySubscription: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var amountMinor: Int64
    public var currency: String
    public var period: BillingPeriod
    public var status: SubscriptionStatus
    /// 다음 결제일(yyyy-MM-dd). 지났으면 리포트가 주기만큼 굴려서 보여준다(저장값은 불변).
    public var nextBillingDate: String?
    /// 결제수단 — 카드 또는 계좌. 둘 다 nil 이면 "어느 카드로 빠지나"에 답할 수 없다.
    public var paymentCardID: String?
    public var paymentAccountID: String?
    /// 귀속 사업체(BusinessProfile.id). 경비 귀속·세금 처리의 축이다.
    /// 개인 구독이면 nil — scope(개인/사업)와는 별개다. 사업 원장 안에도
    /// 사업체가 여럿일 수 있어 scope 만으로는 못 가른다.
    public var businessID: String?
    /// 이 행을 만든 외부 앱의 슬러그(예: "ai-cli-account-manager").
    /// 사람이 직접 넣었으면 nil.
    public var sourceApp: String?
    /// 그 앱에서의 식별자(예: ACM 계정 uuid). `sourceApp` 과 짝이며,
    /// 둘이 같으면 같은 구독이다 — 재수입 시 중복 생성 대신 갱신한다.
    public var externalID: String?
    /// 프로모 종료일(yyyy-MM-dd). 이 날 이후 `regularAmountMinor` 로 오른다.
    public var promoEndsOn: String?
    /// 프로모 종료 후 정가(minor units). 프로모가 없으면 nil.
    /// 지금 금액(`amountMinor`)만 저장하면 "$33/월" 로 보이다가 조용히 "$300/월"이
    /// 되는 절벽을 원장이 예고하지 못한다.
    public var regularAmountMinor: Int64?
    public var note: String?
    public var archived: Bool
    public var createdAt: Date
    public var updatedAt: Date?

    /// `sourceApp` + `externalID` 가 둘 다 있을 때의 앱 간 동일성 키.
    public var externalKey: String? {
        guard let sourceApp, let externalID else { return nil }
        return "\(sourceApp)#\(externalID)"
    }

    /// Init-only grouping — stored fields stay flat for payload JSON.
    public struct Amount: Sendable, Equatable {
        public var amountMinor: Int64
        public var currency: String
        public var period: BillingPeriod

        public init(
            amountMinor: Int64,
            currency: String = "KRW",
            period: BillingPeriod = .monthly
        ) {
            self.amountMinor = amountMinor
            self.currency = currency
            self.period = period
        }
    }

    public struct Billing: Sendable, Equatable {
        public var status: SubscriptionStatus
        public var nextBillingDate: String?
        public var promoEndsOn: String?
        public var regularAmountMinor: Int64?

        public init(
            status: SubscriptionStatus = .active,
            nextBillingDate: String? = nil,
            promoEndsOn: String? = nil,
            regularAmountMinor: Int64? = nil
        ) {
            self.status = status
            self.nextBillingDate = nextBillingDate
            self.promoEndsOn = promoEndsOn
            self.regularAmountMinor = regularAmountMinor
        }
    }

    public struct Links: Sendable, Equatable {
        public var paymentCardID: String?
        public var paymentAccountID: String?
        public var businessID: String?
        public var sourceApp: String?
        public var externalID: String?

        public init(
            paymentCardID: String? = nil,
            paymentAccountID: String? = nil,
            businessID: String? = nil,
            sourceApp: String? = nil,
            externalID: String? = nil
        ) {
            self.paymentCardID = paymentCardID
            self.paymentAccountID = paymentAccountID
            self.businessID = businessID
            self.sourceApp = sourceApp
            self.externalID = externalID
        }
    }

    public init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        amount: Amount,
        billing: Billing = Billing(),
        links: Links = Links(),
        note: String? = nil,
        archived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.amountMinor = amount.amountMinor
        self.currency = MoneyAmount.normalizedCurrency(amount.currency)
        self.period = amount.period
        self.status = billing.status
        self.nextBillingDate = billing.nextBillingDate
        self.paymentCardID = links.paymentCardID
        self.paymentAccountID = links.paymentAccountID
        self.businessID = links.businessID
        self.sourceApp = links.sourceApp
        self.externalID = links.externalID
        self.promoEndsOn = billing.promoEndsOn
        self.regularAmountMinor = billing.regularAmountMinor
        self.note = note
        self.archived = archived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        amount: Amount,
        billing: Billing = Billing(),
        links: Links = Links(),
        note: String? = nil,
        archived: Bool = false,
        createdAt: Date
    ) {
        self.init(
            id: id,
            name: name,
            amount: amount,
            billing: billing,
            links: links,
            note: note,
            archived: archived,
            createdAt: createdAt,
            updatedAt: nil
        )
    }

    public init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        amountMinor: Int64,
        currency: String = "KRW",
        period: BillingPeriod = .monthly,
        status: SubscriptionStatus = .active,
        nextBillingDate: String? = nil,
        note: String? = nil
    ) {
        self.init(
            id: id,
            name: name,
            amount: Amount(amountMinor: amountMinor, currency: currency, period: period),
            billing: Billing(status: status, nextBillingDate: nextBillingDate),
            note: note
        )
    }
}

/// 거래 구분.
public enum TransactionKind: String, Codable, Sendable, CaseIterable {
    case expense
    case income
    case transfer
    case settlement

    public func label(korean: Bool) -> String {
        switch self {
        case .expense: korean ? "지출" : "expense"
        case .income: korean ? "수입" : "income"
        case .transfer: korean ? "이체" : "transfer"
        case .settlement: korean ? "카드대금" : "settlement"
        }
    }
}

/// 입출금 거래 한 건. amountMinor 부호가 방향이다 — 음수 출금, 양수 입금.
public struct MoneyTransaction: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    /// 거래일 "yyyy-MM-dd". 문자열 사전순 = 날짜순이라 범위 질의가 단순해진다.
    public var date: String
    /// 거래시각 "HH:mm:ss" — 은행 CSV 에 있으면 채운다(중복판정 정확도에 기여).
    public var time: String?
    public var amountMinor: Int64
    public var currency: String
    public var accountID: String?
    public var cardID: String?
    /// 귀속 사업체(BusinessProfile.id). 사업 원장 안에 사업체가 여럿일 때 거래를 가르는 축이며,
    /// 사업체별 손익·증빙 원장은 이 거래 id 를 참조한다. 공급가액·세액은 여기 두지 않는다
    /// (위키 결정 9261be4f — 증빙 원장이 거래 id 를 참조한다).
    /// 옛 원장(컬럼·payload 키 없음)은 nil 로 디코딩된다.
    public var businessID: String?
    public var description: String
    public var category: String?
    public var memo: String?
    /// 거래 구분 (지출, 수입, 이체, 카드대금납부 등).
    public var kind: TransactionKind?
    /// 거래 후 잔액(최소단위) — 은행 CSV 컬럼이 있을 때만.
    public var balanceAfterMinor: Int64?
    public var importBatchID: String?
    /// 중복판정 해시(ContentHash.transactionHash). UNIQUE 인덱스가 재가져오기를 막는다.
    public var contentHash: String
    public var createdAt: Date

    /// Init-only grouping — stored fields stay flat for payload JSON.
    public struct Stamp: Sendable, Equatable {
        public var date: String
        public var time: String?

        public init(date: String, time: String? = nil) {
            self.date = date
            self.time = time
        }
    }

    public struct Amount: Sendable, Equatable {
        public var amountMinor: Int64
        public var currency: String
        public var balanceAfterMinor: Int64?

        public init(
            amountMinor: Int64,
            currency: String = "KRW",
            balanceAfterMinor: Int64? = nil
        ) {
            self.amountMinor = amountMinor
            self.currency = currency
            self.balanceAfterMinor = balanceAfterMinor
        }
    }

    public struct Parties: Sendable, Equatable {
        public var accountID: String?
        public var cardID: String?
        public var businessID: String?

        public init(accountID: String? = nil, cardID: String? = nil, businessID: String? = nil) {
            self.accountID = accountID
            self.cardID = cardID
            self.businessID = businessID
        }
    }

    public struct Narrative: Sendable, Equatable {
        public var description: String
        public var category: String?
        public var memo: String?

        public init(description: String, category: String? = nil, memo: String? = nil) {
            self.description = description
            self.category = category
            self.memo = memo
        }
    }

    public init(
        id: String = UUID().uuidString.lowercased(),
        stamp: Stamp,
        amount: Amount,
        parties: Parties = Parties(),
        narrative: Narrative,
        kind: TransactionKind? = nil,
        importBatchID: String? = nil,
        contentHash: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.date = stamp.date
        self.time = stamp.time
        self.amountMinor = amount.amountMinor
        self.currency = MoneyAmount.normalizedCurrency(amount.currency)
        self.accountID = parties.accountID
        self.cardID = parties.cardID
        self.businessID = parties.businessID
        self.description = narrative.description
        self.category = narrative.category
        self.memo = narrative.memo
        self.kind = kind
        self.balanceAfterMinor = amount.balanceAfterMinor
        self.importBatchID = importBatchID
        self.contentHash = contentHash
        self.createdAt = createdAt
    }

    public init(
        id: String,
        date: String,
        amount: Amount,
        accountID: String? = nil,
        description: String,
        category: String? = nil,
        kind: TransactionKind? = nil,
        contentHash: String
    ) {
        self.init(
            id: id,
            stamp: Stamp(date: date),
            amount: amount,
            parties: Parties(accountID: accountID),
            narrative: Narrative(description: description, category: category),
            kind: kind,
            contentHash: contentHash
        )
    }

    public init(
        date: String,
        amountMinor: Int64,
        currency: String = "KRW",
        accountID: String? = nil,
        description: String,
        category: String? = nil,
        kind: TransactionKind? = nil,
        contentHash: String
    ) {
        self.init(
            id: UUID().uuidString.lowercased(),
            stamp: Stamp(date: date),
            amount: Amount(amountMinor: amountMinor, currency: currency),
            parties: Parties(accountID: accountID),
            narrative: Narrative(description: description, category: category),
            kind: kind,
            contentHash: contentHash
        )
    }

    public init(
        id: String,
        date: String,
        amountMinor: Int64,
        accountID: String? = nil,
        description: String,
        contentHash: String
    ) {
        self.init(
            id: id,
            stamp: Stamp(date: date),
            amount: Amount(amountMinor: amountMinor),
            parties: Parties(accountID: accountID),
            narrative: Narrative(description: description),
            contentHash: contentHash
        )
    }
}

/// CSV 가져오기 1회 기록 — undo 단위.
public struct ImportBatch: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var createdAt: Date
    public var sourceFile: String
    public var encoding: String
    public var mapping: String
    public var inserted: Int
    public var duplicates: Int
    public var errorCount: Int

    public init(
        id: String = UUID().uuidString.lowercased(),
        createdAt: Date = .now,
        sourceFile: String,
        encoding: String,
        mapping: String,
        inserted: Int,
        duplicates: Int,
        errorCount: Int
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceFile = sourceFile
        self.encoding = encoding
        self.mapping = mapping
        self.inserted = inserted
        self.duplicates = duplicates
        self.errorCount = errorCount
    }
}

/// 카테고리별 월간 예산.
public struct MoneyBudget: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var category: String
    /// 대상 월("yyyy-MM"). nil이면 모든 월에 적용되는 기본 월별 예산.
    public var month: String?
    public var amountMinor: Int64
    public var currency: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString.lowercased(),
        category: String,
        month: String? = nil,
        amountMinor: Int64,
        currency: String = "KRW",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.category = category
        self.month = month
        self.amountMinor = amountMinor
        self.currency = MoneyAmount.normalizedCurrency(currency)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 매월 반복되는 고정비 템플릿.
public struct RecurringTemplate: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    /// 고정비 명칭 (예: 월세, 관리비, 적금, 실손보험 등).
    public var name: String
    /// 매월 반복 발생일 (1~31).
    public var dayOfMonth: Int
    public var amountMinor: Int64
    public var currency: String
    /// 거래 구분 (.expense 또는 .transfer).
    public var kind: TransactionKind
    public var category: String?
    /// 출금 계좌 ID.
    public var accountID: String?
    /// 이체 시 입금 계좌 ID (.transfer 일 때).
    public var transferTargetAccountID: String?
    public var memo: String?
    public var isActive: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        dayOfMonth: Int,
        amountMinor: Int64,
        currency: String = "KRW",
        kind: TransactionKind = .expense,
        category: String? = nil,
        accountID: String? = nil,
        transferTargetAccountID: String? = nil,
        memo: String? = nil,
        isActive: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.dayOfMonth = max(1, min(31, dayOfMonth))
        self.amountMinor = amountMinor
        self.currency = MoneyAmount.normalizedCurrency(currency)
        self.kind = kind
        self.category = category
        self.accountID = accountID
        self.transferTargetAccountID = transferTargetAccountID
        self.memo = memo
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
