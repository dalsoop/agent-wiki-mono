import Foundation
import StateRootKit

public enum RoomPaths {
    public static let tenantsDirectoryName = ".tenants"
    public static let roomsDirectoryName = "rooms"
    public static let baseBinName = "_base-bin"
    public static let specFileName = "spec.json"
    public static let legacyRoomJSONName = "ROOM.json"

    public static func cleanTenantSlug(_ tenant: String) -> String {
        var cleaned = tenant.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("tenant:") {
            cleaned = String(cleaned.dropFirst("tenant:".count))
        }
        if cleaned.hasPrefix("@") {
            cleaned = String(cleaned.dropFirst())
        }
        return cleaned.precomposedStringWithCanonicalMapping
    }

    /// 방이 속한 테넌트의 상태 루트 `<.tenants>/<slug>` — 방 env 의 `SWIFT_APP_STATE_ROOT` 값.
    public static func tenantStateRoot(
        tenant: String,
        environment: [String: String] = [:],
        homeDirectory: String = NSHomeDirectory()
    ) -> URL {
        URL(
            fileURLWithPath: StateRootKit.tenantStateRoot(
                tenant: cleanTenantSlug(tenant),
                environment: environment,
                homeDirectory: homeDirectory
            ),
            isDirectory: true
        )
    }

    /// `~/.tenants` 는 홈 한 층의 규약이다. 계산은 `StateRootKit.tenantsRoot` 가 정본이다.
    public static func tenantsRoot(
        environment: [String: String] = [:],
        homeDirectory: String = NSHomeDirectory()
    ) -> URL {
        URL(
            fileURLWithPath: StateRootKit.tenantsRoot(
                environment: environment,
                homeDirectory: homeDirectory
            ),
            isDirectory: true
        )
    }

    public static func baseBin(
        environment: [String: String] = [:],
        homeDirectory: String = NSHomeDirectory()
    ) -> URL {
        tenantsRoot(environment: environment, homeDirectory: homeDirectory)
            .appendingPathComponent(baseBinName, isDirectory: true)
    }

    /// 정본 방 폴더: `~/.tenants/<cleanTenant>/rooms/<roomID>`
    public static func roomDirectory(
        tenant: String,
        roomID: String,
        environment: [String: String] = [:],
        homeDirectory: String = NSHomeDirectory()
    ) -> URL {
        let cleanTenant = cleanTenantSlug(tenant)
        let normRoomID = roomID.precomposedStringWithCanonicalMapping
        return tenantsRoot(environment: environment, homeDirectory: homeDirectory)
            .appendingPathComponent(cleanTenant, isDirectory: true)
            .appendingPathComponent(roomsDirectoryName, isDirectory: true)
            .appendingPathComponent(normRoomID, isDirectory: true)
    }

    /// 정본 스펙 파일: `~/.tenants/<cleanTenant>/rooms/<roomID>/spec.json`
    public static func specURL(
        tenant: String,
        roomID: String,
        environment: [String: String] = [:],
        homeDirectory: String = NSHomeDirectory()
    ) -> URL {
        roomDirectory(tenant: tenant, roomID: roomID, environment: environment, homeDirectory: homeDirectory)
            .appendingPathComponent(specFileName, isDirectory: false)
    }

    /// 정본 윈도우 스냅샷 파일: `windows.json`
    public static func windowsURL(
        roomID: String,
        tenant: String? = nil,
        environment: [String: String] = [:],
        homeDirectory: String = NSHomeDirectory()
    ) -> URL {
        if let dir = findRoomDirectory(roomID: roomID, tenant: tenant, environment: environment, homeDirectory: homeDirectory) {
            return dir.appendingPathComponent("windows.json", isDirectory: false)
        }
        let t = tenant ?? "default"
        return roomDirectory(tenant: t, roomID: roomID, environment: environment, homeDirectory: homeDirectory)
            .appendingPathComponent("windows.json", isDirectory: false)
    }

    /// 방 폴더 탐색 (정본 rooms/<roomID> 우선, 없으면 레거시 2-depth rooms/*/<slug> 탐색)
    public static func findRoomDirectory(
        roomID: String,
        tenant: String? = nil,
        environment: [String: String] = [:],
        homeDirectory: String = NSHomeDirectory()
    ) -> URL? {
        let normRoomID = roomID.precomposedStringWithCanonicalMapping
        let root = tenantsRoot(environment: environment, homeDirectory: homeDirectory)
        if let tenant, !tenant.isEmpty {
            return findInTenant(cleanTenantSlug(tenant), roomID: normRoomID, root: root)
        }
        for tenantDir in directories(in: root) where tenantDir.lastPathComponent.precomposedStringWithCanonicalMapping != baseBinName {
            if let found = findInTenant(tenantDir.lastPathComponent, roomID: normRoomID, root: root) {
                return found
            }
        }
        return nil
    }

    private static func findInTenant(_ tenant: String, roomID: String, root: URL) -> URL? {
        let normTenant = cleanTenantSlug(tenant)
        let normRoomID = roomID.precomposedStringWithCanonicalMapping
        let roomsDir = root
            .appendingPathComponent(normTenant, isDirectory: true)
            .appendingPathComponent(roomsDirectoryName, isDirectory: true)
        if let canonical = existingDirectory(roomsDir.appendingPathComponent(normRoomID, isDirectory: true)) {
            return canonical
        }
        let directMatches = directories(in: roomsDir).first {
            $0.lastPathComponent.precomposedStringWithCanonicalMapping == normRoomID
        }
        guard directMatches == nil else { return directMatches }
        let wanted = normRoomID.lowercased()
        return directories(in: roomsDir).compactMap { findInSubdir($0, wanted: wanted, normRoomID: normRoomID) }.first
    }

    private static func findInSubdir(_ subdir: URL, wanted: String, normRoomID: String) -> URL? {
        if let candidate = existingDirectory(subdir.appendingPathComponent(normRoomID, isDirectory: true)) {
            return candidate
        }
        return directories(in: subdir).first { child in
            let pathMatch = child.lastPathComponent.precomposedStringWithCanonicalMapping.lowercased() == wanted
            let declaredMatch = declaredRoomID(in: child)?.precomposedStringWithCanonicalMapping.lowercased() == wanted
            return pathMatch || declaredMatch
        }
    }

    private static func existingDirectory(_ url: URL) -> URL? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return url
    }

    private static func directories(in url: URL) -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }
    }

    /// 레거시 폴더(`rooms/<layout>/<slug>`)가 스스로 선언한 roomID — `spec.json` 이 우선, 없으면 `ROOM.json`.
    private static func declaredRoomID(in child: URL) -> String? {
        for fileName in [specFileName, legacyRoomJSONName] {
            let file = child.appendingPathComponent(fileName, isDirectory: false)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            do {
                let data = try Data(contentsOf: file)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let id = (json?["roomID"] as? String) ?? (json?["id"] as? String) {
                    return id.precomposedStringWithCanonicalMapping
                }
            } catch {
                continue
            }
        }
        return nil
    }
}
