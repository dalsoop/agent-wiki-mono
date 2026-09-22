import Foundation
import StateRootKit
import FastDiskIOKit

/// 1. 최상위 테넌트 컨텍스트 (L3 Tenant Root)
/// 모든 데이터, DB, 워크트리, 런타임 세션의 물리적 최상위 경계
public struct TenantContext: Sendable, Equatable, Codable {
    public let tenantID: String                // 예: "tenant:company"
    public let tenantSlug: String              // 예: "company"
    public let rootURL: URL                    // ~/.tenants/company/
    public let documentsURL: URL               // ~/.tenants/company/Documents/Gujo/

    public init(
        tenantID: String,
        tenantSlug: String,
        rootURL: URL,
        documentsURL: URL
    ) {
        self.tenantID = tenantID
        self.tenantSlug = tenantSlug
        self.rootURL = rootURL
        self.documentsURL = documentsURL
    }

    /// 표준 홈 경로로부터 테넌트 컨텍스트 조립
    public static func make(
        tenantID: String,
        homeURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> TenantContext {
        let slug = tenantID.hasPrefix("tenant:") ? String(tenantID.dropFirst(7)) : tenantID
        let cleanSlug = slug.isEmpty ? "personal" : slug
        let root = homeURL.appendingPathComponent(".tenants", isDirectory: true).appendingPathComponent(cleanSlug, isDirectory: true)
        let docs = root.appendingPathComponent("Documents", isDirectory: true).appendingPathComponent("Gujo", isDirectory: true)
        return TenantContext(
            tenantID: tenantID,
            tenantSlug: cleanSlug,
            rootURL: root,
            documentsURL: docs
        )
    }
}

/// 2. 룸 컨텍스트 (L2 Room Root) — 테넌트로부터 단방향 파생
/// Git Worktree 및 방 전용 작업공간
public struct RoomContext: Sendable, Equatable, Codable {
    public let tenant: TenantContext
    public let roomID: String                  // 예: "ROOM-001"
    public let roomSlug: String                // 예: "payment-refactor"
    public let roomURL: URL                    // ~/.tenants/company/rooms/ROOM-001/
    public let worktreeURL: URL                // ~/.tenants/company/rooms/ROOM-001/worktree/
    public let specURL: URL                    // ~/.tenants/company/rooms/ROOM-001/spec.json
    public let windowsURL: URL                 // ~/.tenants/company/rooms/ROOM-001/windows.json

    public init(
        tenant: TenantContext,
        roomID: String,
        roomSlug: String,
        roomURL: URL,
        worktreeURL: URL,
        specURL: URL,
        windowsURL: URL
    ) {
        self.tenant = tenant
        self.roomID = roomID
        self.roomSlug = roomSlug
        self.roomURL = roomURL
        self.worktreeURL = worktreeURL
        self.specURL = specURL
        self.windowsURL = windowsURL
    }

    /// 테넌트 컨텍스트로부터 룸 컨텍스트 파생
    public static func make(
        tenant: TenantContext,
        roomID: String,
        roomSlug: String? = nil
    ) -> RoomContext {
        let slug = roomSlug ?? roomID.lowercased()
        let roomDir = tenant.rootURL.appendingPathComponent("rooms", isDirectory: true).appendingPathComponent(roomID, isDirectory: true)
        let worktree = roomDir.appendingPathComponent("worktree", isDirectory: true)
        let spec = roomDir.appendingPathComponent("spec.json", isDirectory: false)
        let windows = roomDir.appendingPathComponent("windows.json", isDirectory: false)
        return RoomContext(
            tenant: tenant,
            roomID: roomID,
            roomSlug: slug,
            roomURL: roomDir,
            worktreeURL: worktree,
            specURL: spec,
            windowsURL: windows
        )
    }

    /// 임의의 파일 또는 디렉터리 경로로부터 소속 RoomContext 역산
    public static func resolve(fromPath path: String) -> RoomContext? {
        let url = URL(fileURLWithPath: path).standardized
        let comps = url.pathComponents

        // 1. 고객용 표준 기기 로컬 Room 경로 (~/Library/Application Support/net.ranode.shared/rooms/<room_id>/)
        if let sharedIdx = comps.firstIndex(of: CustomerRoomLayout.sharedDomain),
           sharedIdx + 2 < comps.count,
           comps[sharedIdx + 1] == "rooms" {
            let rawRoomID = comps[sharedIdx + 2]
            let roomID = (rawRoomID == "room-default" || rawRoomID == "room:default")
                ? CustomerRoomLayout.defaultRoomID
                : rawRoomID
            return CustomerRoomLayout.makeCustomerRoomContext(roomID: roomID)
        }

        // 2. 개발자/테넌트 멀티룸 경로 (~/.tenants/<slug>/rooms/<room_id>/)
        guard let tenantsIdx = comps.firstIndex(of: ".tenants"),
              tenantsIdx + 3 < comps.count,
              comps[tenantsIdx + 2] == "rooms" else {
            return nil
        }
        let tenantSlug = comps[tenantsIdx + 1]
        let roomID = comps[tenantsIdx + 3]
        let homeComps = comps[0..<tenantsIdx]
        let homePath = homeComps.joined(separator: "/").replacingOccurrences(of: "//", with: "/")
        let homeURL = URL(fileURLWithPath: homePath.isEmpty ? NSHomeDirectory() : homePath, isDirectory: true)
        let tenant = TenantContext.make(tenantID: tenantSlug, homeURL: homeURL)
        return RoomContext.make(tenant: tenant, roomID: roomID)
    }
}

/// 고객용 표준 단일 기기 로컬 Room 레이아웃 (Customer-Grade Single Room SSOT)
/// 경로: ~/Library/Application Support/net.ranode.shared/rooms/<room_id>/
public enum CustomerRoomLayout: Sendable {
    public static let defaultRoomID = "room:default"
    public static let defaultTenantID = "tenant:personal"
    public static let sharedDomain = "net.ranode.shared"

    /// ~/Library/Application Support/
    public static func applicationSupportURL(
        fileManager: FileManager = .default
    ) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    /// ~/Library/Application Support/net.ranode.shared/rooms/
    public static func roomsBaseURL(
        fileManager: FileManager = .default
    ) -> URL {
        applicationSupportURL(fileManager: fileManager)
            .appendingPathComponent(sharedDomain, isDirectory: true)
            .appendingPathComponent("rooms", isDirectory: true)
    }

    /// ~/Library/Application Support/net.ranode.shared/rooms/<room_id>/ (SSOT: StateRootKit.customerRoomRoot)
    public static func roomURL(
        roomID: String = defaultRoomID,
        fileManager: FileManager = .default
    ) -> URL {
        StateRootKit.customerRoomRoot(roomID: roomID)
    }

    /// 고객용 단일 정본 RoomContext 생성
    public static func makeCustomerRoomContext(
        roomID: String = defaultRoomID,
        tenantID: String = defaultTenantID,
        fileManager: FileManager = .default
    ) -> RoomContext {
        let rURL = roomURL(roomID: roomID, fileManager: fileManager)
        let roomsBase = rURL.deletingLastPathComponent()
        let tenantRoot = roomsBase.deletingLastPathComponent()
        let tenantDocs = tenantRoot.appendingPathComponent("Documents/Gujo", isDirectory: true)
        let tenant = TenantContext(
            tenantID: tenantID,
            tenantSlug: "personal",
            rootURL: tenantRoot,
            documentsURL: tenantDocs
        )
        let worktree = rURL.appendingPathComponent("worktree", isDirectory: true)
        let spec = rURL.appendingPathComponent("spec.json", isDirectory: false)
        let windows = rURL.appendingPathComponent("windows.json", isDirectory: false)
        return RoomContext(
            tenant: tenant,
            roomID: roomID,
            roomSlug: roomID.replacingOccurrences(of: "room:", with: ""),
            roomURL: rURL,
            worktreeURL: worktree,
            specURL: spec,
            windowsURL: windows
        )
    }

    /// 첫 기동 시 기본 Room(room:default) 디렉터리 및 spec.json/windows.json 자동 준비 (0-overhead idempotent)
    @discardableResult
    public static func ensureDefaultRoom(
        roomID: String = defaultRoomID,
        fileManager: FileManager = .default
    ) throws -> RoomContext {
        try ensureDefaultRoom(roomID: roomID, performGC: true, fileManager: fileManager)
    }

    /// 첫 기동 시 기본 Room 디렉터리 자동 준비 및 GC 수명주기 제어
    @discardableResult
    public static func ensureDefaultRoom(
        roomID: String = defaultRoomID,
        performGC: Bool,
        fileManager: FileManager = .default
    ) throws -> RoomContext {
        runStorageGCIfNeeded(roomID: roomID, performGC: performGC, fileManager: fileManager)
        let context = makeCustomerRoomContext(roomID: roomID, fileManager: fileManager)
        try createDirectoryIfNeeded(at: context.roomURL, fileManager: fileManager)
        try createDirectoryIfNeeded(at: context.roomURL.appendingPathComponent("apps", isDirectory: true), fileManager: fileManager)
        try createDirectoryIfNeeded(at: context.worktreeURL, fileManager: fileManager)

        let initialSpec = """
        {"roomID":"\(roomID)","task":"Default Customer Isolated Room","verdict":"ok"}
        """
        try createFileIfNeeded(at: context.specURL, content: initialSpec, fileManager: fileManager)

        let initialWindows = """
        {"roomID":"\(roomID)","windows":[]}
        """
        try createFileIfNeeded(at: context.windowsURL, content: initialWindows, fileManager: fileManager)

        return context
    }

    /// 고객 룸 작업공간 생성 및 샌드박스 프로비저닝 (GC 수명주기 명시 실행)
    @discardableResult
    public static func createCustomerWorkspace(
        roomID: String = defaultRoomID,
        options: FastStorageGCOptions = .default,
        fileManager: FileManager = .default
    ) throws -> (context: RoomContext, gcReport: RoomStorageGCReport) {
        let report = try RoomStorageGC.runCustomerRoomGC(roomID: roomID, options: options, fileManager: fileManager)
        let context = try ensureDefaultRoom(roomID: roomID, performGC: false, fileManager: fileManager)
        return (context, report)
    }

    private static func runStorageGCIfNeeded(roomID: String, performGC: Bool, fileManager: FileManager) {
        guard performGC else { return }
        do {
            _ = try RoomStorageGC.runCustomerRoomGC(roomID: roomID, fileManager: fileManager)
        } catch {
            fputs("CustomerRoomLayout: Storage GC warning in room \(roomID): \(error.localizedDescription)\n", stderr)
        }
    }

    private static func createDirectoryIfNeeded(at url: URL, fileManager: FileManager) throws {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private static func createFileIfNeeded(at url: URL, content: String, fileManager: FileManager) throws {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        try content.data(using: .utf8)?.write(to: url, options: .atomic)
    }
}

/// 3. 앱 런타임 컨텍스트 (L1 App / DB Layer) — 룸으로부터 단방향 파생
/// 물리적으로 완전히 독립된 DB 파일 및 전용 프로필 경로 주입
public struct AppRuntimeContext: Sendable, Equatable, Codable {
    public let room: RoomContext
    public let appSlug: String                 // 예: "agent-app-probe-doctor"
    public let appDirectoryURL: URL            // ~/.tenants/company/rooms/ROOM-001/apps/<appSlug>/
    
    /// 물리적으로 분리된 SQLite DB 파일 URL (Tier 1)
    public let databaseURL: URL                // .../apps/<appSlug>/app.sqlite
    
    /// 사용자 가시 Cloud SSOT 문서 디렉터리 (Tier 2)
    public let cloudDocumentsURL: URL          // ~/.tenants/company/Documents/Gujo/<roomSlug>/<appSlug>/
    
    /// 격리 프로필 디렉터리 (VS Code, Chromium 등 단일 PID 앱용)
    public let profileURL: URL                 // .../apps/<appSlug>/profile/
    
    /// StateMirror 관제 요약 캐시 URL
    public let stateMirrorURL: URL             // .../apps/<appSlug>/state.json

    public init(
        room: RoomContext,
        appSlug: String,
        appDirectoryURL: URL,
        databaseURL: URL,
        cloudDocumentsURL: URL,
        profileURL: URL,
        stateMirrorURL: URL
    ) {
        self.room = room
        self.appSlug = appSlug
        self.appDirectoryURL = appDirectoryURL
        self.databaseURL = databaseURL
        self.cloudDocumentsURL = cloudDocumentsURL
        self.profileURL = profileURL
        self.stateMirrorURL = stateMirrorURL
    }

    /// 룸 컨텍스트로부터 앱 런타임 컨텍스트 파생
    public static func make(
        room: RoomContext,
        appSlug: String
    ) -> AppRuntimeContext {
        let appDir = room.roomURL.appendingPathComponent("apps", isDirectory: true).appendingPathComponent(appSlug, isDirectory: true)
        let db = appDir.appendingPathComponent("app.sqlite", isDirectory: false)
        let docs = room.tenant.documentsURL
            .appendingPathComponent(room.roomSlug, isDirectory: true)
            .appendingPathComponent(appSlug, isDirectory: true)
        let profile = appDir.appendingPathComponent("profile", isDirectory: true)
        let state = appDir.appendingPathComponent("state.json", isDirectory: false)
        return AppRuntimeContext(
            room: room,
            appSlug: appSlug,
            appDirectoryURL: appDir,
            databaseURL: db,
            cloudDocumentsURL: docs,
            profileURL: profile,
            stateMirrorURL: state
        )
    }
}
