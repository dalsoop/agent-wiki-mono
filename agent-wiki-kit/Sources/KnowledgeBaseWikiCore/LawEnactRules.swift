import Foundation
import WikiLedgerKit

// ledger 3 공포 규칙의 주입 지점과 오류.
// 근거: docs/business-rules.md "작성자와 모델 기록"·"화자"·"관계"·"출처 표시"·"공포·개정·폐지·원상회복",
// docs/security.md "작성자·화자 신뢰", 결정 0007.

/// 공포하는 주체와 그 모델 기록(코어에 들어간다).
public struct LawActor: Sendable, Equatable {
    public var author: String
    public var kind: LawAuthorKind
    public var device: String?
    public var runtime: String?
    public var runtimeVersion: String?
    public var model: String?
    public var effort: String?
    public var app: String?
    public var appVersion: String?

    public init(
        author: String, kind: LawAuthorKind, device: String? = nil, runtime: String? = nil,
        runtimeVersion: String? = nil, model: String? = nil, effort: String? = nil,
        app: String? = nil, appVersion: String? = nil
    ) {
        self.author = author
        self.kind = kind
        self.device = device
        self.runtime = runtime
        self.runtimeVersion = runtimeVersion
        self.model = model
        self.effort = effort
        self.app = app
        self.appVersion = appVersion
    }
}

/// 공포할 기록의 입력. 공포일·id·본문 해시는 공포 경로가 정한다.
public struct LawDraft: Sendable, Equatable {
    public var actor: LawActor
    /// 비우면 기본값(에이전트 → `agent`, 사람 → `user`, 증거 유형 → `external`, 증언 확인 시 그 화자).
    public var speaker: String?
    public var title: String?
    public var type: String
    public var origin: String?
    public var batch: String?
    public var tags: [String]
    public var cites: [LawCite]
    public var exhibits: [String]
    public var amends: String?
    public var amendsAlso: [String]
    public var repeals: String?
    /// `source:` JSON 한 줄.
    public var source: String?
    public var body: String
    public var cost: LawCost?

    public init(
        actor: LawActor, speaker: String? = nil, title: String? = nil,
        type: String = LawRecordType.record.rawValue, origin: String? = nil, batch: String? = nil,
        tags: [String] = [], cites: [LawCite] = [], exhibits: [String] = [], amends: String? = nil,
        amendsAlso: [String] = [], repeals: String? = nil, source: String? = nil, body: String,
        cost: LawCost? = nil
    ) {
        self.actor = actor
        self.speaker = speaker
        self.title = title
        self.type = type
        self.origin = origin
        self.batch = batch
        self.tags = tags
        self.cites = cites
        self.exhibits = exhibits
        self.amends = amends
        self.amendsAlso = amendsAlso
        self.repeals = repeals
        self.source = source
        self.body = body
        self.cost = cost
    }
}

// MARK: - 증언 확인(주입)

/// 증언 확인에 넘기는 인용 구절 하나 — 증거물 sha256 과, 로컬 증거물 파일이 있으면 그 내용(UTF-8).
public struct LawExhibitQuote: Sendable, Equatable {
    public let sha256: String
    public let text: String?

    public init(sha256: String, text: String?) {
        self.sha256 = sha256
        self.text = text
    }
}

/// 증거 기록 공포 때 증언 확인자에게 묻는 내용(증거 기록의 머리 칸과 증거물).
public struct LawTestimonyRequest: Sendable, Equatable {
    public let session: String?
    public let utteranceAt: String?
    public let runtime: String?
    public let device: String?
    public let quotes: [LawExhibitQuote]

    public init(session: String?, utteranceAt: String?, runtime: String?, device: String?, quotes: [LawExhibitQuote]) {
        self.session = session
        self.utteranceAt = utteranceAt
        self.runtime = runtime
        self.device = device
        self.quotes = quotes
    }
}

/// 증언 확인자 — 실제 세션 조회 구현은 소환 모듈이 주입한다.
public protocol LawTestimonyVerifying: Sendable {
    /// 가린 인용 구절이, 같은 가림 규칙을 적용한 세션 발화 하나의 연속된 부분 문자열과 글자 단위로 같으면
    /// 그 발화 역할에 해당하는 화자를 돌려준다. 맞는 발화가 없으면 nil.
    func speaker(for request: LawTestimonyRequest) throws -> LawSpeaker?
}

// MARK: - 참조 해석(주입)

/// 참조가 놓인 자리. 허용 범위(같은 원장·상위 사슬·그 전신) 판정은 주입된 해석기가 한다.
public enum LawReferenceScope: String, Sendable, Equatable {
    case sameLedger = "same-ledger"
    case ancestor
    case predecessor
}

public struct LawResolvedReference: Sendable, Equatable {
    public let id: String
    /// 도착 기록의 유형(전신 객체면 옛 유형).
    public let type: String?
    public let origin: String?
    public let speaker: String?
    public let scope: LawReferenceScope

    public init(id: String, type: String?, origin: String?, speaker: String?, scope: LawReferenceScope) {
        self.id = id
        self.type = type
        self.origin = origin
        self.speaker = speaker
        self.scope = scope
    }
}

/// 참조 해석기. 같은 원장 밖(상위 사슬·전신)의 참조를 허용 범위 안에서만 풀고, 범위 밖이면 nil.
public protocol LawReferenceResolving: Sendable {
    func resolve(_ id: String) -> LawResolvedReference?
}

/// 기본 해석기 — 같은 원장 안만 본다.
public struct LawSameLedgerResolver: LawReferenceResolving {
    private let byID: [String: LawResolvedReference]

    public init(records: [LawStoredRecord]) {
        var map: [String: LawResolvedReference] = [:]
        for stored in records {
            map[stored.id] = LawResolvedReference(
                id: stored.id, type: stored.record.type, origin: stored.record.origin,
                speaker: stored.record.speaker, scope: .sameLedger)
        }
        byID = map
    }

    public func resolve(_ id: String) -> LawResolvedReference? { byID[id] }
}

/// 공포·감사에 주입하는 것들.
public struct LawEnactContext: Sendable {
    /// 증언 확인자. 없으면 세션 증언이 필요한 공포를 거부한다.
    public var testimony: (any LawTestimonyVerifying)?
    /// 같은 원장 밖 참조의 해석기(같은 원장은 항상 먼저 본다). 없으면 같은 원장 안만 본다.
    public var resolver: (any LawReferenceResolving)?

    public init(testimony: (any LawTestimonyVerifying)? = nil, resolver: (any LawReferenceResolving)? = nil) {
        self.testimony = testimony
        self.resolver = resolver
    }
}

/// 공포 거부 사유. 명령 계약의 종료 코드 1(거부)에 대응한다.
public enum LawEnactError: Error, Equatable, CustomStringConvertible {
    case unknownType(String)
    case valueNotAllowed(field: String, value: String)
    case multilineValue(String)
    case runtimeUnknown
    case modelUnknown
    case appIdentityMissing
    case humanModelFields
    case emptyBody
    case headField(LawHeadFieldError)
    case invalidExhibit(String)
    case relationNotAllowed(String)
    case relationSourceRefused(rel: String, type: String)
    case relationTargetRefused(rel: String, target: String)
    case unresolvedReference(String)
    case dreamCitationRefused(String)
    case migrationRequiresMigratedFrom
    case testimonyUnavailable
    case testimonyMismatch
    case speakerUserRequiresTestimony
    case duplicateID(String)
    case batchNotFound(String)

    public var description: String {
        switch self {
        case .unknownType(let t): return "모르는 유형: \(t)"
        case .valueNotAllowed(let f, let v): return "\(f) 값 \(v) 는 허용되지 않음"
        case .multilineValue(let f): return "\(f) 값에 줄바꿈이 있음"
        case .runtimeUnknown: return "실행 도구 미상 — 에이전트 공포는 runtime 이 필요하다"
        case .modelUnknown: return "모델 미상 — 에이전트 공포는 model 이 필요하다"
        case .appIdentityMissing: return "앱 공포는 app·app-version 이 필요하다"
        case .humanModelFields: return "사람 공포는 모델 칸을 비운다"
        case .emptyBody: return "빈 본문(폐지만 예외)"
        case .headField(let e): return e.description
        case .invalidExhibit(let s): return "증거물 sha256 형식 오류: \(s)"
        case .relationNotAllowed(let r): return "허용되지 않은 관계: \(r)"
        case .relationSourceRefused(let r, let t): return "관계 \(r) 는 유형 \(t) 에서 출발할 수 없음"
        case .relationTargetRefused(let r, let id): return "관계 \(r) 의 도착 \(id) 가 규칙에 맞지 않음"
        case .unresolvedReference(let id): return "없는 기록 참조(또는 허용 범위 밖): \(id)"
        case .dreamCitationRefused(let id): return "드리밍 정리본 \(id) 는 증거·증언·사실인정 근거가 될 수 없음"
        case .migrationRequiresMigratedFrom: return "이관 기록은 전신 객체를 migrated-from 으로 인용해야 함"
        case .testimonyUnavailable: return "증언 확인자가 없어 세션 증언을 확인할 수 없음"
        case .testimonyMismatch: return "증언 불일치 — 인용 구절이 세션 발화와 맞지 않음"
        case .speakerUserRequiresTestimony: return "speaker: user 는 speaker: user 증거 기록을 testifies 로 인용해야 함"
        case .duplicateID(let id): return "이미 공포된 id 에 다른 바이트: \(id)"
        case .batchNotFound(let b): return "묶음을 찾을 수 없음: \(b)"
        }
    }
}
