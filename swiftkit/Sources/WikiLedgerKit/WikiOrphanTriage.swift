import Foundation

/// 위키 고립 지식의 원인 분류(triage). 위키 도메인 지식이라 이 킷이 소유 —
/// studio(대시보드)와 reaper(처치)가 같은 분류를 공유한다.
public enum WikiOrphanTriage {

    /// 고립 원인. 분류별 처치가 다르다.
    public enum Cause: String, Sendable, Codable, CaseIterable {
        /// 수입 부채 — llmwiki-import 등 대량 수입이 연결 없이 쏟아진 것. 처치: 통합/승격.
        case importDebt = "import-debt"
        /// 단말 — run/screening/classification 처럼 잘 수행된 操作 기록. 정상. 처치: 면제.
        case terminal
        /// 씨앗 — 의도적 신규(최근 발행). 처치: N일 관찰 후 연결 안 되면 경고.
        case seed
        /// 진짜 죽음 — 옛 지식이 supersede/retract 안 되고 방치. 처치: retract/삭제 후보(사람 판단).
        case trulyDead = "truly-dead"
    }

    /// 수입 부채로 보는 author 집합(정책 SSOT).
    public static let importAuthors: Set<String> = [
        "llmwiki-import", "import-classifier", "inbox-classifier", "taxonomy-drafter"
    ]
    /// 단말(정상)로 보는 type 집합 — 잘 수행된 操作 기록.
    public static let terminalTypes: Set<String> = [
        "run", "screening", "classification", "checkpoint", "observation"
    ]
    /// seed 로 볼 최근 기준(일).
    public static let seedDays: Double = 14

    /// fractional seconds 를 처리하는 ISO8601 포매터 — 원장 published 가
    /// `2026-07-18T12:47:14.000Z` 형식이라 기본 포매터가 nil 반환(#10 버그).
    public static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    /// 고립 객체 하나의 원인 판정.
    public static func cause(of node: WikiNode, now: Date = Date()) -> Cause {
        if importAuthors.contains(node.author) { return .importDebt }
        if terminalTypes.contains(node.type) { return .terminal }
        if let published = parseDate(node.published),
           now.timeIntervalSince(published) < seedDays * 86_400 { return .seed }
        return .trulyDead
    }

    public struct Breakdown: Sendable {
        public let importDebt: Int
        public let terminal: Int
        public let seed: Int
        public let trulyDead: Int
        public var total: Int { importDebt + terminal + seed + trulyDead }
        public func count(_ c: Cause) -> Int {
            switch c { case .importDebt: return importDebt; case .terminal: return terminal
            case .seed: return seed; case .trulyDead: return trulyDead }
        }
    }

    /// 고립 노드들을 원인별로 집계.
    public static func breakdown(orphans: [WikiNode], now: Date = Date()) -> Breakdown {
        var b = [Cause: Int](); for n in orphans { b[cause(of: n, now: now), default: 0] += 1 }
        return Breakdown(importDebt: b[.importDebt] ?? 0, terminal: b[.terminal] ?? 0,
                         seed: b[.seed] ?? 0, trulyDead: b[.trulyDead] ?? 0)
    }
}
