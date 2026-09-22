import Foundation

/// 사람 심사 판정 — 심사대의 정제본(digest)을 사람이 루브릭+코멘트로 판정한 결과.
/// distiller 세대 진화(3단계)의 학습 신호이자, 수락 시 위키 확립의 근거다.
/// 심사 객체는 `reviews` rel 로 대상 정제본을 인용하고, 본문에 판정·점수·코멘트를 담는다.
public struct ReviewVerdict: Sendable, Equatable {
    public enum Decision: String, Sendable { case accept, reject }

    public var decision: Decision
    public var scores: [String: Int]   // 축 → 0~5
    public var comment: String

    /// 루브릭 축 — distiller 자가채점과 같은 축(사람이 대조·보정).
    public static let axes = ["정확성", "구조", "출처밀도", "간결성"]
    /// 심사 객체가 정제본을 가리키는 인용 rel.
    public static let rel = "reviews"

    public init(decision: Decision, scores: [String: Int] = [:], comment: String = "") {
        self.decision = decision; self.scores = scores; self.comment = comment
    }

    public var averageScore: Double? {
        let vals = Self.axes.compactMap { scores[$0] }
        guard !vals.isEmpty else { return nil }
        return Double(vals.reduce(0, +)) / Double(vals.count)
    }

    /// 발행 본문 — frontmatter 아래 구조화 블록 + 코멘트. 파싱 왕복 가능.
    public func body() -> String {
        var lines = ["verdict: \(decision.rawValue)"]
        for axis in Self.axes { if let v = scores[axis] { lines.append("\(axis): \(v)") } }
        lines.append("---")
        lines.append(comment.isEmpty ? "(코멘트 없음)" : comment)
        return lines.joined(separator: "\n")
    }

    /// 심사 객체 본문에서 판정을 복원. 실패하면 nil.
    public init?(body: String) {
        let parts = body.components(separatedBy: "\n---\n")
        let head = parts.first ?? ""
        var decision: Decision?
        var scores: [String: Int] = [:]
        for line in head.split(separator: "\n") {
            let kv = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2 else { continue }
            if kv[0] == "verdict" { decision = Decision(rawValue: kv[1]) }
            else if Self.axes.contains(kv[0]), let n = Int(kv[1]) { scores[kv[0]] = n }
        }
        guard let decision else { return nil }
        self.init(decision: decision, scores: scores,
                  comment: parts.count > 1 ? parts[1...].joined(separator: "\n---\n") : "")
    }
}
