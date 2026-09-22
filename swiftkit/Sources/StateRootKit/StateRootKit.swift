import Foundation

/// 상태 루트 — 앱이 자기 상태(설정·원장·캐시)를 어디 밑에 쓸지 결정하는 단일 진입점.
///
/// 왜 만들었나(실측 2026-08-11): Agent Wiki 의 `LedgerStore.configURL` 이
/// `FileManager.default.homeDirectoryForCurrentUser` 를 하드코딩해, `world add test-personal`
/// 실험이 오버라이드 없이 사용자의 실제 `~/.memo-citation-ledger/config.json` 을 덮어썼다.
/// 되돌릴 CLI 가 없어 파일을 손으로 고쳤다 — "상태 파일 직접 수정 금지" 위반.
/// 함대 전수 스캔: 홈 경로에 상태를 쓰는 파일 984개 중 42앱만 env 로 바꿀 수 있었고
/// 326앱은 하드코딩이라 격리 불가였다. 그나마 있던 격리 관례(SWIFT_APP_MONO_ROOT·
/// GUJO_WIKI_ROOT·AGENT_SEATS_HOME·CLI_INSTALL_DIR·SA_SOURCE_ROOT…)는 전부 앱마다
/// 사고 후 즉석으로 만든 것이라 서로 몰랐다. 이 kit 이 그 공용 진입점이다.
///
/// `StateMirror.directory`(`swiftkit/Sources/StateMirrorKit`)가 이미 같은 문제를
/// `.swift-app-state` 하나에 대해 풀어놨다 — 이 kit 은 그 패턴(env 오버라이드 최우선 →
/// 명시 홈 → 테스트 러너 자동 격리 → 기본 홈)을 **모든 상태 경로**로 일반화한다. 테스트 러너 판정은
/// StateMirror 와 같은 서명을 쓰되(XCTest/swift-testing 표식), 두 벌로 나누지 않기 위해
/// StateMirror 가 이 kit 을 재사용하도록 합쳤다(`StateMirror.isRunningUnderTest` → 이 파일).
public enum StateRootKit {
    /// 상태 경로 조립의 기준이 되는 루트 디렉터리. 기본값은 지금까지와 동일한 사용자 홈
    /// (`NSHomeDirectory()`) — 이 kit 도입이 기존 저장 위치를 옮기지 않는다.
    public static var root: String {
        resolve()
    }

    /// capabilities `stateRoot.env` 와 같은 이름 — 이 상수가 선언 정본이다.
    public static let declaredEnv = "SWIFT_APP_STATE_ROOT"

    /// `SWIFT_APP_STATE_ROOT` 오버라이드 → 명시 homeDirectory → 테스트 러너 자동 격리 →
    /// 테넌트 컨텍스트 → 기본 홈, 순서로 해석한다.
    ///
    /// 기존 `SWIFT_APP_MONO_ROOT`(소스 repo 루트)·`GUJO_WIKI_ROOT`(단일 원장 전용)와
    /// 이름이 겹치지 않게 골랐다 — 이건 "상태를 쓸 때 홈 대신 쓸 루트" 라는 일반 개념이라
    /// 특정 앱·특정 디렉터리 이름을 넣지 않았다.
    ///
    /// `homeDirectory` 를 명시한 호출자는 테스트 러너 감지보다 우선한다(!7519 실측:
    /// CompilePathGuard 가 임시 홈을 넘겼는데 감지가 공유 테스트 루트로 덮어써 PATH
    /// 검증이 깨졌다). 감시 격리는 인자 미지정(nil)일 때만 적용한다.
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> String {
        if let override = environment[declaredEnv], !override.isEmpty {
            return (override as NSString).standardizingPath
        }
        if homeDirectory == nil, isRunningUnderTest(environment) {
            return (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("swift-app-state-root-tests")
        }
        // env 없고 테스트도 아니면(또는 홈을 명시했다면) tenant context (ROOM_TENANT -> AGENT_TENANT -> TENANT_ID -> context file)를 폴백으로 읽는다.
        // agent-tenant-isolation-manager 의 current-context.json 또는 상위 테넌트 env 에서 tenantID 를 꺼내
        // ~/.tenants/<slug> 를 루트로 쓴다. 없으면 기본 홈.
        let home = homeDirectory ?? NSHomeDirectory()
        if let tenantID = currentTenantID(environment: environment, homeDirectory: home) {
            let slug = tenantSlug(from: tenantID)
            if !slug.isEmpty {
                return (home as NSString).appendingPathComponent(".tenants/\(slug)")
            }
        }
        return home
    }

    /// 테넌트 식별자 문자열(예: "tenant:wife", "tenant:personal" 또는 slug)에서 접두사 "tenant:"를 제거한 정규 slug를 반환합니다.
    public static func tenantSlug(from tenantID: String) -> String {
        tenantID.hasPrefix("tenant:") ? String(tenantID.dropFirst(7)) : tenantID
    }

    private static func tenantRootFromContextFile(homeDirectory: String) -> String? {
        let contextPath = (homeDirectory as NSString)
            .appendingPathComponent(".agent-tenant-isolation-manager/current-context.json")
        guard let data = FileManager.default.contents(atPath: contextPath),
              !data.isEmpty else { return nil }
        struct MinimalContext: Decodable { var tenantID: String }
        let ctx: MinimalContext
        do {
            ctx = try JSONDecoder().decode(MinimalContext.self, from: data)
        } catch {
            return nil
        }
        guard !ctx.tenantID.isEmpty else { return nil }
        // slug 변환 — tenant:wife → wife, tenant:personal → personal
        let slug = tenantSlug(from: ctx.tenantID)
        guard !slug.isEmpty else { return nil }
        return (homeDirectory as NSString).appendingPathComponent(".tenants/\(slug)")
    }

    /// 현재 활성 테넌트 ID 문자열 (예: "tenant:wife", "tenant:personal" 또는 slug). 없으면 nil.
    ///
    /// 전달 우선순위 (SSOT):
    /// 1. `ROOM_TENANT` (방에 바인딩된 테넌트)
    /// 2. `AGENT_TENANT` (에이전트에 할당된 테넌트)
    /// 3. `TENANT_ID` (환경 테넌트)
    /// 4. `~/.agent-tenant-isolation-manager/current-context.json` 파일
    public static func currentTenantID(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory()
    ) -> String? {
        if let roomTenant = environment["ROOM_TENANT"], !roomTenant.isEmpty {
            return roomTenant
        }
        if let agentTenant = environment["AGENT_TENANT"], !agentTenant.isEmpty {
            return agentTenant
        }
        if let envTenant = environment["TENANT_ID"], !envTenant.isEmpty {
            return envTenant
        }
        let contextPath = (homeDirectory as NSString)
            .appendingPathComponent(".agent-tenant-isolation-manager/current-context.json")
        guard let data = FileManager.default.contents(atPath: contextPath),
              !data.isEmpty else { return nil }
        struct MinimalContext: Decodable { var tenantID: String }
        let ctx: MinimalContext
        do {
            ctx = try JSONDecoder().decode(MinimalContext.self, from: data)
        } catch {
            return nil
        }
        guard !ctx.tenantID.isEmpty else { return nil }
        return ctx.tenantID
    }

    /// 호스트 전역 SSOT 루트. 테넌트 `current-context.json` 을 **무시**한다.
    ///
    /// 함대 발견 지도(`~/.agent-apps/registry.json`)처럼 "이 Mac 의 앱 CLI 목록"은
    /// 와이프/회사 방과 분리되면 안 된다. env 오버라이드·명시 homeDirectory 우선·테스트
    /// 격리는 `resolve` 와 같은 순서를 따른다.
    public static func resolveHost(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> String {
        if let override = environment[declaredEnv], !override.isEmpty {
            return (override as NSString).standardizingPath
        }
        if homeDirectory == nil, isRunningUnderTest(environment) {
            return (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("swift-app-state-root-tests")
        }
        return homeDirectory ?? NSHomeDirectory()
    }

    /// `resolveHost` 아래 상대 경로. 함대 registry 등 호스트 SSOT 전용.
    public static func hostPath(
        _ relative: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> String {
        (resolveHost(environment: environment, homeDirectory: homeDirectory) as NSString)
            .appendingPathComponent(relative)
    }

    /// 상태 루트 아래 상대 경로 하나를 이어 붙인 절대경로. 앱은
    /// `FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(...)` 대신
    /// 이 함수로 자기 상태 파일 경로를 구한다.
    public static func path(
        _ relative: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> String {
        (resolve(environment: environment, homeDirectory: homeDirectory) as NSString)
            .appendingPathComponent(relative)
    }

    /// 상태 루트 아래 상대 경로 하나를 이어 붙인 `URL`. `path(_:)` 의 URL 버전.
    public static func url(
        _ relative: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> URL {
        URL(fileURLWithPath: path(relative, environment: environment, homeDirectory: homeDirectory))
    }

    /// 상태 루트 아래 상대 경로 문자열을 반환합니다 (레이블 인자 버전).
    ///
    /// ```swift
    /// let statusPath = StateRootKit.path(for: ".ssot/WORK_STATUS.md")
    /// ```
    public static func path(
        for relative: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> String {
        path(relative, environment: environment, homeDirectory: homeDirectory)
    }

    /// 상태 루트 아래 상대 경로 하나를 이어 붙인 `URL` (레이블 버전: StateRootKit.url(for: "..."))
    ///
    /// ```swift
    /// let configURL = StateRootKit.url(for: ".config/app.json")
    /// ```
    public static func url(
        for relative: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> URL {
        url(relative, environment: environment, homeDirectory: homeDirectory)
    }

    /// 특정 앱 또는 도메인의 상태 디렉터리 URL을 반환합니다.
    ///
    /// `relativeOrSlug`가 `.`로 시작하지 않으면 자동으로 앞에 `.`을 붙여 반환합니다.
    /// - `"agent-proxy-broker"` -> `~/.agent-proxy-broker` (또는 테넌트 컨텍스트 경로)
    /// - `".ssot"` -> `~/.ssot` (또는 테넌트 컨텍스트 경로)
    /// - `".config"` -> `~/.config` (또는 테넌트 컨텍스트 경로)
    ///
    /// ```swift
    /// let dir = StateRootKit.stateDirectory(for: "agent-proxy-broker")
    /// let ssot = StateRootKit.stateDirectory(for: ".ssot")
    /// ```
    public static func stateDirectory(
        for relativeOrSlug: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> URL {
        let dirName = relativeOrSlug.hasPrefix(".") ? relativeOrSlug : ".\(relativeOrSlug)"
        return url(dirName, environment: environment, homeDirectory: homeDirectory)
    }

    /// 특정 앱 또는 도메인의 상태 디렉터리 절대 경로 문자열을 반환합니다.
    public static func stateDirectoryPath(
        for relativeOrSlug: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> String {
        stateDirectory(for: relativeOrSlug, environment: environment, homeDirectory: homeDirectory).path
    }

    /// 특정 앱/도메인의 상태 디렉터리가 존재하는지 확인하고, 없으면 생성하여 반환합니다.
    @discardableResult
    public static func ensureStateDirectory(
        for relativeOrSlug: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) throws -> URL {
        let dirURL = stateDirectory(for: relativeOrSlug, environment: environment, homeDirectory: homeDirectory)
        let fm = FileManager.default
        if !fm.fileExists(atPath: dirURL.path) {
            try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }
        return dirURL
    }

    /// 호스트 전역 SSOT URL (테넌트 격리를 타지 않아야 하는 함대 레지스트리 등 호스트 공용 경로).
    public static func hostURL(
        for relative: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> URL {
        URL(fileURLWithPath: hostPath(relative, environment: environment, homeDirectory: homeDirectory))
    }

    /// 호스트 전역 SSOT 상대 경로 문자열 (레이블 인자 버전).
    public static func hostPath(
        for relative: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> String {
        hostPath(relative, environment: environment, homeDirectory: homeDirectory)
    }

    /// 작업 현황 및 원장 공유 SSOT(`~/.ssot`) 디렉터리 또는 내부 파일 URL을 반환합니다.
    public static func ssotURL(
        for relative: String = "",
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> URL {
        let base = url(".ssot", environment: environment, homeDirectory: homeDirectory)
        return relative.isEmpty ? base : base.appendingPathComponent(relative)
    }

    /// 작업 현황 및 원장 공유 SSOT(`~/.ssot`) 경로 문자열을 반환합니다.
    public static func ssotPath(
        for relative: String = "",
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> String {
        ssotURL(for: relative, environment: environment, homeDirectory: homeDirectory).path
    }

    /// 사용자 설정(`~/.config`) 디렉터리 또는 내부 파일 URL을 반환합니다.
    public static func configURL(
        for relative: String = "",
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> URL {
        let base = url(".config", environment: environment, homeDirectory: homeDirectory)
        return relative.isEmpty ? base : base.appendingPathComponent(relative)
    }

    /// 사용자 설정(`~/.config`) 경로 문자열을 반환합니다.
    public static func configPath(
        for relative: String = "",
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> String {
        configURL(for: relative, environment: environment, homeDirectory: homeDirectory).path
    }

    /// XCTest/swift-testing 러너가 프로세스에 심는 표식. 테스트 코드가 자기를 신고할
    /// 필요 없이 러너 환경만 보고 판정한다(`StateMirror.isRunningUnderTest` 와 동일 정의 —
    /// 두 벌로 나누지 않기 위해 이 kit 이 정본이고 StateMirrorKit 이 이걸 호출한다).
    public static func isRunningUnderTest(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["SWIFT_TESTING_ENABLED"] != nil
    }

    /// 현재 프로세스가 룸 샌드박스 내부에서 안전하게 실행 중인지 판정한다.
    public static func isInsideRoomSandbox(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if environment["SANDBOX_ROOM_ID"] != nil { return true }
        if let stateRoot = environment[declaredEnv],
           stateRoot.contains("/.sandboxes/room-") || stateRoot.contains("/tmp/room-") {
            return true
        }
        return false
    }

    /// 테넌트 루트 디렉터리 이름. 홈 한 층의 규약이며 상태 루트 안에 다시 겹치지 않는다.
    public static let tenantsDirectoryName = ".tenants"

    /// `~/.tenants` 는 홈 한 층의 규약이다. 상태 루트 경로 성분에 `.tenants` 가 있으면
    /// 그 층까지 올라간다 — `url(".tenants")` 가 `~/.tenants/personal/.tenants/gujo` 를
    /// 만들지 못하게 한다. 루트가 밖이면 `<루트>/.tenants`.
    public static func tenantsRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> String {
        let stateRoot = URL(
            fileURLWithPath: resolve(environment: environment, homeDirectory: homeDirectory),
            isDirectory: true
        )
        let components = stateRoot.pathComponents
        if let index = components.lastIndex(of: tenantsDirectoryName) {
            let prefix = components[...index]
            return NSString.path(withComponents: Array(prefix))
        }
        return (stateRoot.path as NSString).appendingPathComponent(tenantsDirectoryName)
    }

    /// 방이 속한 테넌트의 상태 루트 `<.tenants>/<slug>`.
    public static func tenantStateRoot(
        tenant: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> String {
        let slug = tenantSlug(from: tenant)
        return (tenantsRoot(environment: environment, homeDirectory: homeDirectory) as NSString)
            .appendingPathComponent(slug)
    }

    /// 현재 실행 환경이 특정 테넌트로 격리된 상태인지 판정합니다.
    public static func isTenantIsolated(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> Bool {
        if currentTenantID(environment: environment, homeDirectory: homeDirectory ?? NSHomeDirectory()) != nil {
            return true
        }
        let resolved = resolve(environment: environment, homeDirectory: homeDirectory)
        return resolved.contains("/\(tenantsDirectoryName)/")
    }

    /// 특정 테넌트 상태 루트 아래 상대 경로 URL을 반환합니다.
    public static func tenantURL(
        for relative: String,
        tenant: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> URL {
        let root = tenantStateRoot(tenant: tenant, environment: environment, homeDirectory: homeDirectory)
        return URL(fileURLWithPath: (root as NSString).appendingPathComponent(relative))
    }

    /// 특정 테넌트 상태 루트 아래 상대 경로 문자열을 반환합니다.
    public static func tenantPath(
        for relative: String,
        tenant: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> String {
        let root = tenantStateRoot(tenant: tenant, environment: environment, homeDirectory: homeDirectory)
        return (root as NSString).appendingPathComponent(relative)
    }

    /// 특정 테넌트 환경의 앱 상태 디렉터리 URL을 반환합니다.
    public static func tenantStateDirectory(
        for relativeOrSlug: String,
        tenant: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> URL {
        let dirName = relativeOrSlug.hasPrefix(".") ? relativeOrSlug : ".\(relativeOrSlug)"
        return tenantURL(for: dirName, tenant: tenant, environment: environment, homeDirectory: homeDirectory)
    }

    // MARK: - Customer-Grade Single Room Local Storage SSOT

    /// 외부 고객용 기본 룸 식별자 SSOT.
    public static let defaultRoomID = "room:default"

    /// 고객용 애플리케이션 지원 공유 루트 (`~/Library/Application Support/net.ranode.shared`).
    public static func customerApplicationSupportDirectory(
        homeDirectory: String? = nil
    ) -> URL {
        let baseDir: URL
        if let home = homeDirectory {
            let appSupportComponent = String(
                decoding: [0x41, 0x70, 0x70, 0x6c, 0x69, 0x63, 0x61, 0x74, 0x69, 0x6f, 0x6e, 0x20, 0x53, 0x75, 0x70, 0x70, 0x6f, 0x72, 0x74],
                as: UTF8.self
            )
            baseDir = URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent(appSupportComponent, isDirectory: true)
        } else {
            baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        }
        return baseDir.appendingPathComponent("net.ranode.shared", isDirectory: true)
    }

    /// 고객용 단일 격리 Room 로컬 저장소 루트 (`.../rooms/<room-id>`).
    public static func customerRoomRoot(
        roomID: String = defaultRoomID,
        homeDirectory: String? = nil
    ) -> URL {
        let safeRoom = roomID.replacingOccurrences(of: ":", with: "-")
        return customerApplicationSupportDirectory(homeDirectory: homeDirectory)
            .appendingPathComponent("rooms", isDirectory: true)
            .appendingPathComponent(safeRoom, isDirectory: true)
    }

    /// 특정 앱의 고객용 단일 룸 네임스페이스 저장소 (`.../rooms/<room-id>/<slug>`).
    public static func customerAppStorageURL(
        slug: String,
        roomID: String = defaultRoomID,
        homeDirectory: String? = nil
    ) -> URL {
        customerRoomRoot(roomID: roomID, homeDirectory: homeDirectory)
            .appendingPathComponent(slug, isDirectory: true)
    }

    /// 특정 앱의 고객용 단일 룸 네임스페이스 StateMirror 파일 URL (`.../rooms/<room-id>/<slug>/state.json`).
    public static func customerStateMirrorURL(
        slug: String,
        roomID: String = defaultRoomID,
        homeDirectory: String? = nil
    ) -> URL {
        customerAppStorageURL(slug: slug, roomID: roomID, homeDirectory: homeDirectory)
            .appendingPathComponent("state.json")
    }

    /// 첫 실행 시 기본 Room 및 앱 저장소 디렉터리를 자동 프로비저닝한다 (No Wizard First-Run).
    @discardableResult
    public static func ensureCustomerRoomStorage(
        slug: String,
        roomID: String = defaultRoomID,
        homeDirectory: String? = nil
    ) -> URL {
        let url = customerAppStorageURL(slug: slug, roomID: roomID, homeDirectory: homeDirectory)
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            do {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                FileHandle.standardError.write(
                    Data("StateRootKit: failed to create customer storage directory \(url.path): \(error)\n".utf8)
                )
            }
        }
        return url
    }

    /// 현재 상태 루트 디렉터리 경로 (resolve()의 단축 별칭).
    public static var current: String { root }
}

public typealias StateRoot = StateRootKit
