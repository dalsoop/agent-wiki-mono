import Foundation

/// 세션 전사본(JSONL) 또는 로그로부터 실제 토큰 사용량(`prompt_tokens`, `completion_tokens`, `total_tokens`, `cost_usd`)을 수집한다.
///
/// 어림짐작(로그 크기 / 4 등)을 배제하고, 에이전트 런타임(Grok, Codex, Claude, Antigravity, Generic API)이
/// 남긴 실제 계량 필드(`usage`, `token_usage`, `last_token_usage`, `total_token_usage`)를 단일 정본으로 파싱한다.
public struct SessionTokenUsage: Codable, Equatable, Sendable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var totalTokens: Int
    public var costUSD: Double?

    public init(
        promptTokens: Int = 0,
        completionTokens: Int = 0,
        totalTokens: Int = 0,
        costUSD: Double? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens > 0 ? totalTokens : (promptTokens + completionTokens)
        self.costUSD = costUSD
    }

    public static let zero = SessionTokenUsage()
}

public enum TranscriptUsageReader {
    /// 세션 로그 또는 전사본(JSONL) 파일 경로에서 실제 token_usage / usage 를 읽는다.
    public static func readUsage(atPath path: String) -> SessionTokenUsage {
        guard FileManager.default.fileExists(atPath: path) else { return .zero }
        var aggregator = Aggregator()
        JSONLine.forEachLine(path: path) { obj in
            aggregator.ingest(obj)
            return true
        }
        return aggregator.finalize()
    }

    /// 세션 로그 또는 전사본 텍스트(개행 구분 줄)에서 실제 token_usage / usage 를 읽는다.
    public static func readUsage(from text: String) -> SessionTokenUsage {
        var aggregator = Aggregator()
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let data = trimmed.data(using: .utf8) else { continue }
            let obj: [String: Any]
            do {
                guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                obj = parsed
            } catch {
                continue
            }
            aggregator.ingest(obj)
        }
        return aggregator.finalize()
    }

    // MARK: - Aggregator

    struct Aggregator {
        var cumulativeUsage: SessionTokenUsage?
        var accumulatedPrompt = 0
        var accumulatedCompletion = 0
        var accumulatedTotal = 0
        var accumulatedCost: Double?
        var sawAnyUsage = false

        mutating func ingest(_ obj: [String: Any]) {
            if ingestResultLine(obj) { return }
            if ingestCodexTotal(obj) { return }
            if ingestCodexTurn(obj) { return }
            if ingestAssistantTurn(obj) { return }
            if ingestGrokACPTurn(obj) { return }
            _ = ingestTopLevelUsage(obj)
        }

        private mutating func ingestResultLine(_ obj: [String: Any]) -> Bool {
            guard (obj["type"] as? String) == "result" else { return false }
            let cost = extractDouble(obj, keys: ["total_cost_usd", "totalCostUsd", "cost_usd", "costUSD"])

            if let usageDict = obj["usage"] as? [String: Any],
               let parsed = parseUsageDict(usageDict, explicitCost: cost) {
                cumulativeUsage = parsed
                sawAnyUsage = true
                return true
            }

            guard let modelUsage = obj["modelUsage"] as? [String: Any] else { return false }
            return ingestModelUsage(modelUsage, explicitCost: cost)
        }

        private mutating func ingestModelUsage(_ modelUsage: [String: Any], explicitCost: Double?) -> Bool {
            var totalP = 0
            var totalC = 0
            var totalCost = explicitCost
            for (_, v) in modelUsage {
                guard let modelDict = v as? [String: Any],
                      let p = parseUsageDict(modelDict, explicitCost: nil) else { continue }
                totalP += p.promptTokens
                totalC += p.completionTokens
                if let mc = extractDouble(modelDict, keys: ["costUSD", "cost_usd", "total_cost_usd"]) {
                    totalCost = (totalCost ?? 0.0) + mc
                }
            }
            guard totalP > 0 || totalC > 0 || totalCost != nil else { return false }
            cumulativeUsage = SessionTokenUsage(
                promptTokens: totalP,
                completionTokens: totalC,
                totalTokens: totalP + totalC,
                costUSD: totalCost
            )
            sawAnyUsage = true
            return true
        }

        private mutating func ingestCodexTotal(_ obj: [String: Any]) -> Bool {
            guard let payload = obj["payload"] as? [String: Any],
                  let info = payload["info"] as? [String: Any],
                  let totalDict = (info["total_token_usage"] ?? info["totalTokenUsage"]) as? [String: Any],
                  let parsed = parseUsageDict(totalDict, explicitCost: nil) else {
                return false
            }
            cumulativeUsage = parsed
            sawAnyUsage = true
            return true
        }

        private mutating func ingestCodexTurn(_ obj: [String: Any]) -> Bool {
            guard let payload = obj["payload"] as? [String: Any],
                  let info = payload["info"] as? [String: Any],
                  let lastDict = (info["last_token_usage"] ?? info["lastTokenUsage"]) as? [String: Any],
                  let parsed = parseUsageDict(lastDict, explicitCost: nil) else {
                return false
            }
            accumulate(parsed)
            return true
        }

        private mutating func ingestAssistantTurn(_ obj: [String: Any]) -> Bool {
            guard let message = obj["message"] as? [String: Any],
                  let usageDict = message["usage"] as? [String: Any],
                  let parsed = parseUsageDict(usageDict, explicitCost: nil) else {
                return false
            }
            accumulate(parsed)
            return true
        }

        private mutating func ingestGrokACPTurn(_ obj: [String: Any]) -> Bool {
            guard let params = obj["params"] as? [String: Any],
                  let update = params["update"] as? [String: Any],
                  let usageDict = update["usage"] as? [String: Any],
                  let parsed = parseUsageDict(usageDict, explicitCost: nil) else {
                return false
            }
            accumulate(parsed)
            return true
        }

        private mutating func ingestTopLevelUsage(_ obj: [String: Any]) -> Bool {
            guard let usageDict = (obj["token_usage"] ?? obj["tokenUsage"] ?? obj["usage"]) as? [String: Any] else {
                return false
            }
            let cost = extractDouble(obj, keys: ["total_cost_usd", "totalCostUsd", "cost_usd", "costUSD"])
            guard let parsed = parseUsageDict(usageDict, explicitCost: cost) else { return false }
            accumulate(parsed)
            return true
        }

        private mutating func accumulate(_ parsed: SessionTokenUsage) {
            accumulatedPrompt += parsed.promptTokens
            accumulatedCompletion += parsed.completionTokens
            accumulatedTotal += parsed.totalTokens
            if let c = parsed.costUSD {
                accumulatedCost = (accumulatedCost ?? 0.0) + c
            }
            sawAnyUsage = true
        }

        func finalize() -> SessionTokenUsage {
            if let cum = cumulativeUsage, cum.totalTokens > 0 {
                return cum
            }
            guard sawAnyUsage else { return .zero }
            let total = accumulatedTotal > 0 ? accumulatedTotal : (accumulatedPrompt + accumulatedCompletion)
            return SessionTokenUsage(
                promptTokens: accumulatedPrompt,
                completionTokens: accumulatedCompletion,
                totalTokens: total,
                costUSD: cumulativeUsage?.costUSD ?? accumulatedCost
            )
        }
    }

    private static func parseUsageDict(_ dict: [String: Any], explicitCost: Double?) -> SessionTokenUsage? {
        let prompt = extractInt(dict, keys: [
            "prompt_tokens", "promptTokens", "input_tokens", "inputTokens", "prompt"
        ]) ?? 0
        let completion = extractInt(dict, keys: [
            "completion_tokens", "completionTokens", "output_tokens", "outputTokens", "completion"
        ]) ?? 0
        let total = extractInt(dict, keys: [
            "total_tokens", "totalTokens", "total"
        ]) ?? (prompt + completion)
        let cost = explicitCost ?? extractDouble(dict, keys: [
            "total_cost_usd", "totalCostUsd", "cost_usd", "costUSD", "cost"
        ])

        guard prompt > 0 || completion > 0 || total > 0 || cost != nil else { return nil }
        return SessionTokenUsage(
            promptTokens: prompt,
            completionTokens: completion,
            totalTokens: total,
            costUSD: cost
        )
    }

    private static func extractInt(_ dict: [String: Any], keys: [String]) -> Int? {
        for k in keys {
            if let val = dict[k] as? Int { return val }
            if let val = dict[k] as? Double { return Int(val) }
            if let val = dict[k] as? NSNumber { return val.intValue }
            if let s = dict[k] as? String, let val = Int(s) { return val }
        }
        return nil
    }

    private static func extractDouble(_ dict: [String: Any], keys: [String]) -> Double? {
        for k in keys {
            if let val = dict[k] as? Double { return val }
            if let val = dict[k] as? Int { return Double(val) }
            if let val = dict[k] as? NSNumber { return val.doubleValue }
            if let s = dict[k] as? String, let val = Double(s) { return val }
        }
        return nil
    }
}
