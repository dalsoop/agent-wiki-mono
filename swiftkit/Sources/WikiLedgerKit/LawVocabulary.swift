import Foundation

// ledger 3(agent-law) 어휘의 단일 정본.
// 근거: agent-wiki-mono docs/business-rules.md "agent-law(ledger 3)" 절(유형·작성자와 모델 기록·화자·
// 본문 머리 칸·관계), docs/standards.md "agent-law (ledger 3)" — 각 집합은 여기 한 곳에서만 정의한다.
// 엔진(KnowledgeBaseWikiCore)과 읽기 앱은 이 상수를 쓰고, 같은 목록을 다시 적지 않는다.

/// 기록 유형(`type`). 지식 기록과 처리 기록으로 나뉜다.
public enum LawRecordType: String, CaseIterable, Sendable, Hashable, Codable {
    case record, article, judgment
    case evidence, finding, appeal, proposal, ruling, redaction, contents, report, checkpoint, registration
    case promotionReceipt = "promotion-receipt"

    /// 지식 기록 — 사실인정의 대상(`finds` 도착), 사실인정이 없으면 감사에서 "판단 대기".
    public static let knowledgeTypes: Set<LawRecordType> = [.record, .article, .judgment]

    /// 처리 기록(사실인정을 요구하지 않음) — 지식 기록이 아닌 나머지 전부(파생, 따로 나열하지 않음).
    public static let processTypes: Set<LawRecordType> = Set(allCases).subtracting(knowledgeTypes)

    public var isKnowledge: Bool { Self.knowledgeTypes.contains(self) }

    /// 원시 문자열이 지식 기록 유형인가(모르는 값·전신의 옛 유형은 아니다).
    public static func isKnowledge(_ raw: String?) -> Bool {
        raw.flatMap(LawRecordType.init(rawValue:))?.isKnowledge ?? false
    }
}

/// `author-kind`.
public enum LawAuthorKind: String, CaseIterable, Sendable, Hashable, Codable {
    case agent, human, app
}

/// `runtime` — ledger 3 기록 어휘(실행 파일 이름이 아니다).
public enum LawRuntime: String, CaseIterable, Sendable, Hashable, Codable {
    case claudeCode = "claude-code"
    case codex, grok, antigravity, human, app
}

/// `effort` — 모르면 `unknown`.
public enum LawEffort: String, CaseIterable, Sendable, Hashable, Codable {
    case low, medium, high, xhigh, max, unknown
}

/// `speaker`.
public enum LawSpeaker: String, CaseIterable, Sendable, Hashable, Codable {
    case user, agent, external
    case otherAgent = "other-agent"
}

/// `origin` — 값이 없으면 직접 공포한 기록.
public enum LawOrigin: String, CaseIterable, Sendable, Hashable, Codable {
    /// 드리밍 정리본 — `testifies`·`finds` 근거나 증거 인용 대상이 될 수 없다.
    case dream
    /// 전신에서 옮겨 온 기록 — 전신 객체를 `migrated-from` 으로 반드시 인용한다.
    case migration
}

/// 사실인정 `subject`.
public enum LawSubject: String, CaseIterable, Sendable, Hashable, Codable {
    case person
    case agentSelf = "agent-self"
    case project, external
}

/// 사실인정 `certainty`.
public enum LawCertainty: String, CaseIterable, Sendable, Hashable, Codable {
    case confirmed, probable, possible
}

/// 사실인정 `domain`(분야 8개).
public enum LawDomain: String, CaseIterable, Sendable, Hashable, Codable {
    case agentMemorySSOT = "agent-memory-ssot"
    case agentOrchestration = "agent-orchestration"
    case infraHosting = "infra-hosting"
    case secretsIdentity = "secrets-identity"
    case gujoCommerce = "gujo-commerce"
    case macosApps = "macos-apps"
    case mediaAIPipeline = "media-ai-pipeline"
    case devWorkflow = "dev-workflow"
}

/// 결정(`ruling`) `level`.
public enum LawRulingLevel: String, CaseIterable, Sendable, Hashable, Codable {
    case appellate, supreme
}

/// 결정(`ruling`) `outcome`.
public enum LawRulingOutcome: String, CaseIterable, Sendable, Hashable, Codable {
    case uphold, overturn, refer, approve, reject
}

/// 판결 등록(`registration`) `status`.
public enum LawRegistrationStatus: String, CaseIterable, Sendable, Hashable, Codable {
    case provisional, confirmed
}

/// 관계(`cites: <id> <rel>` 의 rel). 이 집합 밖의 관계는 거부한다.
public enum LawRelation: String, CaseIterable, Sendable, Hashable, Codable {
    case cites, finds, testifies
    case migratedFrom = "migrated-from"
    case appeals, proposes, hears
    case perRuling = "per-ruling"
    case checkpoints, receipts
    case promotedAs = "promoted-as"

    /// 출발 규칙.
    public enum Source: Sendable, Equatable {
        case anyType
        case types(Set<LawRecordType>)
        /// `origin: migration` 기록.
        case migrationOrigin
        /// 개정·원상회복·폐지 기록(`amends`·`amends-also`·`repeals` 가 있는 기록).
        case amendingOrRepealing
    }

    /// 도착 규칙.
    public enum Target: Sendable, Equatable {
        case anyRecord
        case types(Set<LawRecordType>)
        /// 지식 기록.
        case knowledge
        /// 전신 원장의 객체.
        case predecessorObject
    }

    /// 관계표(business-rules "관계")의 단일 정본.
    public var rule: (source: Source, target: Target) {
        switch self {
        case .cites: return (.anyType, .anyRecord)
        case .finds: return (.types([.finding]), .knowledge)
        case .testifies: return (.anyType, .types([.evidence]))
        case .migratedFrom: return (.migrationOrigin, .predecessorObject)
        case .appeals: return (.types([.appeal]), .anyRecord)
        case .proposes: return (.types([.proposal]), .anyRecord)
        case .hears: return (.types([.ruling]), .types([.appeal, .proposal]))
        case .perRuling: return (.amendingOrRepealing, .types([.ruling]))
        case .checkpoints: return (.types([.checkpoint]), .types([.checkpoint]))
        case .receipts, .promotedAs: return (.types([.promotionReceipt]), .anyRecord)
        }
    }

    public func allowsSource(type: String?, origin: String?, amendsOrRepeals: Bool) -> Bool {
        switch rule.source {
        case .anyType: return true
        case .types(let allowed):
            return type.flatMap(LawRecordType.init(rawValue:)).map(allowed.contains) ?? false
        case .migrationOrigin: return origin == LawOrigin.migration.rawValue
        case .amendingOrRepealing: return amendsOrRepeals
        }
    }

    /// - Parameters:
    ///   - type: 도착 기록의 유형(전신 객체면 옛 유형일 수 있다).
    ///   - isPredecessor: 도착이 전신 원장의 객체인가.
    public func allowsTarget(type: String?, isPredecessor: Bool) -> Bool {
        switch rule.target {
        case .anyRecord: return true
        case .predecessorObject: return isPredecessor
        case .knowledge: return !isPredecessor && LawRecordType.isKnowledge(type)
        case .types(let allowed):
            return !isPredecessor && (type.flatMap(LawRecordType.init(rawValue:)).map(allowed.contains) ?? false)
        }
    }
}
