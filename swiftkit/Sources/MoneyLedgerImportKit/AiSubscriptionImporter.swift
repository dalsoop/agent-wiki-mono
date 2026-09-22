import CommandKit
import Foundation
import MoneyLedgerModels
import InteropKit

/// AI CLI 구독을 원장으로 들여오는 창구 — **소유 앱 CLI 가 문**이다.
///
/// 경계: `ai-cli-account-manager` 는 플랜·한도·갱신일·프로모 조건을 **관측**할 수 있고
/// (서버를 찌른다), 원장은 카드·사업체 귀속과 영수증, 비-AI 구독까지 묶은 **총지출**을
/// 낸다. 서로 못 하는 일이라 한쪽이 다 가지면 드리프트만 남는다.
/// 그래서 돈의 정본은 원장이고, 관측값은 여기로 흘러 들어온다.
public struct AiSubscriptionImporter: Sendable {
    /// 원장이 받아 적을 수 있는 형태로 정규화한 관측 1건.
    public struct Row: Sendable, Equatable {
        public let externalID: String
        public let client: String
        public let label: String
        public let plan: String?
        /// 지금 실제로 나가는 월 환산액(프로모 적용가).
        public let monthlyMinor: Int64
        public let currency: String
        /// 다음 결제일 "yyyy-MM-dd".
        public let nextBillingDate: String?
        /// 프로모 종료일 "yyyy-MM-dd" — 이 날 이후 `regularMinor` 로 오른다.
        public let promoEndsOn: String?
        public let regularMinor: Int64?

        /// 원장 행 이름 — 플랜이 있으면 "SuperGrok Heavy (grok)".
        public var displayName: String {
            guard let plan, !plan.isEmpty else { return client }
            return "\(plan) (\(client))"
        }
    }

    public enum ImportError: Error, CustomStringConvertible {
        case cliUnavailable(String)
        case cliFailed(String)
        case badEnvelope(String)
        /// 계약 필드가 없다 = 설치된 CLI 가 낡았다. 문자열을 파싱해 때우지 않는다 —
        /// 조용히 틀린 금액이 원장에 박히는 것보다 여기서 멈추는 게 낫다.
        case contractTooOld(String)

        public var description: String {
            switch self {
            case .cliUnavailable(let path):
                return "ai-cli-account-manager 를 찾지 못했습니다: \(path)"
            case .cliFailed(let message):
                return "ai-cli-account-manager 실행 실패: \(message)"
            case .badEnvelope(let message):
                return "ai-cli-account-manager 응답을 읽지 못했습니다: \(message)"
            case .contractTooOld(let message):
                return """
                    설치된 ai-cli-account-manager 가 금액 계약을 만족하지 않습니다(\(message)).
                    `billing --json` 행에 monthlyAmount·currency 가 있어야 합니다.
                    앱을 다시 설치한 뒤(app-build-manager install) 재시도하세요.
                    """
            }
        }
    }

    private let cliPath: String
    private let runner: CommandRunning

    public init(
        cliPath: String = HostPlatform.cliBinPath("ai-cli-account-manager"),
        runner: CommandRunning = ProcessCommandRunner()
    ) {
        self.cliPath = cliPath
        self.runner = runner
    }

    public func fetch(now: Date = Date()) async throws -> [Row] {
        guard FileManager.default.isExecutableFile(atPath: cliPath) else {
            throw ImportError.cliUnavailable(cliPath)
        }
        let reply = await runner.run(cliPath, ["billing", "--json"], timeout: 120)
        guard reply.exitCode == 0 else {
            throw ImportError.cliFailed(reply.stderr.isEmpty ? "exit \(reply.exitCode)" : reply.stderr)
        }
        return try Self.parse(reply.stdout, now: now)
    }

    /// 봉투를 벗기고 행을 정규화한다. 테스트가 프로세스 없이 부를 수 있게 분리.
    public static func parse(_ payload: String, now: Date = Date()) throws -> [Row] {
        guard let data = payload.data(using: .utf8) else {
            throw ImportError.badEnvelope("JSON 아님")
        }
        let root: [String: Any]
        do {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ImportError.badEnvelope("JSON 아님")
            }
            root = obj
        } catch let err as ImportError {
            throw err
        } catch {
            throw ImportError.badEnvelope("JSON 아님: \(error.localizedDescription)")
        }

        // `{"ok":true,"result":{…}}` 봉투. 옛 판은 맨 객체였다 — 둘 다 받는다.
        let result = (root["result"] as? [String: Any]) ?? root
        if let ok = root["ok"] as? Bool, ok == false {
            let message = ((root["error"] as? [String: Any])?["message"] as? String) ?? "unknown"
            throw ImportError.cliFailed(message)
        }
        guard let rawRows = result["rows"] as? [[String: Any]] else {
            throw ImportError.badEnvelope("rows 없음")
        }

        var rows: [Row] = []
        for raw in rawRows {
            guard let id = raw["id"] as? String, let client = raw["client"] as? String else {
                throw ImportError.badEnvelope("행에 id/client 없음")
            }
            guard let monthly = raw["monthlyAmount"] as? Double,
                  let currency = raw["currency"] as? String
            else {
                // 가격을 모르는 행은 건너뛴다(ACM 이 unpricedRowCount 로 따로 센다).
                // 다만 **한 행도** 금액 필드를 안 가지면 계약 자체가 낡은 것이다.
                if raw["monthlyAmount"] == nil && rawRows.allSatisfy({ $0["monthlyAmount"] == nil }) {
                    throw ImportError.contractTooOld("monthlyAmount 없음")
                }
                continue
            }
            let regular = raw["postPromoMonthlyAmount"] as? Double
            let promoEndsOn = (raw["promoEndsInDays"] as? Int).map {
                LedgerDate.format(now.addingTimeInterval(Double($0) * 86_400))
            }
            rows.append(
                Row(
                    externalID: id,
                    client: client,
                    label: raw["label"] as? String ?? client,
                    plan: raw["plan"] as? String,
                    monthlyMinor: try Self.minor(monthly, currency: currency),
                    currency: MoneyAmount.normalizedCurrency(currency),
                    nextBillingDate: (raw["renewsAt"] as? String).map { String($0.prefix(10)) },
                    promoEndsOn: promoEndsOn,
                    regularMinor: try regular.map { try Self.minor($0, currency: currency) }
                )
            )
        }
        return rows
    }

    /// Double(달러 단위) → 최소단위. 통화 자릿수로 먼저 반올림해서 넘긴다 —
    /// 그냥 문자열화하면 부동소수 꼬리("33.000000000000004")가 파서를 튕긴다.
    private static func minor(_ major: Double, currency: String) throws -> Int64 {
        let digits = MoneyAmount.exponent(of: currency)
        return try MoneyAmount.minorUnits(
            from: String(format: "%.\(digits)f", major), currency: currency
        )
    }
}
