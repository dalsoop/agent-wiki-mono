import Foundation
import LocalizationKit

/// **휴대폰 화면에서 사람이 눌러야 하는** 설정만 모은 온보딩 정본.
/// Mac adb 진단과 분리 — 여기는 폰 UI 경로.
public enum PhoneConnectionPlaybook: Sendable {
    public struct Step: Sendable, Codable, Identifiable, Equatable {
        public var id: String
        public var title: String
        /// 폰 화면 기준 큰 안내.
        public var phoneScreen: String
        /// 손가락으로 할 일 (번호).
        public var taps: [String]
        /// 삼성/픽셀/샤오미 등 메뉴 이름 차이.
        public var brandNotes: [String]
        /// 이 단계 끝나면 Mac 쪽 기대.
        public var macSees: String
        /// AdbDiagnosis.kind 와 맞추면 자동 체크 (optional).
        public var passWhen: PassWhen?

        public enum PassWhen: String, Sendable, Codable, Equatable {
            case alwaysManual
            /// adb 목록에 무언가 보임 (unauthorized 포함)
            case anyListed
            case unauthorized
            case physicalReady
            case anyReady
        }

        public init(
            id: String,
            title: String,
            phoneScreen: String,
            taps: [String],
            brandNotes: [String] = [],
            macSees: String,
            passWhen: PassWhen? = .alwaysManual
        ) {
            self.id = id
            self.title = title
            self.phoneScreen = phoneScreen
            self.taps = taps
            self.brandNotes = brandNotes
            self.macSees = macSees
            self.passWhen = passWhen
        }
    }

    public static let steps: [Step] = [
        Step(
            id: "intro",
            title: CLILocalization.string("PhoneConnectionPlaybook.title"),
            phoneScreen: "Mac 앱이 아니라 **휴대폰**에서 설정을 바꿉니다. 케이블은 아직 안 꽂아도 됩니다.",
            taps: [
                "Android 폰/패드를 잠금 해제해 두세요",
                "화면을 켜 둔 채로 아래 단계를 따라가세요",
                "Mac 오른쪽(또는 아래) 실측 패널이 초록이 되면 연결 성공입니다",
            ],
            macSees: "아직 변화 없음이 정상",
            passWhen: .alwaysManual
        ),
        Step(
            id: "developer-options",
            title: CLILocalization.string("PhoneConnectionPlaybook.title-2"),
            phoneScreen: "설정 앱 → (디바이스) 정보 / 휴대전화 정보 → 소프트웨어 정보 근처 **빌드번호**",
            taps: [
                "설정 앱 열기",
                "『휴대전화 정보』 또는 『디바이스 정보』 또는 『내 디바이스』 로 이동",
                "『소프트웨어 정보』가 있으면 들어감",
                "『빌드번호』(또는 빌드 번호) 항목을 **연속 7번** 탭",
                "『개발자가 되었습니다』 토스트/팝업이 뜨면 성공",
                "설정 앱 첫 화면으로 돌아가면 『개발자 옵션』 메뉴가 생겨 있음",
            ],
            brandNotes: [
                "삼성: 설정 → 휴대전화 정보 → 소프트웨어 정보 → 빌드번호",
                "Pixel/순정: 설정 → 휴대전화 정보 → 빌드 번호",
                "샤오미: 설정 → 내 디바이스 → 전체 사양 → MIUI 버전 또는 빌드번호 여러 번",
                "원플러스/OPPO: 설정 → 정보 → 버전 → 빌드 번호",
            ],
            macSees: "아직 adb 변화 없음",
            passWhen: .alwaysManual
        ),
        Step(
            id: "usb-debugging",
            title: CLILocalization.string("PhoneConnectionPlaybook.title-3"),
            phoneScreen: "설정 → 개발자 옵션 (시스템 / 추가 설정 안에 있을 수 있음)",
            taps: [
                "설정에서 『개발자 옵션』 검색 또는 시스템 → 개발자 옵션",
                "맨 위 『개발자 옵션』 스위치 **ON**",
                "『USB 디버깅』 스위치 **ON**",
                "확인 팝업이 뜨면 『확인』/『허용』",
                "(있으면) 『USB 디버깅(보안 설정)』 또는 『설치 통해 USB』 도 ON 권장",
                "(있으면) 『기본 USB 구성』 → **파일 전송 / MTP / Android Auto 아님**",
            ],
            brandNotes: [
                "삼성: 설정 → 개발자 옵션 → USB 디버깅",
                "일부 기기는 개발자 옵션이 『시스템』 맨 아래",
                "『무선 디버깅』은 나중에 — 지금은 USB 디버깅만",
            ],
            macSees: "케이블 꽂기 전이라 목록 비어 있을 수 있음",
            passWhen: .alwaysManual
        ),
        Step(
            id: "cable",
            title: CLILocalization.string("PhoneConnectionPlaybook.title-4"),
            phoneScreen: "폰 하단 USB-C/라이트닝(어댑터) 포트 · Mac USB",
            taps: [
                "**데이터 전송 되는 케이블** 사용 (충전 전용 케이블이면 실패)",
                "폰 ↔ Mac 직접 연결 (허브/독 없이 먼저 시도)",
                "폰 알림/팝업: USB 용도 → **파일 전송 / MTP / Android** 선택 (충전만 X)",
                "화면 잠금 해제 상태 유지",
            ],
            brandNotes: [
                "『USB를 통해』 알림이 안 뜨면 알림창을 내려 확인",
                "『이 장치 충전 중』만 보이면 케이블 또는 포트 교체",
            ],
            macSees: "adb 에 serial 이 생기거나 unauthorized 로 잡힘",
            passWhen: .anyListed
        ),
        Step(
            id: "trust-dialog",
            title: CLILocalization.string("PhoneConnectionPlaybook.title-5"),
            phoneScreen: CLILocalization.string("PhoneConnectionPlaybook.string-2"),
            taps: [
                "폰에 RSA 지문과 함께 허용 팝업이 뜨면 **허용** 탭",
                "『항상 이 컴퓨터에서 허용』 체크 권장",
                "팝업이 없으면: 개발자 옵션 → 『USB 디버깅 권한 취소』/『철회』 후 케이블 뽑았다 다시 꽂기",
                "화면이 꺼져 있으면 잠금 해제 후 다시 연결",
            ],
            brandNotes: [
                "unauthorized 상태 = 이 단계를 안 끝낸 것",
                "허용 후에도 안 되면 다른 USB 포트 시도",
            ],
            macSees: "unauthorized → device(ready) · physical PASS",
            passWhen: .physicalReady
        ),
        Step(
            id: "mac-verify",
            title: CLILocalization.string("PhoneConnectionPlaybook.title-6"),
            phoneScreen: "폰은 그대로 둔 채 Mac 앱/CLI 확인",
            taps: [
                "이 앱 운영 탭 실측 checks 에서 physical 이 PASS 인지 확인",
                "또는 터미널: gujo-store-ops adb  → physical PASS",
                "『등록』 버튼으로 서버에 폰을 올림",
                "패키지 선택 → install job → 실행",
            ],
            brandNotes: [],
            macSees: "physical shell OK · 서버 기기 목록에 폰",
            passWhen: .physicalReady
        ),
        Step(
            id: "wireless-optional",
            title: CLILocalization.string("PhoneConnectionPlaybook.title-7"),
            phoneScreen: "개발자 옵션 → 무선 디버깅 — USB 없이도 연결할 때",
            taps: [
                "같은 Wi‑Fi 에 폰과 Mac 연결",
                "개발자 옵션 → 무선 디버깅 ON",
                "『기기 페어링』 → 페어링 코드·IP:포트 확인",
                "Mac: adb pair IP:PORT  (코드 입력)",
                "adb connect IP:PORT  후 gujo-store-ops adb",
            ],
            brandNotes: [
                "Android 11+ 권장",
                "USB 로 한 번 성공한 뒤 무선으로 넘어가면 수월",
            ],
            macSees: "무선 serial device",
            passWhen: .alwaysManual
        ),
    ]

    public static func isStepPassed(_ step: Step, diagnosis: AdbDiagnosis?) -> Bool {
        guard let pass = step.passWhen else { return false }
        guard let d = diagnosis else { return pass == .alwaysManual ? false : false }
        switch pass {
        case .alwaysManual:
            return false
        case .anyListed:
            return !d.devices.isEmpty
        case .unauthorized:
            return d.unauthorizedCount > 0 || d.isReady
        case .physicalReady:
            return d.physicalShellOkCount > 0
        case .anyReady:
            return d.isReady
        }
    }

    public static func plainText() -> String {
        var lines: [String] = [
            "휴대폰 연결 설정 온보딩 (폰에서 누를 것)",
            "정본: PhoneConnectionPlaybook · GUI 『휴대폰 설정』",
            "",
        ]
        for s in steps {
            lines.append("## \(s.title)")
            lines.append(CLILocalization.format("PhoneConnectionPlaybook.string", "\(s.phoneScreen)"))
            lines.append("")
            for (i, t) in s.taps.enumerated() {
                lines.append("  \(i + 1). \(t)")
            }
            if !s.brandNotes.isEmpty {
                lines.append("브랜드:")
                for n in s.brandNotes { lines.append("  · \(n)") }
            }
            lines.append("Mac: \(s.macSees)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
