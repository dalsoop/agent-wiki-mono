import Foundation

/// 발행 완결성 규칙 — scene evidence 분.
///
/// scene evidence 는 결정(decision) 객체의 현장 근거를 담는 **독립 객체**다:
/// - 본문 첫 줄에 `of: <decision-id>` 역링크 필드를 갖는다(선별 screeningBody 와 같은 본문 필드 방식).
/// - 결정 객체는 evidence 쪽 cite(rel `of`)로만 인용한다 — 결정 객체 스키마는 바꾸지 않는다.
/// - 완결성: cite 1개 이상만 요구한다. 결정용 생략표 요구는 scene-evidence 에 **적용하지 않는다**.
public enum PublishCompleteness {
    public struct Failure: Error, Equatable, Sendable {
        public let message: String
        public init(_ message: String) { self.message = message }
    }

    public static let sceneEvidenceType = "scene-evidence"
    /// evidence → 결정 역링크 cite rel.
    public static let sceneEvidenceRel = "of"

    /// scene-evidence 발행 준비 — of 대상 검증 후 역링크 cite 를 만든다.
    /// 대상이 원장에 없거나, 있어도 결정(decision)이 아니면 거절.
    public static func sceneEvidenceLink(
        of decisionID: String,
        objects: [LedgerObject]
    ) -> Result<LedgerObject.Cite, Failure> {
        guard let target = objects.first(where: { $0.id == decisionID }) else {
            return .failure(Failure("없는 결정 객체: \(decisionID)"))
        }
        guard target.effectiveType == "decision" else {
            return .failure(Failure(
                "of 대상이 결정(decision)이 아님: \(decisionID) (type: \(target.effectiveType ?? "없음"))"))
        }
        return .success(LedgerObject.Cite(id: decisionID, rel: sceneEvidenceRel))
    }

    /// scene-evidence 본문 — `of:` 역링크 필드를 첫 줄로 박는다(이미 같은 값이 있으면 그대로).
    public static func sceneEvidenceBody(of decisionID: String, body: String) -> String {
        if parseSceneEvidenceOf(body) == decisionID { return body }
        return "of: \(decisionID)\n\n" + body
    }

    /// 본문에서 `of:` 역링크 필드를 읽는다(없으면 nil).
    public static func parseSceneEvidenceOf(_ body: String) -> String? {
        for line in body.split(separator: "\n") where line.hasPrefix("of: ") {
            let value = line.dropFirst("of: ".count).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// scene-evidence 완결성 — cite 1 이상. 결정용 생략표 요구는 적용하지 않는다.
    public static func validateSceneEvidence(cites: [LedgerObject.Cite]) -> Failure? {
        guard !cites.isEmpty else {
            return Failure("scene-evidence 는 cite 1개 이상이 필요합니다 (--of <decision-id>)")
        }
        return nil
    }
}
