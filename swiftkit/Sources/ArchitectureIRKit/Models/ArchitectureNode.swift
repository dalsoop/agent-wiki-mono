import Foundation

public enum ArchitectureNodeType: String, Codable, Sendable, CaseIterable {
    case app
    case swiftkit
    case hostTool
    case externalMCP
}

public enum ArchitectureDistrict: String, Codable, Sendable, CaseIterable {
    case agent
    case business
    case infra
    case tooling
    case store
    case core
    case system
}

public struct ArchitectureNode: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var type: ArchitectureNodeType
    public var district: ArchitectureDistrict
    public var tetrahedron: TetrahedronSurfaceCompletion
    public var sourceEvidence: SourceEvidence
    public var wikiId: String?
    public var tags: [String]
    public var summary: String?
    public var temporal: NodeTemporalProfile?

    public init(
        id: String,
        name: String,
        type: ArchitectureNodeType,
        district: ArchitectureDistrict,
        tetrahedron: TetrahedronSurfaceCompletion,
        sourceEvidence: SourceEvidence,
        wikiId: String? = nil,
        tags: [String] = [],
        summary: String? = nil,
        temporal: NodeTemporalProfile? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.district = district
        self.tetrahedron = tetrahedron
        self.sourceEvidence = sourceEvidence
        self.wikiId = wikiId
        self.tags = tags
        self.summary = summary
        self.temporal = temporal
    }

    public static func makeId(type: ArchitectureNodeType, slug: String) -> String {
        "\(type.rawValue):\(slug)"
    }
}

public enum SurfaceFacetStatus: String, Codable, Sendable {
    case implemented
    case partial
    case missing
    case notApplicable
}

public struct SurfaceFacet: Codable, Sendable, Equatable {
    public var status: SurfaceFacetStatus
    public var evidencePath: String?
    public var note: String?

    public init(
        status: SurfaceFacetStatus,
        evidencePath: String? = nil,
        note: String? = nil
    ) {
        self.status = status
        self.evidencePath = evidencePath
        self.note = note
    }

    public var score: Double {
        switch status {
        case .implemented: return 1.0
        case .partial: return 0.5
        case .missing: return 0.0
        case .notApplicable: return 1.0
        }
    }
}

public struct TetrahedronSurfaceCompletion: Codable, Sendable, Equatable {
    public var gui: SurfaceFacet
    public var core: SurfaceFacet
    public var cli: SurfaceFacet
    public var statemirror: SurfaceFacet

    public init(
        gui: SurfaceFacet,
        core: SurfaceFacet,
        cli: SurfaceFacet,
        statemirror: SurfaceFacet
    ) {
        self.gui = gui
        self.core = core
        self.cli = cli
        self.statemirror = statemirror
    }

    public var overallScore: Double {
        (gui.score + core.score + cli.score + statemirror.score) / 4.0
    }

    public var grade: String {
        switch overallScore {
        case 1.0: return "reached"
        case 0.5..<1.0: return "partial"
        default: return "unreached"
        }
    }

    public var isComplete: Bool {
        overallScore >= 1.0
    }
}

public struct LineRange: Codable, Sendable, Equatable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

public struct SourceEvidence: Codable, Sendable, Equatable {
    public var filePath: String
    public var lineRange: LineRange?
    public var gitCommit: String?

    public init(filePath: String, lineRange: LineRange? = nil, gitCommit: String? = nil) {
        self.filePath = filePath
        self.lineRange = lineRange
        self.gitCommit = gitCommit
    }
}

public enum LifecyclePhase: String, Codable, Sendable, CaseIterable {
    case genesis      // 신생 (3~6월 태동/초기)
    case cambrian1    // 1차 캄브리아기 (7월 메뉴바/도구 폭발)
    case cambrian2    // 2차 캄브리아기 (8월 에이전트 함대 폭발)
    case mature       // 린 모노레포 및 안정기 (9월)
}

public enum ActivityTier: String, Codable, Sendable, CaseIterable {
    case tier1Core       // 매일 진화하는 심장부 (버전 1.6+ 또는 15회 이상 릴리즈)
    case tier2Platform   // 플랫폼/스토어 서비스 (버전 1.2~1.5)
    case tier3Stable     // 완성형 안정 유틸리티 (버전 1.0.x)
}

public struct NodeTemporalProfile: Codable, Sendable, Equatable {
    public var firstSeenDate: String       // YYYY-MM-DD
    public var currentVersion: String      // Versions/<slug>
    public var releaseCount: Int           // 버전/체인지로그 기반 변경 횟수
    public var lifecyclePhase: LifecyclePhase
    public var activityTier: ActivityTier
    public var pulseSpeed: Double          // 펄스 애니메이션 속도 (초 단위, 빠를수록 활성)

    public init(
        firstSeenDate: String,
        currentVersion: String,
        releaseCount: Int,
        lifecyclePhase: LifecyclePhase,
        activityTier: ActivityTier,
        pulseSpeed: Double = 0
    ) {
        self.firstSeenDate = firstSeenDate
        self.currentVersion = currentVersion
        self.releaseCount = releaseCount
        self.lifecyclePhase = lifecyclePhase
        self.activityTier = activityTier
        self.pulseSpeed = pulseSpeed
    }
}

