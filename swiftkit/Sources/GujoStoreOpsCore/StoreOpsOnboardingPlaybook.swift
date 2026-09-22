import Foundation
import LocalizationKit

/// Gujo Store Ops — **사람이 바로 따라하는** 온보딩 정본.
///
/// GUI 온보딩 · CLI `guide` · README 가 **같은 steps 배열**을 쓴다.
public enum StoreOpsOnboardingPlaybook: Sendable {
    public enum Actor: String, Sendable, Codable {
        case alreadyDone = "이미 됨"
        case human = "사람"
        case agent = "에이전트"
        case either = "사람 또는 에이전트"
        case macOnly = "Mac"
    }

    public struct Step: Sendable, Codable, Identifiable, Equatable {
        public var id: String
        public var title: String
        public var actor: Actor
        public var summary: String
        public var actions: [String]
        public var doneWhen: String
        public var refs: [String]
        /// 라이브 프로브 키 — `StoreOpsOnboardingProbe` 가 판정.
        public var probeKey: String?

        public init(
            id: String,
            title: String,
            actor: Actor,
            summary: String,
            actions: [String],
            doneWhen: String,
            refs: [String] = [],
            probeKey: String? = nil
        ) {
            self.id = id
            self.title = title
            self.actor = actor
            self.summary = summary
            self.actions = actions
            self.doneWhen = doneWhen
            self.refs = refs
            self.probeKey = probeKey
        }
    }

    public static let steps: [Step] = [
        Step(
            id: "map",
            title: CLILocalization.string("StoreOpsOnboardingPlaybook.title"),
            actor: .alreadyDone,
            summary: "서버 ops/v1 · 토큰 인증 · catalog 발행 · job API · Mac/iOS 클라이언트는 준비됐다. 남은 핵심은 **내 Mac에서 Android에 APK를 설치**하는 한 줄이다다.",
            actions: [
                "목표 한 줄: USB(또는 무선) Android 연결 → 패키지 고르기 → install job → run-jobs → 폰에 앱 뜸",
                CLILocalization.format("StoreOpsOnboardingPlaybook.string-5", "\(OpsPreferences.prodURLString)"),
                "Staff 토큰: Keychain service net.ranode.gujo account staff (발급은 GujoAuthKit)",
                "계정 SSOT: Agent Vault tenant:gujo (SSO·API·Store Ops Bearer 카드)",
                CLILocalization.format("StoreOpsOnboardingPlaybook.string-4", "\(CatalogArtifactURL.hostJP)"),
                "확인: gujo-store-ops doctor · gujo-store-ops accounts",
            ],
            doneWhen: "doctor 가 health ok · token set · packages 목록이 보인다.",
            refs: [
                "gujo-store-ops doctor",
                "gujo-store-ops accounts",
                ["apps", "store-operation-controller", "README.md"].joined(separator: "/"),
            ],
            probeKey: "doctor"
        ),
        Step(
            id: "token",
            title: CLILocalization.string("StoreOpsOnboardingPlaybook.title-2"),
            actor: .human,
            summary: "prod 는 Bearer 필수. 없으면 packages/health 가 401 이거나 빈 목록이다. 카드 정본은 Agent Vault tenant:gujo.",
            actions: [
                CLILocalization.format("StoreOpsOnboardingPlaybook.string-3", "\(OpsPreferences.prodURLString)"),
                "Staff 토큰은 Keychain service net.ranode.gujo account staff 에서만 읽는다",
                "옛 ~/.gujo-store-ops/token 또는 ~/.gujo-skill-store/token 이 있으면 앱 안 프롬프트로 한 번 가져온다",
                "앱 재실행 또는 새로고침 — 하단 상태줄에 token ok · N pkg 가 보이면 끝",
                "CLI: gujo-store-ops status · gujo-store-ops accounts",
            ],
            doneWhen: "상태줄에 token ok 이고 패키지 목록이 1개 이상이다.",
            refs: [
                "설정 시트",
                "Keychain net.ranode.gujo / staff",
                "Agent Vault tenant:gujo",
                "gujo-store-ops accounts",
            ],
            probeKey: "token"
        ),
        Step(
            id: "adb",
            title: CLILocalization.string("StoreOpsOnboardingPlaybook.title-3"),
            actor: .human,
            summary: "먼저 **휴대폰 화면**에서 개발자 옵션·USB 디버깅·허용을 켠다. 앱 『휴대폰 설정』 온보딩이 정본.",
            actions: [
                "앱 운영 탭 → **『휴대폰 설정』** 버튼 (또는 설정 → 휴대폰 연결 설정)",
                "폰: 빌드번호 7번 → 개발자 옵션 → USB 디버깅 ON",
                "데이터 케이블로 Mac 연결 → 파일 전송 모드",
                "폰 팝업 『이 컴퓨터 허용』 → 허용",
                "Mac 실측 physical PASS 될 때까지 휴대폰 설정 화면의 오른쪽 패널 확인",
                "CLI: gujo-store-ops phone-setup · gujo-store-ops adb --watch",
            ],
            doneWhen: "gujo-store-ops adb 에서 physical PASS (실기기) 또는 에뮬 shell OK.",
            refs: [
                "PhoneConnectionPlaybook",
                "gujo-store-ops phone-setup",
                "gujo-store-ops adb --watch",
            ],
            probeKey: "adb"
        ),
        Step(
            id: "register",
            title: CLILocalization.string("StoreOpsOnboardingPlaybook.title-4"),
            actor: .either,
            summary: "install job 은 ‘서버에 등록된 기기 ID’ 로 큐에 쌓인다. 로컬 adb 만으로는 job 을 못 만든다.",
            actions: [
                "앱 운영 탭 → 로컬 adb 기기 선택 → ‘서버에 등록’ (또는 동등 버튼)",
                "CLI: gujo-store-ops register-device \"내 폰\"",
                "등록 후: gujo-store-ops devices  또는 앱에서 서버 기기 목록에 라벨이 보임",
                "스모크용 가상 기기(smoke-virtual)가 있어도 됨 — 실 설치는 실제 serial 필요",
            ],
            doneWhen: "서버 기기 목록에 내 기기(또는 스모크 기기)가 1대 이상이다.",
            refs: ["gujo-store-ops register-device", "gujo-store-ops devices"],
            probeKey: "serverDevice"
        ),
        Step(
            id: "job-install",
            title: CLILocalization.string("StoreOpsOnboardingPlaybook.title-5"),
            actor: .either,
            summary: "패키지 선택 → job 생성 → Mac runner 가 claim → APK 다운로드 → adb install.",
            actions: [
                "운영 탭에서 패키지 하나 클릭 (예: Gujo 앱 스토어)",
                "서버 기기 선택 (3단계에서 등록한 것)",
                "‘install job 생성’ 버튼 클릭 (또는 create-job CLI)",
                "Jobs 목록에 queued 가 보이면: ‘queued job 실행’ / run-jobs",
                "CLI 한 줄: gujo-store-ops run-jobs",
                "성공: job status=succeeded · 폰에 앱 아이콘",
                "실패 시 Jobs 의 error 문구 확인 — TLS 면 앱 최신 빌드(HTTP rewrite) 재설치",
            ],
            doneWhen: "job 이 succeeded 이고 기기에서 패키지가 실행된다.",
            refs: [
                "gujo-store-ops create-job <pkg> <deviceId>",
                "gujo-store-ops run-jobs",
            ],
            probeKey: "installReady"
        ),
        Step(
            id: "runner",
            title: CLILocalization.string("StoreOpsOnboardingPlaybook.title-6"),
            actor: .either,
            summary: "여러 번 설치하거나 iOS 앱에서 job 만 만들 때, Mac 이 heartbeat 로 online 이어야 한다.",
            actions: [
                "터미널: gujo-store-ops heartbeat   (한 번 찍기)",
                "gujo-store-ops runners  → 이 호스트가 목록에 보이면 OK",
                "상시: while true; do gujo-store-ops heartbeat; sleep 60; done",
                "또는 앱 배포 탭 → runners 목록 새로고침",
                "health 의 runners_online ≥ 1 이면 원격 job 대기 가능",
            ],
            doneWhen: "health.runners_online ≥ 1 또는 runners 에 내 host 가 최근 seen.",
            refs: ["gujo-store-ops heartbeat", "gujo-store-ops runners"],
            probeKey: "runner"
        ),
        Step(
            id: "ios",
            title: CLILocalization.string("StoreOpsOnboardingPlaybook.title-7"),
            actor: .human,
            summary: "현장에서는 패키지·job 생성만 하고, 실제 adb 설치는 Mac runner 가 한다.",
            actions: [
                "Mac: ./scripts/make-ios-app.sh apps/gujo-store-ops-ios debug --simulator",
                "시뮬 설치 후 설정에 같은 Bearer 토큰 입력 (시뮬은 호스트 token 파일 못 봄)",
                "또는 simctl defaults write net.ranode.gujo-store-ops-ios gujo.store.ops.token -string \"$TOKEN\"",
                "패키지 탭에 목록 · 기기 선택 · install job 생성",
                "Mac 에서 gujo-store-ops run-jobs 로 소화",
                "실기기: release --device --install (프로파일 필요)",
            ],
            doneWhen: "iOS 앱에서 packages 가 보이고 job 이 서버에 queued 된다.",
            refs: [
                ["apps", "gujo-store-ops-ios", "README.md"].joined(separator: "/"),
                "gujo-store-ops-ios doctor",
            ],
            probeKey: nil
        ),
        Step(
            id: "service-ops",
            title: CLILocalization.string("StoreOpsOnboardingPlaybook.title-8"),
            actor: .either,
            summary: "다운로드 supply·퍼널·시뮬 스케줄은 **서비스 탭**에서 Store Ops 가 소유한다. 셸에 흩어 두지 않는다.",
            actions: [
                "앱 **서비스** 탭 열기 (예전 이름: 허브)",
                "「스케줄 보장」 → 잡 4개 등록 확인",
                "「전체 점검」 → supply·ops·handoff·catalog_sim",
                "CLI: gujo-store-ops service-ops status",
                "CLI: gujo-store-ops service-ops ensure",
                "토큰: Keychain net.ranode.gujo / staff (비밀 미출력)",
                "정본 문서: docs/gujo-service-ops.md",
            ],
            doneWhen: "service-ops status 가 잡 4/4 · 자리 5/5 · health ready 이다.",
            refs: [
                "gujo-store-ops service-ops status",
                "gujo-store-ops hub",
                "docs/gujo-service-ops.md",
            ],
            probeKey: "serviceOps"
        ),
        Step(
            id: "daily",
            title: CLILocalization.string("StoreOpsOnboardingPlaybook.title-9"),
            actor: .either,
            summary: "이 앱이 운영 콕핏이다. 온보딩은 설정에서 다시 연다.",
            actions: [
                "앱: 운영(패키지·job) · 배포(publish/runners) · 허브(download 게이트)",
                "CLI 치트시트: gujo-store-ops help",
                "이 안내 다시: 설정 → ‘따라하기 온보딩 다시 보기’ 또는 gujo-store-ops guide",
                "막히면 doctor 먼저: gujo-store-ops doctor",
            ],
            doneWhen: "토큰·adb·기기 없이도 상태줄만 보고 어디가 비었는지 안다.",
            refs: ["gujo-store-ops guide", "설정 → 온보딩"],
            probeKey: nil
        ),
    ]

    public static func plainText() -> String {
        var lines: [String] = []
        lines.append("Gujo Store Ops — 따라하기 온보딩")
        lines.append("정본: StoreOpsOnboardingPlaybook · GUI · gujo-store-ops guide")
        lines.append("")
        for step in steps {
            lines.append("## \(step.title)  [\(step.actor.rawValue)]")
            lines.append(step.summary)
            lines.append("")
            for (i, a) in step.actions.enumerated() {
                lines.append("  \(i + 1). \(a)")
            }
            lines.append("")
            lines.append(CLILocalization.format("StoreOpsOnboardingPlaybook.string-2", "\(step.doneWhen)"))
            if !step.refs.isEmpty {
                lines.append(CLILocalization.format("StoreOpsOnboardingPlaybook.string", "\(step.refs.joined(separator: " · "))"))
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
