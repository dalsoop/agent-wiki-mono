import Foundation
import LocalizationKit

/// adb 연결을 **감시하며 한 수씩 지도**하는 코치.
///
/// 정적 체크리스트가 아니라: 지금 관측 → 지금 할 일 1개 → 성공 조건.
/// GUI 폴링·CLI `--watch`·에이전트 루프가 같은 턴 모델을 쓴다.
public struct AdbCoachTurn: Sendable, Equatable, Codable {
    public var kind: AdbDiagnosis.Kind
    /// 지금 사람이 할 단 한 가지 (AI 가 그대로 말해도 됨).
    public var nowDo: String
    /// 왜 그 일인지 한 줄.
    public var why: String
    /// 이게 보이면 다음으로 넘어감.
    public var waitingFor: String
    public var ready: Bool
    /// 직전 스캔 대비 상태 전이 (있으면 에이전트가 축하/전환 멘트).
    public var event: Event?
    public var headline: String
    public var deviceLines: [String]
    public var scannedAt: Date

    public enum Event: String, Sendable, Codable, Equatable {
        case becameReady
        case becameUnauthorized
        case becameOffline
        case lostDevices
        case adbAppeared
        case stillWaiting
        case firstScan
    }

    public init(
        kind: AdbDiagnosis.Kind,
        nowDo: String,
        why: String,
        waitingFor: String,
        ready: Bool,
        event: Event? = nil,
        headline: String,
        deviceLines: [String] = [],
        scannedAt: Date = Date()
    ) {
        self.kind = kind
        self.nowDo = nowDo
        self.why = why
        self.waitingFor = waitingFor
        self.ready = ready
        self.event = event
        self.headline = headline
        self.deviceLines = deviceLines
        self.scannedAt = scannedAt
    }

    /// 에이전트/사람이 읽기 좋은 한 덩어리.
    public var spokenLine: String {
        if let event, event == .becameReady {
            return CLILocalization.format("AdbConnectCoach.return", nowDo)
        }
        if let event, event != .stillWaiting, event != .firstScan {
            return CLILocalization.format("AdbConnectCoach.return-2", event.rawValue, nowDo)
        }
        return nowDo
    }

    public var plainText: String {
        var lines = [
            CLILocalization.format("AdbConnectCoach.string-9", "\(nowDo)"),
            CLILocalization.format("AdbConnectCoach.string-8", "\(why)"),
            CLILocalization.format("AdbConnectCoach.string-7", "\(waitingFor)"),
            CLILocalization.format("AdbConnectCoach.string-6", "\(headline)"),
        ]
        if let event { lines.append("event: \(event.rawValue)") }
        if !deviceLines.isEmpty {
            lines.append("devices:")
            lines.append(contentsOf: deviceLines.map { "  \($0)" })
        }
        return lines.joined(separator: "\n")
    }
}

public enum AdbConnectCoach: Sendable {
    /// 진단 한 장 → 지도 한 턴.
    public static func turn(
        from diagnosis: AdbDiagnosis,
        previousKind: AdbDiagnosis.Kind? = nil,
        serverSerials: Set<String> = [],
        scannedAt: Date = Date()
    ) -> AdbCoachTurn {
        let event = transitionEvent(from: previousKind, to: diagnosis.kind)
        let (nowDo, why, waiting) = script(for: diagnosis, serverSerials: serverSerials)
        let deviceLines = diagnosis.devices.map { d in
            let serial = d.serial ?? d.id
            let shell = diagnosis.shellOkSerials.contains(serial) ? "shellOK" : "shell—"
            let kind = AdbDiagnosis.isEmulatorSerial(serial) ? "emu" : "phys"
            return "\(d.state)\t\(shell)\t\(kind)\t\(serial)\t\(d.label)"
        }
        return AdbCoachTurn(
            kind: diagnosis.kind,
            nowDo: nowDo,
            why: why,
            waitingFor: waiting,
            ready: diagnosis.isReady,
            event: event,
            headline: diagnosis.headline,
            deviceLines: deviceLines,
            scannedAt: scannedAt
        )
    }

    /// "이 상태로 **들어섰다**" 가 곧 이벤트인 짝들. `if` 사슬로 두면 새 상태를
    /// 중간에 끼워 넣다 순서를 깨뜨리기 쉽다 — 표는 순서에 기대지 않는다
    /// (한 턴의 `current` 는 어차피 한 칸에만 맞는다).
    private static let enterEvents: [(kind: AdbDiagnosis.Kind, event: AdbCoachTurn.Event)] = [
        (.ready, .becameReady),
        (.unauthorized, .becameUnauthorized),
        (.offline, .becameOffline),
        (.noDevices, .lostDevices),
    ]

    private static func transitionEvent(
        from previous: AdbDiagnosis.Kind?,
        to current: AdbDiagnosis.Kind
    ) -> AdbCoachTurn.Event {
        guard let previous else { return .firstScan }
        guard previous != current else { return .stillWaiting }
        guard let entered = enterEvents.first(where: { $0.kind == current }) else {
            // 표에 없는 칸으로 간 전이는 adbMissing 을 벗어난 것뿐이다.
            return previous == .adbMissing ? .adbAppeared : .stillWaiting
        }
        return entered.event
    }

    private static func script(
        for d: AdbDiagnosis,
        serverSerials: Set<String>
    ) -> (String, String, String) {
        switch d.kind {
        case .adbMissing:
            return (
                "터미널에서 brew install android-platform-tools 를 실행하세요.",
                "adb version 실측 실패 — 바이너리가 없거나 깨졌습니다.",
                "checks 의 version 이 PASS"
            )
        case .noDevices:
            return (
                "데이터 케이블로 폰을 꽂고 USB 디버깅을 켠 뒤, 앱에서 ‘지금 검사’로 checks 가 바뀌는지 보세요.",
                "adb devices -l 실측 결과 0대입니다 (목록 장식이 아님).",
                "checks devices_parse > 0 또는 unauthorized 줄 등장"
            )
        case .unauthorized:
            return (
                "폰 팝업에서 USB 디버깅 허용을 누르세요. 허용 후 감시가 shell OK 로 바뀝니다.",
                CLILocalization.format("AdbConnectCoach.string-5", "\(d.unauthorizedCount)"),
                "checks shell.* 가 PASS"
            )
        case .offline:
            return (
                "케이블 재연결 후 adb kill-server && adb start-server 를 실행하세요.",
                CLILocalization.format("AdbConnectCoach.string-4", "\(d.offlineCount)"),
                "state 가 device 이고 shell PASS"
            )
        case .mixedNotReady:
            return (
                "아래 devices 줄의 state/shell 열을 보고 허용 또는 재연결하세요.",
                "파싱된 기기는 있으나 shell OK 가 0입니다.",
                "shell OK ≥ 1"
            )
        case .listedButShellDead:
            return (
                "adb -s SERIAL get-state 가 device 인지 확인하세요. 아니면 케이블 재연결·에뮬 재기동 후 ‘지금 검사’.",
                CLILocalization.format("AdbConnectCoach.string-3", "\(d.listedReadyCount)"),
                "checks probe.* PASS · get-state=device"
            )
        case .ready:
            return readyScript(for: d, serverSerials: serverSerials)
        }
    }

    /// shell 이 통과한 뒤의 갈래 — 서버 등록 여부와 에뮬 전용 여부로 다음 할 일이 갈린다.
    private static func readyScript(
        for d: AdbDiagnosis,
        serverSerials: Set<String>
    ) -> (String, String, String) {
        let registered = Set(d.shellOkSerials).intersection(serverSerials)
        guard registered.isEmpty else {
            let kind = d.onlyEmulator
                ? CLILocalization.string("AdbConnectCoach.emu")
                : CLILocalization.string("AdbConnectCoach.phys")
            return (
                "서버에 이미 등록된 shell OK 기기가 있습니다. 패키지를 고르고 install job 을 만드세요.",
                CLILocalization.format(
                    "AdbConnectCoach.string-10", "\(d.shellOkCount)", "\(registered.count)", kind),
                "job status=succeeded"
            )
        }
        guard !d.onlyEmulator else {
            return (
                "에뮬레이터 shell 만 통과했습니다. 실기기면 USB를 확인하고, 에뮬로 가려면 ‘등록’을 누르세요.",
                CLILocalization.format("AdbConnectCoach.string-2", "\(d.shellOkCount)"),
                "등록 후 서버 목록에 emulator serial 또는 실기기 shell OK"
            )
        }
        return (
            "앱에서 ‘등록’을 누르거나 gujo-store-ops register-device 를 실행하세요.",
            CLILocalization.format("AdbConnectCoach.string", "\(d.shellOkCount)"),
            "서버 기기 목록에 이 serial"
        )
    }
}

#if os(macOS)
/// 폴링 세션 — 이전 kind 를 기억해 event 를 붙인다.
public actor AdbCoachMonitor {
    private let adb: AdbClient
    private var previousKind: AdbDiagnosis.Kind?

    public init(adb: AdbClient = AdbClient()) {
        self.adb = adb
    }

    public func tick(serverSerials: Set<String> = []) async -> AdbCoachTurn {
        let diag = await adb.diagnose()
        let turn = AdbConnectCoach.turn(
            from: diag,
            previousKind: previousKind,
            serverSerials: serverSerials
        )
        previousKind = diag.kind
        return turn
    }

    /// ready 될 때까지 폴링. 에이전트/CLI watch 용.
    public func watch(
        intervalSeconds: Double = AdbCoachTimingConfig.watchIntervalSeconds,
        timeoutSeconds: Double = AdbCoachTimingConfig.watchTimeoutSeconds,
        onTurn: @Sendable (AdbCoachTurn) async -> Void
    ) async -> AdbCoachTurn {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var last: AdbCoachTurn?
        while Date() < deadline {
            let turn = await tick(serverSerials: [])
            last = turn
            await onTurn(turn)
            if turn.ready { return turn }
            do {
                try await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
            } catch {
                // 취소는 감시 종료다. 삼키면 취소된 뒤에도 폴링이 계속 돌아
                // 남은 deadline 동안 adb 를 두드린다.
                return turn
            }
        }
        return last ?? AdbConnectCoach.turn(
            from: AdbDiagnosis.classify(adbAvailable: false, adbPath: "adb", devices: [])
        )
    }
}
#endif
