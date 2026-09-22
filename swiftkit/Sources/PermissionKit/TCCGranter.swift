import Foundation

/// TCC.db 에 직접 grant 를 밀어넣는 그랜터.
///
/// ## 전제
/// 이 프로세스(를 포함한 앱)가 **전체 디스크 접근(FDA)** 을 보유해야 **사용자** TCC.db
/// (`~/Library/…/TCC.db`) 를 쓸 수 있다.
///
/// ## 시스템 db 와 SIP (2026-08-01 실측, 정정)
/// `/Library/…/TCC.db` 는 SIP 보호다. FDA·sudo 모두 INSERT 가
/// `attempt to write a readonly database` 로 실패한다. `BEGIN IMMEDIATE` 만 보면
/// 성공처럼 보이므로 **실제 INSERT 프로브**로 판정한다.
/// → 접근성·화면 기록·입력 모니터링·FDA 자체는 시스템 설정 토글이 정답 경로다.
///
/// ## 두 개의 db
/// 서비스마다 **강제되는 db 가 다르다.** 잘못된 db 에 써도 sqlite 는 성공을 돌려주므로
/// 조용히 무효가 된다.
///
/// - 시스템 db(`/Library/…`): Accessibility · ListenEvent · PostEvent · ScreenCapture ·
///   SystemPolicyAllFiles
/// - 사용자 db(`~/Library/…`): 그 외 전부
///
/// 실제 사고 — 이전 구현은 전부 사용자 db 에 썼다. `SystemPolicyAllFiles` 행이 사용자 db 에
/// 101건 쌓여 있었지만 FDA 는 시스템 db 에서 강제되므로 아무 효과가 없었고, CLI 는
/// "부여 완료" 를 보고했다.
///
/// ## csreq
/// 실제로 동작하는 모든 행은 `csreq` blob(코드서명 요구사항)을 갖는다. 이전 구현은 NULL 을
/// 넣었다. 앱 번들의 designated requirement 를 뽑아 blob 으로 만들어 채운다.
///
/// AppleEvents(`kTCCServiceAppleEvents`)는 `indirect_object_identifier`(제어 대상 앱)가
/// 필요해 대상 쌍마다 행이 달라진다. 이 그랜터는 다루지 않는다.
public struct TCCGranter: Sendable {
    public var userDBPath: String
    public var systemDBPath: String

    /// 이 그랜터가 다루는 서비스. AppleEvents 는 제외한다.
    public static let supportedServices: [TCCService] =
        TCCService.allCases.filter { $0 != .automation }

    /// 예전 이름 호환 — 서비스 키 문자열 목록.
    public static var supportedServiceKeys: [String] {
        supportedServices.map(\.tccDatabaseKey)
    }

    public init(
        userDBPath: String = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
        systemDBPath: String = "/Library/Application Support/com.apple.TCC/TCC.db"
    ) {
        self.userDBPath = userDBPath
        self.systemDBPath = systemDBPath
    }

    // MARK: - 결과

    public enum ServiceOutcome: String, Sendable, Codable {
        /// 써넣고 읽기 검증까지 통과.
        case granted
        /// 이미 허용 상태였다.
        case alreadyGranted
        /// 쓰기는 됐지만 읽기 검증에서 확인되지 않았다(tccd 가 되돌렸을 수 있다).
        case writtenButUnverified
        /// db 를 열 수 없거나 쓰기 잠금을 얻지 못했다.
        case databaseUnwritable
        /// csreq 를 만들 수 없었다(번들이 없거나 서명되지 않음).
        case missingCodeRequirement
        case failed
    }

    public struct GrantResult: Sendable {
        public var success: Bool
        public var servicesGranted: Int
        public var servicesFailed: [String]
        public var detail: String
        /// 서비스별 결과 — 뭉뚱그린 카운트 대신 실제로 무엇이 됐는지 남긴다.
        public var outcomes: [String: ServiceOutcome]
        /// 부여 계획(쓰기 전 산출). 선언 없음 스킵 시 services 가 비고 skipReason 이 찬다.
        public var plan: GrantPlan?

        public init(success: Bool, servicesGranted: Int, servicesFailed: [String],
                    detail: String, outcomes: [String: ServiceOutcome] = [:],
                    plan: GrantPlan? = nil) {
            self.success = success
            self.servicesGranted = servicesGranted
            self.servicesFailed = servicesFailed
            self.detail = detail
            self.outcomes = outcomes
            self.plan = plan
        }

        /// 선언이 없어 부여를 건너뛴 경우 — 실패가 아니라 안전 스킵.
        public var skippedNoDeclaration: Bool {
            plan?.skipReason != nil && (plan?.services.isEmpty ?? true)
        }

        /// 실패가 하나 이상 있고, 그 전부가 “시스템 TCC.db 쓰기 거부(SIP)” 이면 true.
        /// 이 경우 사용자 스코프 grant 는 성공한 것이므로 exit 1 로 몰면 안 된다.
        public var onlySystemDBBlocked: Bool {
            let ok: Set<ServiceOutcome> = [.granted, .alreadyGranted]
            var sawFailure = false
            for (key, outcome) in outcomes {
                if ok.contains(outcome) { continue }
                sawFailure = true
                if outcome == .databaseUnwritable,
                   let service = TCCService(tccDatabaseKey: key),
                   service.isSystemScoped {
                    continue
                }
                return false
            }
            return sawFailure
        }

        /// 전체 success 이거나 SIP 로 시스템만 막힌 경우 — 운영상 “부여 가능분은 끝”.
        public var effectiveSuccess: Bool { success || onlySystemDBBlocked }

        public var systemBlockedCount: Int {
            outcomes.reduce(0) { acc, pair in
                guard pair.value == .databaseUnwritable,
                      let s = TCCService(tccDatabaseKey: pair.key),
                      s.isSystemScoped else { return acc }
                return acc + 1
            }
        }
    }

    /// grant 대상 **db 스코프** (사용자/시스템/둘 다).
    /// 서비스 **집합** 정책은 `ServiceSelection` — 예전엔 scope=.all 이 곧 전 서비스 부여여서
    /// 카메라·마이크 등 미사용 권한이 함대에 박혔다(2026-08 실측).
    public enum Scope: String, Sendable, CaseIterable {
        /// 사용자+시스템 db 서비스 모두(필터 없음).
        case all
        /// 사용자 TCC.db 만 — SIP 환경에서 실제로 쓸 수 있는 축.
        case user
        /// 시스템 TCC.db 만 — SIP 켜면 거의 항상 실패; 명시 요청 시.
        case system

        public func includes(_ service: TCCService) -> Bool {
            switch self {
            case .all: return true
            case .user: return !service.isSystemScoped
            case .system: return service.isSystemScoped
            }
        }
    }

    /// 부여할 **서비스 집합** 정책. 기본은 선언만 — 전 서비스는 명시 탈출구.
    public enum ServiceSelection: String, Sendable, CaseIterable {
        /// Info.plist `SwiftAppRequired/OptionalPermissions` 교차만 (기본).
        case declared
        /// 지원 서비스 전부. CLI 에서 `--scope all` 을 사람이 직접 줄 때만.
        case all
    }

    /// 실제 TCC 쓰기 전 부여 대상 계획.
    public struct GrantPlan: Sendable, Equatable {
        public var services: [TCCService]
        /// 부여를 건너뛴 이유. nil 이면 계획의 services 를 쓴다.
        public var skipReason: String?
        public var serviceSelection: ServiceSelection
        public var scope: Scope

        public init(services: [TCCService], skipReason: String? = nil,
                    serviceSelection: ServiceSelection, scope: Scope) {
            self.services = services
            self.skipReason = skipReason
            self.serviceSelection = serviceSelection
            self.scope = scope
        }

        public var isEmpty: Bool { services.isEmpty }
    }

    /// 선언 없는 앱에 조용히 전 권한을 주지 않기 위한 고정 안내.
    /// 왜 이 문구인가: 폴백으로 전 서비스를 주면 2026-08 함대 오부여 사고가 재발한다.
    public static let noDeclarationSkipMessage =
        "선언 없음 — 부여 건너뜀. mac-permission-monitor declarations 로 선언을 먼저 채우세요"

    // MARK: - 계획 산출 (쓰기 없음)

    /// 앱 경로에서 Info.plist 후보를 고른다(설치본 Contents · Packaging · 직접 경로).
    public static func infoPlistPath(forAppAt appPath: String) -> String? {
        let fm = FileManager.default
        if appPath.hasSuffix("Info.plist"), fm.fileExists(atPath: appPath) {
            return appPath
        }
        // 설치본 · 소스 Packaging · 번들 루트 순. 있는 첫 경로만 쓴다.
        let candidates = [
            (appPath as NSString).appendingPathComponent("Contents/Info.plist"),
            (appPath as NSString).appendingPathComponent("Packaging/Info.plist"),
            (appPath as NSString).appendingPathComponent("Info.plist"),
        ]
        return candidates.first { fm.fileExists(atPath: $0) }
    }

    /// 부여 계획만 산출한다. TCC.db 를 읽거나 쓰지 않는다.
    public static func planGrant(
        appPath: String?,
        scope: Scope = .user,
        serviceSelection: ServiceSelection = .declared
    ) -> GrantPlan {
        switch serviceSelection {
        case .all:
            // 명시적 탈출구 — 지원 서비스 × scope 필터.
            let services = supportedServices.filter { scope.includes($0) }
            return GrantPlan(services: services, skipReason: nil,
                             serviceSelection: .all, scope: scope)
        case .declared:
            guard let appPath,
                  let plist = infoPlistPath(forAppAt: appPath),
                  let declaration = PermissionRequirements.declared(infoPlistPath: plist),
                  !declaration.isEmpty
            else {
                return GrantPlan(services: [], skipReason: noDeclarationSkipMessage,
                                 serviceSelection: .declared, scope: scope)
            }
            // 선언(Permission) → TCCService, automation 제외, scope 교집합, 중복 제거.
            var seen = Set<TCCService>()
            var services: [TCCService] = []
            for permission in declaration.all {
                let service = permission.tccService
                guard service != .automation, scope.includes(service) else { continue }
                if seen.insert(service).inserted {
                    services.append(service)
                }
            }
            return GrantPlan(services: services, skipReason: nil,
                             serviceSelection: .declared, scope: scope)
        }
    }

    // MARK: - 부여

    /// 한 앱에 grant 한다. **기본은 선언된 권한만** — 미선언 앱은 건너뛴다.
    ///
    /// - Parameters:
    ///   - bundleID: TCC `client` 값.
    ///   - appPath: csreq·Info.plist 를 뽑을 `.app`(또는 Packaging) 경로.
    ///   - scope: db 스코프 필터. 기본 `.user`(SIP 환경에서 쓸 수 있는 축).
    ///   - serviceSelection: `.declared`(기본) 또는 전 서비스 탈출구 `.all`.
    public func grantAll(
        bundleID: String,
        appPath: String?,
        scope: Scope = .user,
        serviceSelection: ServiceSelection = .declared
    ) -> GrantResult {
        guard !bundleID.isEmpty else {
            return GrantResult(success: false, servicesGranted: 0, servicesFailed: [],
                               detail: "empty bundleID")
        }

        let plan = Self.planGrant(appPath: appPath, scope: scope, serviceSelection: serviceSelection)
        if let reason = plan.skipReason {
            // 선언 없음 — 전 서비스로 폴백하지 않는다(함대 오부여 재발 방지).
            return GrantResult(
                success: true, servicesGranted: 0, servicesFailed: [],
                detail: reason, outcomes: [:], plan: plan)
        }
        let services = plan.services
        guard !services.isEmpty else {
            return GrantResult(
                success: true, servicesGranted: 0, servicesFailed: [],
                detail: "no services in plan", outcomes: [:], plan: plan)
        }

        guard let requirement = appPath.flatMap({ Self.designatedRequirement(ofBundleAt: $0) }),
              let csreqHex = Self.csreqHex(for: requirement) else {
            let keys = services.map(\.tccDatabaseKey)
            return GrantResult(
                success: false, servicesGranted: 0, servicesFailed: keys,
                detail: "csreq 를 만들 수 없다(번들 경로 없음·미서명). csreq 없는 행은 TCC 가 무시한다.",
                outcomes: Dictionary(uniqueKeysWithValues: keys.map { ($0, .missingCodeRequirement) }),
                plan: plan)
        }

        var outcomes: [String: ServiceOutcome] = [:]
        for service in services {
            outcomes[service.tccDatabaseKey] = grant(service: service, bundleID: bundleID, csreqHex: csreqHex)
        }

        let ok: Set<ServiceOutcome> = [.granted, .alreadyGranted]
        let failedKeys = outcomes.filter { !ok.contains($0.value) }.keys.sorted()
        let grantedCount = outcomes.values.filter { ok.contains($0) }.count

        return GrantResult(
            success: failedKeys.isEmpty,
            servicesGranted: grantedCount,
            servicesFailed: failedKeys,
            detail: failedKeys.isEmpty
                ? "ok"
                : failedKeys.map { "\($0)=\(outcomes[$0]!.rawValue)" }.joined(separator: ", "),
            outcomes: outcomes,
            plan: plan)
    }

    /// 서비스 하나에 grant 하고 읽어서 확인한다.
    public func grant(service: TCCService, bundleID: String, csreqHex: String) -> ServiceOutcome {
        // 강제되는 db 로 라우팅한다. 틀린 db 에 쓰면 sqlite 는 성공하지만 무효다.
        let db = service.isSystemScoped ? systemDBPath : userDBPath
        guard FileManager.default.fileExists(atPath: db) else { return .databaseUnwritable }

        // auth_value=2 여도 csreq 가 없으면 TCC 가 무시한다 → 덮어써서 고친다.
        if currentAuthValue(service: service, bundleID: bundleID, db: db) == 2,
           hasCodeRequirement(service: service, bundleID: bundleID, db: db) {
            return .alreadyGranted
        }

        let client = Self.sqlQuoted(bundleID)
        let sql = """
        INSERT OR REPLACE INTO access \
        (service, client, client_type, auth_value, auth_reason, auth_version, csreq, flags, last_modified) \
        VALUES ('\(service.tccDatabaseKey)', \(client), 0, 2, 4, 1, X'\(csreqHex)', 0, strftime('%s','now'));
        """
        guard runSqlite(db: db, sql: sql, readOnly: false) != nil else { return .databaseUnwritable }

        // 성공 판정은 exit code 가 아니라 읽기 검증으로 한다.
        return currentAuthValue(service: service, bundleID: bundleID, db: db) == 2
            ? .granted
            : .writtenButUnverified
    }

    /// 여러 앱 일괄. 기본은 앱별 선언만 부여.
    public func grantAllForApps(
        _ apps: [(bundleID: String, path: String?)],
        scope: Scope = .user,
        serviceSelection: ServiceSelection = .declared
    ) -> [String: GrantResult] {
        var results: [String: GrantResult] = [:]
        for app in apps {
            results[app.bundleID] = grantAll(
                bundleID: app.bundleID, appPath: app.path,
                scope: scope, serviceSelection: serviceSelection)
        }
        return results
    }

    // MARK: - 조회

    /// 현재 auth_value (2 = allowed). 못 읽으면 nil.
    public func currentAuthValue(service: TCCService, bundleID: String, db: String) -> Int? {
        let sql = """
        select auth_value from access where service='\(service.tccDatabaseKey)' \
        and client=\(Self.sqlQuoted(bundleID)) limit 1;
        """
        guard let out = runSqlite(db: db, sql: sql, readOnly: true) else { return nil }
        return Int(out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// csreq blob 이 비어 있지 않은지. 없으면 행이 있어도 무효에 가깝다.
    public func hasCodeRequirement(service: TCCService, bundleID: String, db: String) -> Bool {
        let sql = """
        select length(csreq) from access where service='\(service.tccDatabaseKey)' \
        and client=\(Self.sqlQuoted(bundleID)) limit 1;
        """
        guard let out = runSqlite(db: db, sql: sql, readOnly: true) else { return false }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let n = Int(trimmed), n > 0 else { return false }
        return true
    }

    /// 이 프로세스가 각 db 에 쓸 수 있는지 — grant 전에 확인해 원인을 분명히 한다.
    ///
    /// 시스템 db 는 BEGIN 성공·INSERT 실패가 흔하다(SIP). INSERT 프로브로 판정한다.
    public func writability() -> (user: Bool, system: Bool) {
        (canWriteUserDB(), canWriteSystemDB())
    }

    private func canWriteUserDB() -> Bool {
        runSqlite(db: userDBPath, sql: "BEGIN IMMEDIATE; ROLLBACK;", readOnly: false) != nil
    }

    private func canWriteSystemDB() -> Bool {
        guard FileManager.default.fileExists(atPath: systemDBPath) else { return false }
        // BEGIN 만으로는 readonly 를 못 잡는다 — 실제 INSERT 후 즉시 DELETE.
        let client = "net.ranode.permissionkit.writability-probe"
        let insert = """
        INSERT OR REPLACE INTO access \
        (service, client, client_type, auth_value, auth_reason, auth_version, flags, last_modified) \
        VALUES ('kTCCServiceAccessibility', '\(client)', 0, 0, 4, 1, 0, strftime('%s','now'));
        """
        let delete = "DELETE FROM access WHERE client='\(client)';"
        guard runSqlite(db: systemDBPath, sql: insert, readOnly: false) != nil else { return false }
        _ = runSqlite(db: systemDBPath, sql: delete, readOnly: false)
        return true
    }

    /// 시스템 스코프 권한 설정 딥링크(중복 제거).
    public static var systemSettingsURLs: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for service in supportedServices where service.isSystemScoped {
            let url = service.settingsURLString
            if seen.insert(url).inserted { out.append(url) }
        }
        return out
    }

    // MARK: - csreq

    /// 번들의 designated requirement 문자열.
    public static func designatedRequirement(ofBundleAt path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let out = runTool("/usr/bin/codesign", ["-d", "-r-", path]) else { return nil }
        for line in out.split(separator: "\n") where line.hasPrefix("designated => ") {
            return String(line.dropFirst("designated => ".count))
        }
        return nil
    }

    /// requirement 문자열 → TCC `csreq` blob 의 hex.
    public static func csreqHex(for requirement: String) -> String? {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("csreq-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: tmp) }

        guard runTool("/usr/bin/csreq", ["-r", "-", "-b", tmp.path], stdin: requirement) != nil,
              let data = try? Data(contentsOf: tmp), !data.isEmpty else { return nil }
        return data.map { String(format: "%02X", $0) }.joined()
    }

    // MARK: - 내부

    /// SQL 문자열 리터럴로 안전하게 감싼다. bundleID 는 스캔된 임의 값이라 이스케이프가 필요하다.
    public static func sqlQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    private func runSqlite(db: String, sql: String, readOnly: Bool) -> String? {
        var args: [String] = []
        if readOnly { args.append("-readonly") }
        args += [db, sql]
        return Self.runTool("/usr/bin/sqlite3", args)
    }

    /// 표준출력을 돌려준다. 0 이 아니면 nil.
    static func runTool(_ bin: String, _ args: [String], stdin: String? = nil) -> String? {
        guard FileManager.default.isExecutableFile(atPath: bin) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = args

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice
        if let stdin {
            let inPipe = Pipe()
            process.standardInput = inPipe
            guard (try? process.run()) != nil else { return nil }
            inPipe.fileHandleForWriting.write(Data(stdin.utf8))
            try? inPipe.fileHandleForWriting.close()
        } else {
            guard (try? process.run()) != nil else { return nil }
        }

        // 파이프 버퍼가 차면 교착한다. 이전 구현은 동기 drain 뒤에 watchdog을
        // 등록해서, sqlite가 멈춘 경우 watchdog까지 절대 도달하지 못했다.
        final class OutputBox: @unchecked Sendable {
            private let lock = NSLock()
            private var value = Data()
            func set(_ data: Data) { lock.lock(); value = data; lock.unlock() }
            func get() -> Data { lock.lock(); defer { lock.unlock() }; return value }
        }
        let output = OutputBox()
        let outputRead = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            output.set(outPipe.fileHandleForReading.readDataToEndOfFile())
            outputRead.signal()
        }
        let watchdog = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: watchdog)
        process.waitUntilExit()
        watchdog.cancel()
        _ = outputRead.wait(timeout: .now() + 1)

        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: output.get(), as: UTF8.self)
    }
}

// MARK: - 하위 호환

public extension TCCGranter {
    /// 예전 시그니처 — 경로를 찾고 **선언 기반**으로 부여한다(전 서비스 폴백 없음).
    func grantAll(bundleID: String) -> GrantResult {
        grantAll(
            bundleID: bundleID,
            appPath: Self.bundlePath(forBundleID: bundleID),
            scope: .user,
            serviceSelection: .declared)
    }

    /// 예전 시그니처 — 선언 기반 일괄.
    func grantAllForApps(bundleIDs: [String]) -> [String: GrantResult] {
        grantAllForApps(
            bundleIDs.map { ($0, Self.bundlePath(forBundleID: $0)) },
            scope: .user,
            serviceSelection: .declared)
    }

    /// bundleID 로 설치 경로를 찾는다(LaunchServices 등록 기준).
    static func bundlePath(forBundleID bundleID: String) -> String? {
        guard let url = NSWorkspace_urlForApplication(bundleID) else { return nil }
        return url.path
    }
}

/// AppKit 없이 bundleID → 경로. PermissionKit 은 CLI 타깃에서도 쓰이므로 AppKit 을 끌어오지 않는다.
private func NSWorkspace_urlForApplication(_ bundleID: String) -> URL? {
    guard let ids = LSCopyApplicationURLsForBundleIdentifier(bundleID as CFString, nil)?
        .takeRetainedValue() as? [URL] else { return nil }
    return ids.first
}
