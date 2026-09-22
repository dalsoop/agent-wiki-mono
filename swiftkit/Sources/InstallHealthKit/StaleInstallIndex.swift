import Foundation
import StateRootKit

/// "지금 도는 이 CLI 가 낡았나" 를 **파일 한 번 읽어** 답하는 색인.
///
/// ## 왜 색인인가
///
/// `InstallProvenance.run()` 은 스탬프마다 `git log -1` 을 띄운다(실측 295개). 정확하지만
/// **CLI 를 부를 때마다** 할 일이 아니다 — 배너 하나 띄우자고 프로세스를 295개 띄우면
/// 그게 더 나쁜 사용성이다. 그래서 이미 그 계산을 하는 곳(`agent-lint-catalog doctor`,
/// App Fleet Doctor)이 결과를 여기 적고, CLI 들은 그 파일만 읽는다.
///
/// ## 왜 배너가 필요한가
///
/// 이 저장소의 검사·연동은 대부분 **설치본**을 부른다. 설치본이 낡으면 계측기가
/// 거짓말을 한다 — 실측 2026-08-10 두 건:
/// - 감사기 설치본(8/5)이 이미 고쳐진 결함 16건을 계속 보고해, 없는 문제를 다시
///   설계할 뻔했다. 소스 빌드로 돌리니 즉시 0.
/// - agent-browser 설치본(8/8)이 낡아 click 버그 진단이 한 바퀴 늦어졌다.
///
/// 둘 다 **CLI 가 스스로 "나 낡았다" 고 말했으면** 즉시 끝났을 일이다.
public enum StaleInstallIndex: Sendable {
    /// 색인 파일 — 스탬프와 같은 디렉터리에 둔다(설치 사실의 원장이 그곳이다).
    /// StateRootKit 경유로 조립 — 테스트 러너 자동 격리·`SWIFT_APP_STATE_ROOT` 오버라이드를 공짜로 얻는다.
    public static var indexURL: URL {
        StateRootKit.url(".agent-ops/install-stamps/stale-index.json")
    }

    /// 배너를 끄는 환경변수 — 배너 자체가 stdout 을 오염시키면 안 되는 자동화용.
    /// (배너는 stderr 로 나가지만, 로그를 통째로 파싱하는 호출자를 위한 탈출구.)
    public static let silenceEnvironmentKey = "SWIFT_APP_NO_STALE_BANNER"

    /// 낡은 설치본 실행 시 경고에 그치지 않고 즉시 차단(Fail-Closed)하는 환경변수.
    public static let enforceEnvironmentKey = "SWIFT_APP_FAIL_CLOSED_STALE"

    public struct Snapshot: Codable, Sendable, Equatable {
        public let updatedAt: String
        /// 낡은 CLI 이름 → 한 줄 사유.
        public let stale: [String: String]

        public init(updatedAt: String, stale: [String: String]) {
            self.updatedAt = updatedAt
            self.stale = stale
        }
    }

    /// 낡음 판정을 계산한 쪽이 결과를 남긴다. 색인은 편의 캐시라 쓰기 실패는 배너가
    /// 안 뜰 뿐 — 낡음의 정본은 스탬프 + git 이고, 다음 doctor 가 다시 쓴다.
    public static func write(_ stale: [(cli: String, reason: String)], at url: URL = indexURL) {
        var table: [String: String] = [:]
        for entry in stale { table[entry.cli] = entry.reason }
        let snapshot = Snapshot(
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            stale: table
        )
        do {
            let data = try JSONEncoder().encode(snapshot)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            // 색인은 편의 캐시라 실패해도 치명적이지 않지만, 조용히 삼키면 배너가
            // 안 뜨는 이유를 아무도 못 찾는다 — stderr 한 줄로 흔적만 남긴다.
            FileHandle.standardError.write(Data("stale-index 쓰기 실패(색인은 캐시, 정본은 스탬프+git): \(error)\n".utf8))
        }
    }

    /// 방금 설치한 CLI 를 색인에서 뺀다.
    ///
    /// 색인은 캐시라 **재설치가 지워 주지 않으면 고친 앱이 계속 "나 낡았다" 고 말한다.**
    /// 실측 2026-08-11: business-request-intake 를 설치한 직후 ADM 은 `verdict=match` 인데
    /// CLI 배너는 "소스가 더 바뀜" 을 계속 냈다. 배너의 존재 이유가 "계측기가 거짓말한다"
    /// 를 막는 것인데, 배너 자체가 거짓말하면 다음부터 아무도 안 믿는다.
    ///
    /// 다음 doctor 가 다시 계산할 때까지의 공백만 메운다 — 낡음의 정본은 여전히 스탬프+git.
    public static func clear(cli: String, at url: URL = indexURL) {
        let snapshot: Snapshot
        do {
            snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
        } catch {
            // 색인이 없거나 깨졌으면 지울 것도 없다 — 침묵이 옳다.
            return
        }
        guard snapshot.stale[cli] != nil else { return }
        var table = snapshot.stale
        table.removeValue(forKey: cli)
        guard let encoded = try? JSONEncoder().encode(
            Snapshot(updatedAt: snapshot.updatedAt, stale: table))
        else { return }
        do {
            try encoded.write(to: url, options: .atomic)
        } catch {
            // clear 실패는 다음 doctor 가 다시 계산하며 자연 치유된다 — 흔적만 남긴다.
            FileHandle.standardError.write(Data("stale-index 정리 실패(다음 doctor 가 다시 쓴다): \(error)\n".utf8))
        }
    }

    /// 이 CLI 가 색인에 낡은 것으로 올라 있으면 사유. 아니면 nil.
    public static func reason(for cli: String, at url: URL = indexURL) -> String? {
        do {
            return try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url)).stale[cli]
        } catch {
            // 색인이 없거나 깨졌으면 낡음 근거가 없다 — nil(배너 안 뜸)이 옳은 답이다.
            return nil
        }
    }

    /// 낡았으면 **stderr 에 한 줄**. stdout 은 절대 건드리지 않는다 — 이 함대의 CLI
    /// stdout 은 기계가 파싱하는 JSON 이라 한 줄만 섞여도 호출자가 깨진다.
    ///
    /// - Parameter cli: 이 실행 파일 이름. 기본값은 argv[0] 의 basename.
    /// - Parameter quietWhenJSON: `--json` 인자가 있으면 배너를 억제한다. 기본값 true.
    public static func warnIfStale(
        cli: String? = nil,
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        at url: URL = indexURL,
        quietWhenJSON: Bool = true,
        emit: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) },
        exitHandler: (Int32) -> Void = { exit($0) }
    ) {
        guard environment[silenceEnvironmentKey] == nil else { return }
        let isEnforced = environment[enforceEnvironmentKey] == "1"
        if quietWhenJSON && !isEnforced {
            let hasJSONFlag = arguments.contains("--json")
            if hasJSONFlag { return }
        }
        let name = cli ?? (arguments.first as NSString?)?.lastPathComponent
        guard let name, !name.isEmpty, let reason = reason(for: name, at: url) else { return }
        if isEnforced {
            emit("[fail-closed] \(name): 설치본이 소스보다 낡아 실행을 차단합니다 (Fail-Closed) — \(reason)\n"
                + "  재설치: app-build-manager 로 apps/<앱> release 를 다시 설치\n"
                + "  (긴급 우회: SWIFT_APP_FAIL_CLOSED_STALE=0 또는 SWIFT_APP_NO_STALE_BANNER=1)\n")
            exitHandler(70)
            return
        }
        emit("⚠ \(name): 설치본이 소스보다 낡았습니다 — \(reason)\n"
            + "  이 결과는 옛 코드에서 나온 것입니다. 재설치: app-build-manager 로 apps/<앱> release 를 다시 설치\n")
    }
}

/// 낡은 설치본 배너를 stderr 로 출력하는 진입점.
/// stdout 오염을 원천 차단하기 위해 stderr 고정 API 를 제공한다.
public enum StaleInstallBanner: Sendable {
    /// 낡은 설치본 배너를 stderr 로 출력한다.
    /// stdout 은 절대 건드리지 않으며, `--json` 인자가 있으면 배너를 억제한다.
    public static func printToStderr(
        cli: String? = nil,
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        at url: URL = StaleInstallIndex.indexURL,
        quietWhenJSON: Bool = true
    ) {
        StaleInstallIndex.warnIfStale(
            cli: cli,
            arguments: arguments,
            environment: environment,
            at: url,
            quietWhenJSON: quietWhenJSON,
            emit: { FileHandle.standardError.write(Data($0.utf8)) }
        )
    }
}
