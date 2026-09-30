import Foundation
import StateRootKit

public enum RoomPaths {
    public static let tenantsDirectoryName = ".tenants"
    public static let roomsDirectoryName = "rooms"
    public static let baseBinName = "_base-bin"
    public static let specFileName = "spec.json"
    public static let legacyRoomJSONName = "ROOM.json"
    public static let roomsRootEnvironmentKey = "SWIFT_APP_ROOMS_ROOT"
    public static let roomsRootDirectoryName = ".rooms"

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

    /// 단일 방 루트: `SWIFT_APP_ROOMS_ROOT`(인자 env, 없으면 프로세스 env), 없으면 `<home>/.rooms`.
    public static func roomsRoot(
        environment: [String: String] = [:],
        homeDirectory: String = NSHomeDirectory()
    ) -> URL {
        if let explicit = explicitRoomsRoot(environment: environment) {
            return URL(fileURLWithPath: explicit, isDirectory: true)
        }
        return URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent(roomsRootDirectoryName, isDirectory: true)
    }

    /// 단일 루트가 켜졌는가 — `SWIFT_APP_ROOMS_ROOT` 를 줬거나 `roomsRoot` 폴더가 실제로 있을 때.
    ///
    /// `roomsRoot` 는 `room migrate-to-single-root --apply` 만 만든다. 이전 전에는 방을 예전
    /// 테넌트 경로에 계속 만든다. 이 킷으로 새로 빌드한 앱과 아직 옛 경로를 직접 조립하는
    /// 코드가 서로 다른 곳에 방을 만들지 않게 하려는 것이다.
    public static func isSingleRootActive(
        environment: [String: String] = [:],
        homeDirectory: String = NSHomeDirectory()
    ) -> Bool {
        if explicitRoomsRoot(environment: environment) != nil { return true }
        return existingDirectory(roomsRoot(environment: environment, homeDirectory: homeDirectory)) != nil
    }

    /// 방 폴더: `roomsRoot/<roomID>`. 테넌트가 없는 새 API 라 이전 뒤에만 쓴다.
    public static func roomDirectory(
        roomID: String,
        environment: [String: String] = [:],
        homeDirectory: String = NSHomeDirectory()
    ) -> URL {
        roomsRoot(environment: environment, homeDirectory: homeDirectory)
            .appendingPathComponent(roomID.precomposedStringWithCanonicalMapping, isDirectory: true)
    }

    /// 방 폴더. 단일 루트가 켜졌으면 `roomsRoot/<roomID>` 이고 `tenant` 는 무시한다(deprecated).
    /// 켜지기 전(이전 전)에는 예전 경로 `~/.tenants/<cleanTenant>/rooms/<roomID>` 다.
    public static func roomDirectory(
        tenant: String,
        roomID: String,
        environment: [String: String] = [:],
        homeDirectory: String = NSHomeDirectory()
    ) -> URL {
        if isSingleRootActive(environment: environment, homeDirectory: homeDirectory) {
            return roomDirectory(roomID: roomID, environment: environment, homeDirectory: homeDirectory)
        }
        return legacyTenantRoomDirectory(
            tenant: tenant, roomID: roomID, environment: environment, homeDirectory: homeDirectory)
    }

    /// 스펙 파일: `roomsRoot/<roomID>/spec.json`
    public static func specURL(
        roomID: String,
        environment: [String: String] = [:],
        homeDirectory: String = NSHomeDirectory()
    ) -> URL {
        roomDirectory(roomID: roomID, environment: environment, homeDirectory: homeDirectory)
            .appendingPathComponent(specFileName, isDirectory: false)
    }

    /// 스펙 파일. 경로 규칙은 `roomDirectory(tenant:roomID:)` 와 같다.
    public static func specURL(
        tenant: String,
        roomID: String,
        environment: [String: String] = [:],
        homeDirectory: String = NSHomeDirectory()
    ) -> URL {
        roomDirectory(tenant: tenant, roomID: roomID, environment: environment, homeDirectory: homeDirectory)
            .appendingPathComponent(specFileName, isDirectory: false)
    }

    /// 정본 윈도우 스냅샷 파일: `windows.json`.
    /// 방 폴더가 없고 테넌트도 없으면 단일 루트 `roomsRoot/<roomID>/windows.json` 이다.
    /// 없는 테넌트를 `"default"` 로 만들지 않는다. 테넌트를 넘긴 호출은 그 테넌트 경로를 유지한다.
    public static func windowsURL(
        roomID: String,
        tenant: String? = nil,
        environment: [String: String] = [:],
        homeDirectory: String = NSHomeDirectory()
    ) -> URL {
        if let dir = findRoomDirectory(roomID: roomID, tenant: tenant, environment: environment, homeDirectory: homeDirectory) {
            return dir.appendingPathComponent("windows.json", isDirectory: false)
        }
        let directory: URL
        if let tenant {
            directory = roomDirectory(
                tenant: tenant, roomID: roomID, environment: environment, homeDirectory: homeDirectory)
        } else {
            directory = roomDirectory(roomID: roomID, environment: environment, homeDirectory: homeDirectory)
        }
        return directory.appendingPathComponent("windows.json", isDirectory: false)
    }

    /// 방 폴더 찾기 — `roomsRoot/<roomID>` 를 먼저 본다. 없으면 과도기 대체 경로로 테넌트별
    /// `rooms/<roomID>` 를 stat 만 한다. 방 폴더 목록을 읽거나 spec 파일을 열지 않는다.
    public static func findRoomDirectory(
        roomID: String,
        tenant: String? = nil,
        environment: [String: String] = [:],
        homeDirectory: String = NSHomeDirectory()
    ) -> URL? {
        let normRoomID = roomID.precomposedStringWithCanonicalMapping
        if let canonical = existingDirectory(
            roomDirectory(roomID: normRoomID, environment: environment, homeDirectory: homeDirectory)) {
            return canonical
        }
        let root = tenantsRoot(environment: environment, homeDirectory: homeDirectory)
        if let tenant = tenant?.trimmingCharacters(in: .whitespacesAndNewlines), !tenant.isEmpty {
            return existingDirectory(tenantRoomsDirectory(root: root, tenant: tenant)
                .appendingPathComponent(normRoomID, isDirectory: true))
        }
        for tenantDir in directories(in: root) where !tenantDir.lastPathComponent.hasPrefix("_") {
            let candidate = tenantDir
                .appendingPathComponent(roomsDirectoryName, isDirectory: true)
                .appendingPathComponent(normRoomID, isDirectory: true)
            if let found = existingDirectory(candidate) {
                return found
            }
        }
        return nil
    }

    /// 이전 전용 — 테넌트 `rooms` 폴더의 UUID 가 아닌 항목(예전 `rooms/<layout>/<slug>` 배치)에서
    /// 방 폴더와 그 방이 스스로 선언한 roomID 를 모은다. 선언이 없으면 폴더 이름을 쓴다.
    /// 평소 조회 경로에서는 부르지 않는다.
    public static func legacyRoomFolders(
        inTenantRoomsDirectory roomsDir: URL
    ) -> [(roomID: String, url: URL)] {
        var results: [(roomID: String, url: URL)] = []
        for entry in directories(in: roomsDir) {
            let name = entry.lastPathComponent.precomposedStringWithCanonicalMapping
            guard !name.hasPrefix("_"), UUID(uuidString: name) == nil else { continue }
            if let declared = declaredRoomID(in: entry) {
                results.append((roomID: declared, url: entry))
                continue
            }
            for child in directories(in: entry) where !child.lastPathComponent.hasPrefix("_") {
                let childName = child.lastPathComponent.precomposedStringWithCanonicalMapping
                results.append((roomID: declaredRoomID(in: child) ?? childName, url: child))
            }
        }
        return results
    }

    /// 레거시 폴더가 스스로 선언한 roomID — `spec.json` 이 우선, 없으면 `ROOM.json`.
    public static func declaredRoomID(in child: URL) -> String? {
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

    private static func explicitRoomsRoot(environment: [String: String]) -> String? {
        let value = environment[roomsRootEnvironmentKey]
            ?? ProcessInfo.processInfo.environment[roomsRootEnvironmentKey]
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    /// 테넌트의 방 폴더 `<root>/<tenant>/rooms`. **이전 과도기 전용** — 아직 단일 루트로 옮기지
    /// 않은 테넌트의 방을 찾거나 옮길 때만 쓴다. 새 방은 `roomDirectory(roomID:)` 다.
    public static func tenantRoomsDirectory(root: URL, tenant: String) -> URL {
        root.appendingPathComponent(cleanTenantSlug(tenant), isDirectory: true)
            .appendingPathComponent(roomsDirectoryName, isDirectory: true)
    }

    private static func legacyTenantRoomDirectory(
        tenant: String,
        roomID: String,
        environment: [String: String],
        homeDirectory: String
    ) -> URL {
        tenantRoomsDirectory(root: tenantsRoot(environment: environment, homeDirectory: homeDirectory), tenant: tenant)
            .appendingPathComponent(roomID.precomposedStringWithCanonicalMapping, isDirectory: true)
    }

    private static func existingDirectory(_ url: URL) -> URL? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return url
    }

    /// 숨김을 뺀 하위 폴더. 읽을 수 없으면 빈 배열.
    private static func directories(in url: URL) -> [URL] {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }
        return entries.filter { existingDirectory($0) != nil }
    }
}
