import Foundation
import AgentSessionKit

/// 세션 로그에 **주입 원문이 실제로 남은** 경우 그것을 회수한다.
///
/// 현재 이게 가능한 런타임은 Codex 뿐이다. Codex 는 매 세션 첫 사용자 메시지로
/// `# AGENTS.md instructions\n\n<INSTRUCTIONS>…</INSTRUCTIONS>` 를 밀어 넣고 그대로 기록한다.
/// 그래서 Codex 세션은 재구성이 아니라 **관측**으로 답할 수 있다.
///
/// 이게 왜 중요한가 — 실측 예: 2026-07-28 세션의 주입본은 "장기 메모리의 정본은 gujo wiki"
/// 라고 적혀 있는데 오늘 같은 파일은 "Agent Wiki" 라고 말한다. 현재 파일만 보고
/// "그때 이렇게 지시했다"고 말하면 틀린다. 시점 내용은 시점 증거로만 답한다.
public enum InjectionEvidence {
    public struct Block: Sendable, Equatable {
        public let text: String
        public let approxTokens: Int
        /// 이 블록과 함께 기록된 cwd(`<environment_context>`). 없을 수 있다.
        public let cwd: String?

        public init(text: String, approxTokens: Int, cwd: String?) {
            self.text = text
            self.approxTokens = approxTokens
            self.cwd = cwd
        }
    }

    /// 세션에서 주입 블록을 뽑는다. 없으면 빈 배열(= 이 런타임/세션은 관측 불가).
    public static func blocks(_ ref: SessionRef, maxBytes: Int = 4 * 1024 * 1024) -> [Block] {
        guard ref.tool == .codex else { return [] }
        var out: [Block] = []
        var pendingCwd: String?
        JSONLine.forEachLine(path: ref.transcriptPath, maxBytes: maxBytes) { line in
            guard let payload = line["payload"] as? [String: Any],
                  payload["type"] as? String == "message",
                  payload["role"] as? String == "user",
                  let parts = payload["content"] as? [[String: Any]]
            else { return true }
            for part in parts {
                guard let text = JSONLine.string(part["text"]) else { continue }
                if let cwd = between(text, "<cwd>", "</cwd>") { pendingCwd = cwd }
                if let body = between(text, "<INSTRUCTIONS>", "</INSTRUCTIONS>") {
                    out.append(Block(
                        text: body,
                        approxTokens: TokenEstimate.approxTokens(body),
                        cwd: pendingCwd
                    ))
                }
            }
            // 첫 주입만 필요하다. 압축(compacted) 후 재주입까지 다 모으면 같은 지침이 중복 계산된다.
            return out.isEmpty
        }
        return out
    }

    /// 재구성한 후보 스택을 주입 원문과 대조해 provenance 를 승격한다.
    ///
    /// 후보의 **현재 내용**이 주입 원문 안에 통째로 들어 있으면 그 파일은 그때 주입됐고
    /// 그 뒤로 안 바뀐 것이다 → `.injected`. 안 들어 있으면 둘 중 하나다 —
    /// 주입되지 않았거나, 주입된 뒤 파일이 바뀌었거나(드리프트). 어느 쪽인지 단정하지 않고
    /// `.reconstructedCurrent` 로 남긴다. 여기서 추측하면 이 앱의 존재 이유가 사라진다.
    public static func reconcile(_ candidates: [InjectedDoc], with blocks: [Block]) -> [InjectedDoc] {
        guard !blocks.isEmpty else { return candidates }
        let haystack = blocks.map(\.text).joined(separator: "\n")
        return candidates.map { doc in
            guard !doc.missing,
                  let text = try? String(contentsOfFile: doc.path, encoding: .utf8),
                  let probe = probe(text),
                  haystack.contains(probe)
            else { return doc }
            return InjectedDoc(
                path: doc.path, layer: doc.layer, provenance: .injected,
                bytes: doc.bytes, approxTokens: doc.approxTokens,
                importedBy: doc.importedBy, missing: doc.missing
            )
        }
    }

    /// 대조용 지문 — 파일 앞부분의 의미 있는 한 조각.
    ///
    /// 전문 비교를 안 하는 이유: Codex 는 여러 AGENTS.md 를 이어 붙이면서 헤더를 덧대고
    /// 줄바꿈을 정규화한다. 전문 일치를 요구하면 항상 실패한다.
    public static func probe(_ text: String, minLength: Int = 40, maxLength: Int = 400) -> String? {
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("---") }
        guard let seed = lines.first(where: { $0.count >= minLength }) else { return nil }
        return String(seed.prefix(maxLength))
    }

    public static func between(_ text: String, _ open: String, _ close: String) -> String? {
        guard let o = text.range(of: open),
              let c = text.range(of: close, range: o.upperBound..<text.endIndex)
        else { return nil }
        return String(text[o.upperBound..<c.lowerBound])
    }
}
