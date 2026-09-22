import Foundation
import KnowledgeBaseWikiCore

// 2026-08-25 main 수리 — landing 6f66992cec 가 WikiCLIShared(CommandVerify·CommandTick)를
// 싣고 왔는데 그 코드가 쓰는 옛 이름(LedgerViolation·LedgerStrength)의 개명 대상은
// 착륙하지 않아 main 빌드가 깨졌다. 사용부 API(violation: id/problem,
// strength: freshness)와 정확히 일치하는 현존 타입으로 별칭을 걸어 원문 그대로 살린다.
typealias LedgerViolation = LedgerStore.Violation
typealias LedgerStrength = EvidenceStrength
