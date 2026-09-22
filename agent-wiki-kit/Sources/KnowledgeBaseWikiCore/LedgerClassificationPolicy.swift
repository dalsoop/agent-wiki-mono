import Foundation

/// 분류 기준선 — **언제 발행된 지식부터** 3축 분류를 요구할지 정하는 정책.
///
/// 왜 전면 강제가 아닌가. 실측(2026-08-04) 기준 지식 객체 914개 중 549개가 미분류다.
/// 그중 219개는 사람이 하나씩 빠뜨린 게 아니라 `wiki-maintainer` 의 과거 대량 이주
/// 배치가 안 붙인 것이다. 여기에 전면 게이트를 걸면 `verify` 가 **첫날부터 항상
/// 빨간불**이 되고, 상시 빨간불은 게이트를 무력화한다 — 오늘 프로모션 봉쇄 위반에서
/// 실제로 그렇게 됐다(위반을 보고도 "통과시킨다"고 오독).
///
/// 그리고 분류는 검색 **도달**과 무관하다(미분류 객체도 FTS 에 잡힌다 —
/// LedgerIndexFreshnessTests). 값어치는 정밀도다: `--domain/--kind/--knowledge`
/// 필터와 결과 줄의 `[domain/kind/knowledge]` 태그. 즉 급한 부채가 아니다.
///
/// 그래서 **기준선 이후 발행분만** 요구한다. 과거분은 부채로 남되 백로그로 보인다.
/// 기준선은 원장 안의 `policy` 객체라 호스트 설정이 아니라 원장을 따라다니고,
/// 옮길 때는 supersede 발행이라 "언제 왜 옮겼는지"가 남는다.
public struct LedgerClassificationPolicy: Sendable {
    public static let policyKind = "classification-baseline"
    public static let objectType = "policy"

    /// 이 시각 **이후** 발행된 지식 객체부터 분류를 요구한다. nil 이면 정책 없음(요구 안 함).
    public let since: Date?
    /// 기준선을 선언한 객체 id — 화면·CLI 가 "무엇이 이걸 정했나"를 가리킬 수 있게.
    public let declaredBy: String?

    public init(since: Date?, declaredBy: String?) {
        self.since = since
        self.declaredBy = declaredBy
    }

    /// 원장에서 현재 유효한 기준선을 읽는다 — 최신 head policy 객체 하나.
    public static func current(objects: [LedgerObject], store: LedgerStore) -> LedgerClassificationPolicy {
        let superseded = Set(objects.compactMap(\.supersedes))
        let retracted = Set(objects.compactMap(\.retracts))
        let head = objects
            .filter {
                $0.effectiveType == objectType
                    && !superseded.contains($0.id) && !retracted.contains($0.id)
                    && $0.retracts == nil
                    && $0.body.contains(policyKind)
            }
            .sorted { ($0.published, $0.id) > ($1.published, $1.id) }
            .first
        guard let head, let since = parseSince(head.body) else {
            return LedgerClassificationPolicy(since: nil, declaredBy: nil)
        }
        return LedgerClassificationPolicy(since: since, declaredBy: head.id)
    }

    /// 본문에서 `since: <ISO8601>` 을 읽는다. JSON 이 아니라 한 줄 키:값 —
    /// 사람이 `show` 로 열어 바로 읽을 수 있어야 하기 때문이다.
    ///
    /// **소수점 초까지 읽는다.** 초 단위로 자르면 기준선과 같은 초에 발행된 객체가
    /// 기준선보다 뒤로 밀려 잘못 게이트된다(테스트가 잡은 실제 결함) — 객체
    /// `published` 는 밀리초를 담는데 기준선만 초로 잘렸기 때문이다.
    static func parseSince(_ body: String) -> Date? {
        for line in body.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("since:") else { continue }
            let raw = text.dropFirst("since:".count).trimmingCharacters(in: .whitespaces)
            return LedgerObject.isoFraction.date(from: raw)
                ?? LedgerObject.iso.date(from: raw)
                ?? ISO8601DateFormatter().date(from: raw)
        }
        return nil
    }

    /// 기준선 선언 객체의 본문.
    public static func body(since: Date, reason: String) -> String {
        """
        policy: \(policyKind)
        since: \(LedgerObject.isoFraction.string(from: since))

        이 시각 이후에 발행된 **지식 객체**는 3축 분류(domain/kind/knowledge)를 갖춰야 한다.
        `verify` 가 이 규칙을 게이트로 집행한다. 기준선 이전 객체는 부채로 남되
        미분류 백로그로 드러난다 — 전면 게이트는 상시 빨간불이 되어 게이트를 무력화한다.

        근거: \(reason)
        """
    }

    /// 이 객체가 분류 게이트 대상인가 — 지식이고, 기준선 이후 발행분일 때만.
    ///
    /// `retracted` 는 **다른 객체가 철회한** id 집합이다. 이걸 안 넘기면 철회한 뒤에도
    /// 위반이 계속 뜬다 — 실측 결함(2026-08-04): 시험 객체를 철회했는데 verify 가
    /// 계속 exit 2 였다. 철회 *기록*(`retracts != nil`)만 빼고 철회*된* 객체를
    /// 안 뺐기 때문이다. 폐기한 지식에 분류를 요구하는 건 의미가 없다.
    public func requiresClassification(
        _ object: LedgerObject, retracted: Set<String> = []
    ) -> Bool {
        guard let since else { return false }
        guard !object.isProcess else { return false }   // 처리 기록은 지식이 아니다
        guard object.retracts == nil else { return false }   // 철회 기록 자신
        guard !retracted.contains(object.id) else { return false }  // 철회당한 객체
        return object.published > since
    }

    /// 게이트 대상 중 분류가 없는 것들. `classified` 는 인덱스가 투영한 분류 보유 id 집합.
    public func unclassified(objects: [LedgerObject], classified: Set<String>) -> [LedgerObject] {
        let superseded = Set(objects.compactMap(\.supersedes))
        let retracted = Set(objects.compactMap(\.retracts))
        return objects
            .filter { requiresClassification($0, retracted: retracted) && !superseded.contains($0.id) }
            .filter { !classified.contains($0.id) }
            .sorted { ($0.published, $0.id) < ($1.published, $1.id) }
    }
}
