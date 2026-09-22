import Foundation

/// 프롬프트 문구로부터 어울리는 계층을 추천한다. 오케스트레이터가 태스크를
/// 발행할 때 tier 를 명시하지 않았을 때의 합리적 기본값을 정하는 용도.
public enum TierResolver {
    /// 우선순위: verifier 키워드 → coordinator 키워드 → worker 키워드 → 기본 worker.
    /// (검증 문구가 "구현·검증" 처럼 같이 나오면 더 저렴한 verifier 로 보수적으로 튄다.)
    private static let verifierKeywords = ["검증", "테스트", "lint", "확인"]
    private static let coordinatorKeywords = ["계획", "설계", "판단", "분해"]
    private static let workerKeywords = ["구현", "작성", "수정", "리팩터"]

    public static func resolveTier(fromPrompt prompt: String) -> AgentTier {
        let lower = prompt.lowercased()
        if verifierKeywords.contains(where: { lower.contains($0.lowercased()) }) { return .verifier }
        if coordinatorKeywords.contains(where: { lower.contains($0.lowercased()) }) { return .coordinator }
        if workerKeywords.contains(where: { lower.contains($0.lowercased()) }) { return .worker }
        return .worker
    }
}
