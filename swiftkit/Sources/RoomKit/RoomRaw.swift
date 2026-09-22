import CryptoKit
import Foundation

// MARK: - 에이전트 및 스킬 객체화 (First-Class Agent & Skill Objects)

/// 에이전트의 객체화된 사양 (Agent Specification)
public struct AgentSpec: Codable, Equatable, Sendable {
    public let role: String
    public let tier: String
    public let model: String?
    public let authorityLevel: String
    public let traits: [String]

    public init(
        role: String,
        tier: String = "worker",
        model: String? = nil,
        authorityLevel: String = "standard",
        traits: [String] = []
    ) {
        self.role = role
        self.tier = tier
        self.model = model
        self.authorityLevel = authorityLevel
        self.traits = traits
    }
}

/// 에이전트에 장착되는 객체화된 스킬 묶음 (Skill Bundle)
public struct SkillBundle: Codable, Equatable, Sendable {
    public let bundleID: String
    public let skills: [String]
    public let requiredCLIs: [String]
    public let contractRules: [String]

    public init(
        bundleID: String,
        skills: [String] = [],
        requiredCLIs: [String] = [],
        contractRules: [String] = []
    ) {
        self.bundleID = bundleID
        self.skills = skills
        self.requiredCLIs = requiredCLIs
        self.contractRules = contractRules
    }

    /// 기본 워커 스킬 번들
    public static let standardWorker = SkillBundle(
        bundleID: "skill-bundle.standard-worker",
        skills: ["agent-work-todo", "agent-lint-catalog"],
        requiredCLIs: ["agent-work-todo"],
        contractRules: [
            "미앱화 스크립트(.sh) 생성 및 실행 금지",
            "방 밖에서 일하는 에이전트 금지 (방 안에서만 작업)",
            "Twin-Lock: Versions 마케팅 버전과 CHANGELOG 동시 갱신"
        ]
    )
}

// MARK: - room-raw 원천 규율·스펙 및 신선도 영수증 (RoomRaw & Freshness Receipt)

/// 실무 방에 진입하기 전 반드시 통과해야 하는 원천 규율·스펙·스킬 패키지 (room-raw).
/// 내용이 갱신(update)되면 contentHash가 변경되어 기존 영수증이 stale 무효화됩니다.
public struct RoomRaw: Codable, Equatable, Sendable {
    public let rawID: UUID
    public let planID: UUID
    public let rawRoomID: UUID
    public let targetRoomID: UUID
    public let agentSpec: AgentSpec
    public var skillBundle: SkillBundle
    public var mandatoryRules: [String]
    public var taskBrief: String
    public var documentPaths: [String]
    public var version: Int
    public var contentHash: String
    public var updatedAt: Date
    public var acknowledgedAt: Date?
    public var acknowledgedBy: String?

    public init(
        planID: UUID,
        rawRoomID: UUID,
        targetRoomID: UUID,
        agentSpec: AgentSpec,
        skillBundle: SkillBundle,
        mandatoryRules: [String],
        taskBrief: String,
        documentPaths: [String] = []
    ) {
        self.rawID = UUID()
        self.planID = planID
        self.rawRoomID = rawRoomID
        self.targetRoomID = targetRoomID
        self.agentSpec = agentSpec
        self.skillBundle = skillBundle
        self.mandatoryRules = mandatoryRules
        self.taskBrief = taskBrief
        self.documentPaths = documentPaths
        self.version = 1
        self.updatedAt = Date()
        self.acknowledgedAt = nil
        self.acknowledgedBy = nil
        self.contentHash = Self.calculateHash(
            skills: skillBundle.skills,
            requiredCLIs: skillBundle.requiredCLIs,
            contractRules: skillBundle.contractRules,
            mandatoryRules: mandatoryRules,
            taskBrief: taskBrief,
            documentPaths: documentPaths
        )
    }

    /// 원천 내용 전체의 SHA-256 해시를 계산합니다.
    public static func calculateHash(
        skills: [String],
        requiredCLIs: [String],
        contractRules: [String],
        mandatoryRules: [String],
        taskBrief: String,
        documentPaths: [String] = []
    ) -> String {
        let payload = [
            skills.sorted().joined(separator: ","),
            requiredCLIs.sorted().joined(separator: ","),
            contractRules.joined(separator: "\n"),
            mandatoryRules.joined(separator: "\n"),
            taskBrief,
            documentPaths.sorted().joined(separator: ",")
        ].joined(separator: "||")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// 내용 업데이트 — 해시 재계산 및 버전 증가
    public mutating func updateContent(
        rules: [String]? = nil,
        taskBrief: String? = nil,
        skillBundle: SkillBundle? = nil,
        documentPaths: [String]? = nil
    ) {
        applyMutations(rules: rules, taskBrief: taskBrief, documentPaths: documentPaths)
        if let skillBundle { self.skillBundle = skillBundle }
        self.version += 1
        self.updatedAt = Date()
        self.contentHash = Self.calculateHash(
            skills: self.skillBundle.skills,
            requiredCLIs: self.skillBundle.requiredCLIs,
            contractRules: self.skillBundle.contractRules,
            mandatoryRules: self.mandatoryRules,
            taskBrief: self.taskBrief,
            documentPaths: self.documentPaths
        )
    }

    private mutating func applyMutations(rules: [String]?, taskBrief: String?, documentPaths: [String]?) {
        self.mandatoryRules = rules ?? self.mandatoryRules
        self.taskBrief = taskBrief ?? self.taskBrief
        self.documentPaths = documentPaths ?? self.documentPaths
    }

    /// 교육/원천 이수 완료 여부
    public var isAcknowledged: Bool {
        acknowledgedAt != nil
    }

    // 하위 호환 프로퍼티
    public var orientationID: UUID { rawID }
    public var factoryRoomID: UUID { rawRoomID }
}

/// room-raw 이수 증명 영수증.
/// 이수한 시점의 rawContentHash가 각인되어, 원천 갱신 시 신선도(freshness)를 판정합니다.
public struct RoomRawReceipt: Codable, Equatable, Sendable {
    public let receiptID: UUID
    public let rawID: UUID
    public let rawContentHash: String
    public let rawVersion: Int
    public let planID: UUID
    public let rawRoomID: UUID
    public let targetRoomID: UUID
    public let occupant: String
    public let certifiedAt: Date

    public init(
        receiptID: UUID = UUID(),
        rawID: UUID,
        rawContentHash: String,
        rawVersion: Int = 1,
        planID: UUID,
        rawRoomID: UUID,
        targetRoomID: UUID,
        occupant: String,
        certifiedAt: Date = Date()
    ) {
        self.receiptID = receiptID
        self.rawID = rawID
        self.rawContentHash = rawContentHash
        self.rawVersion = rawVersion
        self.planID = planID
        self.rawRoomID = rawRoomID
        self.targetRoomID = targetRoomID
        self.occupant = occupant
        self.certifiedAt = certifiedAt
    }

    /// 원천 room-raw 및 참조 문서 대비 최신(신선) 상태인지 검증합니다.
    /// 내용 해시뿐 아니라 raw.updatedAt 및 디스크 파일 수정시각(mtime)을 대조하여 만료(stale)를 판정합니다.
    public func isFresh(for raw: RoomRaw, fileManager: FileManager = .default) -> Bool {
        guard self.rawContentHash == raw.contentHash else { return false }
        guard raw.updatedAt <= self.certifiedAt else { return false }
        return areDocumentsFresh(paths: raw.documentPaths, certifiedAt: self.certifiedAt, fileManager: fileManager)
    }

    private func areDocumentsFresh(paths: [String], certifiedAt: Date, fileManager: FileManager) -> Bool {
        for path in paths {
            do {
                let attrs = try fileManager.attributesOfItem(atPath: path)
                guard let mtime = attrs[.modificationDate] as? Date else { continue }
                if mtime > certifiedAt {
                    return false
                }
            } catch {
                continue
            }
        }
        return true
    }

    public static func == (lhs: RoomRawReceipt, rhs: RoomRawReceipt) -> Bool {
        lhs.receiptID == rhs.receiptID &&
        lhs.rawID == rhs.rawID &&
        lhs.rawContentHash == rhs.rawContentHash &&
        lhs.rawVersion == rhs.rawVersion &&
        lhs.planID == rhs.planID &&
        lhs.rawRoomID == rhs.rawRoomID &&
        lhs.targetRoomID == rhs.targetRoomID &&
        lhs.occupant == rhs.occupant &&
        abs(lhs.certifiedAt.timeIntervalSince(rhs.certifiedAt)) < 1.0
    }

    // 하위 호환 프로퍼티
    public var orientationID: UUID { rawID }
    public var factoryRoomID: UUID { rawRoomID }
}

// MARK: - 하위 호환 및 도메인 정합 Typealias

public typealias FactoryOrientation = RoomRaw
public typealias OrientationReceipt = RoomRawReceipt
public typealias RoomOnboarding = RoomRaw
public typealias RoomPermit = RoomRawReceipt

// MARK: - 하네스 교정 및 위임 모델 (Inter-Room Remediation & Delegation)

/// 하네스 락업/린트 차단 시 검수 룸이 발행하는 교정 제안서
public struct RemediationProposal: Codable, Equatable, Sendable {
    public let proposalID: UUID
    public let sourceRoomID: UUID
    public let inspectorRoomID: UUID
    public let issueSummary: String
    public let patchInstructions: [String]
    public let suggestedSkills: [String]
    public let certifiedAt: Date
    public let inspectorIdentity: String

    public init(
        proposalID: UUID = UUID(),
        sourceRoomID: UUID,
        inspectorRoomID: UUID,
        issueSummary: String,
        patchInstructions: [String],
        suggestedSkills: [String] = [],
        certifiedAt: Date = Date(),
        inspectorIdentity: String
    ) {
        self.proposalID = proposalID
        self.sourceRoomID = sourceRoomID
        self.inspectorRoomID = inspectorRoomID
        self.issueSummary = issueSummary
        self.patchInstructions = patchInstructions
        self.suggestedSkills = suggestedSkills
        self.certifiedAt = certifiedAt
        self.inspectorIdentity = inspectorIdentity
    }
}

/// 타 룸 위임 요청 (위임 깊이 = 1 엄격 강제)
public struct DelegationRequest: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let sourceRoomID: UUID
    public let inspectorRoomSlug: String
    public let issue: String
    public let targetSession: String?
    public let requestedAt: Date

    public init(
        requestID: UUID = UUID(),
        sourceRoomID: UUID,
        inspectorRoomSlug: String,
        issue: String,
        targetSession: String? = nil,
        requestedAt: Date = Date()
    ) {
        self.requestID = requestID
        self.sourceRoomID = sourceRoomID
        self.inspectorRoomSlug = inspectorRoomSlug
        self.issue = issue
        self.targetSession = targetSession
        self.requestedAt = requestedAt
    }
}
