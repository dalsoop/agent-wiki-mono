import Foundation

/// srt --settings JSON 렌더링 결과
public struct SRTSettingsResult: Equatable, Sendable {
    /// srt --settings 에 넘길 JSON 문자열
    public var settingsJSON: String
    /// RoomWalls 항목 중 srt 로 매핑할 수 없는 항목 목록
    public var unsupported: [String]

    public init(settingsJSON: String, unsupported: [String] = []) {
        self.settingsJSON = settingsJSON
        self.unsupported = unsupported
    }
}

/// RoomWalls 를 Anthropic sandbox-runtime (srt) 설정 JSON 으로 변환하는 순수 렌더러 (L3).
///
/// srt 스키마: `{ filesystem: { denyRead, allowRead, allowWrite, denyWrite },
///   network: { allowedDomains, deniedDomains, allowLocalBinding, allowUnixSockets, allowAllUnixSockets } }`
public enum SRTSettingsRenderer {

    /// RoomWalls 와 경로 컨텍스트로부터 srt 설정 JSON 을 렌더링한다.
    public static func render(
        walls: RoomWalls,
        workdir: String?,
        roomDir: String,
        home: String
    ) -> SRTSettingsResult {
        let resolved = walls.resolved(workdir: workdir)
        var unsupported: [String] = []

        // --- filesystem ---
        let fsDenyRead: [Any] = resolved.filesystem.denyRead.map(expandHome(home:home))
        var fsAllowRead: [Any] = resolved.filesystem.allowRead.map(expandHome(home:home))
        var fsAllowWrite: [Any] = resolved.filesystem.allowWrite.map(expandHome(home:home))
        let fsDenyWrite: [Any] = resolved.filesystem.denyWrite.map(expandHome(home:home))

        // srt 는 방 폴더, /private/tmp, /private/var/folders 를 기본 쓰기 허용하지 않으므로 명시한다.
        let stdRoomDir = (roomDir as NSString).standardizingPath
        let stdTmpDir = (roomDir as NSString).appendingPathComponent("tmp")
        for extra in [stdRoomDir, stdTmpDir, "/private/tmp", "/private/var/folders", "/dev/null"] {
            if !fsAllowWrite.contains(where: { ($0 as? String) == extra }) {
                fsAllowWrite.append(extra)
            }
        }
        // /dev/null, /dev/tty 등 읽기도 명시
        for extra in ["/dev/null", "/dev/zero", "/dev/tty"] {
            if !fsAllowRead.contains(where: { ($0 as? String) == extra }) {
                fsAllowRead.append(extra)
            }
        }

        let filesystem: [String: Any] = [
            "denyRead": fsDenyRead,
            "allowRead": fsAllowRead,
            "allowWrite": fsAllowWrite,
            "denyWrite": fsDenyWrite,
        ]

        // --- network ---
        let network: [String: Any] = renderNetwork(resolved.network)

        // --- unix sockets ---
        var networkWithSockets = network
        if resolved.unixSockets.isEmpty {
            networkWithSockets["allowAllUnixSockets"] = false
        } else {
            networkWithSockets["allowUnixSockets"] = resolved.unixSockets
        }

        // --- executables ---
        switch resolved.executables {
        case .allowList(let list):
            if !list.isEmpty {
                unsupported.append("executables.allowList(\(list.joined(separator: ",")))")
            }
        case .hostPath:
            break // srt 기본 동작과 동일
        }

        // --- shell ---
        if resolved.shell == .restricted {
            unsupported.append("shell.restricted")
        }

        // --- enableWeakerNestedSandbox ---
        // SwiftPM 의 sandbox-exec 중첩 문제를 srt 에서 우회하는 플래그
        let topLevel: [String: Any] = [
            "filesystem": filesystem,
            "network": networkWithSockets,
            "enableWeakerNestedSandbox": true,
        ]

        let json = renderJSON(topLevel)
        return SRTSettingsResult(settingsJSON: json, unsupported: unsupported)
    }

    // MARK: - Private

    private static func renderNetwork(_ wall: NetworkWall) -> [String: Any] {
        switch wall {
        case .closed:
            return [
                "allowedDomains": [String](),
                "deniedDomains": ["*"],
                "allowLocalBinding": false,
            ]
        case .open:
            return [
                "allowLocalBinding": true,
            ]
        case .allow(let domains):
            return [
                "allowedDomains": domains,
                "allowLocalBinding": false,
            ]
        }
    }

    private static func expandHome(home: String) -> (String) -> String {
        return { path in
            if path.hasPrefix("~") {
                return (path as NSString).expandingTildeInPath
            }
            return path
        }
    }

    private static func renderJSON(_ dict: [String: Any]) -> String {
        do {
            let data = try JSONSerialization.data(
                withJSONObject: dict,
                options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]
            )
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            assertionFailure("SRTSettingsRenderer JSON serialization failed: \(error)")
            return "{}"
        }
    }
}
