import Foundation

/// scene evidence 독립 역링크 객체 구조체.
/// 결정(decision) 객체에 역링크된 현장 근거 객체를 독립적인 메타데이터로 표현한다.
public struct SceneEvidenceBacklink: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let targetDecisionID: String
    public let title: String?
    public let author: String
    public let published: Date
    public let rel: String
    public let body: String

    public init(
        id: String,
        targetDecisionID: String,
        title: String? = nil,
        author: String,
        published: Date,
        rel: String = PublishCompleteness.sceneEvidenceRel,
        body: String
    ) {
        self.id = id
        self.targetDecisionID = targetDecisionID
        self.title = title
        self.author = author
        self.published = published
        self.rel = rel
        self.body = body
    }

    /// LedgerObject 로부터 SceneEvidenceBacklink 추출.
    public static func from(object: LedgerObject, targetDecisionID: String? = nil) -> SceneEvidenceBacklink? {
        guard object.effectiveType == PublishCompleteness.sceneEvidenceType else { return nil }
        let decisionID: String
        if let target = targetDecisionID {
            guard object.cites.contains(where: { $0.id == target && $0.rel == PublishCompleteness.sceneEvidenceRel })
                    || PublishCompleteness.parseSceneEvidenceOf(object.body) == target
            else { return nil }
            decisionID = target
        } else {
            if let cite = object.cites.first(where: { $0.rel == PublishCompleteness.sceneEvidenceRel }) {
                decisionID = cite.id
            } else if let parsed = PublishCompleteness.parseSceneEvidenceOf(object.body) {
                decisionID = parsed
            } else {
                return nil
            }
        }
        return SceneEvidenceBacklink(
            id: object.id,
            targetDecisionID: decisionID,
            title: object.title,
            author: object.author,
            published: object.published,
            rel: PublishCompleteness.sceneEvidenceRel,
            body: object.body
        )
    }
}

extension LedgerObject {
    /// 이 객체가 scene-evidence 인지 여부.
    public var isSceneEvidence: Bool {
        effectiveType == PublishCompleteness.sceneEvidenceType
    }

    /// 이 객체가 scene-evidence 인 경우 역링크 메타데이터 객체를 반환.
    public var sceneEvidenceBacklink: SceneEvidenceBacklink? {
        SceneEvidenceBacklink.from(object: self)
    }

    /// 이 객체가 결정(decision)인 경우, 전달받은 전체 객체 풀에서 이 결정을 역링크하는 scene evidence 객체들을 찾는다.
    public func sceneEvidenceBacklinks(in objects: [LedgerObject]) -> [SceneEvidenceBacklink] {
        guard effectiveType == "decision" else { return [] }
        return objects.compactMap { SceneEvidenceBacklink.from(object: $0, targetDecisionID: self.id) }
    }
}

extension LedgerStore {
    /// 주어진 결정(decision) 객체에 대한 scene evidence 역링크 객체 목록을 반환한다.
    public func sceneEvidences(forDecisionID decisionID: String, in objects: [LedgerObject]? = nil) -> [SceneEvidenceBacklink] {
        let pool = objects ?? scan()
        return pool.compactMap { SceneEvidenceBacklink.from(object: $0, targetDecisionID: decisionID) }
    }
}
