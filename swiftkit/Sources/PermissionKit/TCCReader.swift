import Foundation

/// TCC.db 를 읽어 "어떤 앱이 무슨 권한을 받았나"를 뽑는 공용 리더.
///
/// SSOT: 이 타입은 PermissionKit 이 정본이다. mac-permissions-manager 의 전체 매트릭스도,
/// 개별 앱이 자기 권한만 확인하는 경우(`grants(forBundleID:)`)도 같은 구현을 쓴다.
///
/// 사용자 db(`~/Library/Application Support/com.apple.TCC/TCC.db`)는 **전체 디스크 접근(FDA)**
/// 만 있으면 읽힌다. 시스템 db(`/Library/...`, 화면기록·손쉬운사용 등)는 root 가 필요해
/// 대개 못 읽는다 → 그 서비스는 호출자가 `.unknown` 으로 정직하게 표기한다.
///
/// ## ⚠️ 앱 시작 시 호출하지 말 것
///
/// `~/Library/Application Support/com.apple.TCC` 는 **다른 앱의 데이터**다. macOS
/// Sequoia 의 앱 데이터 보호가 이 읽기를 `kTCCServiceSystemPolicyAppData` 로 잡아
/// "다른 앱의 데이터에 접근하려 합니다" 프롬프트를 띄운다. 실측(rightclick, MR !2035)
/// 결과 그 요청은 tccd 로그상 `DB Action:None` 으로 처리돼 **사용자가 [허용] 을 눌러도
/// 저장되지 않는다** — 즉 실행할 때마다 다시 뜬다.
///
/// 그래서 규칙은 하나다: **사용자가 명시적으로 "권한 상태 확인" 을 요청했을 때만 부른다.**
/// init·onAppear·타이머·상태 새로고침 경로에 넣지 않는다. 확인 전 상태는 `.unknown`
/// 이지만 그것을 "읽을 수 없음(FDA 필요)" 으로 표시해서도 안 된다 — 아직 안 본 것과
/// 보고 실패한 것은 다른 사실이다.
///
/// 권한 실패는 예방적 조회 대신 **실제 실패를 관측해서** 알린다:
/// `Automation.isDenied(stderr:)` 처럼 시도 결과로 판정하면 프롬프트가 없다.
///
/// 전체 매트릭스를 보여주는 것이 제품의 목적인 앱(mac-permissions-manager)만
/// 예외다 — 그 앱은 FDA 를 전제로 하고, 조회 자체가 사용자가 요청한 기능이다.
///
/// ## 파이프 교착 (2026-08-01 실측)
/// 사용자 TCC.db 가 커지면 `SELECT service, client, auth_value FROM access` 출력이
/// 64KB 파이프 버퍼를 넘긴다. wait 후에만 stdout 을 읽으면 자식이 write 에 막히고
/// 워치독이 빈 결과를 돌려 **카메라·마이크 등 사용자 스코프 권한이 status 에서
/// 전부 사라진다.** 대기 전에 드레인한다(TCCGranter / ProcessWait 와 동일).
public struct TCCReader: Sendable {
    public var userDBPath: String
    public var systemDBPath: String

    public init(
        userDBPath: String = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
        systemDBPath: String = "/Library/Application Support/com.apple.TCC/TCC.db"
    ) {
        self.userDBPath = userDBPath
        self.systemDBPath = systemDBPath
    }

    /// 이 프로세스가 사용자 TCC.db 를 읽을 수 있나(= FDA 보유 신호).
    /// `Permission.fullDiskAccess.isGranted` 와 같은 1차 신호 + sqlite 실제 질의.
    public var canReadUserDB: Bool {
        // PermissionKit 공용 프로브와 경로 기준을 맞춘 뒤, 쿼리까지 통과해야 true.
        guard Permission.canReadUserTCCDatabase()
                || FileManager.default.isReadableFile(atPath: userDBPath) else {
            return false
        }
        return querySucceeds(db: userDBPath)
    }

    /// bundleID → (service → GrantState) 맵.
    ///
    /// 시스템 스코프 서비스(Accessibility·ScreenCapture·FDA 등)는 **시스템 db 행만**
    /// 인정한다. 사용자 db 에 같은 키가 있어도 enforcement 가 읽지 않으므로
    /// granted 로 보여 주면 오판이다(grant-all 이 사용자 db 에 쌓아 둔 가짜 행).
    /// 사용자 스코프는 사용자 db, 그 위에 시스템 db 가 있으면 덮어쓴다.
    public func grants() -> [String: [String: GrantState]] {
        var out: [String: [String: GrantState]] = [:]
        if FileManager.default.isReadableFile(atPath: userDBPath) {
            for row in rows(db: userDBPath) where !isSystemScopedServiceKey(row.service) {
                out[row.client, default: [:]][row.service] = row.state
            }
        }
        if FileManager.default.isReadableFile(atPath: systemDBPath) {
            for row in rows(db: systemDBPath) {
                out[row.client, default: [:]][row.service] = row.state
            }
        }
        return out
    }

    /// 한 앱만 — 자기 권한을 확인하는 앱이 전체 맵을 만들 필요가 없게.
    /// 읽지 못하면 빈 맵(호출자가 `canReadUserDB` 로 "모름"과 "없음"을 구분한다).
    public func grants(forBundleID bundleID: String) -> [String: GrantState] {
        var out: [String: GrantState] = [:]
        if FileManager.default.isReadableFile(atPath: userDBPath) {
            for row in rows(db: userDBPath)
                where row.client == bundleID && !isSystemScopedServiceKey(row.service) {
                out[row.service] = row.state
            }
        }
        if FileManager.default.isReadableFile(atPath: systemDBPath) {
            for row in rows(db: systemDBPath) where row.client == bundleID {
                out[row.service] = row.state
            }
        }
        return out
    }

    /// TCC.db service 키가 시스템 스코프인지 — 카탈로그에 없으면 false.
    private func isSystemScopedServiceKey(_ key: String) -> Bool {
        TCCService(tccDatabaseKey: key)?.isSystemScoped == true
    }

    // MARK: -

    private struct Row { var service: String; var client: String; var state: GrantState }

    private func rows(db: String) -> [Row] {
        // auth_value: 0 denied · 2 allowed · 3 limited (사진 등). 컬럼명은 최신 스키마 기준.
        let sql = "SELECT service, client, auth_value FROM access;"
        return sqlite(db: db, sql: sql).compactMap { line in
            let cols = line.components(separatedBy: "|")
            guard cols.count >= 3 else { return nil }
            return Row(service: cols[0], client: cols[1], state: .fromAuthValue(cols[2]))
        }
    }

    private func querySucceeds(db: String) -> Bool {
        !sqlite(db: db, sql: "SELECT 1 FROM access LIMIT 1;").isEmpty
    }

    /// `sqlite3` CLI 로 읽기 전용 쿼리(파일이 잠겨 있을 수 있어 immutable 모드).
    ///
    /// **대기 전에 stdout 을 드레인한다.** 출력이 파이프 버퍼(보통 64KB)를 넘기면
    /// wait-then-read 순서는 교착 → 타임아웃 → 빈 결과로 끝난다.
    private func sqlite(db: String, sql: String) -> [String] {
        let bin = "/usr/bin/sqlite3"
        guard FileManager.default.isExecutableFile(atPath: bin) else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        // 경로에 공백이 있어도 동작하도록 plain path + -readonly 를 쓴다.
        // (file: URI 는 인코딩 실수 여지가 있고, 실측 plain path 가 충분했다.)
        process.arguments = ["-readonly", db, sql]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }

        // 드레인 먼저 — 파이프 버퍼 교착 방지.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        let watchdog = DispatchWorkItem { process.terminate() }
        // 대형 user TCC.db 도 수 초 안에 끝나야 한다. 15s 는 여유.
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: watchdog)
        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationStatus == 0 else { return [] }
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n").map(String.init)
    }
}
