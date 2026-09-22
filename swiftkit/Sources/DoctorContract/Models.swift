import Foundation

/// Fleet-wide doctor finding — one atomic observation.
public struct DoctorFinding: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var category: DoctorCategory
    public var severity: DoctorSeverity
    public var subject: String
    public var title: String
    public var detail: String
    public var remedy: String?
    public var source: String
    public var observedAt: Date
    public var checkKind: CheckKind = .structural
    public var payload: [String: String]

    public enum CheckKind: String, Sendable, Codable {
        case structural
        case behavioral
    }

    public struct Body: Sendable, Equatable, Codable {
        public var subject: String
        public var title: String
        public var detail: String
        public var remedy: String?
        public init(
            subject: String,
            title: String,
            detail: String,
            remedy: String? = nil
        ) {
            self.subject = subject
            self.title = title
            self.detail = detail
            self.remedy = remedy
        }
    }

    public init(
        id: String = UUID().uuidString,
        category: DoctorCategory,
        severity: DoctorSeverity,
        body: Body,
        source: String,
        observedAt: Date = Date(),
        checkKind: CheckKind = .structural,
        payload: [String: String] = [:]
    ) {
        self.id = id
        self.category = category
        self.severity = severity
        self.subject = body.subject
        self.title = body.title
        self.detail = body.detail
        self.remedy = body.remedy
        self.source = source
        self.observedAt = observedAt
        self.checkKind = checkKind
        self.payload = payload
    }
}

public enum DoctorCategory: String, Codable, CaseIterable, Sendable {
    case install
    case dependency
    case crash
    case quarantine
    case runtime
    case published
    /// Fleet management tools (path-cli-health, agent-cli-manager, ADM, …).
    case management
    /// 에이전트 도달 감시 — agent-reach-watch 가 당긴 도달 분포/갭.
    case reach
    /// 설치본 신선도 — path-cli-health stale-source 가 당긴, 번들이 origin/main
    /// 최신 소스보다 뒤처진 앱들(SourceProvenance 대조).
    case staleSource
    /// 자격 도달 — 앱이 부르는 vault agentID 가 실제로 등록돼 있나.
    /// 도달 4인자(registry·capabilities·agentSurface·stateMirror)는 "에이전트가 앱을
    /// 찾는 통로" 를 재지만, "앱이 자격에 닿는가" 는 아무도 안 봤다(2026-08-11 실측:
    /// 12개 앱의 조회가 죽어 있었고 vault 는 usage 오류 한 줄로만 답했다).
    case credentialReach
    case other
}

public enum DoctorSeverity: String, Codable, CaseIterable, Sendable, Comparable {
    case ok
    case info
    case warn
    case fail

    private var rank: Int {
        switch self {
        case .ok: return 0
        case .info: return 1
        case .warn: return 2
        case .fail: return 3
        }
    }

    public static func < (lhs: DoctorSeverity, rhs: DoctorSeverity) -> Bool {
        lhs.rank < rhs.rank
    }
}

public struct DoctorReport: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var findings: [DoctorFinding]

    public init(generatedAt: Date = Date(), findings: [DoctorFinding]) {
        self.generatedAt = generatedAt
        self.findings = findings
    }

    public var failCount: Int { findings.filter { $0.severity == .fail }.count }
    public var warnCount: Int { findings.filter { $0.severity == .warn }.count }
    public var okCount: Int { findings.filter { $0.severity == .ok }.count }

    public func filtered(category: DoctorCategory? = nil, minSeverity: DoctorSeverity = .ok) -> DoctorReport {
        let items = findings.filter { f in
            (category == nil || f.category == category) && f.severity >= minSeverity
        }
        return DoctorReport(generatedAt: generatedAt, findings: items)
    }
}

/// Per-app published doctor payload (StateMirror or ~/.swift-app-doctor/<app>.json).
public struct AppDoctorReport: Codable, Equatable, Sendable {
    public var app: String
    public var updatedAt: Date
    public var findings: [DoctorFinding]

    public init(app: String, updatedAt: Date = Date(), findings: [DoctorFinding]) {
        self.app = app
        self.updatedAt = updatedAt
        self.findings = findings
    }
}
