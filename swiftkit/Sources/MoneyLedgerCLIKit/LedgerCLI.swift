import CommandKit
import Foundation
import InteropKit
import MoneyLedgerKit

/// Ledger 제품군 공용 CLI 라우터 — 두 앱(business-ledger/-personal)의 main.swift 가
/// scope 만 정해 위임한다. 커맨드 표면이 앱 간에 구조적으로 드리프트할 수 없다.
///
/// 계약(docs/app-interop-contract.md): --json 봉투 {ok,result}/{ok,error.message},
/// exit 0 성공(중복 삽입 포함 — 에이전트 멱등성) / 64 사용법 / 1 실행 실패.
public enum LedgerCLI {
    public static func run(
        context: LedgerContext,
        arguments: [String],
        output: CLIOutput = CLIOutput(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> Int32 {
        let scanner = ArgScanner(arguments, valueFlags: valueFlags)
        let json = scanner.has("json")
        let effectiveContext = resolveContext(context, scanner: scanner)
        // 하위명령 + --help 조합도 도움말이다 — 동작을 실행하지 않는다
        // (`gitlabctl merge --help` 가 실제 머지를 실행한 사고 유형).
        if arguments.contains("--help") || arguments.contains("-h") {
            output.out(usage(context: effectiveContext))
            return 0
        }
        let command = scanner.positionals.first ?? "help"
        let rest = Array(scanner.positionals.dropFirst())
        do {
            return try await dispatch(
                command, rest: rest, scanner: scanner, context: effectiveContext,
                json: json, output: output, environment: environment
            )
        } catch let error as UsageError {
            return handleUsageError(error, json: json, context: effectiveContext, output: output)
        } catch {
            return handleGenericError(error, json: json, output: output)
        }
    }

    private static func handleUsageError(
        _ error: UsageError, json: Bool, context: LedgerContext, output: CLIOutput
    ) -> Int32 {
        if json {
            output.failJSON(error.message)
        } else {
            output.err("error: \(error.message)")
            output.err(usage(context: context))
        }
        return 64
    }

    private static func handleGenericError(_ error: any Error, json: Bool, output: CLIOutput) -> Int32 {
        let message = (error as CustomStringConvertible).description
        if json { output.failJSON(message) } else { output.err("error: \(message)") }
        return 1
    }

    public static var cliVersion: String { CLIMarketingVersion.current() }

    /// 값을 받는 플래그 전부. 여기 등록되지 않은 `--x 값` 은 조용히 무시되고 값이 positional 로 샌다
    /// (명령은 성공한 것처럼 끝난다). 새 플래그를 만들면 반드시 여기에 넣는다.
    static let valueFlags: Set<String> = [
        "name", "bank", "last4", "currency", "purpose", "note", "issuer", "account", "card",
        "billing-day", "amount", "period", "next-billing", "status", "date", "time", "desc",
        "category", "memo", "balance", "month", "from", "to", "limit", "map", "encoding",
        "skip-rows", "days", "data-root", "year", "reg-no", "rep", "opened", "type", "item",
        "tax", "address", "initial-balance", "kind",
        // 구독 4축 — 결제수단(card/account 는 위에) · 사업체 · 외부 링크 · 프로모.
        // `--business` 는 tx add/list/set-business · import csv · report 도 같이 쓴다.
        "business", "source", "external-id", "promo-ends", "regular-amount",
        // sub import 브리지.
        "from", "match", "source-cli",
        // export & budget
        "format", "output",
    ]

    /// --data-root: 테스트·백업 검사용 원장 경로 재지정.
    static func resolveContext(_ context: LedgerContext, scanner: ArgScanner) -> LedgerContext {
        guard let dataRoot = scanner.value("data-root") else { return context }
        return LedgerContext(
            scope: context.scope,
            databaseURL: URL(fileURLWithPath: dataRoot, isDirectory: true)
                .appendingPathComponent("ledger.sqlite")
        )
    }

    private static func dispatch(
        _ command: String, rest: [String], scanner: ArgScanner, context: LedgerContext,
        json: Bool, output: CLIOutput, environment: [String: String]
    ) async throws -> Int32 {
        switch command {
        case "help", "-h", "--help":
            output.out(usage(context: context))
        case "version", "-V", "--version":
            output.out("\(context.scope.slug) \(cliVersion)")
        case "capabilities":
            try CapabilitiesCommand.run(context: context, output: output)
        case "open":
            return openGUI(context: context, output: output)
        case "account":
            try await AccountCommands.run(context: context, sub: rest, scanner: scanner, json: json, output: output)
        case "card":
            try await CardCommands.run(context: context, sub: rest, scanner: scanner, json: json, output: output)
        case "sub":
            try await SubscriptionCommands.run(context: context, sub: rest, scanner: scanner, json: json, output: output)
        case "tx":
            try await TransactionCommands.run(context: context, sub: rest, scanner: scanner, json: json, output: output)
        case "import":
            try await ImportCommands.run(context: context, sub: rest, scanner: scanner, json: json, output: output)
        case "report":
            try await ReportCommands.run(context: context, sub: rest, scanner: scanner, json: json, output: output)
        case "net-worth", "networth":
            try await NetWorthCommand.run(context: context, scanner: scanner, json: json, output: output)
        case "export":
            try await ExportCommands.run(context: context, sub: rest, scanner: scanner, json: json, output: output)
        case "budget":
            try await BudgetCommands.run(context: context, sub: rest, scanner: scanner, json: json, output: output)
        case "biz":
            try await BusinessCommands.run(context: context, sub: rest, scanner: scanner, json: json, output: output)
        case "vault":
            try await VaultCommands.run(
                context: context, sub: rest, scanner: scanner, json: json,
                output: output, environment: environment
            )
        default:
            throw UsageError("unknown command: \(command) (try help)")
        }
        return 0
    }

    /// GUI 앱 열기 — `open -a` 를 CommandKit 동기 러너로(Process 직접 생성 금지 규칙).
    static func openGUI(context: LedgerContext, output: CLIOutput) -> Int32 {
        let result = CommandKitSync.run("/usr/bin/open", ["-a", context.scope.appName], timeout: 15)
        guard result.exitCode == 0 else {
            output.err("error: open failed: \(result.stderr)")
            return 1
        }
        return 0
    }

    static func usage(context: LedgerContext) -> String {
        usageAccountsCardsSubs(context: context) + "\n\n" + usageBizTxReports()
    }

    private static func usageAccountsCardsSubs(context: LedgerContext) -> String {
        let cli = context.scope.slug
        let korean = context.scope.label(korean: true)
        return """
        \(cli) — \(context.scope.appName) CLI (\(korean) 재무 원장, helpers dual-entry)

        계좌:
          account add --name <이름> [--bank <은행>] [--type checking|savings|cash|investment|realEstate|loan]
                      [--initial-balance <잔액>] [--last4 1234] [--currency KRW] [--purpose <용도>] [--note]
                      # 현금/부동산/투자 자산은 --bank 생략 가능
          account list [--all] [--json]
          account show <id|이름> [--json]
          account update <id|이름> [--name] [--bank] [--type] [--initial-balance] [--last4] [--purpose] [--note]
          account archive|unarchive <id|이름>
          account remove <id|이름> --purge        # 참조 거래가 있으면 거부

        카드:
          card add --name <이름> --issuer <카드사> [--last4] [--account <계좌>] [--billing-day N]
          card list|show|update|archive|unarchive|remove …   # account 와 같은 꼴

        구독:
          sub add --name <이름> --amount 15000 [--currency KRW] [--period monthly|yearly|one-time]
                  [--card <카드>|--account <계좌>] [--business <사업체>]
                  [--next-billing yyyy-MM-dd] [--note]
                  [--source <앱슬러그> --external-id <외부id>]   # 짝 — 재수입 시 갱신
                  [--promo-ends yyyy-MM-dd --regular-amount 300] # 짝 — 프로모 종료 절벽
          sub list [--status active|paused|cancelled] [--all] [--json]
          sub show|update|pause|resume|cancel <id|이름>
          # update 도 --business/--promo-ends/--regular-amount 를 받는다.
          sub import --from ai-cli-account-manager [--match <문자열>]
                     [--business <사업체>] [--card <카드>] [--dry-run] [--json]
          # AI 구독 관측을 원장으로 들여온다. externalKey 로 중복 없이 갱신.
          # --match 로 이 원장(개인/사업)이 맡을 것만 고른다.
        """
    }

    private static func usageBizTxReports() -> String {
        return """
        사업자:
          biz add --name <상호> [--reg-no 123-45-67890] [--rep <대표자>] [--opened yyyy-MM-dd]
                  [--type <업태>] [--item <종목>] [--tax <과세유형>] [--address] [--note] [--force]
          biz list|show|update|archive|unarchive|remove --purge
          biz attach <id|상호> <파일> [--name 표시명]    # 로컬 첨부(빠른 열람용)
          biz files <id|상호> [--json] | biz detach <첨부id>
          biz docs upload <사업자> <파일>                # 서류 정본 → 금고 앱(Vaultwarden) 첨부
          biz docs list|download|delete <사업자> … | biz docs status

        거래(입출금·이체·결제):
          tx add --date yyyy-MM-dd --amount -15000 (--account <계좌>|--card <카드>) --desc <적요>
                 [--kind expense|income|transfer|settlement] [--business <사업체>]
                 [--category] [--memo] [--time HH:mm] [--balance <잔액>] [--allow-duplicate]
                 # 같은 내용 재실행은 duplicate:true + exit 0 (멱등)
                 # --kind 에 따라 부호 자동 보정 (expense: 음수, income: 양수)
          tx transfer --from <accID> --to <accID> --amount <금액> [--date yyyy-MM-dd] [--desc <적요>]
                      # 두 계좌 간 원자적 이체 쌍 생성
          tx settle-card --from <accID> --card <cardID> --amount <금액> [--date yyyy-MM-dd] [--desc <적요>]
                         # 계좌 출금 + 카드대금 결제 쌍 생성
          tx update <id> [--amount <금액>] [--desc <적요>] [--category <카테고리>] [--date yyyy-MM-dd] [--memo <메모>]
          tx list [--month yyyy-MM | --from d --to d] [--account|--card] [--business <사업체>]
                  [--category] [--limit N] [--json]
          tx show <id> [--json]
          tx set-category <id> <카테고리>
          tx set-business <id> <사업체|none>            # 귀속 사업체 정정 · none 이면 해제
          tx remove <id> [--dry-run]

        CSV 가져오기(은행/카드사 내려받기):
          import csv <파일> (--account <계좌>|--card <카드>) [--business <사업체>]
                 --map "date=거래일자,out=출금액,in=입금액,desc=적요[,time=거래시간,balance=거래후잔액]"
                 [--encoding auto|utf8|cp949] [--currency KRW] [--skip-rows N] [--dry-run] [--json]
                 # --business 는 배치 전체 귀속 — 은행 CSV 한 장은 한 사업체 계좌에서 나온다
          import list [--json] | import show <배치id> | import undo <배치id> [--dry-run]

        순자산 및 리포트:
          net-worth [--json]                            # 총자산, 총부채, 순자산 및 자산군별 비중
          report monthly [--month yyyy-MM] [--business <사업체>] [--json]     # 통화별 입금/출금/순액
          report categories [--month yyyy-MM] [--business <사업체>] [--json]
          report subs [--json]                          # 구독 월환산 합계
          report upcoming [--days 30] [--json]          # 다가오는 결제
          report net-worth [--json]                     # net-worth 커맨드와 동일

        예산 및 내보내기:
          budget set --category <카테고리> --amount <금액> [--currency KRW]  # 카테고리 예산 설정
          budget list [--json]                          # 이번 달 예산 소진율 및 현황 조회
          export --format csv [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--output <경로>]  # 한국 엑셀 호환 CSV 내보내기

        민감정보(Vaultwarden — 로컬 파일에 전체번호 비저장):
          vault status [--json]
          vault login <server|us|eu> <email>            # 마스터 비밀번호는 stdin
          vault link account|card <id|이름>              # 전체번호를 stdin 으로 → Secure Note
          vault show account|card <id|이름> [--reveal] [--json]
          vault unlink account|card <id|이름> [--delete-note]

        공통: --json (봉투 {ok,result}) · --data-root <경로> (원장 재지정)
        기타: capabilities | version | open | help
        """
    }
}
