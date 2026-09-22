import Foundation
import InteropKit
import MoneyLedgerKit

/// capabilities — 계약 자기소개. 두 앱이 같은 코드로 생성하므로 계약 드리프트가 구조적으로 불가능.
enum CapabilitiesCommand {
    static func run(context: LedgerContext, output: CLIOutput) throws {
        let slug = context.scope.slug
        let caps = Capabilities(
            name: slug,
            version: LedgerCLI.cliVersion,
            cli: HostPlatform.cliBinPath(slug),
            commands: [
                .init(name: "capabilities", summary: "이 계약 출력", json: true),
                .init(name: "account add|list|show|update|archive|remove", summary: "계좌 관리", json: true),
                .init(name: "card add|list|show|update|archive|remove", summary: "카드 관리", json: true),
                .init(name: "sub add|list|show|update|pause|resume|cancel", summary: "구독 관리", json: true),
                .init(name: "biz add|list|show|update|attach|files|detach", summary: "사업자 등록·로컬 첨부", json: true),
                .init(name: "biz docs upload|list|download|delete|status", summary: "사업 서류를 Vaultwarden 첨부로 보관(금고 앱 경유)", json: true),
                .init(
                    name: "tx add|transfer|settle-card|update|list|show|set-category|set-business|remove",
                    summary: "입출금 거래 기록·이체·카드결제·수정·조회(중복 멱등, --business 로 사업체 귀속·필터)",
                    json: true
                ),
                .init(
                    name: "net-worth",
                    summary: "총자산, 총부채, 순자산 및 자산군별 비중 리포트",
                    json: true
                ),
                .init(
                    name: "import csv|list|show|undo",
                    summary: "은행 CSV 가져오기(cp949 자동, --dry-run, --business 로 배치 전체 귀속)",
                    json: true
                ),
                .init(
                    name: "report monthly|categories|subs|upcoming|net-worth",
                    summary: "월간·카테고리(--business 필터)·구독·예정결제·순자산 리포트",
                    json: true
                ),
                .init(
                    name: "budget set|list",
                    summary: "카테고리별 예산 설정 및 소진율 조회",
                    json: true
                ),
                .init(
                    name: "export --format csv [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--output <경로>]",
                    summary: "거래 내역 엑셀/CSV 내보내기(한국 엑셀 UTF-8 BOM)",
                    json: true
                ),
                .init(name: "vault status|login|link|show|unlink", summary: "민감정보 Vaultwarden 연동(stdin 전용, bw 세션 우선)", json: true),
                .init(name: "version", summary: "버전", json: false),
                .init(name: "open", summary: "GUI 앱 열기", json: false),
            ],
            state: [
                .init(
                    path: "~/.swift-app-state/\(slug).json",
                    what: "상태 요약(계좌·카드·구독 수, 월 입출금, 다음 결제, 마지막 가져오기, vault 상태)"
                ),
                .init(
                    path: "~/Library/Application Support/\(context.scope.appName)/ledger.sqlite",
                    what: "원장 본체(sqlite) — 조회는 CLI 를 쓸 것"
                ),
            ],
            health: .init(
                command: "\(HostPlatform.cliBinPath(slug)) capabilities",
                freshness: "~/.swift-app-state/\(slug).json"
            ),
            owned: .init(depends: [
                .init(
                    id: "cli.vaultwarden-client",
                    kind: Capabilities.DependencyKind.cli,
                    ref: "vaultwarden-client",
                    required: false,
                    why: "민감정보·사업 서류 보관처(금고 앱 창구) — 없어도 원장 기능은 전부 동작",
                    commands: ["status --json", "docs upload|list|download|delete", "note set|get|rm"]
                ),
            ])
        )
        let data = try Envelope.ok(caps)
        output.out(String(data: data, encoding: .utf8) ?? "{}")
    }
}
